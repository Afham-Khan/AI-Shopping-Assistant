// grounded product q&a: split a product into passages (specs, highlights, description, policies, review
// sentences), rank them against the question (bm25 + embeddings), answer extractively with templates.
const models = require('../models/ai.models');
const { getCatalog } = require('./retrieval/catalog');
const embeddings = require('./retrieval/embeddings');
const { analyzeText } = require('./retrieval/bm25');
const { cosine } = require('./retrieval/vectorspace');
const { splitSentences, scoreSentence } = require('./reviews/sentiment');
const { aspectsFor, detectAspects, LABELS } = require('./reviews/aspects');
const { money, stars, truncate, plural, list } = require('./format');
const { explainProduct } = require('./explain');

const cache = new Map(); // productId -> { stamp, passages, vectors }

// question words -> spec keys they usually refer to
const SPEC_SYNONYMS = {
  ram: ['ram', 'memory'], storage: ['storage', 'rom', 'ssd', 'capacity'], battery: ['battery', 'charge', 'mah', 'backup'],
  camera: ['camera', 'rear camera', 'front camera', 'megapixel', 'mp'], display: ['display', 'screen', 'resolution'],
  processor: ['processor', 'chip', 'cpu', 'chipset'], os: ['os', 'operating system', 'android', 'ios', 'windows'],
  weight: ['weight', 'heavy', 'light'], size: ['size', 'dimensions', 'volume', 'capacity'], material: ['material', 'fabric', 'made of'],
  warranty: ['warranty', 'guarantee'], waterproof: ['water resistance', 'waterproof', 'water'], charging: ['charging', 'charger', 'fast charging'],
  color: ['colour', 'color', 'shade'], connectivity: ['bluetooth', 'connectivity', 'wifi', 'network', '5g', '4g'],
  longevity: ['longevity', 'last', 'lasts', 'long lasting'], transmission: ['transmission', 'automatic', 'manual', 'gearbox', 'gears'],
  biometrics: ['face id', 'touch id', 'fingerprint', 'face unlock'], stylus: ['stylus', 'pen', 'pencil'],
};

// ---- yes/no answers: say "yes" only when the asked feature is actually in the passage --------------------

const QUESTION_FILLER = new Set(['is', 'it', 'its', 'does', 'do', 'did', 'have', 'has', 'come', 'comes', 'with', 'a', 'an', 'the', 'support', 'supports',
  'can', 'could', 'i', 'use', 'this', 'that', 'for', 'of', 'any', 'there', 'will', 'would', 'be', 'my', 'me', 'you', 'your', 'are', 'they', 'get',
  'include', 'includes', 'included', 'offer', 'work', 'works', 'in', 'on', 'to', 'kya', 'hai', 'or', 'not', 'one', 'product', 'item', 'really', 'also']);
// the words a passage may use for an asked feature
const FEATURE_WORDS = {
  waterproof: ['waterproof', 'water resistance', 'water resistant', 'water-resistant', 'ip67', 'ip68', 'ip65', 'ip54', 'atm'],
  wireless: ['wireless', 'qi', 'magsafe'], real: ['real', 'genuine'], men: ['men', 'male', 'unisex'], women: ['women', 'female', 'unisex'],
  stylus: ['stylus', 'pen', 'pencil'], automatic: ['automatic', 'cvt'], warranty: ['warranty', 'guarantee'],
};
// passage words that answer "no" when the asked feature is missing ("automatic?" -> "6-speed manual")
const CONTRARY = [
  [/\bautomatic\b/, /\bmanual\b/], [/\bmanual\b/, /\bautomatic\b|\bcvt\b/], [/\bwireless\b/, /\bwired\b/], [/\breal\b|\bgenuine\b/, /\bfaux\b|\bpu\b|synthetic|vegan leather/],
  [/\b5g\b/, /\blte\b|\b4g\b/], [/\bface\b/, /touch id|fingerprint/], [/\bwaterproof\b/, /not water|no water/],
];
const stem = (w) => w.replace(/(?:es|s)$/, '');
const contentTerms = (q) => q.replace(/[^a-z0-9\s-]/g, ' ').split(/\s+/).filter((w) => w && !QUESTION_FILLER.has(w));
const mentions = (text, term) => {
  const clean = (x) => x.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const t = ` ${clean(text)} `;
  return (FEATURE_WORDS[term] || [term]).map(clean).some((w) => t.includes(` ${w} `) || t.includes(` ${stem(w)} `) || (w.length > 4 && t.includes(w)));
};

