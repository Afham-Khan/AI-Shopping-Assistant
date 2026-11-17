// engine facade used by the controller
const models = require('../models/ai.models');
const nlu = require('./nlu');
const { getCatalog, peek } = require('./retrieval/catalog');
const embeddings = require('./retrieval/embeddings');
const { retrieve } = require('./retrieval/search');
const { getProfile } = require('./ranking/personalization');
const recommender = require('./ranking/recommender');
const { compareProducts } = require('./compare');
const { reviewSummary } = require('./reviews/summary');
const finder = require('./finder');
const llm = require('./llm');
const { respond } = require('./dialogue/manager');
const S = require('./dialogue/state');
const nlg = require('./dialogue/nlg');
const L = require('./nlu/lexicon');
const { recommended, recommendedList, serializeBundle, toCard } = require('./serialize');
const { buildBundle, listTemplates: bundleTemplates } = require('./bundle');
const qa = require('./qa');
const { cartInsights: computeCartInsights } = require('./cartInsights');
const { shoppingDna } = require('./shoppingDna');
const visual = require('./visual');
const { titleCase } = require('./format');
const { completeLook: buildLook } = require('./outfit');
const { explainProduct } = require('./explain');
const { buildGift } = require('./gift');
const discover = require('./discover');

const plain = (s) => String(s || '').replace(/\*\*/g, '');

const recommendations = async (userId, limit) => {
  const rec = await recommender.recommendations(userId, limit);
  return { title: rec.title, subtitle: rec.subtitle, strategy: rec.strategy, products: recommendedList(rec.products) };
};

const similar = async (id, limit) => {
  const items = await recommender.similar(id, limit);
  return items && recommendedList(items);
};

const boughtTogether = async (id, limit) => {
  const items = await recommender.boughtTogether(id, limit);
  return items && recommendedList(items);
};

const SORT_LABELS = { price_asc: 'Cheapest first', price_desc: 'Most expensive first', rating: 'Best rated', popular: 'Most popular', newest: 'Newest', discount: 'Biggest discounts' };

const chipsFor = (slots, catalog) => {
  const chips = [];
  for (const name of nlg.categoryNames(slots, catalog)) chips.push({ type: 'category', label: name });
  if (!slots.categories.length && slots.department) chips.push({ type: 'department', label: catalog.taxonomy.find((c) => c.departmentSlug === slots.department)?.departmentName || slots.department });
  for (const b of slots.brands) chips.push({ type: 'brand', label: catalog.brands.find((x) => x.toLowerCase() === b) || titleCase(b) });
  const b = slots.budget;
  if (b) chips.push({ type: 'budget', label: plain(nlg.budgetPhrase(b)).replace(/^\w/, (c) => c.toUpperCase()) });
  for (const f of slots.features) chips.push({ type: 'feature', label: titleCase(L.FEATURES[f]?.label || f) });
  if (slots.color) chips.push({ type: 'color', label: titleCase(slots.color) });
  if (slots.gender && !slots.recipient) chips.push({ type: 'gender', label: slots.gender === 'women' ? 'For women' : 'For men' });
  if (slots.recipient) chips.push({ type: 'recipient', label: `For ${slots.recipient}` });
  if (slots.occasion) chips.push({ type: 'occasion', label: titleCase(slots.occasion) });
  if (slots.minRating) chips.push({ type: 'rating', label: `${slots.minRating}★ & up` });
  if (slots.sort) chips.push({ type: 'sort', label: SORT_LABELS[slots.sort] });
  for (const x of slots.excludeBrands) chips.push({ type: 'exclude', label: `No ${titleCase(x)}` });
  for (const x of slots.excludeColors) chips.push({ type: 'exclude', label: `No ${x}` });
  for (const k of slots.keywords) chips.push({ type: 'keyword', label: k });
  return chips;
};

