// visual search ("snap & find"): clip (vit-b/32) image embeddings for every product thumbnail,
// nearest-neighbour search for an uploaded photo, zero-shot category detection, and text->image search.
// clip loads lazily on the first visual request, never at boot.
//
// open-set rejection: nearest-neighbour search always has *some* closest product, so a photo of class
// notes used to come back as "laptops". every query now goes through three gates before products are
// shown (thresholds are calibrated by `node scripts/calibrateVisual.js`, see visual-thresholds.json):
//   1. zero-shot over catalog categories AND "not a product" classes (handwritten notes, a screenshot,
//      a street...). if a non-product class wins -> not recognized.
//   2. the winning product category must reach `minCategoryProb` (its probability renormalized over the
//      product classes: "how sure are we which category it is"), a backstop for off-catalog photos that
//      no non-product prompt describes.
//   3. neighbours below the cosine `simFloor` are dropped; if none survive -> not recognized.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const models = require('../models/ai.models');
const { getCatalog } = require('./retrieval/catalog');
const { money, stars } = require('./format');

const MODEL_ID = 'Xenova/clip-vit-base-patch32';
const MODEL_KEY = 'clip-vit-base-patch32';
const DIMS = 512;
const LOGIT_SCALE = 100;
const BACKEND_ROOT = path.join(__dirname, '../../../..');
const { transformersCacheDir } = require('../../../../helpers/aiCache');
const THRESHOLDS_FILE = path.join(__dirname, '../training/models/visual-thresholds.json');

// prompt ensembling: every class description is expanded with these templates, embedded, averaged and
// re-normalized. product and non-product classes share the templates so neither side is favoured.
const TEMPLATES = ['a photo of {}.', 'a close-up photo of {}.', 'a cropped photo of {}.', 'a good photo of {}.', 'a picture of {}.'];

// descriptions per catalog category (avoid ambiguous words: "notebook" used to pull note pages into laptops)
const CATEGORY_PROMPTS = {
  smartphones: ['a smartphone', 'a mobile phone'], laptops: ['a laptop computer', 'an open laptop with a keyboard and screen'], tablets: ['a tablet computer', 'an ipad'],
  'mobile-accessories': ['earphones or headphones', 'a phone charger or accessory', 'a smart speaker', 'camera gear or a tripod'], 'mens-shirts': ["a men's shirt", 'a t-shirt'],
  'mens-shoes': ["men's shoes", 'sneakers'], 'mens-watches': ["a men's wristwatch", 'a luxury watch'], tops: ["a women's top", 'a blouse', 'a patterned summer top or dress'],
  'womens-dresses': ['a dress', 'a gown'], 'womens-shoes': ["women's shoes", 'high heels'], 'womens-bags': ['a handbag', 'a purse'],
  'womens-jewellery': ['earrings', 'jewellery'], 'womens-watches': ["a women's wristwatch"], sunglasses: ['sunglasses', 'eyeglasses'],
  beauty: ['makeup', 'lipstick or mascara', 'nail polish'], fragrances: ['a perfume bottle', 'a fragrance'], 'skin-care': ['a lotion bottle', 'skin care cream or soap'],
  furniture: ['a sofa', 'a bed', 'a chair or table'], 'home-decoration': ['a home decoration item', 'a lamp or vase'], 'kitchen-accessories': ['a kitchen utensil', 'cookware', 'an empty plate or bowl', 'a kitchen gadget'],
  groceries: ['fresh food', 'fruits or vegetables', 'a grocery item', 'raw meat or fish', 'a packaged food product'], 'sports-accessories': ['a sports ball', 'sports equipment'],
  motorcycle: ['a motorcycle', 'a scooter'], vehicle: ['a car', 'an suv', 'a new car for sale'],
};