// 'yes' | 'no' | 'partly' | 'unknown' for a yes/no question against one passage
const yesNo = (q, passage) => {
  const value = passage.text.includes(':') ? passage.text.split(':').slice(1).join(':') : passage.text;
  if (passage.source === 'spec' && NEGATIVE_VALUE.test(value)) return 'no';
  const terms = contentTerms(q);
  const missing = terms.filter((t) => !mentions(passage.text, t));
  if (/\bwaterproof\b/.test(q) && /splash/i.test(value)) return 'partly';
  if (!missing.length) return 'yes';
  if (missing.every((t) => ['men', 'women', 'male', 'female'].includes(t)) && /unisex/i.test(value)) return 'yes';
  if (CONTRARY.some(([asked, contra]) => asked.test(q) && contra.test(value.toLowerCase()))) return 'no';
  return 'unknown';
};

// ---- "is it good for gaming?": judge the use case from the spec explainer's levels -------------------------

const USES = [
  [/\bgam(?:e|es|ing|er|ers)\b|pubg|fortnite/, 'gaming', ['Processor', 'RAM', 'Graphics', 'Display']],
  [/\bphoto(?:s|graphy)?\b|pictures|camera|selfies?|vlog/, 'photography', ['Rear Camera', 'Front Camera']],
  [/\b(?:work|office|study|studies|students?|school|university|college|programming|coding)\b/, 'work and study', ['Processor', 'RAM', 'Battery Life']],
  [/\b(?:travel(?:ling)?|trips?|commut\w*)\b/, 'travel', ['Weight', 'Battery', 'Battery Life']],
  [/\b(?:movies|videos|netflix|youtube|streaming|watching)\b/, 'videos', ['Display', 'Battery', 'Battery Life']],
  [/\b(?:music|calls)\b/, 'music', ['Battery', 'Noise Cancellation']],
];
const suitabilityAnswer = (p, q) => {
  const m = q.match(/\b(?:good|great|suitable|ok|okay|fine|enough|decent|ideal|best|any good)\s+for\s+(.+)$/) || q.match(/\bcan (?:i|it|you) (?:play|use it for|run|edit)\s+(.+)$/);
  if (!m) return null;
  const use = USES.find(([re]) => re.test(m[1]));
  if (!use) return null;
  const [, label, keys] = use;
  const specs = explainProduct(p).specs.filter((s) => s.level && keys.some((k) => k.toLowerCase() === s.key.toLowerCase()));
  if (!specs.length) return null;
  let level = specs.reduce((a, s) => a + s.level, 0) / specs.length;
  const laptopNoGpu = label === 'gaming' && p.category_slug === 'laptops' && !/\b(?:rtx|gtx|radeon rx|arc a)\b/i.test(String(p.specs?.Graphics || ''));
  if (laptopNoGpu) level = Math.min(level, 2.5);
  const facts = specs.map((s) => `${s.key}: ${s.value}`);
  const strong = specs.filter((s) => s.level >= 4).map((s) => s.key.toLowerCase());
  const weak = specs.filter((s) => s.level <= 2).map((s) => s.key.toLowerCase());
  let answer;
  if (level >= 3.75) answer = `**Yes** — it's strong for ${label}${strong.length ? `: ${list(strong)} ${strong.length > 1 ? 'are' : 'is'} rated ${specs.find((s) => s.level >= 4).levelLabel.toLowerCase()} or better` : ''}.`;
  else if (level >= 2.75) answer = `**It's fine for casual ${label}**, not the best${weak.length ? ` — the ${list(weak)} ${weak.length > 1 ? 'are' : 'is'} the limit` : ''}.`;
  else answer = `**Not really** — for ${label} its ${list(weak.length ? weak : specs.map((s) => s.key.toLowerCase()))} ${(weak.length || specs.length) > 1 ? 'are' : 'is'} basic${laptopNoGpu ? ', and it has no dedicated graphics card, so only light games will run' : ''}.`;
  return { answer: `${answer} (${facts.join('; ')})`, evidence: facts.slice(0, 3).map((text) => ({ source: 'spec', text })), confidence: 0.8 };
};

