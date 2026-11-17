// in-memory catalog index (lazy singleton): bm25 + tf-idf/lsa + neural vectors + precomputed stats.
// refreshed when the products signature (count + max updated_at) changes.
const models = require('../../models/ai.models');
const { BM25 } = require('./bm25');
const { VectorSpace, cosine } = require('./vectorspace');
const embeddings = require('./embeddings');
const { getVocabulary } = require('../nlu/vocab');
const { baseClean, tokenize } = require('../nlu/normalizer');

const CHECK_EVERY_MS = 60 * 1000;
const BAYES_PRIOR_COUNT = 5;

const embeddingText = (p) =>
  [
    p.title, p.brand_name, p.category_name, (p.highlights || []).join('. '), (p.tags || []).join(', '),
    p.color, p.description,
  ].filter(Boolean).join('. ');

class Catalog {
  constructor(rows, taxonomy, brands, signature) {
    this.signature = signature;
    this.products = rows;
    this.byId = new Map(rows.map((p) => [p.id, p]));
    this.taxonomy = taxonomy;
    this.brands = brands;
    this.builtAt = new Date();
    const t0 = Date.now();
    this.bm25 = new BM25().build(rows);
    this.space = new VectorSpace({ dims: 64 }).build(rows);
    this.neural = new Map();
    this.computeStats();
    this.buildMs = Date.now() - t0;
  }

  computeStats() {
    const rated = this.products.filter((p) => p.rating_count > 0);
    const total = rated.reduce((s, p) => s + p.rating_count, 0) || 1;
    this.meanRating = rated.reduce((s, p) => s + p.rating * p.rating_count, 0) / total || 3.5;
    this.maxSold = Math.max(1, ...this.products.map((p) => p.sold_count || 0));
    const sold = this.products.map((p) => p.sold_count || 0).sort((a, b) => a - b);
    this.bestsellerCut = Math.max(3, sold[Math.floor(sold.length * 0.8)] || 0);
    for (const p of this.products) {
      p._bayes = (BAYES_PRIOR_COUNT * this.meanRating + p.rating * p.rating_count) / (BAYES_PRIOR_COUNT + p.rating_count);
      p._quality = Math.min(1, Math.max(0, (p._bayes - 2.5) / 2.5));
      p._popularity = Math.log1p(p.sold_count || 0) / Math.log1p(this.maxSold);
      p._discount = Math.min(1, (p.discount_percent || 0) / 40);
      p._text = [
        p.title, p.brand_name, p.category_name, p.color, (p.tags || []).join(' '), p.search_keywords,
        (p.highlights || []).join(' '), Object.entries(p.specs || {}).map(([k, v]) => `${k} ${v}`).join(' '), p.description,
      ].join(' ').toLowerCase();
    }
  }

  get mode() {
    return this.neural.size >= this.products.length * 0.9 && embeddings.ready() ? 'neural' : 'tfidf';
  }

  vectorOf(id) {
    return this.neural.get(id) || this.space.vectorOf(id);
  }

  similarity(a, b) {
    const va = this.neural.get(a);
    const vb = this.neural.get(b);
    if (va && vb) return cosine(va, vb);
    return cosine(this.space.vectorOf(a), this.space.vectorOf(b));
  }

  // semantic relevance of every product to a free-text query
  async semanticScores(text) {
    if (!text || !text.trim()) return { mode: this.mode, scores: new Map() };
    if (this.mode === 'neural') {
      const q = await embeddings.embedQuery(text);
      if (q) {
        const scores = new Map();
        for (const [id, v] of this.neural) scores.set(id, Math.max(0, cosine(q, v)));
        return { mode: 'neural', scores };
      }
    }
    return { mode: 'tfidf', scores: this.space.scores(text) };
  }

  async attachNeural() {
    if (!embeddings.wanted()) return;
    const rows = await models.loadEmbeddings(embeddings.MODEL_KEY);
    for (const r of rows) if (this.byId.has(r.product_id) && r.vector?.length === embeddings.DIMS) this.neural.set(r.product_id, Float32Array.from(r.vector));
    const missing = this.products.filter((p) => !this.neural.has(p.id));
    // never block requests: load the model and fill gaps in the background
    embeddings.load().then(async (extractor) => {
      if (!extractor || !missing.length) return;
      try {
        const vectors = await embeddings.embed(missing.map(embeddingText));
        const upserts = missing.map((p, i) => {
          this.neural.set(p.id, vectors[i]);
          return { product_id: p.id, model: embeddings.MODEL_KEY, dims: embeddings.DIMS, vector: Array.from(vectors[i], (x) => +x.toFixed(6)) };
        });
        await models.upsertEmbeddings(upserts);
      } catch {
        // stays in tf-idf mode for the missing products
      }
    });
  }
}

let current = null;
let building = null;
let lastCheck = 0;

const syncVocabulary = (catalog) => {
  const vocab = getVocabulary();
  vocab.setTaxonomy(catalog.taxonomy);
  vocab.setBrands(catalog.brands);
  const words = new Set();
  for (const p of catalog.products) {
    const text = [p.title, p.search_keywords, (p.tags || []).join(' '), (p.highlights || []).join(' '), p.description].join(' ');
    for (const w of tokenize(baseClean(text))) if (/^[a-z]+$/.test(w)) words.add(w);
  }
  vocab.addKnownWords(words);
};

const build = async () => {
  const [signature, rows, taxonomy, brands] = await Promise.all([
    models.catalogSignature(), models.loadCatalogRows(), models.loadTaxonomy(), models.loadBrandNames(),
  ]);
  const catalog = new Catalog(rows, taxonomy, brands, signature);
  syncVocabulary(catalog);
  await catalog.attachNeural().catch(() => {});
  current = catalog;
  lastCheck = Date.now();
  return catalog;
};

const getCatalog = async () => {
  if (!current) {
    if (!building) building = build().finally(() => { building = null; });
    return building;
  }
  if (Date.now() - lastCheck > CHECK_EVERY_MS && !building) {
    lastCheck = Date.now();
    // stale-while-revalidate: answer from the current index, rebuild in the background if changed
    models.catalogSignature().then((sig) => {
      if (sig !== current.signature && !building) building = build().catch(() => current).finally(() => { building = null; });
    }).catch(() => {});
  }
  return current;
};

const refresh = async () => {
  current = null;
  return getCatalog();
};

const peek = () => current;

module.exports = { getCatalog, refresh, peek, embeddingText, Catalog };