// things people point the camera at that we do not sell. `label` is what the user is told.
const NON_PRODUCT_CLASSES = [
  { slug: 'handwritten-notes', label: 'a page of handwritten notes', prompts: ['a page of handwritten notes', 'handwriting on lined paper', 'handwritten class notes'] },
  { slug: 'printed-text', label: 'a page of printed text', prompts: ['a page of printed text', 'a printed page with paragraphs of text', 'a page of a book'] },
  { slug: 'document', label: 'a paper document', prompts: ['a paper document', 'a sheet of paper', 'a printed form or a receipt'] },
  { slug: 'screenshot', label: 'a screenshot', prompts: ['a screenshot of a website', 'a screenshot of an app', 'a screenshot of a chat conversation'] },
  { slug: 'whiteboard', label: 'a whiteboard', prompts: ['a whiteboard with writing', 'a chalkboard', 'a diagram drawn on a board'] },
  { slug: 'blank-wall', label: 'a blank wall', prompts: ['a blank wall', 'an empty painted wall', 'a bare wall in a room'] },
  { slug: 'landscape', label: 'a landscape', prompts: ['a landscape', 'mountains and sky', 'a beach or a forest'] },
  { slug: 'street', label: 'a street', prompts: ['a city street', 'buildings along a road', 'a sidewalk in a town'] },
  { slug: 'room', label: 'a room interior', prompts: ['a room interior', 'the inside of a classroom or an office', 'a hallway'] },
  { slug: 'pet', label: 'a pet animal', prompts: ['a pet animal', 'a dog', 'a cat'] },
  { slug: 'cooked-food', label: 'a plate of cooked food', prompts: ['a plate of cooked food', 'a cooked meal served with sauce and sides', 'a restaurant dish ready to eat'] },
  { slug: 'blurry', label: 'a blurry photo', prompts: ['a blurry photo', 'an out of focus picture', 'a dark unclear photo'] },
  { slug: 'pattern', label: 'an abstract pattern', prompts: ['an abstract pattern', 'random noise', 'a checkerboard pattern'] },
  { slug: 'drawing', label: 'a drawing or scribble', prompts: ['a scribble', 'a doodle drawn with a pen', "a child's drawing"] },
];

const DEFAULT_THRESHOLDS = { minCategoryProb: 0.3, simFloor: 0.6, simCeil: 0.92, textSimFloor: 0.2 };

const state = { status: 'idle', error: null, promise: null, parts: null, vectors: null, vectorsSignature: null, classVecs: null, indexing: null, thresholds: null };

const enabled = () => process.env.AI_VISUAL !== 'off';

const load = () => {
  if (!enabled()) {
    state.status = 'disabled';
    return Promise.resolve(null);
  }
  if (state.promise) return state.promise;
  state.status = 'loading';
  state.promise = (async () => {
    try {
      const T = require('@huggingface/transformers');
      T.env.cacheDir = transformersCacheDir(); // AI_CACHE_DIR (e.g. /home/.cache on Azure) or backend/.cache
      const [processor, vision, tokenizer, text] = await Promise.all([
        T.AutoProcessor.from_pretrained(MODEL_ID),
        T.CLIPVisionModelWithProjection.from_pretrained(MODEL_ID, { dtype: 'q8' }),
        T.AutoTokenizer.from_pretrained(MODEL_ID),
        T.CLIPTextModelWithProjection.from_pretrained(MODEL_ID, { dtype: 'q8' }),
      ]);
      state.parts = { T, processor, vision, tokenizer, text };
      state.status = 'ready';
      return state.parts;
    } catch (error) {
      state.status = 'failed';
      state.error = error.message;
      state.promise = null; // allow a later retry
      return null;
    }
  })();
  return state.promise;
};

const normalize = (arr) => {
  const v = Float32Array.from(arr);
  const n = Math.sqrt(v.reduce((s, x) => s + x * x, 0)) || 1;
  for (let i = 0; i < v.length; i += 1) v[i] /= n;
  return v;
};

const dot = (a, b) => {
  let s = 0;
  for (let i = 0; i < a.length; i += 1) s += a[i] * b[i];
  return s;
};

const clamp01 = (x) => Math.max(0, Math.min(1, x));

// ---- thresholds ------------------------------------------------------------------------------------

