// training pipeline shared by `npm run ai:train` and the runtime self-heal (model file missing)
const fs = require('fs');
const path = require('path');
const { normalize } = require('./normalizer');
const { getVocabulary } = require('./vocab');
const {
  maskTokens, extractFeatures, TfidfVectorizer, SoftmaxRegression, NaiveBayes, evaluate, mulberry32, shuffle,
} = require('./classifier');

const DATA_FILE = path.join(__dirname, '../../training/data/intents.json');
const MODEL_FILE = path.join(__dirname, '../../training/models/intent-model.json');

const loadDataset = (file = DATA_FILE) => {
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const samples = [];
  for (const [intent, texts] of Object.entries(json.intents)) for (const text of texts) samples.push({ text, intent });
  return samples;
};

const featurize = (text, vocab = getVocabulary()) => {
  const norm = normalize(text, { corrector: vocab.corrector, known: vocab.known });
  return { norm, feats: extractFeatures(norm.tokens, maskTokens(norm.tokens, vocab)) };
};

// per-class split keeps every intent represented in train and test
const stratifiedSplit = (samples, ratio, rand) => {
  const byClass = new Map();
  for (const s of samples) {
    if (!byClass.has(s.intent)) byClass.set(s.intent, []);
    byClass.get(s.intent).push(s);
  }
  const train = [];
  const test = [];
  for (const list of byClass.values()) {
    const shuffled = shuffle(list, rand);
    const cut = Math.max(1, Math.round(list.length * ratio));
    test.push(...shuffled.slice(0, cut));
    train.push(...shuffled.slice(cut));
  }
  return { train, test };
};

// eda-style augmentation (train split only): chat fillers, dropped filler words and injected typos
const FILLERS_BEFORE = ['please', 'hey', 'ok', 'can you', 'bhai', 'yaar', 'umm', 'so'];
const FILLERS_AFTER = ['please', 'pls', 'now', 'thanks', 'yaar', 'bhai', 'quickly'];
const DROPPABLE = new Set(['the', 'a', 'an', 'me', 'my', 'please', 'to', 'is', 'of', 'for', 'some']);

const typo = (word, rand) => {
  if (word.length < 5 || /\d/.test(word)) return word;
  const i = 1 + Math.floor(rand() * (word.length - 2));
  return rand() < 0.5
    ? word.slice(0, i) + word[i + 1] + word[i] + word.slice(i + 2)
    : word.slice(0, i) + word.slice(i + 1);
};

const augment = (samples, vocab, rand, copies = 2) => {
  const out = samples.slice();
  for (const s of samples) {
    for (let k = 0; k < copies; k += 1) {
      let words = s.text.split(/\s+/);
      const r = rand();
      if (r < 0.3) words = [FILLERS_BEFORE[Math.floor(rand() * FILLERS_BEFORE.length)], ...words];
      else if (r < 0.55) words = [...words, FILLERS_AFTER[Math.floor(rand() * FILLERS_AFTER.length)]];
      else if (r < 0.75) words = words.filter((w, i) => i === 0 || !DROPPABLE.has(w) || rand() < 0.5);
      else {
        const idx = Math.floor(rand() * words.length);
        words[idx] = typo(words[idx], rand);
      }
      const text = words.join(' ');
      if (text !== s.text) out.push({ text, intent: s.intent, feats: featurize(text, vocab).feats });
    }
  }
  return out;
};

const fitModels = (rawTrain, classes, seed, vocab = getVocabulary()) => {
  const train = augment(rawTrain, vocab, mulberry32(seed + 99));
  const vectorizer = new TfidfVectorizer().fit(train.map((s) => s.feats));
  const X = train.map((s) => vectorizer.transform(s.feats));
  const y = train.map((s) => classes.indexOf(s.intent));
  const dims = vectorizer.idf.length;
  const lr = new SoftmaxRegression({ classes, dims, seed }).fit(X, y);
  const nb = new NaiveBayes({ classes, dims }).fit(X, y);
  return { vectorizer, lr, nb };
};

