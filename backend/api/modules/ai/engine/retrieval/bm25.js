// okapi bm25 over field-weighted product documents
const { baseClean, tokenize, stem } = require('../nlu/normalizer');
const { STOPWORDS } = require('../nlu/lexicon');

const analyzeText = (text) =>
  tokenize(baseClean(text)).filter((t) => t.length > 1 && !STOPWORDS.has(t)).map(stem);

// fields repeated by weight so title/brand matches count more than description matches
const FIELD_WEIGHTS = { title: 3, brand: 2, category: 2, tags: 2, keywords: 1, highlights: 1, specs: 1, description: 1 };

const productFields = (p) => ({
  title: p.title,
  brand: p.brand_name || '',
  category: `${p.category_name || ''} ${p.department_name || ''}`,
  tags: (p.tags || []).join(' '),
  keywords: p.search_keywords || '',
  highlights: (p.highlights || []).join('. '),
  specs: Object.entries(p.specs || {}).map(([k, v]) => `${k} ${v}`).join('. '),
  description: `${p.description || ''} ${p.color || ''}`,
});

class BM25 {
  constructor({ k1 = 1.2, b = 0.75 } = {}) {
    this.k1 = k1;
    this.b = b;
  }

  build(products) {
    this.docs = products.map((p) => {
      const tf = new Map();
      let len = 0;
      for (const [field, text] of Object.entries(productFields(p))) {
        const w = FIELD_WEIGHTS[field];
        for (const t of analyzeText(text)) {
          tf.set(t, (tf.get(t) || 0) + w);
          len += w;
        }
      }
      return { id: p.id, tf, len };
    });
    this.N = this.docs.length;
    this.avgLen = this.docs.reduce((s, d) => s + d.len, 0) / (this.N || 1);
    this.df = new Map();
    for (const d of this.docs) for (const t of d.tf.keys()) this.df.set(t, (this.df.get(t) || 0) + 1);
    this.byId = new Map(this.docs.map((d) => [d.id, d]));
    return this;
  }

  idf(term) {
    const df = this.df.get(term) || 0;
    return Math.log(1 + (this.N - df + 0.5) / (df + 0.5));
  }

  // terms: Map(term -> query weight); returns Map(id -> score)
  score(terms, ids = null) {
    const scores = new Map();
    const docs = ids ? ids.map((id) => this.byId.get(id)).filter(Boolean) : this.docs;
    const prepared = [...terms].map(([t, w]) => [t, w, this.idf(t)]).filter(([, , idf]) => idf > 0);
    for (const d of docs) {
      let s = 0;
      for (const [t, w, idf] of prepared) {
        const f = d.tf.get(t);
        if (!f) continue;
        s += w * idf * ((f * (this.k1 + 1)) / (f + this.k1 * (1 - this.b + (this.b * d.len) / this.avgLen)));
      }
      if (s > 0) scores.set(d.id, s);
    }
    return scores;
  }

  // does the product text contain a (multi-word) phrase?
  has(id, term) {
    return Boolean(this.byId.get(id)?.tf.get(term));
  }

  vocabulary() {
    return [...this.df.keys()];
  }
}

module.exports = { BM25, analyzeText, productFields };