// fingerprint of everything the calibration depends on; a mismatch means the json is stale
const classesSignature = () => crypto.createHash('sha1')
  .update(JSON.stringify({ MODEL_KEY, LOGIT_SCALE, TEMPLATES, CATEGORY_PROMPTS, NON_PRODUCT_CLASSES }))
  .digest('hex').slice(0, 12);

const envNumber = (name) => {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return undefined;
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
};

// calibrated file -> env overrides (VISUAL_MIN_CATEGORY_PROB, VISUAL_SIM_FLOOR, VISUAL_SIM_CEIL, VISUAL_TEXT_SIM_FLOOR)
const loadThresholds = ({ reload = false } = {}) => {
  if (state.thresholds && !reload) return state.thresholds;
  let file = null;
  try {
    file = JSON.parse(fs.readFileSync(THRESHOLDS_FILE, 'utf8'));
  } catch {
    file = null;
  }
  const t = { ...DEFAULT_THRESHOLDS, ...((file && file.thresholds) || {}) };
  const overrides = {
    minCategoryProb: envNumber('VISUAL_MIN_CATEGORY_PROB'),
    simFloor: envNumber('VISUAL_SIM_FLOOR'),
    simCeil: envNumber('VISUAL_SIM_CEIL'),
    textSimFloor: envNumber('VISUAL_TEXT_SIM_FLOOR'),
  };
  const overridden = [];
  for (const [k, v] of Object.entries(overrides)) {
    if (v !== undefined) {
      t[k] = v;
      overridden.push(k);
    }
  }
  if (t.simCeil <= t.simFloor) t.simCeil = Math.min(1, t.simFloor + 0.05);
  state.thresholds = {
    ...t,
    source: file ? 'calibrated' : 'defaults',
    overridden,
    calibratedAt: (file && file.calibratedAt) || null,
    stale: Boolean(file && file.classesSignature && file.classesSignature !== classesSignature()),
  };
  return state.thresholds;
};

// ---- embeddings ------------------------------------------------------------------------------------

// source: Buffer | local path | url
const embedImage = async (source) => {
  const parts = await load();
  if (!parts) throw new Error('visual model unavailable');
  const { T, processor, vision } = parts;
  const image = Buffer.isBuffer(source) ? await T.RawImage.fromBlob(new Blob([source])) : await T.RawImage.read(source);
  const { image_embeds: emb } = await vision(await processor(image));
  return normalize(emb.data);
};

const embedTexts = async (texts) => {
  const parts = await load();
  if (!parts) throw new Error('visual model unavailable');
  const inputs = parts.tokenizer(texts, { padding: true, truncation: true });
  const { text_embeds: emb } = await parts.text(inputs);
  return emb.tolist().map(normalize);
};

const thumbnailSource = (p) => {
  const url = p.thumbnail_url || '';
  if (url.startsWith('/')) {
    const local = path.join(BACKEND_ROOT, url);
    if (fs.existsSync(local)) return local;
  }
  return /^https?:\/\//.test(url) ? url : null;
};

// compute missing (or all) thumbnail embeddings and persist them
const indexProducts = async (rows, { onProgress = () => {} } = {}) => {
  const out = [];
  let done = 0;
  for (const p of rows) {
    const src = thumbnailSource(p);
    if (!src) continue;
    try {
      const v = await embedImage(src);
      out.push({ product_id: p.id, model: MODEL_KEY, dims: DIMS, vector: Array.from(v, (x) => +x.toFixed(6)) });
    } catch {
      // unreadable image: product simply won't appear in visual results
    }
    done += 1;
    if (out.length >= 25) await models.upsertImageEmbeddings(out.splice(0));
    onProgress(done, rows.length);
  }
  await models.upsertImageEmbeddings(out);
  state.vectors = null;
  return done;
};

const loadVectors = async (catalog) => {
  if (state.vectors && state.vectorsSignature === catalog.signature) return state.vectors;
  const rows = await models.loadImageEmbeddings(MODEL_KEY);
  state.vectors = new Map(rows.filter((r) => catalog.byId.has(r.product_id)).map((r) => [r.product_id, Float32Array.from(r.vector)]));
  state.vectorsSignature = catalog.signature;
  return state.vectors;
};

