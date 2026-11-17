// visual search ("snap & find"): clip (vit-b/32) image embeddings for every product thumbnail,
// nearest-neighbour search for an uploaded photo, zero-shot category detection, and text->image search.
// clip loads lazily on the first visual request, never at boot.
const fs = require('fs');
const path = require('path');
const models = require('../models/ai.models');
const { getCatalog } = require('./retrieval/catalog');
const { money, stars } = require('./format');

const MODEL_ID = 'Xenova/clip-vit-base-patch32';
const MODEL_KEY = 'clip-vit-base-patch32';
const DIMS = 512;
const BACKEND_ROOT = path.join(__dirname, '../../../..');
const CACHE_DIR = path.join(BACKEND_ROOT, '.cache/transformers');

// prompt ensembles per category improve zero-shot accuracy over a single "a photo of a x"
const CATEGORY_PROMPTS = {
  smartphones: ['a smartphone', 'a mobile phone'], laptops: ['a laptop computer', 'an open notebook computer'], tablets: ['a tablet computer', 'an ipad'],
  'mobile-accessories': ['earphones or headphones', 'a phone charger or accessory', 'a smart speaker'], 'mens-shirts': ["a men's shirt", 'a t-shirt'],
  'mens-shoes': ["men's shoes", 'sneakers'], 'mens-watches': ["a men's wristwatch", 'a luxury watch'], tops: ["a women's top", 'a blouse'],
  'womens-dresses': ['a dress', 'a gown'], 'womens-shoes': ["women's shoes", 'high heels'], 'womens-bags': ['a handbag', 'a purse'],
  'womens-jewellery': ['earrings', 'jewellery'], 'womens-watches': ["a women's wristwatch"], sunglasses: ['sunglasses', 'eyeglasses'],
  beauty: ['makeup', 'lipstick or mascara', 'nail polish'], fragrances: ['a perfume bottle', 'a fragrance'], 'skin-care': ['a lotion bottle', 'skin care cream or soap'],
  furniture: ['a sofa', 'a bed', 'a chair or table'], 'home-decoration': ['a home decoration item', 'a lamp or vase'], 'kitchen-accessories': ['a kitchen utensil', 'cookware'],
  groceries: ['fresh food', 'fruits or vegetables', 'a grocery item'], 'sports-accessories': ['a sports ball', 'sports equipment'],
  motorcycle: ['a motorcycle', 'a scooter'], vehicle: ['a car', 'an suv'],
};

const state = { status: 'idle', error: null, promise: null, parts: null, vectors: null, vectorsSignature: null, categoryVecs: null, indexing: null };

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
      T.env.cacheDir = CACHE_DIR;
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

const categoryVectors = async (catalog) => {
  if (state.categoryVecs) return state.categoryVecs;
  const entries = [];
  for (const c of catalog.taxonomy) {
    const prompts = (CATEGORY_PROMPTS[c.slug] || [c.name.toLowerCase()]).map((x) => `a product photo of ${x}`);
    const vecs = await embedTexts(prompts);
    const mean = new Float32Array(DIMS);
    for (const v of vecs) for (let i = 0; i < DIMS; i += 1) mean[i] += v[i] / vecs.length;
    entries.push({ slug: c.slug, name: c.name, vec: normalize(mean) });
  }
  state.categoryVecs = entries;
  return entries;
};

// clip zero-shot: softmax over logit_scale (100) * cosine
const detectCategory = (vec, cats) => {
  const logits = cats.map((c) => 100 * dot(vec, c.vec));
  const max = Math.max(...logits);
  const exps = logits.map((l) => Math.exp(l - max));
  const sum = exps.reduce((a, b) => a + b, 0);
  const probs = exps.map((e) => e / sum);
  const best = probs.indexOf(Math.max(...probs));
  return { category: { slug: cats[best].slug, name: cats[best].name }, confidence: +probs[best].toFixed(3), top: cats.map((c, i) => ({ slug: c.slug, p: probs[i] })).sort((a, b) => b.p - a.p).slice(0, 3) };
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

const rankByVector = (query, vectors, catalog, detected, limit) => {
  const ranked = [];
  for (const [id, v] of vectors) {
    const p = catalog.byId.get(id);
    if (!p || p.stock <= 0) continue;
    const sim = dot(query, v);
    const catBoost = detected && detected.confidence >= 0.35 && p.category_slug === detected.category.slug ? 1 : 0;
    ranked.push({ p, sim, score: 0.85 * sim + 0.15 * catBoost });
  }
  ranked.sort((a, b) => b.score - a.score);
  return ranked.slice(0, limit);
};

const visualSearch = async (buffer, { limit = 12 } = {}) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const vectors = await ensureReady(catalog);
  const query = await embedImage(buffer);
  const detected = detectCategory(query, await categoryVectors(catalog));
  const items = rankByVector(query, vectors, catalog, detected, limit).map((r) => ({
    product: r.p,
    score: +Math.max(0, Math.min(1, r.score)).toFixed(3),
    reasons: [
      `Looks ${Math.round(Math.max(0, r.sim) * 100)}% similar`,
      r.p.category_slug === detected.category.slug ? `Matches detected category: ${detected.category.name}` : null,
      r.p.rating >= 4 && r.p.rating_count >= 3 ? `Rated ${stars(r.p.rating)}` : null,
      `${money(r.p.price)}`,
    ].filter(Boolean),
  }));
  return { items, detected: { category: detected.category, confidence: detected.confidence, alternatives: detected.top.slice(1) }, latencyMs: Date.now() - started };
};

const textToImage = async (q, { limit = 12 } = {}) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const vectors = await ensureReady(catalog);
  const [query] = await embedTexts([`a product photo of ${q}`]);
  const items = rankByVector(query, vectors, catalog, null, limit).map((r) => ({
    product: r.p,
    score: +Math.max(0, Math.min(1, r.sim * 3)).toFixed(3),
    reasons: [`Visually matches “${q}”`, r.p.rating >= 4 && r.p.rating_count >= 3 ? `Rated ${stars(r.p.rating)}` : null].filter(Boolean),
  }));
  return { items, latencyMs: Date.now() - started };
};

const info = async () => {
  let indexedImages = 0;
  try {
    indexedImages = Number((await models.db('product_image_embeddings').where({ model: MODEL_KEY }).count('* as n').first()).n);
  } catch {
    indexedImages = 0;
  }
  return { enabled: enabled() && state.status !== 'failed', status: state.status, model: MODEL_ID, dims: DIMS, indexedImages, error: state.error };
};

module.exports = { visualSearch, textToImage, indexProducts, load, info, detectCategory, VisualUnavailable, MODEL_KEY, thumbnailSource };
