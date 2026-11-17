/* npm run ai:prefetch
   Downloads the AI models (MiniLM ~23 MB, CLIP ~150 MB unless AI_VISUAL=off) into backend/.cache once, so the first
   request after a deploy does not wait for them. Used while building the Docker image. Never fails the build:
   when a download fails the API simply downloads the model later, or falls back to TF-IDF search. */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const seconds = (since) => `${((Date.now() - since) / 1000).toFixed(1)}s`;

const main = async () => {
  const embeddings = require('../api/modules/ai/engine/retrieval/embeddings');
  if (embeddings.wanted()) {
    const started = Date.now();
    console.log(`Prefetching ${embeddings.MODEL_ID}...`);
    const extractor = await embeddings.load();
    console.log(extractor ? `  ready in ${seconds(started)}` : `  not available (${embeddings.info().error}); the API will retry at runtime`);
  } else {
    console.log('AI_EMBEDDINGS=tfidf: no neural model to prefetch.');
  }

  if (process.env.AI_VISUAL === 'off') {
    console.log('AI_VISUAL=off: skipping CLIP.');
    return;
  }
  const started = Date.now();
  console.log('Prefetching Xenova/clip-vit-base-patch32 (Snap & Find)...');
  const visual = require('../api/modules/ai/engine/visual');
  console.log((await visual.load()) ? `  ready in ${seconds(started)}` : '  not available; Snap & Find will retry at runtime');
};

main()
  .catch((error) => console.warn(`Model prefetch skipped: ${error.message}`))
  .finally(() => process.exit(0));
