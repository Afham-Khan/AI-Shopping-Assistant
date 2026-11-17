/* npm run ai:index:visual   [-- --env <file>] [--all] [--yes]
   Fills ONLY the CLIP image vectors (product_image_embeddings) that Snap & Find needs. Nothing else is touched:
   no migrations, no seed, no text embeddings. Products that already have a vector are skipped, so it is safe to run
   again after a failure; --all recomputes every product.

     --env <file>  load the database settings from this file first (e.g. .env.neon for the hosted Neon database)
     --yes         required when the target is a hosted database (DATABASE_URL), so it cannot run there by accident
     --all         recompute vectors that already exist

   Hosted database, run once from the laptop (the models are already in backend/.cache):
     npm run ai:index:visual -- --env .env.neon --yes
   Takes a few minutes: every product thumbnail is downloaded from the image CDN and embedded locally. */
const path = require('path');
const dotenv = require('dotenv');

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const envIndex = args.indexOf('--env');
const envFile = envIndex >= 0 ? args[envIndex + 1] : null;

if (envIndex >= 0) {
  if (!envFile) {
    console.error('--env needs a file name, e.g. --env .env.neon');
    process.exit(1);
  }
  const file = path.resolve(__dirname, '..', envFile);
  const loaded = dotenv.config({ quiet: true, path: file, override: true });
  if (loaded.error) {
    console.error(`Cannot read ${file}: ${loaded.error.message}`);
    process.exit(1);
  }
}
dotenv.config({ quiet: true, path: path.join(__dirname, '..', '.env') }); // local defaults, never overrides --env

const { describeTarget, usesHostedUrl } = require('../helpers/dbConfig');

const main = async () => {
  if (process.env.AI_VISUAL === 'off') throw new Error('AI_VISUAL=off is set: unset it to build the CLIP index.');
  const target = describeTarget();
  const hosted = usesHostedUrl();
  console.log(`Target database: ${target}${hosted ? ' (hosted)' : ' (local)'}`);
  if (hosted && !flag('--yes')) {
    throw new Error('This writes CLIP vectors into a hosted database. Re-run with --yes if that is intended.');
  }

  const db = require('../api/db/connection');
  try {
    const models = require('../api/modules/ai/models/ai.models');
    const visual = require('../api/modules/ai/engine/visual');

    const rows = await models.loadCatalogRows();
    if (!rows.length) throw new Error('No products found in this database.');
    const existing = new Set((await models.loadImageEmbeddings(visual.MODEL_KEY)).map((r) => r.product_id));
    const todo = flag('--all') ? rows : rows.filter((p) => !existing.has(p.id));
    const noImage = todo.filter((p) => !visual.thumbnailSource(p)).length;
    console.log(`Products: ${rows.length}, already indexed: ${existing.size}, to index now: ${todo.length}${noImage ? ` (${noImage} without a usable thumbnail)` : ''}`);
    if (!todo.length) {
      console.log('Nothing to do: every product already has a CLIP vector.');
      return;
    }

    const { transformersCacheDir } = require('../helpers/aiCache');
    console.log(`Loading CLIP (Xenova/clip-vit-base-patch32) from ${transformersCacheDir()} (first run downloads ~150 MB)...`);
    const t0 = Date.now();
    if (!(await visual.load())) throw new Error(`CLIP unavailable: ${(await visual.info()).error}`);
    console.log(`CLIP ready in ${Date.now() - t0} ms. Embedding ${todo.length} thumbnails...`);

    const t1 = Date.now();
    let last = 0;
    await visual.indexProducts(todo, {
      onProgress: (done, total) => {
        if (done - last >= 25 || done === total) {
          last = done;
          console.log(`  ${done}/${total}`);
        }
      },
    });
    const after = (await models.loadImageEmbeddings(visual.MODEL_KEY)).length;
    console.log(`Done in ${((Date.now() - t1) / 1000).toFixed(1)}s. product_image_embeddings now holds ${after}/${rows.length} vectors.`);
    if (after < rows.length) console.log('Some thumbnails could not be read (CDN error or missing image); run the command again to retry those.');
  } finally {
    await db.destroy();
  }
};

main().catch((error) => {
  console.error(`ai:index:visual failed: ${error.message}`);
  process.exitCode = 1;
});
