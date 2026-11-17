const assert = require('node:assert/strict');
const { damerauLevenshtein } = require('../api/modules/ai/engine/nlu/fuzzy');
const { jacobiEigen, VectorSpace } = require('../api/modules/ai/engine/retrieval/vectorspace');
const { BM25 } = require('../api/modules/ai/engine/retrieval/bm25');
const { scoreAll, reasonsFor, mmr, budgetFit } = require('../api/modules/ai/engine/ranking/ranker');
const S = require('../api/modules/ai/engine/dialogue/state');
const { grounded } = require('../api/modules/ai/engine/llm');
const { budgetOptions, answersToSlots } = require('../api/modules/ai/engine/finder');
const nlu = require('../api/modules/ai/engine/nlu');

// minimal product rows shaped like productBaseQuery() output
const product = (id, over = {}) => {
  const p = {
    id, title: `Product ${id}`, brand_name: 'Acme', category_slug: 'laptops', category_name: 'Laptops', department_slug: 'electronics',
    price: 100000, compare_at_price: null, discount_percent: 0, rating: 4, rating_count: 10, stock: 5, sold_count: 3,
    tags: [], highlights: [], specs: {}, description: '', search_keywords: '', color: null, gender: null, created_at: new Date(),
    ...over,
  };
  p._bayes = p.rating;
  p._quality = Math.max(0, (p.rating - 2.5) / 2.5);
  p._popularity = 0.3;
  p._discount = (p.discount_percent || 0) / 40;
  p._text = [p.title, p.brand_name, p.category_name, p.description, (p.highlights || []).join(' '), Object.entries(p.specs).map(([k, v]) => `${k} ${v}`).join(' '), p.search_keywords].join(' ').toLowerCase();
  return p;
};