const smartSearch = async (q, { userId = null, limit = 20 } = {}) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const a = nlu.analyze(q);
  const slots = S.mergeSlots(S.EMPTY_SLOTS(), a.entities, 'new');
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const result = await retrieve(slots, { profile, limit });
  const what = nlg.describe(slots, catalog);
  const budget = plain(nlg.budgetPhrase(slots.budget));
  const text = result.noMatch
    ? `No matches for "${q}"`
    : [`Showing ${what}${budget ? ` ${budget}` : ''}`, ...result.relaxed.map((r) => r.message)].join('. ').replace(/\.\./g, '.');
  return {
    interpretation: { text, chips: chipsFor(slots, catalog), corrections: a.corrections, intent: a.intent },
    entities: nlu.publicEntities(a.entities),
    products: recommendedList(result.items),
    total: result.total,
    fallback: result.fallback,
    mode: result.mode,
    latencyMs: Date.now() - started,
  };
};

const nluPlayground = (text) => {
  const a = nlu.analyze(text);
  return {
    intent: a.intent,
    confidence: +a.confidence.toFixed(4),
    alternatives: a.alternatives,
    entities: nlu.publicEntities(a.entities),
    tokens: a.tokens,
    normalized: a.normalized,
    corrections: a.corrections,
    source: a.source,
    latencyMs: +a.latencyMs.toFixed(2),
  };
};

const finderFlows = () => finder.getFlows();

const runFinder = async (args) => {
  const result = await finder.runFinder(args);
  return result && { summary: result.summary, products: recommendedList(result.products), total: result.total, fallback: result.fallback };
};

const insights = async () => {
  const [catalog, stats, embedCounts] = await Promise.all([getCatalog(), models.aiStats(), models.countEmbeddings().catch(() => [])]);
  if (embeddings.wanted() && embeddings.info().status === 'idle') embeddings.load();
  const info = nlu.modelInfo();
  const emb = embeddings.info();
  const mode = catalog.mode;
  return {
    intentModel: {
      algorithm: info.algorithm,
      classes: info.classes,
      trainingSamples: info.trainingSamples,
      testAccuracy: info.testAccuracy,
      trainedAt: info.trainedAt,
      macroF1: info.macroF1,
      cvAccuracy: info.cvAccuracy,
      baselineNaiveBayesAccuracy: info.baselineNaiveBayesAccuracy,
      vocabularySize: info.vocabularySize,
      calibration: info.calibration,
    },
    embeddings: {
      mode,
      model: mode === 'neural' ? emb.model : 'tfidf-lsa',
      dims: mode === 'neural' ? emb.dims : catalog.space.dims || 0,
      indexedProducts: mode === 'neural' ? catalog.neural.size : catalog.products.length,
      neuralStatus: emb.status,
      storedVectors: embedCounts,
      fallback: `TF-IDF + LSA (${catalog.space.dims || 0} latent dims via Jacobi SVD)`,
      lexical: `BM25 (${catalog.bm25.df.size} terms)`,
    },
    llm: llm.info(),
    recommender: {
      signals: ['semantic similarity', 'BM25 lexical match', 'Bayesian-average rating', 'popularity (sold count)', 'discount', 'requested features', 'category & brand affinity', 'taste centroid of viewed/wishlisted/purchased items', 'co-purchase lift'],
      algorithms: ['hybrid weighted scoring with explanations', 'MMR diversity re-ranking', 'association rules (support / confidence / lift)', 'content-based nearest neighbours'],
      interactionWeights: require('./ranking/personalization').TYPE_WEIGHTS,
    },
    visual: await visual.info(),
    stats,
    catalog: { products: catalog.products.length, builtAt: catalog.builtAt, buildMs: catalog.buildMs },
  };
};

const bundle = async ({ goal, budget }) => {
  const b = await buildBundle({ goal, budget });
  return b.error ? b : serializeBundle(b);
};