const toXY = (samples, vectorizer, classes) => ({
  X: samples.map((s) => vectorizer.transform(s.feats)),
  y: samples.map((s) => classes.indexOf(s.intent)),
});

const train = ({ seed = 42, testRatio = 0.2, folds = 5, log = () => {} } = {}) => {
  const t0 = Date.now();
  const vocab = getVocabulary();
  const raw = loadDataset();
  const samples = raw.map((s) => ({ ...s, feats: featurize(s.text, vocab).feats }));
  const classes = [...new Set(samples.map((s) => s.intent))];
  const rand = mulberry32(seed);

  // 1) hold-out evaluation (+ temperature fitted on a validation slice of the train split)
  const { train: trainSet, test: testSet } = stratifiedSplit(samples, testRatio, rand);
  const { train: fitSet, test: valSet } = stratifiedSplit(trainSet, 0.15, rand);
  const calib = fitModels(fitSet, classes, seed);
  const val = toXY(valSet, calib.vectorizer, classes);
  const temperature = calib.lr.calibrate(val.X, val.y);

  const holdout = fitModels(trainSet, classes, seed);
  holdout.lr.temperature = temperature;
  const test = toXY(testSet, holdout.vectorizer, classes);
  const lrMetrics = evaluate(holdout.lr, test.X, test.y, classes);
  const nbMetrics = evaluate(holdout.nb, test.X, test.y, classes);
  log(`hold-out: logistic regression ${(lrMetrics.accuracy * 100).toFixed(1)}% | naive bayes ${(nbMetrics.accuracy * 100).toFixed(1)}%`);

  // 2) k-fold cross-validation for a more stable estimate
  const cvScores = [];
  const foldRand = mulberry32(seed + 1);
  const shuffled = shuffle(samples, foldRand);
  for (let k = 0; k < folds; k += 1) {
    const testFold = shuffled.filter((_, i) => i % folds === k);
    const trainFold = shuffled.filter((_, i) => i % folds !== k);
    const m = fitModels(trainFold, classes, seed);
    m.lr.temperature = temperature;
    const d = toXY(testFold, m.vectorizer, classes);
    cvScores.push(evaluate(m.lr, d.X, d.y, classes).accuracy);
  }
  const cvMean = cvScores.reduce((a, b) => a + b, 0) / folds;
  const cvStd = Math.sqrt(cvScores.reduce((s, v) => s + (v - cvMean) ** 2, 0) / folds);
  log(`${folds}-fold cv accuracy: ${(cvMean * 100).toFixed(1)}% ± ${(cvStd * 100).toFixed(1)}`);

  // 3) final model on all data for deployment
  const final = fitModels(samples, classes, seed);
  final.lr.temperature = temperature;

  const counts = {};
  for (const s of samples) counts[s.intent] = (counts[s.intent] || 0) + 1;
  return {
    algorithm: 'Multinomial logistic regression (softmax, SGD) over TF-IDF word uni/bi-grams + char trigrams, slot-masked, temperature-calibrated',
    version: 1,
    trainedAt: new Date().toISOString(),
    classes,
    trainingSamples: samples.length,
    samplesPerClass: counts,
    vocabularySize: final.vectorizer.idf.length,
    metrics: {
      testSize: testSet.length,
      trainSize: trainSet.length,
      testAccuracy: lrMetrics.accuracy,
      macroF1: lrMetrics.macroF1,
      ece: lrMetrics.ece,
      temperature,
      cvAccuracy: +cvMean.toFixed(4),
      cvStd: +cvStd.toFixed(4),
      baselineNaiveBayesAccuracy: nbMetrics.accuracy,
      perClass: lrMetrics.perClass,
      confusions: lrMetrics.confusions,
    },
    trainingMs: Date.now() - t0,
    vectorizer: final.vectorizer.toJSON(),
    model: final.lr.toJSON(),
  };
};

const save = (artifact, file = MODEL_FILE) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(artifact));
  return file;
};

module.exports = { train, save, featurize, loadDataset, stratifiedSplit, DATA_FILE, MODEL_FILE };
