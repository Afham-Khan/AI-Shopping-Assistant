// node scripts/calibrateVisual.js [--recall 0.95] [--dry-run] [--dump <dir>] [--cache <file.json>]
// (--cache reuses image embeddings between runs while iterating on prompts; delete it if images change)
// calibrates the open-set thresholds of visual search ("snap & find") and writes
// api/modules/ai/training/models/visual-thresholds.json (loaded by engine/visual.js at runtime).
//
// positives: every product thumbnail in the db, queried like an upload. it should land in its own
//   category; we record the winning class, the top product-category probability and the best
//   *non-self* neighbour similarity (the thumbnail itself is in the index, a real photo would not be).
// negatives: synthetic images generated in pure node (scripts/lib/syntheticImages.js): note pages,
//   printed text, diagrams, scribbles, solid colours, noise, gradients, shapes, checkerboards.
//   they approximate real off-catalog photos; real camera shots are messier, so treat the rejection
//   rate as indicative, not a guarantee.
// thresholds: grid search for (minCategoryProb, simFloor) that keeps >= --recall of positives
//   recognized (full rule) while rejecting as many negatives as possible with gates 2+3 *alone*.
//   the synthetic negatives are mostly caught by the non-product classes (gate 1) already, which gives
//   the grid no signal; scoring the backstop gates without gate 1 simulates off-catalog photos that
//   none of the non-product prompts describe. we also report a leave-the-winning-class-out rejection.
require('dotenv').config({ quiet: true });
const fs = require('fs');
const path = require('path');
const db = require('../api/db/connection');
const visual = require('../api/modules/ai/engine/visual');
const { getCatalog } = require('../api/modules/ai/engine/retrieval/catalog');
const { generateNegatives } = require('./lib/syntheticImages');

const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
};
const TARGET_RECALL = Number(arg('--recall', '0.95'));
const DRY_RUN = process.argv.includes('--dry-run');
const DUMP = arg('--dump', null);
const CACHE = arg('--cache', null);

// text side (GET /ai/visual-search/text): shopping phrases vs off-catalog phrases
const TEXT_POSITIVE_EXTRA = [
  'red sneakers', 'white leather sneakers with a gum sole', 'running shoes', 'a black handbag', 'gaming laptop', 'wireless earbuds',
  'a smartwatch', 'a summer dress', 'aviator sunglasses', 'lipstick', 'a perfume for women', 'face moisturizer', 'a wooden chair',
  'a table lamp', 'a frying pan', 'fresh apples', 'a football', 'a sports car', 'a motorbike', 'a gold necklace', 'a denim shirt',
  'high heels', 'an ipad', 'a phone case', 'a cozy sofa', 'kitchen knives', 'a luxury watch', 'a silk blouse', 'something cozy for winter',
];
const TEXT_NEGATIVES = [
  'my class notes', 'handwritten notes', 'a page of my notebook', 'quantum physics homework', 'a printed essay', 'a tax form',
  'a screenshot of my chat', 'a whiteboard from the lecture', 'a blank wall', 'a mountain landscape', 'a sunset over the sea',
  'a busy city street', 'my bedroom', 'my dog', 'a cat sleeping', 'a plate of pasta', 'a bowl of ramen', 'a blurry photo',
  'the weather tomorrow', 'asdfghjkl', 'a tree in the park', 'clouds in the sky', 'a crowd of people', 'my passport photo',
];

const pct = (arr, q) => {
  if (!arr.length) return null;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.max(0, Math.floor(q * (s.length - 1))))];
};
const r3 = (x) => (x === null || x === undefined ? null : +x.toFixed(3));
const summary = (arr) => ({ p05: r3(pct(arr, 0.05)), p25: r3(pct(arr, 0.25)), median: r3(pct(arr, 0.5)), p75: r3(pct(arr, 0.75)), p95: r3(pct(arr, 0.95)) });
const countBy = (arr, key) => arr.reduce((m, x) => ({ ...m, [key(x)]: (m[key(x)] || 0) + 1 }), {});

const sample = (z, bestSim) => ({
  topKind: z.top.c.kind,
  topSlug: z.top.c.slug,
  topP: z.top.p,
  productSlug: z.bestProduct ? z.bestProduct.c.slug : null,
  productP: z.bestProduct ? z.bestProduct.p : 0,
  categoryProb: z.categoryProb,
  bestSim,
});

// full runtime rule (mirrors visual.openSetDecision)
const passes = (s, minCategoryProb, simFloor) => s.topKind !== 'other' && s.categoryProb >= minCategoryProb && s.bestSim >= simFloor;
// gates 2+3 only
const passesBackstop = (s, minCategoryProb, simFloor) => s.categoryProb >= minCategoryProb && s.bestSim >= simFloor;

