/* Downloads product images from the CDN into uploads/products/<sku>/ and points the DB at the local copies.
   Local/offline option only (IMAGE_MODE=local, the default on a laptop with a local database). A deployed API has no
   uploads folder, so with IMAGE_MODE=cdn (default in production or with DATABASE_URL set) this script does nothing. */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const fs = require('fs');
const path = require('path');
const db = require('../api/db/connection');
const { imageMode } = require('../helpers/imageMode');

const UPLOAD_ROOT = path.join(__dirname, '..', 'uploads', 'products');
const CONCURRENCY = 4;
const TIMEOUT_MS = 20000;
const ALLOWED_HOST = 'cdn.dummyjson.com';

const safeSegment = (s) => String(s).replace(/[^A-Za-z0-9._-]/g, '_');

const download = async (url, dest) => {
  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const type = res.headers.get('content-type') || '';
  if (!type.startsWith('image/')) throw new Error(`unexpected content-type ${type}`);
  const buffer = Buffer.from(await res.arrayBuffer());
  const tmp = `${dest}.part`;
  await fs.promises.writeFile(tmp, buffer);
  await fs.promises.rename(tmp, dest);
};

const runPool = async (jobs, worker) => {
  let index = 0;
  const next = async () => {
    while (index < jobs.length) {
      const job = jobs[index];
      index += 1;
      await worker(job);
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, next));
};

const main = async () => {
  const products = await db('products').select('id', 'sku', 'thumbnail_url');
  const images = await db('product_images').select('id', 'product_id', 'url');
  const skuById = new Map(products.map((p) => [p.id, p.sku]));

  // one job per distinct remote url
  const jobs = new Map();
  const addJob = (url, sku) => {
    if (!url || !/^https?:\/\//.test(url) || jobs.has(url)) return;
    const { hostname, pathname } = new URL(url);
    if (hostname !== ALLOWED_HOST) return;
    const file = safeSegment(path.basename(pathname));
    const dir = path.join(UPLOAD_ROOT, safeSegment(sku));
    jobs.set(url, { url, dir, file, local: `/uploads/products/${safeSegment(sku)}/${file}` });
  };
  products.forEach((p) => addJob(p.thumbnail_url, p.sku));
  images.forEach((i) => addJob(i.url, skuById.get(i.product_id)));

  const stats = { downloaded: 0, skipped: 0, failed: 0 };
  const resolved = new Map();
  await runPool([...jobs.values()], async (job) => {
    const dest = path.join(job.dir, job.file);
    if (fs.existsSync(dest) && fs.statSync(dest).size > 0) {
      stats.skipped += 1;
      resolved.set(job.url, job.local);
      return;
    }
    await fs.promises.mkdir(job.dir, { recursive: true });
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      try {
        await download(job.url, dest);
        stats.downloaded += 1;
        resolved.set(job.url, job.local);
        return;
      } catch (error) {
        if (attempt === 2) {
          stats.failed += 1;
          console.warn(`  failed ${job.url}: ${error.message}`);
        }
      }
    }
  });

  await db.transaction(async (trx) => {
    for (const p of products) {
      if (resolved.has(p.thumbnail_url)) await trx('products').where({ id: p.id }).update({ thumbnail_url: resolved.get(p.thumbnail_url) });
    }
    for (const i of images) {
      if (resolved.has(i.url)) await trx('product_images').where({ id: i.id }).update({ url: resolved.get(i.url) });
    }
    // categories, departments and banners reuse product thumbnails
    for (const table of ['categories', 'departments', 'banners']) {
      const rows = await trx(table).whereLike('image_url', 'http%').select('id', 'image_url');
      for (const r of rows) {
        if (resolved.has(r.image_url)) await trx(table).where({ id: r.id }).update({ image_url: resolved.get(r.image_url) });
      }
    }
    // order snapshots too, so order history works offline
    const items = await trx('order_items').whereLike('thumbnail_url', 'http%').select('id', 'thumbnail_url');
    for (const it of items) {
      if (resolved.has(it.thumbnail_url)) await trx('order_items').where({ id: it.id }).update({ thumbnail_url: resolved.get(it.thumbnail_url) });
    }
  });

  console.log(`Images: ${stats.downloaded} downloaded, ${stats.skipped} already cached, ${stats.failed} failed (of ${jobs.size})`);
};

if (imageMode() === 'cdn') {
  console.log('IMAGE_MODE=cdn: products keep their cdn.dummyjson.com image URLs, nothing to cache. Set IMAGE_MODE=local to cache images on this machine.');
  process.exit(0);
}

main()
  .then(() => db.destroy())
  .catch(async (error) => {
    console.error('Image caching failed:', error);
    await db.destroy();
    process.exit(1);
  });
