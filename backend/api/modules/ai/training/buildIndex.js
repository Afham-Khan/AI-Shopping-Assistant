// npm run ai:index — computes product embeddings into product_embeddings (neural when available)
require('dotenv').config({ quiet: true });
const db = require('../../../db/connection');
const models = require('../models/ai.models');
const embeddings = require('../engine/retrieval/embeddings');
const { Catalog, embeddingText } = require('../engine/retrieval/catalog');

const main = async () => {
  const started = Date.now();
  const [signature, rows, taxonomy, brands] = await Promise.all([
    models.catalogSignature(), models.loadCatalogRows(), models.loadTaxonomy(), models.loadBrandNames(),
  ]);
  if (!rows.length) throw new Error('No products found. Run `npm run db:seed` first.');
  console.log(`Catalog: ${rows.length} products, ${taxonomy.length} categories, ${brands.length} brands`);

  const catalog = new Catalog(rows, taxonomy, brands, signature);
  console.log(`Lexical + TF-IDF/LSA index: ${catalog.bm25.df.size} terms, LSA ${catalog.space.dims || 0} dims (${catalog.buildMs} ms)`);

  if (!embeddings.wanted()) {
    console.log('AI_EMBEDDINGS=tfidf — skipping neural embeddings; the API uses the TF-IDF/LSA space.');
    return;
  }
  console.log(`Loading ${embeddings.MODEL_ID} (first run downloads ~23 MB into backend/.cache)...`);
  const extractor = await embeddings.load();
  if (!extractor) {
    console.log(`Neural model unavailable (${embeddings.info().error}). The API falls back to TF-IDF/LSA automatically.`);
    process.exitCode = 0;
    return;
  }
  console.log(`Model ready in ${embeddings.info().loadMs} ms. Embedding products...`);
  const t0 = Date.now();
  const vectors = await embeddings.embed(rows.map(embeddingText));
  await models.upsertEmbeddings(rows.map((p, i) => ({
    product_id: p.id, model: embeddings.MODEL_KEY, dims: embeddings.DIMS, vector: Array.from(vectors[i], (x) => +x.toFixed(6)),
  })));
  console.log(`Stored ${vectors.length} x ${embeddings.DIMS}-dim vectors in product_embeddings (${Date.now() - t0} ms)`);

  // sanity check: nearest neighbour of the first product
  const [a] = vectors;
  const nn = vectors.map((v, i) => [i, v.reduce((s, x, k) => s + x * a[k], 0)]).sort((x, y) => y[1] - x[1]).slice(1, 4);
  console.log(`Nearest to "${rows[0].title}": ${nn.map(([i, s]) => `${rows[i].title} (${s.toFixed(2)})`).join(', ')}`);
  await indexVisual(rows);
  console.log(`Done in ${Date.now() - started} ms`);
};

// clip image embeddings for visual search (skip with --skip-visual or AI_VISUAL=off)
const indexVisual = async (rows) => {
  if (process.argv.includes('--skip-visual') || process.env.AI_VISUAL === 'off') {
    console.log('Skipping visual (CLIP) index.');
    return;
  }
  const visual = require('../engine/visual');
  console.log('Loading CLIP (Xenova/clip-vit-base-patch32; first run downloads ~150 MB)...');
  const t0 = Date.now();
  if (!(await visual.load())) {
    console.log(`CLIP unavailable (${(await visual.info()).error}). Visual search will report itself as disabled.`);
    return;
  }
  console.log(`CLIP ready in ${Date.now() - t0} ms. Embedding ${rows.length} product thumbnails...`);
  const t1 = Date.now();
  let last = 0;
  await visual.indexProducts(rows, {
    onProgress: (done, total) => {
      if (done - last >= 50 || done === total) {
        last = done;
        console.log(`  ${done}/${total}`);
      }
    },
  });
  console.log(`Stored image embeddings in product_image_embeddings (${Date.now() - t1} ms)`);
};

main()
  .catch((error) => {
    console.error('ai:index failed:', error.message);
    process.exitCode = 1;
  })
  .finally(() => db.destroy());