// expand descriptions x templates, embed in one batch, average + normalize per class
const ensembleVectors = async (classes) => {
  const texts = [];
  const spans = [];
  for (const c of classes) {
    const start = texts.length;
    for (const d of c.prompts) for (const t of TEMPLATES) texts.push(t.replace('{}', d));
    spans.push([start, texts.length]);
  }
  const vecs = await embedTexts(texts);
  return classes.map((c, k) => {
    const [a, b] = spans[k];
    const mean = new Float32Array(DIMS);
    for (let j = a; j < b; j += 1) for (let i = 0; i < DIMS; i += 1) mean[i] += vecs[j][i] / (b - a);
    return { ...c, vec: normalize(mean) };
  });
};

// every catalog category (kind 'product') + every non-product class (kind 'other')
const classVectors = async (catalog) => {
  if (state.classVecs && state.classVecs.signature === catalog.signature) return state.classVecs.entries;
  const products = catalog.taxonomy.map((c) => ({ kind: 'product', slug: c.slug, name: c.name, label: c.name, prompts: CATEGORY_PROMPTS[c.slug] || [c.name.toLowerCase()] }));
  const others = NON_PRODUCT_CLASSES.map((c) => ({ kind: 'other', slug: c.slug, name: c.label, label: c.label, prompts: c.prompts }));
  const entries = await ensembleVectors([...products, ...others]);
  state.classVecs = { signature: catalog.signature, entries };
  return entries;
};

// ---- zero-shot + open-set decision -----------------------------------------------------------------

// clip zero-shot: softmax over logit_scale (100) * cosine. classes without `kind` count as products.
const zeroShot = (vec, classes) => {
  const logits = classes.map((c) => LOGIT_SCALE * dot(vec, c.vec));
  const max = Math.max(...logits);
  const exps = logits.map((l) => Math.exp(l - max));
  const sum = exps.reduce((a, b) => a + b, 0);
  const ranked = classes.map((c, i) => ({ c, p: exps[i] / sum })).sort((a, b) => b.p - a.p);
  const isOther = (r) => r.c.kind === 'other';
  const bestProduct = ranked.find((r) => !isOther(r)) || null;
  const productMass = ranked.filter((r) => !isOther(r)).reduce((s, r) => s + r.p, 0);
  return {
    top: ranked[0],
    bestProduct,
    bestOther: ranked.find(isOther) || null,
    productMass,
    // probability of the best category among product classes only (= softmax over product classes)
    categoryProb: bestProduct && productMass > 0 ? bestProduct.p / productMass : 0,
    ranked,
  };
};

// back-compatible helper: category detection over the product classes in `cats`
const detectCategory = (vec, cats) => {
  const z = zeroShot(vec, cats);
  const best = z.bestProduct || z.top;
  return {
    category: { slug: best.c.slug, name: best.c.name },
    confidence: +best.p.toFixed(3),
    top: z.ranked.slice(0, 3).map((r) => ({ slug: r.c.slug, p: r.p })),
  };
};

// the gate logic, pure so it is unit-testable and shared with the calibration script.
// bestSim: best neighbour cosine similarity (or null when unknown).
const openSetDecision = (z, bestSim, thresholds) => {
  if (z.top.c.kind === 'other') return { recognized: false, reason: 'non-product' };
  if (!z.bestProduct || z.categoryProb < thresholds.minCategoryProb) return { recognized: false, reason: 'low-confidence' };
  if (bestSim !== null && bestSim !== undefined && bestSim < thresholds.simFloor) return { recognized: false, reason: 'no-close-match' };
  return { recognized: true, reason: null };
};

// similarity -> displayed match confidence (0 at the floor, 1 at the calibrated ceiling)
const matchConfidence = (sim, thresholds) => clamp01((sim - thresholds.simFloor) / (thresholds.simCeil - thresholds.simFloor));

const TRY_HINT = 'Try a clear photo of a product — shoes, a phone, a bag…';

