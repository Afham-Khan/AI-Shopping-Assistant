// offline semantic fallback: tf-idf vector space + latent semantic analysis (truncated svd via the
// eigen-decomposition of the document gram matrix, jacobi rotations). pure js, no model download.
const { analyzeText, productFields } = require('./bm25');

const MAX_LSA_DOCS = 600;

const docText = (p) => {
  const f = productFields(p);
  return [f.title, f.title, f.brand, f.category, f.tags, f.keywords, f.highlights, f.description].join(' ');
};

const l2 = (vec) => Math.sqrt(vec.reduce((s, v) => s + v * v, 0)) || 1;

// cyclic jacobi eigenvalue algorithm for a symmetric matrix (array of Float64Array rows)
const jacobiEigen = (input, maxSweeps = 12) => {
  const n = input.length;
  const a = input.map((row) => Float64Array.from(row));
  const v = Array.from({ length: n }, (_, i) => {
    const row = new Float64Array(n);
    row[i] = 1;
    return row;
  });
  for (let sweep = 0; sweep < maxSweeps; sweep += 1) {
    let off = 0;
    for (let p = 0; p < n; p += 1) for (let q = p + 1; q < n; q += 1) off += a[p][q] * a[p][q];
    if (off < 1e-10) break;
    for (let p = 0; p < n - 1; p += 1) {
      for (let q = p + 1; q < n; q += 1) {
        const apq = a[p][q];
        if (Math.abs(apq) < 1e-12) continue;
        const theta = (a[q][q] - a[p][p]) / (2 * apq);
        const t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
        const c = 1 / Math.sqrt(t * t + 1);
        const s = t * c;
        for (let k = 0; k < n; k += 1) {
          const akp = a[k][p];
          const akq = a[k][q];
          a[k][p] = c * akp - s * akq;
          a[k][q] = s * akp + c * akq;
        }
        for (let k = 0; k < n; k += 1) {
          const apk = a[p][k];
          const aqk = a[q][k];
          a[p][k] = c * apk - s * aqk;
          a[q][k] = s * apk + c * aqk;
        }
        for (let k = 0; k < n; k += 1) {
          const vkp = v[k][p];
          const vkq = v[k][q];
          v[k][p] = c * vkp - s * vkq;
          v[k][q] = s * vkp + c * vkq;
        }
      }
    }
  }
  const values = a.map((row, i) => row[i]);
  return { values, vectors: v }; // eigenvector j is column j of v
};

class VectorSpace {
  constructor({ dims = 64 } = {}) {
    this.targetDims = dims;
  }

  build(products) {
    const docs = products.map((p) => {
      const tf = new Map();
      for (const t of analyzeText(docText(p))) tf.set(t, (tf.get(t) || 0) + 1);
      return tf;
    });
    const N = docs.length;
    const df = new Map();
    for (const d of docs) for (const t of d.keys()) df.set(t, (df.get(t) || 0) + 1);
    this.idf = new Map([...df].map(([t, n]) => [t, Math.log((1 + N) / (1 + n)) + 1]));
    this.ids = products.map((p) => p.id);
    this.indexOf = new Map(this.ids.map((id, i) => [id, i]));
    this.tfidf = docs.map((d) => this.weigh(d));
    this.buildLsa();
    return this;
  }

  // sparse map -> l2-normalized tf-idf map
  weigh(tf) {
    const out = new Map();
    let norm = 0;
    for (const [t, f] of tf) {
      const idf = this.idf.get(t);
      if (!idf) continue;
      const w = (1 + Math.log(f)) * idf;
      out.set(t, w);
      norm += w * w;
    }
    norm = Math.sqrt(norm) || 1;
    for (const [t, w] of out) out.set(t, w / norm);
    return out;
  }

  static sparseDot(a, b) {
    const [small, large] = a.size < b.size ? [a, b] : [b, a];
    let s = 0;
    for (const [t, w] of small) {
      const o = large.get(t);
      if (o) s += w * o;
    }
    return s;
  }

  buildLsa() {
    const n = this.tfidf.length;
    this.lsa = null;
    if (n < 3 || n > MAX_LSA_DOCS) return;
    const gram = Array.from({ length: n }, () => new Float64Array(n));
    for (let i = 0; i < n; i += 1) {
      for (let j = i; j < n; j += 1) {
        const d = VectorSpace.sparseDot(this.tfidf[i], this.tfidf[j]);
        gram[i][j] = d;
        gram[j][i] = d;
      }
    }
    const { values, vectors } = jacobiEigen(gram);
    const order = values.map((v, i) => [v, i]).filter(([v]) => v > 1e-8).sort((a, b) => b[0] - a[0]);
    const k = Math.min(this.targetDims, order.length);
    const comps = order.slice(0, k);
    // u: n x k basis, s: singular values
    this.u = comps.map(([, j]) => Float64Array.from(vectors, (row) => row[j]));
    this.s = comps.map(([v]) => Math.sqrt(v));
    // document coordinates = u * s, normalized for cosine
    this.lsa = Array.from({ length: n }, (_, i) => {
      const vec = Float32Array.from(this.u.map((col, c) => col[i] * this.s[c]));
      const norm = l2(vec);
      return vec.map((x) => x / norm);
    });
    this.dims = k;
  }

  queryVector(text) {
    const tf = new Map();
    for (const t of analyzeText(text)) tf.set(t, (tf.get(t) || 0) + 1);
    return this.weigh(tf);
  }

  // fold a query into lsa space: q_k = (q . X^T) U S^-1
  foldIn(qTfidf) {
    if (!this.lsa) return null;
    const dots = this.tfidf.map((d) => VectorSpace.sparseDot(qTfidf, d));
    const vec = Float32Array.from(this.u.map((col, c) => col.reduce((s, u, i) => s + u * dots[i], 0) / this.s[c]));
    const norm = l2(vec);
    return norm > 1e-9 ? vec.map((x) => x / norm) : null;
  }

  // blended cosine (lexical tf-idf + latent lsa) for every product
  scores(text) {
    const q = this.queryVector(text);
    const out = new Map();
    if (!q.size) return out;
    const qk = this.foldIn(q);
    this.ids.forEach((id, i) => {
      const lexical = VectorSpace.sparseDot(q, this.tfidf[i]);
      const latent = qk ? Math.max(0, cosine(qk, this.lsa[i])) : lexical;
      out.set(id, 0.5 * lexical + 0.5 * latent);
    });
    return out;
  }

  vectorOf(id) {
    const i = this.indexOf.get(id);
    return i === undefined || !this.lsa ? null : this.lsa[i];
  }
}

const cosine = (a, b) => {
  if (!a || !b) return 0;
  let s = 0;
  for (let i = 0; i < a.length; i += 1) s += a[i] * b[i];
  return s;
};

module.exports = { VectorSpace, jacobiEigen, cosine, docText };
