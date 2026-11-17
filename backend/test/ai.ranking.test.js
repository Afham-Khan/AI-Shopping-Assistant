// recommendation relevance: attribute tags, colour/gender/type constraints, mmr order, nlg top-pick consistency,
// and the golden-set threshold (api/modules/ai/training/data/ranking-eval.json, same pipeline as `npm run ai:eval`)
const assert = require('node:assert/strict');
const A = require('../api/modules/ai/engine/ranking/attributes');
const { scoreAll, order, mmr } = require('../api/modules/ai/engine/ranking/ranker');
const { applyFilters, filtersFromSlots } = require('../api/modules/ai/engine/retrieval/search');
const nlg = require('../api/modules/ai/engine/dialogue/nlg');
const { keepsTopPick } = require('../api/modules/ai/engine/llm');
const S = require('../api/modules/ai/engine/dialogue/state');
const nlu = require('../api/modules/ai/engine/nlu');
const { respond } = require('../api/modules/ai/engine/dialogue/manager');
const { getCatalog } = require('../api/modules/ai/engine/retrieval/catalog');
const { runEval, judge, topPickConsistency } = require('../api/modules/ai/training/rankingEval');

// rows shaped like productBaseQuery() output
const product = (id, over = {}) => {
  const p = {
    id, title: `Product ${id}`, brand_name: 'Acme', category_slug: 'womens-shoes', category_name: "Women's Shoes", department_slug: 'fashion',
    price: 10000, compare_at_price: null, discount_percent: 0, rating: 4, rating_count: 10, stock: 5, sold_count: 3,
    tags: [], highlights: [], specs: {}, description: '', search_keywords: '', color: null, gender: null, created_at: new Date(),
    ...over,
  };
  p._bayes = p.rating;
  p._quality = 0.6;
  p._popularity = 0.3;
  p._discount = 0;
  p._text = [p.title, p.search_keywords, p.description].join(' ').toLowerCase();
  return p;
};

const slotsFor = (text) => S.mergeSlots(S.EMPTY_SLOTS(), nlu.analyze(text).entities, 'new');
const ctxFor = (slots) => ({ catalog: { similarity: () => 0, vectorOf: () => null }, slots, semantic: new Map(), lexical: new Map(), profile: null });

const HEEL = product(1, { title: 'Calvin Klein Heel Shoes', color: 'Black', gender: 'women', search_keywords: 'heels high heels formal shoes office shoes', specs: { 'Heel Height': '7.5 cm' } });
const SNEAKER = product(2, {
  title: 'Nike Air Jordan 1 Red And Black', color: 'Red', gender: 'men', category_slug: 'mens-shoes', category_name: "Men's Shoes",
  tags: ['footwear', 'athletic shoes'], search_keywords: 'sneakers basketball shoes gym shoes', specs: { Sole: 'Rubber cupsole with Nike Air-Sole unit in heel', Colourway: 'Red and black' },
});
const SLIPPER = product(3, { title: 'Black & Brown Slipper', color: 'Black', gender: 'women', search_keywords: 'slippers house slippers chappal', specs: { Heel: 'Flat' } });

