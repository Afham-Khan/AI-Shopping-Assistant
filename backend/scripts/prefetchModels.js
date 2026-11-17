/* npm run ai:prefetch   [-- --strict]
   Downloads the AI models (MiniLM ~23 MB, CLIP ~150 MB unless AI_VISUAL=off) into the model cache once, so the first
   request after a deploy does not wait for them. The cache is backend/.cache, or AI_CACHE_DIR when set (Azure uses
   /home/.cache). Used while building the Docker image, and by the Azure workflow as a smoke test of the bundle.
   Never fails by default: when a download fails the API simply downloads the model later, or falls back to TF-IDF
   search. With --strict it exits with code 1 when a wanted model cannot be loaded (CI uses this). */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const strict = process.argv.includes('--strict');
const seconds = (since) => `${((Date.now() - since) / 1000).toFixed(1)}s`;

const main = async () => {
  const { transformersCacheDir } = require('../helpers/aiCache');
  console.log(`Model cache: ${transformersCacheDir()}`);
  let failed = 0;

  const embeddings = require('../api/modules/ai/engine/retrieval/embeddings');
  if (embeddings.wanted()) {
    const started = Date.now();
    console.log(`Prefetching ${embeddings.MODEL_ID}...`);
    const extractor = await embeddings.load();
    if (!extractor) failed += 1;
    console.log(extractor ? `  ready in ${seconds(started)}` : `  not available (${embeddings.info().error}); the API will retry at runtime`);
  } else {
    console.log('AI_EMBEDDINGS=tfidf: no neural model to prefetch.');
  }

  if (process.env.AI_VISUAL === 'off') {
    console.log('AI_VISUAL=off: skipping CLIP.');
  } else {
    const started = Date.now();
    console.log('Prefetching Xenova/clip-vit-base-patch32 (Snap & Find)...');
    const visual = require('../api/modules/ai/engine/visual');
    const parts = await visual.load();
    if (!parts) failed += 1;
    console.log(parts ? `  ready in ${seconds(started)}` : `  not available (${(await visual.info()).error}); Snap & Find will retry at runtime`);
  }
  return failed;
};

main()
  .then((failed) => {
    if (strict && failed) {
      console.error(`${failed} model(s) could not be loaded (--strict).`);
      process.exit(1);
    }
    process.exit(0);
  })
  .catch((error) => {
    console.warn(`Model prefetch skipped: ${error.message}`);
    process.exit(strict ? 1 : 0);
  });