// what the user is told when a photo is rejected
const rejectionDetected = (z) => {
  const other = z.bestOther;
  if (other && (z.top.c.kind === 'other' || other.p >= 0.1)) {
    return { label: other.c.label, confidence: +other.p.toFixed(3), message: `This looks like ${other.c.label}, not something we sell. ${TRY_HINT}` };
  }
  return { label: 'something we could not recognize', confidence: +(1 - z.productMass).toFixed(3), message: `We couldn't spot a product we sell in this photo. ${TRY_HINT}` };
};

// best-selling categories with stock, as plain names for suggestion chips
const popularCategories = (catalog, n = 6) => {
  const sold = new Map();
  for (const p of catalog.products) {
    if (p.stock <= 0) continue;
    sold.set(p.category_slug, (sold.get(p.category_slug) || 0) + (p.sold_count || 0) + 1);
  }
  return catalog.taxonomy
    .filter((c) => sold.has(c.slug))
    .sort((a, b) => sold.get(b.slug) - sold.get(a.slug))
    .slice(0, n)
    .map((c) => c.name);
};

class VisualUnavailable extends Error {}

const ensureReady = async (catalog) => {
  const parts = await load();
  if (!parts) throw new VisualUnavailable('Visual search is unavailable right now (the image model could not be loaded).');
  const vectors = await loadVectors(catalog);
  if (vectors.size < catalog.products.length * 0.5) {
    if (!state.indexing) {
      const missing = catalog.products.filter((p) => !vectors.has(p.id));
      state.indexing = indexProducts(missing).finally(() => { state.indexing = null; });
    }
    throw new VisualUnavailable('The visual index is still being built. Please try again in a minute.');
  }
  return vectors;
};

// all in-stock neighbours by similarity (optionally skipping one product: the calibration's "non-self")
const rankByVector = (query, vectors, catalog, detected, { limit = 12, excludeId = null, minSim = -Infinity } = {}) => {
  const ranked = [];
  for (const [id, v] of vectors) {
    if (id === excludeId) continue;
    const p = catalog.byId.get(id);
    if (!p || p.stock <= 0) continue;
    const sim = dot(query, v);
    if (sim < minSim) continue;
    const catBoost = detected && detected.confidence >= 0.35 && p.category_slug === detected.category.slug ? 1 : 0;
    ranked.push({ p, sim, score: 0.85 * sim + 0.15 * catBoost });
  }
  ranked.sort((a, b) => b.score - a.score);
  return ranked.slice(0, limit);
};

const bestSimilarity = (query, vectors, catalog, excludeId = null) => {
  let best = -1;
  for (const [id, v] of vectors) {
    if (id === excludeId) continue;
    const p = catalog.byId.get(id);
    if (!p || p.stock <= 0) continue;
    const s = dot(query, v);
    if (s > best) best = s;
  }
  return best;
};

// analysis shared by the endpoint and the calibration script
const analyzeImage = async (query, catalog, vectors, { excludeId = null } = {}) => {
  const z = zeroShot(query, await classVectors(catalog));
  const bestSim = bestSimilarity(query, vectors, catalog, excludeId);
  return { z, bestSim };
};

const unrecognized = (z, catalog, started, extra = {}) => {
  const d = rejectionDetected(z);
  return {
    recognized: false,
    message: d.message,
    items: [],
    detected: { label: d.label, confidence: d.confidence, category: null, alternatives: [] },
    suggestions: popularCategories(catalog),
    latencyMs: Date.now() - started,
    ...extra,
  };
};