describe('AI ranking relevance (unit, no db)', () => {
  it('RNK-01 derives shoe types from title/keywords/specs, never from spec prose', () => {
    assert.ok(A.deriveAttributes(HEEL).types.has('heel'));
    const jordan = A.deriveAttributes(SNEAKER);
    assert.ok(jordan.types.has('sneaker'));
    assert.ok(!jordan.types.has('heel'), '"Air-Sole unit in heel" is not a heel');
    const slipper = A.deriveAttributes(SLIPPER);
    assert.ok(slipper.types.has('slipper'));
    assert.ok(!slipper.types.has('heel'), 'Heel: Flat is not a heel');
  });

  it('RNK-02 derives colour families: primary, secondary and multi-colour', () => {
    const suit = A.productColors(product(4, { title: 'Marni Red & Black Suit', color: 'Red' }));
    assert.equal(suit.primary, 'red');
    assert.deepEqual(suit.secondary, ['black']);
    assert.equal(suit.multi, true);
    const off = A.productColors(product(5, { title: 'Sports Sneakers Off White & Red', color: 'Off White' }));
    assert.equal(off.primary, 'white');
    assert.ok(off.secondary.includes('red'));
    assert.equal(A.productColors(product(6, { title: 'Rolex Datejust', color: 'Rose Gold' })).primary, 'gold');
  });

  it('RNK-03 colour tiers: exact > dominant > secondary > none', () => {
    assert.equal(A.colorTier(product(7, { title: 'Tartan Dress', color: 'Red' }), 'red'), 3);
    assert.equal(A.colorTier(product(8, { title: 'Marni Red & Black Suit', color: 'Red' }), 'red'), 2);
    assert.equal(A.colorTier(product(9, { title: 'Sports Sneakers Off White & Red', color: 'Off White' }), 'red'), 1);
    assert.equal(A.colorTier(product(10, { title: "Black Women's Gown", color: 'Black' }), 'red'), 0);
  });

  it('RNK-04 an explicit colour outranks a higher score', () => {
    const slots = slotsFor('red dress');
    const red = product(11, { title: 'Tartan Dress', color: 'Red', category_slug: 'womens-dresses', rating: 3 });
    const black = product(12, { title: "Black Women's Gown", color: 'Black', category_slug: 'womens-dresses', rating: 5 });
    const scored = scoreAll([black, red], { ...ctxFor(slots), semantic: new Map([[12, 1], [11, 0.2]]), lexical: new Map([[12, 1], [11, 0.1]]) });
    assert.ok(scored.find((s) => s.p.id === 12).score > scored.find((s) => s.p.id === 11).score, 'gown scores higher on text');
    assert.deepEqual(order(scored).map((s) => s.p.id), [11, 12], 'but the red dress is listed first');
  });

  it('RNK-05 "best running shoes" keeps heels and slippers below sneakers', () => {
    const slots = slotsFor('best running shoes');
    assert.ok(slots.features.includes('running'), 'running is understood inside "running shoes"');
    const scored = scoreAll([HEEL, SLIPPER, SNEAKER], { ...ctxFor(slots), semantic: new Map([[1, 1], [3, 1], [2, 0.1]]) });
    assert.equal(order(scored)[0].p.id, 2);
    assert.equal(scored.find((s) => s.p.id === 1).fit.avoidOk, false);
  });

  it('RNK-06 gender filter also uses the category (womens-*) when the product has no gender', () => {
    const womens = product(13, { gender: null, category_slug: 'womens-shoes' });
    const unisex = product(14, { gender: 'unisex', category_slug: 'sunglasses' });
    const mens = product(15, { gender: null, category_slug: 'mens-shoes' });
    const f = filtersFromSlots({ ...S.EMPTY_SLOTS(), gender: 'men' });
    assert.deepEqual(applyFilters([womens, unisex, mens], f).map((p) => p.id), [14, 15]);
  });

  it('RNK-07 "dress" also finds frocks filed under Tops (same department)', () => {
    const frock = product(16, { title: 'Blue Frock', category_slug: 'tops', department_slug: 'fashion', search_keywords: 'blue frock blue dress' });
    const watch = product(17, { title: 'Rolex Cellini', category_slug: 'womens-watches', department_slug: 'fashion', search_keywords: 'dress watch' });
    const f = filtersFromSlots(slotsFor('blue dress'));
    assert.deepEqual(applyFilters([frock, watch], f).map((p) => p.id), [16], 'a "dress watch" is not a dress');
  });

  it('RNK-08 mmr diversity never lifts a lower constraint tier above a higher one', () => {
    const items = [
      { p: { id: 1 }, score: 0.9, tier: 1113 }, { p: { id: 2 }, score: 0.89, tier: 1113 },
      { p: { id: 3 }, score: 0.95, tier: 1110 }, { p: { id: 4 }, score: 0.5, tier: 1112 },
    ];
    // every pair looks identical except 1 vs 3, so plain mmr would love to promote item 3
    const catalog = { similarity: (a, b) => (a + b === 4 ? 0 : 1) };
    const picked = mmr(order(items), 4, catalog).map((s) => s.p.id);
    assert.deepEqual(picked.slice(0, 2).sort(), [1, 2]);
    assert.equal(picked[2], 4, 'tier 1112 before tier 1110');
    assert.equal(picked[3], 3);
  });

  it('RNK-09 nlg: no "shoes or shoes", reply describes the first card, honest partial colour match', () => {
    const catalog = { taxonomy: [{ slug: 'mens-shoes', name: "Men's Shoes" }, { slug: 'womens-shoes', name: "Women's Shoes" }, { slug: 'womens-dresses', name: "Women's Dresses" }] };
    assert.equal(nlg.describe({ ...S.EMPTY_SLOTS(), categories: ['mens-shoes', 'womens-shoes'] }, catalog), 'shoes');
    const item = (id, title, fit) => ({ product: { id, title, price: 1000 }, reasons: ['Comes in Red'], fit });
    const slots = { ...S.EMPTY_SLOTS(), categories: ['womens-dresses'], color: 'red' };
    const reply = nlg.searchReply({
      slots, catalog, seed: 1, intent: 'recommendation',
      result: { items: [item(1, 'Tartan Dress', { colorTier: 3 }), item(2, 'Marni Red & Black Suit', { colorTier: 2 }), item(3, "Black Women's Gown", { colorTier: 0 })], relaxed: [], total: 3 },
    });
    assert.match(reply, /\*\*Tartan Dress\*\*/);
    assert.ok(topPickConsistency(reply, [{ title: 'Tartan Dress' }, { title: 'Marni Red & Black Suit' }]).ok);
    assert.match(reply, /Only 2 of these come in red/);
    assert.doesNotMatch(reply, /3 dresses in red/, 'never promises all cards are red');
    const closest = nlg.searchReply({ slots, catalog, seed: 1, intent: 'product_search', result: { items: [item(2, 'Marni Red & Black Suit', { colorTier: 2 })], relaxed: [], total: 1 } });
    assert.match(closest, /closest in red is \*\*Marni Red & Black Suit\*\*/);
    const none = nlg.searchReply({ slots: { ...slots, color: 'purple' }, catalog, seed: 1, intent: 'product_search', result: { items: [item(3, "Black Women's Gown", { colorTier: 0 })], relaxed: [], total: 1 } });
    assert.match(none, /couldn't find an exact match in purple/);
  });

  it('RNK-10 an llm rewrite may not swap the top pick', () => {
    const products = [{ title: "Black Women's Gown" }, { title: 'Marni Red & Black Suit' }];
    const draft = "My top pick is **Black Women's Gown** at **Rs 36,399**.";
    assert.equal(keepsTopPick("Try the **Black Women's Gown** (Rs 36,399), or the Marni Red & Black Suit.", draft, products), true);
    assert.equal(keepsTopPick('The **Marni Red & Black Suit** is my favourite, then the Black Women\'s Gown.', draft, products), false);
  });

  it('RNK-11 head noun wins: "charger for iphone" is a charger, "sports bike" is a bike', () => {
    assert.deepEqual(nlu.analyze('charger for iphone').entities.categories, ['mobile-accessories']);
    assert.deepEqual(nlu.analyze('fast sports bike').entities.categories, ['motorcycle']);
    assert.deepEqual(nlu.analyze('phone and charger').entities.categories.sort(), ['mobile-accessories', 'smartphones']);
  });

  it('RNK-12 eval judge: secondary colour is partial, heel prose in specs is not a heel', () => {
    const exp = { color: 'red', mustMatchAny: [], mustNotMatch: ['heel'] };
    assert.equal(judge(product(18, { title: 'Sports Sneakers Off White & Red', color: 'Off White' }), exp).grade, 1);
    assert.equal(judge(SNEAKER, exp).grade, 2);
    assert.equal(judge(HEEL, { mustNotMatch: ['heel'] }).grade, 0);
  });
});

describe('AI ranking relevance (live pipeline, local db)', function live() {
  this.timeout(240000);

  it('RNK-20 "best running shoes": sneakers only, clean grammar', async () => {
    const out = await respond({ text: 'best running shoes', context: null });
    const catalog = await getCatalog();
    const top = out.meta.products.slice(0, 3).map((c) => catalog.byId.get(c.id));
    for (const p of top) {
      const { types } = A.attrsOf(p);
      assert.ok(!types.has('heel') && !types.has('slipper') && !types.has('sandal'), `${p.title} is not a running shoe`);
    }
    assert.doesNotMatch(out.content, /shoes or shoes/);
    assert.ok(topPickConsistency(out.content, out.meta.products).ok);
  });

  it('RNK-21 "Suggest a best red dress for women": red first and the reply describes the first card', async () => {
    const out = await respond({ text: 'Suggest a best red dress for women', context: null });
    const catalog = await getCatalog();
    const first = catalog.byId.get(out.meta.products[0].id);
    assert.ok(A.colorTier(first, 'red') >= 2, `${first.title} should be red`);
    assert.match(out.content, new RegExp(`\\*\\*${first.title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\*\\*`));
    assert.ok(topPickConsistency(out.content, out.meta.products).ok);
  });

  it('RNK-22 golden set: every query not marked knownFailure passes (regression gate)', async () => {
    const { summary } = await runEval({ respond, getCatalog });
    // baseline achieved when this gate was added: 138/138 queries, 0 hard-constraint violations (BEFORE: 105/138)
    assert.deepEqual(summary.unexpectedFailures, [], `failing queries: ${summary.unexpectedFailures.join(' | ')} — run npm run ai:eval`);
    assert.ok(summary.passRate >= 0.95, `pass rate ${(summary.passRate * 100).toFixed(1)}% fell below 95%`);
    assert.equal(summary.inconsistentReplies, 0);
  });
});
