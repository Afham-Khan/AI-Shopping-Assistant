// open-set rejection for visual search ("snap & find"): unit tests for the decision logic and the
// synthetic image generator (no db, no model), plus api tests that skip when CLIP can't load.
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const visual = require('../api/modules/ai/engine/visual');
const { encodePng, crc32, GENERATORS, mulberry32, generateNegatives } = require('../scripts/lib/syntheticImages');
const { api, db } = require('./helpers');

const AI = '/api/v1/ai';
const unit = (i, n = 4) => Float32Array.from({ length: n }, (_, k) => (k === i ? 1 : 0));
const mix = (a, b, t) => {
  const v = Float32Array.from(a, (x, k) => x * (1 - t) + b[k] * t);
  const n = Math.hypot(...v);
  return v.map((x) => x / n);
};
const CLASSES = [
  { kind: 'product', slug: 'laptops', name: 'Laptops', label: 'Laptops', vec: unit(0) },
  { kind: 'product', slug: 'smartphones', name: 'Smartphones', label: 'Smartphones', vec: unit(1) },
  { kind: 'other', slug: 'handwritten-notes', name: 'a page of handwritten notes', label: 'a page of handwritten notes', vec: unit(2) },
  { kind: 'other', slug: 'blank-wall', name: 'a blank wall', label: 'a blank wall', vec: unit(3) },
];
const T = { minCategoryProb: 0.6, simFloor: 0.7, simCeil: 0.9, textSimFloor: 0.2 };

describe('AI visual search open-set rejection (unit, no db)', () => {
  it('VOS-01 zero-shot softmax spans product and non-product classes', () => {
    const z = visual.zeroShot(mix(unit(0), unit(2), 0.7), CLASSES);
    assert.equal(z.top.c.slug, 'handwritten-notes');
    assert.equal(z.bestProduct.c.slug, 'laptops');
    assert.equal(z.bestOther.c.slug, 'handwritten-notes');
    assert.ok(Math.abs(z.ranked.reduce((s, r) => s + r.p, 0) - 1) < 1e-9);
    assert.ok(z.productMass > 0 && z.productMass < 0.5);
  });

  it('VOS-02 a non-product winner is rejected even with a close neighbour', () => {
    const z = visual.zeroShot(mix(unit(0), unit(2), 0.7), CLASSES);
    assert.deepEqual(visual.openSetDecision(z, 0.99, T), { recognized: false, reason: 'non-product' });
    const d = visual.rejectionDetected(z);
    assert.equal(d.label, 'a page of handwritten notes');
    assert.match(d.message, /^This looks like a page of handwritten notes, not something we sell\. Try a clear photo of a product/);
    assert.ok(d.confidence > 0.5 && d.confidence <= 1);
  });

  it('VOS-03 a weak product winner and a far neighbour are rejected', () => {
    const torn = visual.zeroShot(Float32Array.from([0.5, 0.499, 0.1, 0.1]), CLASSES); // laptops barely beats smartphones
    assert.equal(torn.top.c.slug, 'laptops');
    assert.ok(torn.categoryProb > 0.5 && torn.categoryProb < T.minCategoryProb);
    assert.equal(visual.openSetDecision(torn, 0.95, T).reason, 'low-confidence');
    const clear = visual.zeroShot(unit(1), CLASSES);
    assert.equal(visual.openSetDecision(clear, 0.5, T).reason, 'no-close-match');
    assert.deepEqual(visual.openSetDecision(clear, 0.8, T), { recognized: true, reason: null });
  });

  it('VOS-04 displayed match confidence is scaled between the floor and the ceiling', () => {
    assert.equal(visual.matchConfidence(0.6, T), 0);
    assert.equal(visual.matchConfidence(0.7, T), 0);
    assert.ok(Math.abs(visual.matchConfidence(0.8, T) - 0.5) < 1e-9);
    assert.equal(visual.matchConfidence(0.97, T), 1);
  });

  it('VOS-05 popular categories come from in-stock sales', () => {
    const catalog = {
      taxonomy: [{ slug: 'a', name: 'A' }, { slug: 'b', name: 'B' }, { slug: 'c', name: 'C' }],
      products: [
        { category_slug: 'a', stock: 5, sold_count: 3 }, { category_slug: 'b', stock: 5, sold_count: 40 },
        { category_slug: 'c', stock: 0, sold_count: 900 },
      ],
    };
    assert.deepEqual(visual.popularCategories(catalog), ['B', 'A']);
  });

  it('VOS-06 thresholds load from the calibrated file and env overrides win', () => {
    const before = process.env.VISUAL_SIM_FLOOR;
    try {
      process.env.VISUAL_SIM_FLOOR = '0.55';
      const t = visual.loadThresholds({ reload: true });
      assert.equal(t.simFloor, 0.55);
      assert.ok(t.overridden.includes('simFloor'));
      assert.ok(t.simCeil > t.simFloor);
      for (const k of ['minCategoryProb', 'simCeil', 'textSimFloor']) assert.equal(typeof t[k], 'number');
      if (fs.existsSync(visual.THRESHOLDS_FILE)) {
        const file = JSON.parse(fs.readFileSync(visual.THRESHOLDS_FILE, 'utf8'));
        assert.equal(t.source, 'calibrated');
        assert.equal(t.minCategoryProb, file.thresholds.minCategoryProb);
        assert.equal(file.classesSignature, visual.classesSignature(), 'visual-thresholds.json is stale: re-run node scripts/calibrateVisual.js');
        assert.ok(file.calibration.positives.recall >= file.calibration.targetRecall);
      }
    } finally {
      if (before === undefined) delete process.env.VISUAL_SIM_FLOOR;
      else process.env.VISUAL_SIM_FLOOR = before;
      visual.loadThresholds({ reload: true });
    }
  });

  it('VOS-07 the pure-node png encoder writes valid chunks', () => {
    const rgb = Uint8Array.from([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]);
    const png = encodePng(2, 2, rgb);
    assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    assert.equal(png.toString('ascii', 12, 16), 'IHDR');
    assert.equal(png.readUInt32BE(16), 2);
    assert.equal(png.readUInt32BE(20), 2);
    const idatLen = png.readUInt32BE(33);
    assert.equal(png.toString('ascii', 37, 41), 'IDAT');
    const raw = zlib.inflateSync(png.subarray(41, 41 + idatLen));
    assert.deepEqual([...raw], [0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255]);
    assert.equal(png.readUInt32BE(41 + idatLen), crc32(png.subarray(37, 41 + idatLen)));
    assert.equal(crc32(Buffer.from('123456789')), 0xcbf43926);
  });

  it('VOS-08 synthetic negatives are deterministic and cover every kind', () => {
    const a = GENERATORS.handwrittenNotes(mulberry32(7)).png();
    const b = GENERATORS.handwrittenNotes(mulberry32(7)).png();
    assert.ok(a.equals(b));
    const set = generateNegatives({ counts: Object.fromEntries(Object.keys(GENERATORS).map((k) => [k, 1])) });
    assert.deepEqual(set.map((n) => n.kind), Object.keys(GENERATORS));
    set.forEach((n) => assert.equal(n.png.toString('ascii', 1, 4), 'PNG'));
  });
});