const visualSearch = async (buffer, { limit = 12 } = {}) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const vectors = await ensureReady(catalog);
  const thresholds = loadThresholds();
  const query = await embedImage(buffer);
  const { z, bestSim } = await analyzeImage(query, catalog, vectors);
  const decision = openSetDecision(z, bestSim, thresholds);
  if (!decision.recognized) return unrecognized(z, catalog, started, { reason: decision.reason });

  const category = { slug: z.bestProduct.c.slug, name: z.bestProduct.c.name };
  const confidence = +z.bestProduct.p.toFixed(3);
  const items = rankByVector(query, vectors, catalog, { category, confidence }, { limit, minSim: thresholds.simFloor }).map((r) => {
    const match = matchConfidence(r.sim, thresholds);
    const sameCategory = r.p.category_slug === category.slug;
    return {
      product: r.p,
      // honest: 0 at the similarity floor, 1 at a near-identical look; items outside the detected category are discounted
      score: +(match * (sameCategory ? 1 : 0.8)).toFixed(3),
      reasons: [
        `${Math.round(match * 100)}% visual match`,
        sameCategory ? `Matches detected category: ${category.name}` : null,
        r.p.rating >= 4 && r.p.rating_count >= 3 ? `Rated ${stars(r.p.rating)}` : null,
        `${money(r.p.price)}`,
      ].filter(Boolean),
    };
  });
  if (!items.length) return unrecognized(z, catalog, started, { reason: 'no-close-match' });
  return {
    recognized: true,
    message: null,
    items,
    detected: {
      label: category.name,
      category,
      confidence,
      alternatives: z.ranked.filter((r) => r.c.kind !== 'other' && r.c.slug !== category.slug).slice(0, 2).map((r) => ({ slug: r.c.slug, p: +r.p.toFixed(3) })),
    },
    suggestions: [],
    latencyMs: Date.now() - started,
  };
};

const textQuery = (q) => `a product photo of ${q}`;

const textToImage = async (q, { limit = 12 } = {}) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const vectors = await ensureReady(catalog);
  const thresholds = loadThresholds();
  const [query] = await embedTexts([textQuery(q)]);
  const ranked = rankByVector(query, vectors, catalog, null, { limit, minSim: thresholds.textSimFloor });
  if (!ranked.length) {
    return {
      recognized: false,
      message: `We couldn't find anything in the catalog that looks like “${q}”. Try naming a product — shoes, a phone, a bag…`,
      items: [],
      suggestions: popularCategories(catalog),
      latencyMs: Date.now() - started,
    };
  }
  // text->image cosines live in a narrow band (~0.2-0.35); scale relative to the calibrated floor
  const span = 0.12;
  const items = ranked.map((r) => ({
    product: r.p,
    score: +clamp01((r.sim - thresholds.textSimFloor) / span).toFixed(3),
    reasons: [`Visually matches “${q}”`, r.p.rating >= 4 && r.p.rating_count >= 3 ? `Rated ${stars(r.p.rating)}` : null].filter(Boolean),
  }));
  return { recognized: true, message: null, items, suggestions: [], latencyMs: Date.now() - started };
};

const info = async () => {
  let indexedImages = 0;
  try {
    indexedImages = Number((await models.db('product_image_embeddings').where({ model: MODEL_KEY }).count('* as n').first()).n);
  } catch {
    indexedImages = 0;
  }
  const t = loadThresholds();
  return {
    enabled: enabled() && state.status !== 'failed',
    status: state.status,
    model: MODEL_ID,
    dims: DIMS,
    indexedImages,
    error: state.error,
    openSet: {
      nonProductClasses: NON_PRODUCT_CLASSES.length,
      thresholds: { minCategoryProb: t.minCategoryProb, simFloor: t.simFloor, simCeil: t.simCeil, textSimFloor: t.textSimFloor },
      source: t.source,
      overridden: t.overridden,
      calibratedAt: t.calibratedAt,
      stale: t.stale,
    },
  };
};

module.exports = {
  visualSearch, textToImage, indexProducts, load, info, detectCategory, VisualUnavailable, MODEL_KEY, thumbnailSource,
  // open-set internals (unit tests + scripts/calibrateVisual.js)
  zeroShot, openSetDecision, matchConfidence, rejectionDetected, popularCategories, loadThresholds, classesSignature,
  embedImage, embedTexts, classVectors, loadVectors, ensureReady, analyzeImage, bestSimilarity, textQuery,
  NON_PRODUCT_CLASSES, CATEGORY_PROMPTS, TEMPLATES, THRESHOLDS_FILE, DEFAULT_THRESHOLDS, MODEL_ID,
};