const askProduct = async (productId, question) => {
  const result = await qa.ask(productId, question);
  if (!result) return null;
  let { answer } = result;
  let source = 'local';
  if (llm.active() && result.confidence >= 0.4) {
    const enhanced = await llm.enhance({ query: question, draft: answer, intent: 'product_question', facts: result.evidence.map((e) => `${e.source}: ${e.text}`) });
    answer = enhanced.content;
    source = enhanced.source;
  }
  return { ...result, answer, source };
};

const cartInsights = async (userId) => {
  const r = await computeCartInsights(userId);
  return {
    savings: r.savings.map((s) => ({ productId: s.productId, alternative: recommended(s.alternative), save: s.save, reason: s.reason })),
    completeTheSet: recommendedList(r.completeTheSet),
    freeShippingGap: r.freeShippingGap ? { remaining: r.freeShippingGap.remaining, suggestions: r.freeShippingGap.suggestions.map(toCard) } : null,
    summary: r.summary,
    subtotal: r.subtotal,
  };
};

const visualSearch = async (buffer, limit) => {
  const r = await visual.visualSearch(buffer, { limit });
  return { recognized: r.recognized, message: r.message, products: recommendedList(r.items), detected: r.detected, suggestions: r.suggestions, ...(r.reason ? { reason: r.reason } : {}), latencyMs: r.latencyMs };
};

const visualTextSearch = async (q, limit) => {
  const r = await visual.textToImage(q, { limit });
  return { recognized: r.recognized, message: r.message, products: recommendedList(r.items), suggestions: r.suggestions, latencyMs: r.latencyMs };
};

const completeLook = async (productId, limit) => {
  const r = await buildLook(productId, { limit });
  if (!r) return null;
  return {
    base: toCard(r.base),
    kind: r.kind,
    title: r.title,
    look: r.look.map((l) => ({ role: l.role, category: l.category, product: recommended(l.item), alternatives: l.alternatives.map(toCard) })),
    products: recommendedList(r.items),
    palette: r.palette,
  };
};

const explain = async (productId) => {
  const catalog = await getCatalog();
  const p = catalog.byId.get(Number(productId));
  return p ? explainProduct(p) : null;
};

const gift = async (args) => {
  const r = await buildGift(args);
  return { title: r.title, products: recommendedList(r.items), note: r.note, criteria: r.criteria, relaxed: r.relaxed };
};

const discoverDeck = async (args) => {
  const r = await discover.buildDeck(args);
  return { cards: r.cards.map((c) => ({ ...recommended(c), deckKind: c.kind })), personalized: r.personalized, strategy: r.strategy };
};

const discoverReels = async (args) => {
  const r = await discover.buildReels(args);
  return { reels: r.reels.map(({ affinity, products, ...rest }) => ({ ...rest, products: products.map(toCard) })), personalized: r.personalized };
};

const roomScene = async (args) => (await discover.buildRoom(args)).map((z) => ({ ...z, featured: z.featured.map(toCard) }));

const warmup = () => {
  try {
    nlu.loadModel();
  } catch {
    // retried lazily on first request
  }
  const catalog = getCatalog().catch(() => null);
  // CLIP stays lazy (first Snap & Find request) unless AI_VISUAL_WARMUP=on: then it loads in the background right
  // after boot (~300 MB more RAM), so the first photo search does not wait for the model. Never blocks startup.
  if (process.env.AI_VISUAL_WARMUP === 'on') catalog.then(() => visual.load()).catch(() => null);
  return catalog;
};

module.exports = {
  respond, recommendations, similar, boughtTogether, compare: compareProducts, reviewSummary, smartSearch, nluPlayground,
  finderFlows, finder: runFinder, insights, warmup, peek, bundle, bundleTemplates, serializeBundle, askProduct, cartInsights,
  profile: shoppingDna, visualSearch, visualTextSearch, VisualUnavailable: visual.VisualUnavailable,
  completeLook, explain, gift, discoverDeck, discoverReels, discoverTaste: discover.tasteFrom, roomScene,
};
