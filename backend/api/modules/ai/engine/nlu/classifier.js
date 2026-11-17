// intent classifier: tf-idf features (word uni/bi-grams over slot-masked tokens + char trigrams)
// -> multinomial logistic regression trained with sgd, temperature-scaled for calibrated confidence.
// a multinomial naive bayes baseline is trained alongside for comparison.

const ORDINALS = new Set(['first', 'second', 'third', 'fourth', 'fifth', 'last', '1st', '2nd', '3rd', '4th', '5th']);
const MASKS = {
  brand: '__brand__', category: '__product__', generic: '__product__', department: '__product__', color: '__color__',
  recipient: '__person__', gender: '__person__', occasion: '__occasion__', feature: '__feature__',
};
const CHAR_WEIGHT = 0.4;

// gazetteer features: words that signal an intent family, so unseen synonyms still generalize
const CUE_GROUPS = {
  cheap: 'cheap cheaper cheapest affordable economical inexpensive low lower less budget pocket reduce sasta afford costly pricey',
  premium: 'premium expensive pricier costlier luxury luxurious upscale fancy fancier flagship pro elite classier higher upgrade high end tier quality best',
  deal: 'deal deals discount discounts discounted sale sales offer offers coupon coupons promo promotion promotions voucher bargain bargains savings clearance cashback drops',
  order: 'order orders delivery delivered track tracking shipped dispatch dispatched parcel package arrive arrived shipping status late delayed',
  cart: 'cart basket bag checkout total subtotal bill owe',
  ret: 'return returns refund refunds exchange warranty cancel replacement defective damaged broken guarantee',
  more: 'more else other others another next additional rest continue alternatives different load',
  cmp: 'compare comparison vs versus difference better between which pros cons',
  info: 'details detail specs specifications describe info information about review reviews include size ram battery warranty',
  gift: 'gift present surprise birthday anniversary wedding eid valentine graduation housewarming farewell christmas',
  bye: 'bye goodbye later leaving night farewell done finished exit quit stop end signing',
  hi: 'hi hello hey salam morning evening afternoon greetings sup yo howdy hiya',
  thx: 'thanks thank appreciate appreciated helpful cheers jazakallah',
  help: 'help capable capabilities features use work guide instructions commands menu abilities purpose',
  bot: 'you your yourself bot human ai robot',
  add: 'add put take buy purchase lelo basket',
  offtopic: 'weather joke song music news poem movie score minister capital python homework dinner cook dance sing married sleep feelings bored lol haha hmm wow',
  general: 'won match cricket football election president politics translate assignment essay code coding javascript bitcoin crypto recipe netflix drama planet population invented alarm flight uber rain temperature mausam barish khabar medicine headache stock gold',
  whoami: 'made created built developed creator programmed owner company chatgpt gpt gemini google siri alexa openai model trained artificial intelligence robot human real name kaun banaya technology brain',
  feel: 'sad unhappy lonely alone depressed upset stressed stress anxious anxiety worried nervous tired exhausted angry frustrated heartbroken crying hopeless scared udaas udaasi pareshan tension mood khush excited happy',
  insult: 'stupid idiot useless dumb trash rubbish pathetic garbage worst suck hate annoying nonsense bakwas pagal bewakoof bekaar shut chup lost waste fuck damn wtf',
  storefaq: 'cod cash pay paying payment payments paymnt jazzcash easypaisa card cards accept charges fee fees international abroad outside dubai physical visit hours open sunday contact support customer care complaint human sell categories lahore karachi islamabad quetta peshawar multan days',
};
const CUES = new Map();
for (const [cue, words] of Object.entries(CUE_GROUPS)) for (const w of words.split(' ')) if (!CUES.has(w)) CUES.set(w, cue);

