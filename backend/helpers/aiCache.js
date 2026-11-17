// Where the AI models (MiniLM, CLIP) are cached by @huggingface/transformers.
//
//   AI_CACHE_DIR   folder for the model cache. Unset = backend/.cache (laptop, Docker image built with ai:prefetch).
//                  On Azure App Service set it to /home/.cache: /home is persistent storage, so the models are
//                  downloaded once on the first boot and survive restarts and redeploys (wwwroot is replaced on
//                  every deploy, and is read-only when running from a package).
//
// The transformers files live in <AI_CACHE_DIR>/transformers, the same layout as backend/.cache/transformers.
const path = require('path');

const DEFAULT_ROOT = path.join(__dirname, '..', '.cache');

const cacheRoot = (env = process.env) => path.resolve(String(env.AI_CACHE_DIR || '').trim() || DEFAULT_ROOT);

const transformersCacheDir = (env = process.env) => path.join(cacheRoot(env), 'transformers');

module.exports = { cacheRoot, transformersCacheDir, DEFAULT_ROOT };