describe('AI visual search open-set rejection (api)', function openSetApi() {
  this.timeout(120000);
  let notes;
  let thumb;
  before(async () => {
    notes = GENERATORS.handwrittenNotes(mulberry32(424242)).png();
    try {
      const p = await db('products as p').join('categories as c', 'c.id', 'p.category_id').where('c.slug', 'mens-shoes').orderBy('p.id').first('p.id', 'p.thumbnail_url');
      const file = p && path.join(__dirname, '..', p.thumbnail_url || '');
      thumb = file && fs.existsSync(file) ? { id: p.id, image: fs.readFileSync(file) } : null;
    } catch {
      thumb = null;
    }
  });

  it('VOS-09 a photo of handwritten notes is not recognized and returns no products', async function vos09() {
    const res = await api.post(`${AI}/visual-search`).attach('image', notes, { filename: 'notes.png', contentType: 'image/png' });
    if (res.status === 503) return this.skip();
    assert.equal(res.status, 200);
    const d = res.body.data;
    assert.equal(d.recognized, false);
    assert.deepEqual(d.products, []);
    assert.equal(typeof d.detected.label, 'string');
    assert.ok(d.detected.confidence >= 0 && d.detected.confidence <= 1);
    assert.match(d.message, /not something we sell|couldn't spot a product/);
    assert.ok(Array.isArray(d.suggestions) && d.suggestions.length > 0);
    assert.equal(typeof d.latencyMs, 'number');
    return null;
  });

  it('VOS-10 a product photo is recognized with honest, bounded match scores', async function vos10() {
    if (!thumb) return this.skip();
    const res = await api.post(`${AI}/visual-search?limit=6`).attach('image', thumb.image, { filename: 'p.webp', contentType: 'image/webp' });
    if (res.status === 503) return this.skip();
    assert.equal(res.status, 200);
    const d = res.body.data;
    assert.equal(d.recognized, true);
    assert.equal(d.message, null);
    assert.equal(d.detected.category.slug, 'mens-shoes');
    assert.equal(d.detected.label, d.detected.category.name);
    assert.ok(d.products.length > 0 && d.products[0].id === thumb.id);
    d.products.forEach((p) => assert.ok(p.match.score >= 0 && p.match.score <= 1));
    assert.ok(d.products[d.products.length - 1].match.score <= d.products[0].match.score);
    return null;
  });

  it('VOS-11 off-catalog text queries are not recognized', async function vos11() {
    const res = await api.get(`${AI}/visual-search/text`).query({ q: 'asdfghjkl qwertyuiop' });
    if (res.status === 503) return this.skip();
    assert.equal(res.status, 200);
    const d = res.body.data;
    assert.equal(typeof d.recognized, 'boolean');
    if (!d.recognized) {
      assert.deepEqual(d.products, []);
      assert.ok(d.message && d.suggestions.length > 0);
    }
    const ok = await api.get(`${AI}/visual-search/text`).query({ q: 'running shoes' }).expect(200);
    assert.equal(ok.body.data.recognized, true);
    assert.ok(ok.body.data.products.length > 0);
    return null;
  });

  it('VOS-12 insights expose the open-set thresholds', async () => {
    const res = await api.get(`${AI}/insights`).expect(200);
    const o = res.body.data.visual.openSet;
    assert.ok(o.nonProductClasses >= 12);
    assert.equal(typeof o.thresholds.simFloor, 'number');
  });
});