describe('AI engine (unit, no db)', () => {
  it('ENG-01 damerau-levenshtein counts a transposition as one edit', () => {
    assert.equal(damerauLevenshtein('smartphnoe', 'smartphone'), 1);
    assert.equal(damerauLevenshtein('laptp', 'laptop'), 1);
    assert.equal(damerauLevenshtein('kitten', 'sitting'), 3);
  });

  it('ENG-02 jacobi eigen-decomposition reconstructs the matrix', () => {
    const m = [[4, 1, 2], [1, 3, 0], [2, 0, 5]];
    const { values, vectors } = jacobiEigen(m);
    for (let i = 0; i < 3; i += 1) {
      for (let j = 0; j < 3; j += 1) {
        let s = 0;
        for (let k = 0; k < 3; k += 1) s += vectors[i][k] * values[k] * vectors[j][k];
        assert.ok(Math.abs(s - m[i][j]) < 1e-6);
      }
    }
    assert.ok(Math.abs(values.reduce((a, b) => a + b, 0) - 12) < 1e-9); // trace preserved
  });

  const docs = [
    product(1, { title: 'Asus ROG Gaming Laptop', highlights: ['RTX graphics for gaming'], specs: { RAM: '16 GB' } }),
    product(2, { title: 'Business Notebook', description: 'a thin laptop for office work and gaming on the side' }),
    product(3, { title: 'Red Lipstick', category_slug: 'beauty', category_name: 'Beauty', description: 'long lasting matte lipstick' }),
    product(4, { title: 'Office Chair', category_slug: 'furniture', category_name: 'Furniture', description: 'ergonomic chair' }),
  ];

  it('ENG-03 bm25 ranks title matches above description-only matches', () => {
    const bm = new BM25().build(docs);
    const scores = bm.score(new Map([['gaming', 1]]));
    assert.ok(scores.get(1) > scores.get(2));
    assert.equal(scores.has(3), false);
  });

  it('ENG-04 tf-idf/lsa space finds semantically related products', () => {
    const space = new VectorSpace({ dims: 3 }).build(docs);
    const scores = space.scores('gaming laptop');
    assert.ok(scores.get(1) > scores.get(3));
    assert.ok(scores.get(1) > scores.get(4));
    assert.equal(space.vectorOf(1).length, space.dims);
  });

  it('ENG-05 ranker explains its picks with evidence', () => {
    const slots = { features: ['gaming'], budget: { min: null, max: 150000 } };
    const p = product(9, { title: 'Gaming Beast', specs: { RAM: '16 GB', GPU: 'RTX 3060' }, discount_percent: 15, compare_at_price: 117000, rating: 4.6, rating_count: 120 });
    const ctx = { slots, semantic: new Map(), lexical: new Map(), profile: null, catalog: { bestsellerCut: 100, similarity: () => 0, vectorOf: () => null } };
    const [scored] = scoreAll([p], ctx);
    const reasons = reasonsFor(scored, ctx);
    assert.ok(reasons.includes('Within your Rs 150,000 budget'));
    assert.ok(reasons.some((r) => r.startsWith('Great for gaming:')));
    assert.ok(reasons.some((r) => r.includes('4.6★')));
    assert.ok(scored.score > 0 && scored.score <= 1);
  });

  it('ENG-06 budget fit prefers in-budget prices', () => {
    assert.ok(budgetFit(90000, { max: 100000 }) > budgetFit(120000, { max: 100000 }));
    assert.ok(budgetFit(30000, { target: 30000 }) > budgetFit(45000, { target: 30000 }));
  });

  it('ENG-07 mmr avoids near-duplicates', () => {
    const items = [{ p: { id: 1 }, score: 0.9 }, { p: { id: 2 }, score: 0.89 }, { p: { id: 3 }, score: 0.7 }];
    const catalog = { similarity: (a, b) => ((a === 1 && b === 2) || (a === 2 && b === 1) ? 0.99 : 0.1) };
    const picked = mmr(items, 2, catalog, 0.6).map((x) => x.p.id);
    assert.deepEqual(picked, [1, 3]);
  });

  it('ENG-08 slot merge: follow-ups keep context, topic changes reset', () => {
    const first = S.mergeSlots(S.EMPTY_SLOTS(), nlu.analyze('samsung phones under 100k').entities, 'new');
    const followUp = nlu.analyze('in black').entities;
    const merged = S.mergeSlots(first, followUp, 'filter');
    assert.equal(merged.category, 'smartphones');
    assert.equal(merged.budget.max, 100000);
    assert.equal(merged.color, 'black');
    const laptops = nlu.analyze('laptops').entities;
    assert.equal(S.isTopicChange(merged, laptops), true);
    const fresh = S.mergeSlots(merged, laptops, 'new');
    assert.equal(fresh.budget, null);
    assert.deepEqual(fresh.brands, []);
    const notSamsung = S.mergeSlots(first, nlu.analyze('not samsung').entities, 'filter');
    assert.deepEqual(notSamsung.brands, []);
    assert.deepEqual(notSamsung.excludeBrands, ['samsung']);
  });

  it('ENG-09 cheaper / premium refinements move the price window', () => {
    const slots = { ...S.EMPTY_SLOTS(), category: 'smartphones', categories: ['smartphones'] };
    const cheaper = S.cheaperSlots(slots, [50000, 80000, 120000]);
    assert.ok(cheaper.budget.max < 80000);
    const premium = S.premiumSlots(slots, [50000, 80000, 120000]);
    assert.ok(premium.budget.min > 80000);
  });

  it('ENG-10 llm rewrites with invented numbers are rejected', () => {
    const draft = 'Top pick is **Vivo V9** at **Rs 83,999**.';
    assert.equal(grounded('Go for the **Vivo V9** — only **Rs 83,999**!', draft, ''), true);
    assert.equal(grounded('Go for the **Vivo V9** — only **Rs 59,999**!', draft, ''), false);
    assert.equal(grounded('', draft, ''), false);
  });

  it('ENG-11 finder budget brackets come from price quartiles', () => {
    const options = budgetOptions([1000, 2000, 5000, 9000, 15000, 30000, 60000, 90000]);
    assert.ok(options.length >= 3);
    assert.equal(options[options.length - 1].value, 'any');
    assert.match(options[0].value, /^0-\d+$/);
  });

  it('ENG-12 finder answers become retrieval slots', () => {
    const s = answersToSlots('fashion', { for: 'women', category: 'shoes', color: 'black', budget: '0-20000' });
    assert.deepEqual(s.categories, ['womens-shoes']);
    assert.equal(s.gender, 'women');
    assert.equal(s.color, 'black');
    assert.deepEqual(s.budget, { min: null, max: 20000 });
    const e = answersToSlots('electronics', { type: 'laptops', use: ['gaming'], brand: 'any' });
    assert.deepEqual(e.features, ['gaming']);
    assert.deepEqual(e.brands, []);
  });
});