const buildPassages = (p, reviews) => {
  const out = [];
  for (const [k, v] of Object.entries(p.specs || {})) out.push({ source: 'spec', key: k, text: `${k}: ${v}` });
  for (const h of p.highlights || []) out.push({ source: 'spec', key: 'Highlight', text: h });
  if (p.warranty) out.push({ source: 'spec', key: 'Warranty', text: `Warranty: ${p.warranty}` });
  if (p.return_policy) out.push({ source: 'spec', key: 'Returns', text: `Returns: ${p.return_policy}` });
  if (p.shipping_info) out.push({ source: 'spec', key: 'Shipping', text: `Shipping: ${p.shipping_info}` });
  if (p.color) out.push({ source: 'spec', key: 'Colour', text: `Colour: ${p.color}` });
  for (const s of splitSentences(p.description)) out.push({ source: 'description', text: s });
  for (const r of reviews.slice(0, 80)) {
    for (const s of splitSentences(r.comment)) if (s.length > 12) out.push({ source: 'review', text: s, rating: r.rating });
  }
  return out;
};

const getPassages = async (p) => {
  const stamp = await models.reviewStamp(p.id);
  const hit = cache.get(p.id);
  if (hit && hit.stamp === stamp) return hit;
  const reviews = await models.reviewsFor(p.id);
  const passages = buildPassages(p, reviews);
  passages.forEach((x) => { x.tokens = new Set(analyzeText(x.text)); });
  let vectors = null;
  if (embeddings.ready()) {
    try {
      vectors = await embeddings.embed(passages.map((x) => x.text), { batchSize: 32 });
    } catch {
      vectors = null;
    }
  }
  const entry = { stamp, passages, vectors, reviewCount: reviews.length };
  cache.set(p.id, entry);
  if (cache.size > 100) cache.delete(cache.keys().next().value);
  return entry;
};

