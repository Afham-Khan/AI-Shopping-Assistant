// golden-set evaluation for recommendation relevance (npm run ai:eval, test/ai.ranking.eval.test.js).
// every query runs through the same dialogue manager the chat uses (no http), and the returned cards are
// judged against the machine-checkable expectations in training/data/ranking-eval.json.
// the judge is deliberately independent of the ranking code (it only reads raw product fields), so the
// engine cannot "grade its own homework".
const fs = require('fs');
const path = require('path');

const EVAL_FILE = path.join(__dirname, 'data', 'ranking-eval.json');

// colour families (judge-side copy, kept tiny and explicit)
const COLOR_WORDS = {
  black: ['black', 'onyx', 'charcoal'], white: ['white', 'off white', 'off-white', 'ivory', 'polar white', 'pearl white'],
  red: ['red', 'maroon', 'crimson', 'burgundy'], blue: ['blue', 'navy'], green: ['green', 'olive', 'emerald'],
  yellow: ['yellow', 'mustard'], pink: ['pink'], purple: ['purple', 'violet', 'plum', 'lavender'], orange: ['orange'],
  brown: ['brown', 'tan', 'chocolate', 'cherry'], grey: ['grey', 'gray', 'graphite'], silver: ['silver', 'platinum', 'steel'],
  gold: ['gold', 'golden'], beige: ['beige', 'nude', 'cream'],
};

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// "sneaker" matches "sneakers", "heel" matches "heels" (word start, any ending)
const hasTerm = (text, term) => new RegExp(`(?:^|[^a-z0-9])${escape(term.toLowerCase())}`).test(text);

const colorsIn = (text) => {
  const t = ` ${String(text || '').toLowerCase()} `;
  const found = [];
  for (const [family, words] of Object.entries(COLOR_WORDS)) {
    if (words.some((w) => hasTerm(t, w))) found.push(family);
  }
  return found;
};

const specText = (p, keys) => Object.entries(p.specs || {}).filter(([k]) => keys.test(k)).map(([, v]) => v).join(' ');

// primary = the listed colour; secondary = other colours named in the title or colour specs ("Red & Black")
const productColors = (p) => {
  const primary = colorsIn(p.color);
  const secondary = colorsIn(`${p.title} ${specText(p, /colou?r|shade/i)}`).filter((c) => !primary.includes(c));
  return { primary, secondary };
};

const productGender = (p) => {
  if (p.gender === 'men' || p.gender === 'women') return p.gender;
  if (/^mens-/.test(p.category_slug)) return 'men';
  if (/^womens-/.test(p.category_slug)) return 'women';
  return null;
};

// spec VALUES only: a spec named "Heel" with value "Flat" must not make a slipper match "heel"
const fullText = (p) => [
  p.title, p.category_slug, p.category_name, p.color, p.brand_name, p.search_keywords, (p.tags || []).join(' '),
  Object.values(p.specs || {}).join(' '),
].join(' ').toLowerCase();

// mustNotMatch only looks at what a product *is* (title, category, keywords, tags), not at spec prose,
// so "Nike Air cushioning in the heel" does not make a sneaker a "heel"
const identityText = (p) => [p.title, p.category_slug, p.category_name, p.search_keywords, (p.tags || []).join(' ')].join(' ').toLowerCase();

// -> { grade: 0|1|2, violations: [{ type, detail }], matched: bool }
const judge = (p, exp) => {
  const violations = [];
  if (exp.expectCategories?.length && !exp.expectCategories.includes(p.category_slug)) violations.push({ type: 'category', detail: p.category_slug });
  if (exp.gender) {
    const g = productGender(p);
    if (g && g !== exp.gender) violations.push({ type: 'gender', detail: g });
  }
  if (exp.maxPrice != null && p.price > exp.maxPrice) violations.push({ type: 'budget', detail: `Rs ${Math.round(p.price)} > ${exp.maxPrice}` });
  if (exp.minPrice != null && p.price < exp.minPrice) violations.push({ type: 'budget', detail: `Rs ${Math.round(p.price)} < ${exp.minPrice}` });
  if (exp.brand && (p.brand_name || '').toLowerCase() !== exp.brand.toLowerCase()) violations.push({ type: 'brand', detail: p.brand_name || 'no brand' });
  const idText = identityText(p);
  const bad = (exp.mustNotMatch || []).find((t) => hasTerm(idText, t));
  if (bad) violations.push({ type: 'mustNotMatch', detail: bad });
  let colorLevel = null;
  if (exp.color) {
    const c = productColors(p);
    colorLevel = c.primary.includes(exp.color) ? 'primary' : c.secondary.includes(exp.color) ? 'secondary' : 'none';
    if (colorLevel === 'none') violations.push({ type: 'color', detail: p.color || 'no colour' });
  }
  const text = fullText(p);
  const matched = !(exp.mustMatchAny || []).length || exp.mustMatchAny.some((t) => hasTerm(text, t));
  let grade = 0;
  if (!violations.length) grade = matched && colorLevel !== 'secondary' ? 2 : 1;
  return { grade, violations, matched, colorLevel };
};

const dcg = (grades) => grades.reduce((s, g, i) => s + (2 ** g - 1) / Math.log2(i + 2), 0);

const HARD = new Set(['category', 'gender', 'budget', 'brand', 'color', 'mustNotMatch']);

