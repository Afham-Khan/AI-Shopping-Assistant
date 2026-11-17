// nlu facade: normalize -> entities -> intent (trained model, entity-driven fallback when unsure)
const fs = require('fs');
const { normalize } = require('./normalizer');
const { extractEntities } = require('./entities');
const { getVocabulary } = require('./vocab');
const { maskTokens, extractFeatures, TfidfVectorizer, SoftmaxRegression } = require('./classifier');
const trainer = require('./trainer');

const CONFIDENCE_THRESHOLD = 0.45;
let loaded = null;

// loads the trained artifact; retrains in-process if it is missing or corrupt
const loadModel = () => {
  if (loaded) return loaded;
  let artifact = null;
  try {
    artifact = JSON.parse(fs.readFileSync(trainer.MODEL_FILE, 'utf8'));
  } catch {
    artifact = trainer.train();
    try {
      trainer.save(artifact);
    } catch {
      // read-only deploys still work with the in-memory model
    }
  }
  loaded = {
    artifact,
    vectorizer: TfidfVectorizer.fromJSON(artifact.vectorizer),
    model: SoftmaxRegression.fromJSON(artifact.model),
  };
  return loaded;
};

const modelInfo = () => {
  const { artifact } = loadModel();
  return {
    algorithm: artifact.algorithm,
    classes: artifact.classes,
    trainingSamples: artifact.trainingSamples,
    vocabularySize: artifact.vocabularySize,
    testAccuracy: artifact.metrics.testAccuracy,
    macroF1: artifact.metrics.macroF1,
    cvAccuracy: artifact.metrics.cvAccuracy,
    baselineNaiveBayesAccuracy: artifact.metrics.baselineNaiveBayesAccuracy,
    calibration: { method: 'temperature scaling', temperature: artifact.metrics.temperature, ece: artifact.metrics.ece },
    trainedAt: artifact.trainedAt,
  };
};

const classify = (tokens, vocab) => {
  const { vectorizer, model } = loadModel();
  const masked = maskTokens(tokens, vocab);
  const x = vectorizer.transform(extractFeatures(tokens, masked));
  const probs = model.predictProba(x);
  // out-of-vocabulary input (gibberish, other languages) should not look confident
  const coverage = masked.filter((t) => vectorizer.index.has(`w:${t}`)).length / (masked.length || 1);
  const damp = coverage === 0 ? 0.3 : 1;
  return model.classes
    .map((intent, i) => ({ intent, confidence: +(probs[i] * damp).toFixed(4) }))
    .sort((a, b) => b.confidence - a.confidence);
};

const hasProductSignal = (e) => Boolean(e.category || e.department || e.brands.length || e.features.length || e.keywords.length || e.color);

// when the model is unsure, entities usually reveal what the user wants
const inferFromEntities = (e, tokens) => {
  const has = (...words) => words.some((w) => tokens.includes(w));
  const ord = e.ordinals.indices.length > 0 || e.ordinals.all;
  if (ord && has('compare', 'vs', 'versus', 'difference', 'better')) return 'compare';
  if ((ord || e.ordinals.pronoun) && has('cart', 'add', 'buy', 'take')) return 'add_to_cart';
  if (ord) return 'product_info';
  if (has('gift', 'present') || (e.recipient && !hasProductSignal(e))) return 'gift_suggestion';
  if (e.excludeBrands.length || e.excludeColors.length) return 'refine_filter';
  if (hasProductSignal(e)) return 'product_search';
  if (e.budget) return 'budget_query';
  return null;
};

const analyze = (text) => {
  const started = process.hrtime.bigint();
  const vocab = getVocabulary();
  const norm = normalize(text, { corrector: vocab.corrector, known: vocab.known });
  const entities = extractEntities(norm, vocab);
  const ranked = norm.tokens.length ? classify(norm.tokens, vocab) : [{ intent: 'small_talk', confidence: 0 }];
  let { intent, confidence } = ranked[0];
  let source = 'model';
  if (confidence < CONFIDENCE_THRESHOLD) {
    const inferred = inferFromEntities(entities, norm.tokens);
    if (inferred) {
      source = 'entities';
      if (inferred !== intent) {
        intent = inferred;
        confidence = Math.max(confidence, ranked.find((r) => r.intent === inferred)?.confidence || 0);
      }
    } else {
      source = 'low_confidence';
    }
  }
  return {
    intent,
    confidence,
    source,
    alternatives: ranked.filter((r) => r.intent !== intent).slice(0, 3),
    entities,
    tokens: norm.tokens,
    normalized: norm.text,
    corrections: norm.corrections,
    latencyMs: Number(process.hrtime.bigint() - started) / 1e6,
  };
};

// public entity shape (api contract keys first, extras after)
const publicEntities = (e) => ({
  department: e.department,
  category: e.category,
  brands: e.brands,
  budget: e.budget,
  gender: e.gender,
  color: e.color,
  features: e.features,
  minRating: e.minRating,
  sort: e.sort,
  occasion: e.occasion,
  recipient: e.recipient,
  categories: e.categories,
  excludeBrands: e.excludeBrands,
  excludeColors: e.excludeColors,
  keywords: e.keywords,
  ordinals: e.ordinals.indices.length || e.ordinals.all ? e.ordinals : null,
});

module.exports = { analyze, modelInfo, loadModel, publicEntities, CONFIDENCE_THRESHOLD };