// deterministic prng so training runs are reproducible
const mulberry32 = (seed) => () => {
  let t = (seed += 0x6d2b79f5);
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const shuffle = (arr, rand) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

// tokens -> masked token list (entities replaced by their type)
const maskTokens = (tokens, vocab) => {
  const out = tokens.map((t) => {
    if (/^\$?\d+(?:\.\d+)?(?:k|l|m|lac|lakh|lakhs)$/.test(t) || t.startsWith('$')) return '__money__';
    if (ORDINALS.has(t)) return t;
    if (/^\d+(?:\.\d+)?$/.test(t)) return Number(t) >= 500 ? '__money__' : '__num__';
    return t;
  });
  if (vocab) {
    for (const m of vocab.spot(tokens)) {
      const type = m.annotations.find((a) => MASKS[a.type] && a.type !== 'sort');
      if (!type) continue;
      out[m.start] = MASKS[type.type];
      for (let k = m.start + 1; k < m.end; k += 1) out[k] = null;
    }
  }
  return out.filter(Boolean);
};

// raw feature counts for one utterance
const extractFeatures = (tokens, masked) => {
  const feats = new Map();
  const add = (key, w = 1) => feats.set(key, (feats.get(key) || 0) + w);
  const seq = ['<s>', ...masked, '</s>'];
  masked.forEach((t) => add(`w:${t}`));
  for (let i = 0; i < seq.length - 1; i += 1) add(`b:${seq[i]}_${seq[i + 1]}`);
  for (const t of tokens) {
    const cue = CUES.get(t) || CUES.get(t.replace(/s$/, ''));
    if (cue) add(`g:${cue}`);
  }
  if (tokens.length <= 2) add(`len:${tokens.length}`);
  for (const t of tokens) {
    if (t.length < 4 || /\d/.test(t)) continue;
    const padded = `#${t}#`;
    for (let i = 0; i < padded.length - 2; i += 1) add(`c:${padded.slice(i, i + 3)}`, CHAR_WEIGHT);
  }
  return feats;
};

class TfidfVectorizer {
  fit(docs, { minDf = 1, minCharDf = 2 } = {}) {
    const df = new Map();
    for (const d of docs) for (const k of d.keys()) df.set(k, (df.get(k) || 0) + 1);
    this.index = new Map();
    this.idf = [];
    const n = docs.length;
    for (const [k, count] of df) {
      if (count < (k.startsWith('c:') ? minCharDf : minDf)) continue;
      this.index.set(k, this.idf.length);
      this.idf.push(Math.log((1 + n) / (1 + count)) + 1);
    }
    return this;
  }

  transform(feats) {
    const vec = [];
    let norm = 0;
    for (const [k, tf] of feats) {
      const idx = this.index.get(k);
      if (idx === undefined) continue;
      // sublinear tf; fractional (char-gram) weights stay linear
      const v = (tf >= 1 ? 1 + Math.log(tf) : tf) * this.idf[idx];
      vec.push([idx, v]);
      norm += v * v;
    }
    norm = Math.sqrt(norm) || 1;
    return vec.map(([i, v]) => [i, v / norm]);
  }

  toJSON() {
    return { features: [...this.index.keys()], idf: this.idf.map((v) => +v.toFixed(5)) };
  }

  static fromJSON({ features, idf }) {
    const v = new TfidfVectorizer();
    v.index = new Map(features.map((f, i) => [f, i]));
    v.idf = idf;
    return v;
  }
}

const softmax = (logits, temperature = 1) => {
  const max = Math.max(...logits);
  const exps = logits.map((z) => Math.exp((z - max) / temperature));
  const sum = exps.reduce((a, b) => a + b, 0);
  return exps.map((e) => e / sum);
};

class SoftmaxRegression {
  constructor({ classes, dims, epochs = 60, lr = 0.6, l2 = 1e-5, seed = 7 } = {}) {
    Object.assign(this, { classes, dims, epochs, lr, l2, seed, temperature: 1 });
  }

  logits(x) {
    const C = this.classes.length;
    const out = this.bias.slice();
    for (const [i, v] of x) {
      const row = i * C;
      for (let c = 0; c < C; c += 1) out[c] += this.W[row + c] * v;
    }
    return out;
  }

  fit(X, y) {
    const C = this.classes.length;
    this.W = new Float64Array(this.dims * C);
    this.bias = new Array(C).fill(0);
    const rand = mulberry32(this.seed);
    const order = X.map((_, i) => i);
    for (let epoch = 0; epoch < this.epochs; epoch += 1) {
      const lr = this.lr / (1 + epoch * 0.08);
      for (const n of shuffle(order, rand)) {
        const x = X[n];
        const p = softmax(this.logits(x));
        for (let c = 0; c < C; c += 1) {
          const g = p[c] - (y[n] === c ? 1 : 0);
          if (Math.abs(g) < 1e-6) continue;
          this.bias[c] -= lr * g;
          for (const [i, v] of x) {
            const k = i * C + c;
            this.W[k] -= lr * (g * v + this.l2 * this.W[k]);
          }
        }
      }
    }
    return this;
  }

  predictProba(x, temperature = this.temperature) {
    return softmax(this.logits(x), temperature);
  }

  // temperature scaling: pick t minimizing negative log-likelihood on held-out data
  calibrate(X, y) {
    let best = { t: 1, nll: Infinity };
    for (let t = 0.25; t <= 3.01; t += 0.05) {
      let nll = 0;
      X.forEach((x, n) => {
        nll -= Math.log(Math.max(1e-12, this.predictProba(x, t)[y[n]]));
      });
      if (nll < best.nll) best = { t: +t.toFixed(2), nll };
    }
    this.temperature = best.t;
    return best.t;
  }

  toJSON() {
    const C = this.classes.length;
    // store sparse non-zero weights to keep the artifact small
    const weights = [];
    for (let i = 0; i < this.dims; i += 1) {
      for (let c = 0; c < C; c += 1) {
        const w = this.W[i * C + c];
        if (Math.abs(w) >= 5e-4) weights.push(i, c, +w.toFixed(4));
      }
    }
    return { classes: this.classes, dims: this.dims, bias: this.bias.map((b) => +b.toFixed(4)), temperature: this.temperature, weights };
  }

  static fromJSON(json) {
    const m = new SoftmaxRegression({ classes: json.classes, dims: json.dims });
    const C = json.classes.length;
    m.W = new Float64Array(json.dims * C);
    for (let k = 0; k < json.weights.length; k += 3) m.W[json.weights[k] * C + json.weights[k + 1]] = json.weights[k + 2];
    m.bias = json.bias;
    m.temperature = json.temperature || 1;
    return m;
  }
}

// baseline: multinomial naive bayes over the same sparse features
class NaiveBayes {
  constructor({ classes, dims, alpha = 0.3 }) {
    Object.assign(this, { classes, dims, alpha });
  }

  fit(X, y) {
    const C = this.classes.length;
    const counts = Array.from({ length: C }, () => new Float64Array(this.dims));
    const totals = new Array(C).fill(0);
    const docs = new Array(C).fill(0);
    X.forEach((x, n) => {
      docs[y[n]] += 1;
      for (const [i, v] of x) {
        counts[y[n]][i] += v;
        totals[y[n]] += v;
      }
    });
    this.logPrior = docs.map((d) => Math.log(d / X.length));
    this.logLik = counts.map((row, c) => Array.from(row, (v) => Math.log((v + this.alpha) / (totals[c] + this.alpha * this.dims))));
    return this;
  }

  predictProba(x) {
    const scores = this.logPrior.map((p, c) => x.reduce((s, [i, v]) => s + v * this.logLik[c][i], p));
    return softmax(scores);
  }
}

const argmax = (arr) => arr.reduce((best, v, i) => (v > arr[best] ? i : best), 0);

// accuracy, macro-f1, per-class precision/recall, top confusions and expected calibration error
const evaluate = (model, X, y, classes) => {
  const C = classes.length;
  const confusion = Array.from({ length: C }, () => new Array(C).fill(0));
  const bins = Array.from({ length: 10 }, () => ({ n: 0, conf: 0, correct: 0 }));
  let correct = 0;
  X.forEach((x, n) => {
    const p = model.predictProba(x);
    const pred = argmax(p);
    confusion[y[n]][pred] += 1;
    if (pred === y[n]) correct += 1;
    const bin = bins[Math.min(9, Math.floor(p[pred] * 10))];
    bin.n += 1;
    bin.conf += p[pred];
    bin.correct += pred === y[n] ? 1 : 0;
  });
  const perClass = {};
  let f1Sum = 0;
  classes.forEach((name, c) => {
    const tp = confusion[c][c];
    const fp = confusion.reduce((s, row, r) => s + (r !== c ? row[c] : 0), 0);
    const fn = confusion[c].reduce((s, v, k) => s + (k !== c ? v : 0), 0);
    const precision = tp + fp ? tp / (tp + fp) : 0;
    const recall = tp + fn ? tp / (tp + fn) : 0;
    const f1 = precision + recall ? (2 * precision * recall) / (precision + recall) : 0;
    f1Sum += f1;
    perClass[name] = { precision: +precision.toFixed(3), recall: +recall.toFixed(3), f1: +f1.toFixed(3), support: tp + fn };
  });
  const confusions = [];
  confusion.forEach((row, r) => row.forEach((v, c) => {
    if (r !== c && v) confusions.push({ actual: classes[r], predicted: classes[c], count: v });
  }));
  confusions.sort((a, b) => b.count - a.count);
  const ece = bins.reduce((s, b) => s + (b.n ? (b.n / X.length) * Math.abs(b.conf / b.n - b.correct / b.n) : 0), 0);
  return {
    accuracy: +(correct / X.length).toFixed(4),
    macroF1: +(f1Sum / C).toFixed(4),
    ece: +ece.toFixed(4),
    perClass,
    confusions: confusions.slice(0, 10),
  };
};

module.exports = {
  maskTokens, extractFeatures, TfidfVectorizer, SoftmaxRegression, NaiveBayes, evaluate, softmax, argmax, mulberry32, shuffle,
};