// first catalogue title that the reply puts in **bold** must be the first card
const topPickConsistency = (content, cards) => {
  if (!cards.length) return { ok: true, mentioned: null };
  const bold = [...String(content || '').matchAll(/\*\*([^*]+)\*\*/g)].map((m) => m[1].trim());
  const titles = new Set(cards.map((c) => c.title));
  const first = bold.find((b) => titles.has(b));
  return { ok: !first || first === cards[0].title, mentioned: first || null };
};

// q: one query object, reply: { content, products: [catalog rows in card order] }, inStock: catalog rows a shopper can buy
const evaluateQuery = (q, reply, inStock) => {
  const cards = reply.products;
  const judged = cards.map((p) => ({ p, ...judge(p, q) }));
  const catalogJudged = inStock.map((p) => judge(p, q));
  const catalogGrades = catalogJudged.map((j) => j.grade).sort((a, b) => b - a);
  const availFull = catalogGrades.filter((g) => g >= 1).length; // satisfy every hard constraint
  const availMatched = catalogJudged.filter((j) => j.grade >= 1 && j.matched).length; // ...and are the asked-for kind
  const availRelevant = catalogGrades.filter((g) => g === 2).length;
  const top3 = judged.slice(0, 3);
  const hits3 = top3.filter((j) => j.grade === 2).length;
  const wanted = q['minHits@3'] ?? 2;
  const required = Math.min(wanted, availRelevant, 3);
  // a constraint violation only counts when the catalogue had a compliant product for that slot. a card that IS
  // the asked-for kind (matches mustMatchAny, e.g. a red heel for "black heels") is only beaten by a compliant
  // product of that kind, not by a black slipper
  const violations = [];
  top3.forEach((j, i) => {
    if (i >= (j.matched ? availMatched : availFull)) return;
    for (const v of j.violations) if (HARD.has(v.type)) violations.push({ pos: i + 1, title: j.p.title, ...v });
  });
  const idcg = dcg(catalogGrades.slice(0, 5));
  const ndcg5 = idcg > 0 ? dcg(judged.slice(0, 5).map((j) => j.grade)) / idcg : null;
  const consistency = topPickConsistency(reply.content, cards);
  const reasons = [];
  if (!cards.length && availRelevant > 0) reasons.push('no products returned');
  if (hits3 < required) reasons.push(`only ${hits3}/${required} relevant in top 3`);
  for (const v of violations) reasons.push(`#${v.pos} ${v.type}: ${v.title} (${v.detail})`);
  if (!consistency.ok) reasons.push(`reply's top pick "${consistency.mentioned}" is not the first card`);
  return {
    id: q.id, q: q.q, group: q.group, intent: reply.intent,
    top3: top3.map((j) => j.p.title),
    hits3, required, availRelevant, availFull,
    precision3: availRelevant ? hits3 / Math.min(3, availRelevant) : null,
    ndcg5, violations, consistent: consistency.ok,
    pass: reasons.length === 0, reasons,
    knownFailure: Boolean(q.knownFailure),
  };
};

const summarize = (results) => {
  const n = results.length;
  const avg = (xs) => (xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : 0);
  const byType = {};
  for (const r of results) for (const v of r.violations) byType[v.type] = (byType[v.type] || 0) + 1;
  return {
    queries: n,
    passed: results.filter((r) => r.pass).length,
    passRate: n ? results.filter((r) => r.pass).length / n : 0,
    precisionAt3: avg(results.map((r) => r.precision3).filter((x) => x != null)),
    ndcgAt5: avg(results.map((r) => r.ndcg5).filter((x) => x != null)),
    violations: results.reduce((s, r) => s + r.violations.length, 0),
    violationsByType: byType,
    inconsistentReplies: results.filter((r) => !r.consistent).length,
    // failing queries NOT marked "knownFailure": these are regressions and fail the mocha threshold test
    unexpectedFailures: results.filter((r) => !r.pass && !r.knownFailure).map((r) => r.q),
  };
};

const loadQueries = (file = EVAL_FILE) => {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  return data.queries;
};

// runs every query through the chat pipeline; respond = dialogue manager respond()
const runEval = async ({ respond, getCatalog, queries = loadQueries(), onResult, waitForNeural = true } = {}) => {
  let catalog = await getCatalog();
  // judge what production serves after warm-up: wait for the neural model (unless AI_EMBEDDINGS=tfidf)
  const embeddings = require('../engine/retrieval/embeddings');
  if (waitForNeural && embeddings.wanted()) {
    await embeddings.load();
    catalog = await getCatalog();
  }
  const inStock = catalog.products.filter((p) => p.stock > 0);
  const results = [];
  for (const q of queries) {
    let out = await respond({ text: q.q, context: null, userId: null });
    // guided flows (gift: "what budget?") -> answer with the scripted follow-ups until products appear
    for (const next of q.followUps || []) {
      if (out.meta?.products?.length) break;
      out = await respond({ text: next, context: out.context, userId: null });
    }
    const products = (out.meta?.products || []).map((c) => catalog.byId.get(c.id)).filter(Boolean);
    const r = evaluateQuery(q, { content: out.content, products, intent: out.meta?.intent }, inStock);
    results.push(r);
    if (onResult) onResult(r);
  }
  return { results, summary: summarize(results), mode: catalog.mode };
};

module.exports = { runEval, evaluateQuery, summarize, judge, loadQueries, productColors, topPickConsistency, hasTerm, EVAL_FILE };