const questionType = (q) => {
  if (/^(?:is|does|do|can|has|have|will|are|would|should|could)\b/.test(q) || /\b(?:or not|hai\??$|kya)\b/.test(q)) return 'yesno';
  if (/^(?:how (?:much|many|long|big|heavy|fast|tall|wide|large)|what(?:'s| is)? the|which|what)\b/.test(q)) return 'lookup';
  if (/^(?:how (?:is|are|good)|how's)\b/.test(q)) return 'opinion';
  return 'open';
};

const specIntent = (q) => {
  for (const [key, words] of Object.entries(SPEC_SYNONYMS)) if (words.some((w) => new RegExp(`\\b${w}\\b`).test(q))) return key;
  return null;
};

const NEGATIVE_VALUE = /\b(?:none|no|not|without|n\/a|unavailable)\b/i;

// bm25-style overlap + semantic similarity
const rankPassages = async (question, entry) => {
  const qTokens = analyzeText(question);
  const df = new Map();
  for (const p of entry.passages) for (const t of p.tokens) df.set(t, (df.get(t) || 0) + 1);
  const N = entry.passages.length || 1;
  const qVec = entry.vectors ? await embeddings.embedQuery(question) : null;
  return entry.passages
    .map((p, i) => {
      let lex = 0;
      for (const t of qTokens) if (p.tokens.has(t)) lex += Math.log(1 + (N - (df.get(t) || 0) + 0.5) / ((df.get(t) || 0) + 0.5));
      const sem = qVec && entry.vectors ? Math.max(0, cosine(qVec, entry.vectors[i])) : 0;
      return { ...p, lex, sem, score: 0.55 * Math.min(1, lex / 4) + 0.45 * sem + (p.source === 'spec' ? 0.05 : 0) };
    })
    .sort((a, b) => b.score - a.score);
};

const followUpsFor = (p, asked) => {
  const ideas = [];
  const keys = Object.keys(p.specs || {});
  const has = (re) => keys.some((k) => re.test(k));
  if (has(/battery/i) && asked !== 'battery') ideas.push('How long does the battery last?');
  if (has(/camera/i) && asked !== 'camera') ideas.push('Is the camera good?');
  if (has(/ram|storage/i) && asked !== 'ram') ideas.push('How much RAM does it have?');
  ideas.push('What do reviewers dislike?', 'Is it worth the price?', 'What is the warranty?');
  return ideas.filter((x) => !asked || !x.toLowerCase().includes(asked)).slice(0, 3);
};

const ask = async (productId, rawQuestion) => {
  const catalog = await getCatalog();
  const p = catalog.byId.get(Number(productId));
  if (!p) return null;
  const q = String(rawQuestion || '').toLowerCase().replace(/[?!.]+$/g, '').trim();
  const type = questionType(q);
  const spec = specIntent(q);
  const entry = await getPassages(p);
  const evidence = [];
  let answer = null;
  let confidence = 0;

  const suitability = suitabilityAnswer(p, q);
  // direct catalog facts (cited like any other evidence)
  if (/\b(?:price|cost|kitne ka|how much is it|discount)\b/.test(q) && !spec) {
    answer = `It costs **${money(p.price)}**${p.discount_percent >= 1 && p.compare_at_price ? ` — **${Math.round(p.discount_percent)}% off** the usual ${money(p.compare_at_price)}` : ''}.`;
    evidence.push({ source: 'spec', text: `Price: ${money(p.price)}${p.compare_at_price > p.price ? ` (was ${money(p.compare_at_price)})` : ''}` });
    confidence = 0.95;
  } else if (/\b(?:in stock|available|availability|stock)\b/.test(q)) {
    answer = p.stock > 0 ? `Yes — **${p.stock}** in stock${p.shipping_info ? ` (${p.shipping_info.toLowerCase()})` : ''}.` : 'Sorry, it is **out of stock** right now.';
    evidence.push({ source: 'spec', text: `Stock: ${p.stock > 0 ? `${p.stock} available` : 'out of stock'}` });
    confidence = 0.95;
  } else if (/\b(?:rating|rated|stars)\b/.test(q) && !spec) {
    answer = `It's rated **${stars(p.rating)}** from ${plural(p.rating_count, 'review')}.`;
    evidence.push({ source: 'spec', text: `Rating: ${stars(p.rating)} (${plural(p.rating_count, 'review')})` });
    confidence = 0.9;
  } else if (suitability) {
    ({ answer, confidence } = suitability);
    evidence.push(...suitability.evidence);
  } else if (/\b(?:worth|value for money|good buy|recommend)\b/.test(q)) {
    const pos = entry.passages.filter((x) => x.source === 'review' && scoreSentence(x.text).score > 0.1).length;
    const neg = entry.passages.filter((x) => x.source === 'review' && scoreSentence(x.text).score < -0.1).length;
    const verdict = p._bayes >= 4 ? 'Most shoppers think so' : p._bayes >= 3.4 ? 'Opinions are mixed' : 'Many shoppers were not convinced';
    answer = `${verdict}: **${stars(p.rating)}** average, ${pos} positive vs ${neg} negative review comments, at **${money(p.price)}**${p.discount_percent >= 10 ? ` with ${Math.round(p.discount_percent)}% off` : ''}.`;
    confidence = 0.75;
  } else if (/\b(?:dislike|complain|complaints|cons|problems|issues|negative)\b/.test(q)) {
    const bad = entry.passages.filter((x) => x.source === 'review').map((x) => ({ ...x, s: scoreSentence(x.text).score })).filter((x) => x.s < -0.15).sort((a, b) => a.s - b.s);
    if (bad.length) {
      answer = `The most common complaint: “${truncate(bad[0].text, 120)}”${bad.length > 1 ? ` (${bad.length} critical comments in total)` : ''}.`;
      bad.slice(0, 2).forEach((b) => evidence.push({ source: 'review', text: b.text }));
      confidence = 0.8;
    } else {
      answer = 'I found no real complaints in the reviews.';
      confidence = 0.7;
    }
  }

  if (!answer) {
    const ranked = await rankPassages(q, entry);
    // aspect opinion questions ("is the battery good?") also weigh review sentiment
    const dict = aspectsFor(p.category_slug);
    const aspects = detectAspects(q, dict);
    // a spec row whose name is the asked spec ("Longevity: 8 to 10 hours") beats a highlight that only mentions it
    const keyHit = (x) => (x.key && x.key !== 'Highlight' && SPEC_SYNONYMS[spec].some((w) => x.key.toLowerCase().includes(w)) ? 1 : 0);
    const specPassages = spec ? ranked.filter((x) => x.source === 'spec' && SPEC_SYNONYMS[spec].some((w) => x.text.toLowerCase().includes(w)))
      .sort((a, b) => keyHit(b) - keyHit(a)) : [];
    const top = specPassages[0] || ranked[0];
    // "how long does it last" is a lookup, not an opinion poll
    const opinion = aspects.length && type !== 'lookup' && (type === 'opinion' || /\b(?:good|bad|great|decent|okay|ok|poor|strong)\b/.test(q));
    if (opinion) {
      const aspect = aspects[0];
      const mentions = entry.passages.filter((x) => x.source === 'review' && detectAspects(x.text, dict).includes(aspect))
        .map((x) => ({ ...x, s: scoreSentence(x.text).score }));
      const pos = mentions.filter((m) => m.s > 0.05).length;
      const neg = mentions.filter((m) => m.s < -0.05).length;
      const label = (LABELS[aspect] || aspect).toLowerCase();
      const specLine = specPassages[0] ? ` Spec: ${specPassages[0].text}.` : '';
      if (mentions.length) {
        const tone = pos > neg * 1.5 ? 'mostly positive' : neg > pos * 1.5 ? 'mostly negative' : 'mixed';
        answer = `Reviewers are **${tone}** about the ${label} (${pos} positive, ${neg} negative mentions).${specLine}`;
        mentions.sort((a, b) => Math.abs(b.s) - Math.abs(a.s)).slice(0, 2).forEach((m) => evidence.push({ source: 'review', text: m.text }));
        confidence = Math.min(0.9, 0.5 + 0.08 * mentions.length);
      } else if (specPassages[0]) {
        answer = `No reviews mention the ${label} yet, but here's the spec — ${specPassages[0].text}.`;
        confidence = 0.6;
      }
    }
    // a spec row matching the asked spec ("waterproof" -> "Water Resistance: IP68") is evidence on its own
    if (!answer && top && (top.score >= 0.22 || (specPassages[0] && top === specPassages[0]))) {
      const text = top.text.replace(/\.$/, '');
      if (type === 'yesno') {
        // prefer the spec passage that actually mentions the asked feature
        const best = [top, ...specPassages, ...ranked.slice(0, 4)].find((x) => x && x.score >= 0.15 && yesNo(q, x) !== 'unknown') || top;
        const verdict = yesNo(q, best);
        const said = best.text.replace(/\.$/, '');
        if (verdict === 'yes') answer = `Yes — ${said}.`;
        else if (verdict === 'no') answer = `No — ${said}.`;
        else if (verdict === 'partly') answer = `Only partly — ${said}. Fine for rain and splashes, not for swimming.`;
        else answer = `The listing doesn't mention that. The closest detail: ${said}.`;
        if (best !== top) evidence.push({ source: best.source, text: best.text });
        if (verdict === 'unknown') confidence = 0.35;
      } else if (top.source === 'review') {
        answer = `A reviewer says: “${truncate(text, 140)}”`;
      } else {
        answer = `${text}.`;
      }
      if (!confidence) confidence = Math.min(0.95, 0.35 + top.score);
    }
    for (const x of [top, ...ranked.slice(0, 3)]) {
      if (x && x.score >= 0.15 && evidence.length < 3 && !evidence.some((ev) => ev.text === x.text)) evidence.push({ source: x.source, text: x.text });
    }
  }

  if (!answer) {
    return {
      answer: `I couldn't find that in the product details for **${p.title}**. Try asking about its specs, reviews, warranty or price.`,
      confidence: 0.15,
      evidence: [],
      followUps: followUpsFor(p, spec),
      product: { id: p.id, title: p.title },
    };
  }
  return {
    answer,
    confidence: +confidence.toFixed(2),
    evidence: evidence.slice(0, 3),
    followUps: followUpsFor(p, spec),
    product: { id: p.id, title: p.title },
  };
};

const looksLikeQuestion = (text) =>
  /^(?:is|does|do|can|has|have|will|are|how|what|which|kya|kitn)\b/.test(text) || /\?$/.test(text) || /\b(?:worth|warranty|in stock|battery life|waterproof)\b/.test(text);

module.exports = { ask, buildPassages, questionType, specIntent, looksLikeQuestion, yesNo };