const main = async () => {
  const started = Date.now();
  const catalog = await getCatalog();
  console.log(`Catalog: ${catalog.products.length} products, ${catalog.taxonomy.length} categories`);
  console.log(`Loading CLIP (${visual.MODEL_ID})...`);
  if (!(await visual.load())) throw new Error(`CLIP unavailable: ${(await visual.info()).error}`);
  const vectors = await visual.loadVectors(catalog);
  if (vectors.size < catalog.products.length * 0.5) throw new Error('Visual index is incomplete. Run `npm run ai:index` first.');
  const classes = await visual.classVectors(catalog);
  console.log(`Classes: ${classes.filter((c) => c.kind === 'product').length} product categories + ${classes.filter((c) => c.kind === 'other').length} non-product classes, ${visual.TEMPLATES.length} templates each`);

  const cache = CACHE && fs.existsSync(CACHE) ? JSON.parse(fs.readFileSync(CACHE, 'utf8')) : {};
  const cached = async (key, compute) => {
    if (!cache[key]) cache[key] = Array.from(await compute());
    return Float32Array.from(cache[key]);
  };

  // ---- positives
  const positives = [];
  let i = 0;
  for (const p of catalog.products) {
    i += 1;
    const src = visual.thumbnailSource(p);
    if (!src) continue;
    let vec;
    try {
      vec = await cached(`p${p.id}`, () => visual.embedImage(src));
    } catch {
      continue;
    }
    const { z, bestSim } = await visual.analyzeImage(vec, catalog, vectors, { excludeId: p.id });
    positives.push({ id: p.id, title: p.title, category: p.category_slug, ...sample(z, bestSim) });
    if (i % 50 === 0) console.log(`  positives ${i}/${catalog.products.length}`);
  }

  // ---- negatives
  const negImages = generateNegatives();
  if (DUMP) fs.mkdirSync(DUMP, { recursive: true });
  const negatives = [];
  for (const [k, n] of negImages.entries()) {
    if (DUMP) fs.writeFileSync(path.join(DUMP, `${n.kind}-${n.seed}.png`), n.png);
    const vec = await cached(`n${n.seed}`, () => visual.embedImage(n.png));
    const { z, bestSim } = await visual.analyzeImage(vec, catalog, vectors);
    negatives.push({ kind: n.kind, seed: n.seed, vec, ...sample(z, bestSim) });
    if ((k + 1) % 50 === 0) console.log(`  negatives ${k + 1}/${negImages.length}`);
  }

  if (CACHE) fs.writeFileSync(CACHE, JSON.stringify(cache));
  const stolen = positives.filter((s) => s.topKind === 'other');
  console.log(`Positives won by a non-product class: ${stolen.length}`, countBy(stolen, (s) => s.topSlug));
  stolen.forEach((s) => console.log(`  ${s.title} [${s.category}] -> ${s.topSlug} (${s.topP.toFixed(2)}; best product ${s.productSlug} ${s.productP.toFixed(2)})`));

  // ---- grid search
  const grid = [];
  for (let t = 0; t <= 0.95 + 1e-9; t += 0.005) {
    for (let f = 0.3; f <= 0.98 + 1e-9; f += 0.005) {
      const recall = positives.filter((s) => passes(s, t, f)).length / positives.length;
      if (recall < TARGET_RECALL) continue;
      const rejection = negatives.filter((s) => !passesBackstop(s, t, f)).length / negatives.length;
      grid.push({ minCategoryProb: +t.toFixed(3), simFloor: +f.toFixed(3), recall, rejection });
    }
  }
  if (!grid.length) {
    const ceiling = positives.filter((s) => s.topKind !== 'other').length / positives.length;
    throw new Error(`No thresholds reach ${TARGET_RECALL * 100}% recall (non-product classes already take ${((1 - ceiling) * 100).toFixed(1)}% of positives). Adjust the prompts.`);
  }
  const maxRej = Math.max(...grid.map((g) => g.rejection));
  // within half a point of the best rejection, prefer the most lenient (best recall, lowest thresholds)
  const best = grid
    .filter((g) => g.rejection >= maxRej - 0.005)
    .sort((a, b) => b.recall - a.recall || a.minCategoryProb + a.simFloor - (b.minCategoryProb + b.simFloor))[0];
  // floors below the weakest recognized positive all score the same; take the tightest one minus a
  // small margin (real photos sit a little further from thumbnails than thumbnails from each other)
  const keptSims = positives.filter((s) => passes(s, best.minCategoryProb, best.simFloor)).map((s) => s.bestSim);
  best.simFloor = Math.max(best.simFloor, Math.floor((Math.min(...keptSims) - 0.02) * 200) / 200);
  const posSims = positives.map((s) => s.bestSim);
  const simCeil = +Math.max(best.simFloor + 0.05, pct(posSims, 0.9)).toFixed(3);

  // ---- text floor: keep >= TARGET_RECALL of shopping phrases
  const textPos = [...new Set([...catalog.products.map((p) => p.title), ...catalog.taxonomy.map((c) => c.name), ...TEXT_POSITIVE_EXTRA])];
  const embedQueries = async (qs) => {
    const out = [];
    for (let k = 0; k < qs.length; k += 32) out.push(...(await visual.embedTexts(qs.slice(k, k + 32).map(visual.textQuery))));
    return out;
  };
  const textPosSims = (await embedQueries(textPos)).map((v) => visual.bestSimilarity(v, vectors, catalog));
  const textNegSims = (await embedQueries(TEXT_NEGATIVES)).map((v) => visual.bestSimilarity(v, vectors, catalog));
  const textSimFloor = Math.floor(pct(textPosSims, 1 - TARGET_RECALL) * 200) / 200;
  const extraSims = textPosSims.slice(textPos.length - TEXT_POSITIVE_EXTRA.length);
  const textRecall = textPosSims.filter((s) => s >= textSimFloor).length / textPosSims.length;
  const textRejection = textNegSims.filter((s) => s < textSimFloor).length / textNegSims.length;

  // ---- report
  const t = { minCategoryProb: best.minCategoryProb, simFloor: best.simFloor };
  // leave-the-winning-class-out: drop the non-product class that caught each negative and re-run the rule
  for (const n of negatives) {
    if (n.topKind !== 'other') {
      n.lwoRejected = !passes(n, t.minCategoryProb, t.simFloor);
      continue;
    }
    const z2 = visual.zeroShot(n.vec, classes.filter((c) => c.slug !== n.topSlug));
    n.lwoRejected = !passes(sample(z2, n.bestSim), t.minCategoryProb, t.simFloor);
  }
  const recognizedPos = positives.filter((s) => passes(s, t.minCategoryProb, t.simFloor));
  const rejectedPos = positives.filter((s) => !passes(s, t.minCategoryProb, t.simFloor));
  const negByKind = {};
  for (const n of negatives) {
    const k = (negByKind[n.kind] = negByKind[n.kind] || { n: 0, rejected: 0, byNonProductClass: 0, byBackstopAlone: 0, leaveWinnerOut: 0 });
    k.n += 1;
    if (!passes(n, t.minCategoryProb, t.simFloor)) k.rejected += 1;
    if (n.topKind === 'other') k.byNonProductClass += 1;
    if (!passesBackstop(n, t.minCategoryProb, t.simFloor)) k.byBackstopAlone += 1;
    if (n.lwoRejected) k.leaveWinnerOut += 1;
  }
  for (const k of Object.values(negByKind)) k.rejection = r3(k.rejected / k.n);
  const result = {
    model: visual.MODEL_KEY,
    calibratedAt: new Date().toISOString(),
    classesSignature: visual.classesSignature(),
    rule: 'not recognized if a non-product class wins the zero-shot softmax (logit scale 100, prompt-ensembled), or the best category probability renormalized over product classes < minCategoryProb, or no in-stock neighbour has cosine >= simFloor. displayed match = clamp((sim - simFloor) / (simCeil - simFloor)).',
    thresholds: { minCategoryProb: t.minCategoryProb, simFloor: t.simFloor, simCeil, textSimFloor: +textSimFloor.toFixed(3) },
    calibration: {
      targetRecall: TARGET_RECALL,
      note: 'Negatives are synthetic images generated in pure Node (note pages, printed text, diagrams, scribbles, solid colours, noise, gradients, shapes, checkerboards). They approximate real off-catalog photos; real camera shots (blur, perspective, lighting, real handwriting) may score differently. Positive recall uses each product thumbnail with its own vector excluded from the neighbour search. minCategoryProb/simFloor maximize rejection by gates 2+3 alone (gate 1 already rejects nearly every synthetic negative, which would give the search no signal).',
      positives: {
        n: positives.length,
        recall: r3(recognizedPos.length / positives.length),
        ownCategoryTop1: r3(positives.filter((s) => s.productSlug === s.category).length / positives.length),
        ownCategoryTop1AmongRecognized: r3(recognizedPos.filter((s) => s.productSlug === s.category).length / Math.max(1, recognizedPos.length)),
        nonProductClassWon: positives.filter((s) => s.topKind === 'other').length,
        nonProductClassWonBy: countBy(positives.filter((s) => s.topKind === 'other'), (s) => s.topSlug),
        categoryProb: summary(positives.map((s) => s.categoryProb)),
        bestNonSelfSimilarity: summary(posSims),
        rejected: rejectedPos.map((s) => ({ id: s.id, title: s.title, category: s.category, winner: s.topSlug, categoryProb: r3(s.categoryProb), bestSim: r3(s.bestSim) })),
      },
      negatives: {
        n: negatives.length,
        rejection: r3(negatives.filter((s) => !passes(s, t.minCategoryProb, t.simFloor)).length / negatives.length),
        rejectedByNonProductClassAlone: r3(negatives.filter((s) => s.topKind === 'other').length / negatives.length),
        rejectedByBackstopGatesAlone: r3(negatives.filter((s) => !passesBackstop(s, t.minCategoryProb, t.simFloor)).length / negatives.length),
        rejectedWithWinningClassLeftOut: r3(negatives.filter((s) => s.lwoRejected).length / negatives.length),
        byKind: negByKind,
        winnerClasses: countBy(negatives, (s) => s.topSlug),
        categoryProb: summary(negatives.map((s) => s.categoryProb)),
        bestSimilarity: summary(negatives.map((s) => s.bestSim)),
      },
      text: {
        positives: textPosSims.length,
        negatives: textNegSims.length,
        recall: r3(textRecall),
        rejection: r3(textRejection),
        genericPhraseRecall: r3(extraSims.filter((s) => s >= textSimFloor).length / extraSims.length),
        positiveBestSimilarity: summary(textPosSims),
        negativeBestSimilarity: summary(textNegSims),
      },
      gridSize: grid.length,
      tookMs: Date.now() - started,
    },
  };

  console.log('\nThresholds:', result.thresholds);
  const c = result.calibration;
  console.log(`Positives (${c.positives.n} thumbnails): recall ${(c.positives.recall * 100).toFixed(1)}%, own category top-1 ${(c.positives.ownCategoryTop1 * 100).toFixed(1)}%, non-product class won ${c.positives.nonProductClassWon}`, c.positives.nonProductClassWonBy);
  console.log(`Negatives (${c.negatives.n} synthetic): rejection ${(c.negatives.rejection * 100).toFixed(1)}% (non-product class alone ${(c.negatives.rejectedByNonProductClassAlone * 100).toFixed(1)}%, backstop gates alone ${(c.negatives.rejectedByBackstopGatesAlone * 100).toFixed(1)}%, winning class left out ${(c.negatives.rejectedWithWinningClassLeftOut * 100).toFixed(1)}%)`);
  console.log('  kind              full  gate1  gates2+3  leave-winner-out');
  for (const [k, v] of Object.entries(c.negatives.byKind)) console.log(`  ${k.padEnd(17)} ${String(v.rejected).padStart(3)}/${v.n}  ${String(v.byNonProductClass).padStart(3)}  ${String(v.byBackstopAlone).padStart(6)}  ${String(v.leaveWinnerOut).padStart(8)}`);
  console.log('Negative winners:', c.negatives.winnerClasses);
  console.log('Positive category prob:', c.positives.categoryProb, 'best non-self sim:', c.positives.bestNonSelfSimilarity);
  console.log('Negative category prob:', c.negatives.categoryProb, 'best sim:', c.negatives.bestSimilarity);
  console.log(`Text: floor ${result.thresholds.textSimFloor}, recall ${(c.text.recall * 100).toFixed(1)}% (generic phrases ${(c.text.genericPhraseRecall * 100).toFixed(1)}%), rejection ${(c.text.rejection * 100).toFixed(1)}% of ${c.text.negatives} off-catalog phrases`);
  if (rejectedPos.length) console.log('Rejected positives:', c.positives.rejected.map((r) => `${r.title} [${r.category} -> ${r.winner} p=${r.categoryProb} sim=${r.bestSim}]`).join('; '));
  if (DRY_RUN) {
    console.log('\n--dry-run: not writing', visual.THRESHOLDS_FILE);
  } else {
    fs.mkdirSync(path.dirname(visual.THRESHOLDS_FILE), { recursive: true });
    fs.writeFileSync(visual.THRESHOLDS_FILE, `${JSON.stringify(result, null, 2)}\n`);
    console.log(`\nWrote ${path.relative(process.cwd(), visual.THRESHOLDS_FILE)} in ${Date.now() - started} ms`);
  }
};

main()
  .catch((error) => {
    console.error('calibrateVisual failed:', error.message);
    process.exitCode = 1;
  })
  .finally(() => db.destroy());
