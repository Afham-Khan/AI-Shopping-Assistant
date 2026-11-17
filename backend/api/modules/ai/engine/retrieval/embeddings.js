// neural sentence embeddings (all-MiniLM-L6-v2 via transformers.js / onnxruntime), loaded lazily once.
// everything degrades to the tf-idf/lsa space when the model is disabled, missing or still loading.
const { transformersCacheDir } = require('../../../../../helpers/aiCache');

const MODEL_ID = 'Xenova/all-MiniLM-L6-v2';
const MODEL_KEY = 'all-MiniLM-L6-v2';
const DIMS = 384;

const state = { status: 'idle', error: null, loadMs: null, extractor: null, promise: null };
const queryCache = new Map();

const wanted = () => (process.env.AI_EMBEDDINGS || 'neural').toLowerCase() !== 'tfidf';

const load = () => {
  if (!wanted()) {
    state.status = 'disabled';
    return Promise.resolve(null);
  }
  if (state.promise) return state.promise;
  state.status = 'loading';
  const started = Date.now();
  state.promise = (async () => {
    try {
      const { pipeline, env } = require('@huggingface/transformers');
      env.cacheDir = transformersCacheDir(); // AI_CACHE_DIR (e.g. /home/.cache on Azure) or backend/.cache
      // offline-first: use the cached model when present, download only once
      if (process.env.AI_OFFLINE === 'true') env.allowRemoteModels = false;
      state.extractor = await pipeline('feature-extraction', MODEL_ID, { dtype: 'q8' });
      state.status = 'ready';
      state.loadMs = Date.now() - started;
      return state.extractor;
    } catch (error) {
      state.status = 'failed';
      state.error = error.message;
      return null;
    }
  })();
  return state.promise;
};

const ready = () => state.status === 'ready';

const truncate = (text, max = 1000) => (text.length > max ? text.slice(0, max) : text);

// batch embed -> array of Float32Array (mean pooled, l2 normalized)
const embed = async (texts, { batchSize = 16 } = {}) => {
  const extractor = await load();
  if (!extractor) throw new Error(`neural embeddings unavailable (${state.error || state.status})`);
  const out = [];
  for (let i = 0; i < texts.length; i += batchSize) {
    const batch = texts.slice(i, i + batchSize).map((t) => truncate(t));
    const tensor = await extractor(batch, { pooling: 'mean', normalize: true });
    const data = tensor.data;
    for (let k = 0; k < batch.length; k += 1) out.push(Float32Array.from(data.subarray(k * DIMS, (k + 1) * DIMS)));
  }
  return out;
};

// query embedding with a small lru; null when the model is not ready (caller falls back)
const embedQuery = async (text) => {
  if (!ready() || !text) return null;
  const key = text.toLowerCase().trim();
  if (queryCache.has(key)) return queryCache.get(key);
  try {
    const [vec] = await embed([key]);
    queryCache.set(key, vec);
    if (queryCache.size > 200) queryCache.delete(queryCache.keys().next().value);
    return vec;
  } catch {
    return null;
  }
};

const info = () => ({ model: MODEL_ID, key: MODEL_KEY, dims: DIMS, status: state.status, loadMs: state.loadMs, error: state.error });

module.exports = { load, ready, embed, embedQuery, info, wanted, MODEL_KEY, MODEL_ID, DIMS };
