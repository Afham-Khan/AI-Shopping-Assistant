const assert = require('node:assert/strict');
const fs = require('fs');
const nlu = require('../api/modules/ai/engine/nlu');
const { MODEL_FILE } = require('../api/modules/ai/engine/nlu/trainer');

const ents = (text) => nlu.analyze(text).entities;

describe('AI NLU (unit, no db)', () => {
  describe('budget parsing', () => {
    it('NLU-01 under 50k', () => {
      const e = ents('phones under 50k');
      assert.deepEqual(e.budget, { min: null, max: 50000 });
      assert.equal(e.category, 'smartphones');
    });
    it('NLU-02 1.5 lakh with features', () => {
      const e = ents('gaming laptop under 1.5 lakh');
      assert.equal(e.budget.max, 150000);
      assert.equal(e.category, 'laptops');
      assert.deepEqual(e.features, ['gaming']);
    });
    it('NLU-03 between X and Y', () => assert.deepEqual(ents('phones between 20k and 40k').budget, { min: 20000, max: 40000 }));
    it('NLU-04 dollars converted to PKR', () => assert.equal(ents('headphones under $200').budget.max, 56000));
    it('NLU-05 Rs prefix and comma groups', () => {
      assert.equal(ents('Rs. 25,000 ka phone').budget.max, 25000);
      assert.equal(ents('laptop under 1,50,000').budget.max, 150000);
    });
    it('NLU-06 around gives a band with a target', () => assert.deepEqual(ents('gift around 10k').budget, { min: 8000, max: 12000, target: 10000 }));
    it('NLU-07 lac and L suffixes', () => {
      assert.equal(ents('bike 2 lac tak').budget.max, 200000);
      assert.equal(ents('laptop under 1.5L').budget.max, 150000);
    });
    it('NLU-08 model numbers and specs are not budgets', () => {
      assert.equal(ents('iphone 13').budget, null);
      assert.equal(ents('laptop with 16 gb ram').budget, null);
      assert.equal(ents('phone with 5000 mah battery').budget, null);
    });
  });

  describe('taxonomy, synonyms and typos', () => {
    it('NLU-09 synonyms map to categories', () => {
      assert.equal(ents('mobile').category, 'smartphones');
      assert.equal(ents('i need a notebook').category, 'laptops');
      assert.equal(ents('sneakers for men').category, 'mens-shoes');
      assert.equal(ents('a nice scent').category, 'fragrances');
      assert.equal(ents('sofa').category, 'furniture');
      assert.equal(ents('makeup kit').category, 'beauty');
    });
    it('NLU-10 generic words resolve by gender', () => {
      const w = ents('watch for my husband');
      assert.equal(w.category, 'mens-watches');
      assert.equal(w.gender, 'men');
      const s = ents('shoes for my sister');
      assert.equal(s.category, 'womens-shoes');
      assert.equal(s.gender, 'women');
    });
    it('NLU-11 typos are corrected', () => {
      const a = nlu.analyze('smartphnoe under 50,000');
      assert.equal(a.entities.category, 'smartphones');
      assert.deepEqual(a.corrections[0], { from: 'smartphnoe', to: 'smartphone' });
      assert.equal(ents('laptp for gaming').category, 'laptops');
      const s = ents('samsng galxy');
      assert.deepEqual(s.brands, ['samsung']);
      assert.equal(s.category, 'smartphones');
    });
    it('NLU-12 everyday words are not "corrected"', () => {
      assert.deepEqual(nlu.analyze('see you later').corrections, []);
      assert.deepEqual(nlu.analyze('bye take care').corrections, []);
    });
    it('NLU-19 "something for my kitchen"', () => {
      const e = ents('something for my kitchen');
      assert.equal(e.category, 'kitchen-accessories');
      assert.equal(e.department, 'home-living');
    });
    it('NLU-20 apple the fruit is not Apple the brand', () => assert.deepEqual(ents('fresh green apples').brands, []));
  });

  describe('roman urdu', () => {
    it('NLU-13 sasta mobile chahiye 30k tak', () => {
      const a = nlu.analyze('sasta mobile chahiye 30k tak');
      assert.equal(a.entities.category, 'smartphones');
      assert.equal(a.entities.budget.max, 30000);
      assert.equal(a.entities.sort, 'price_asc');
      assert.ok(['product_search', 'budget_query'].includes(a.intent));
    });
    it('NLU-14 "se kam" idiom', () => {
      const e = ents('50 hazar se kam joote');
      assert.equal(e.budget.max, 50000);
      assert.ok(e.categories.includes('mens-shoes') && e.categories.includes('womens-shoes'));
    });
  });

  describe('references, negations, recipients', () => {
    it('NLU-15 ordinals', () => {
      assert.deepEqual(ents('compare the first two').ordinals.indices, [1, 2]);
      assert.deepEqual(ents('tell me more about the 3rd').ordinals.indices, [3]);
      assert.deepEqual(ents('add the last one').ordinals.indices, [-1]);
      assert.deepEqual(ents('compare 1 and 3').ordinals.indices, [1, 3]);
      assert.deepEqual(ents('doosra wala').ordinals.indices, [2]);
    });
    it('NLU-16 negations', () => {
      const e = ents('samsung phones not apple');
      assert.deepEqual(e.brands, ['samsung']);
      assert.deepEqual(e.excludeBrands, ['apple']);
      assert.deepEqual(ents('shoes no black').excludeColors, ['black']);
      assert.deepEqual(ents('apple nahi chahiye').excludeBrands, ['apple']);
      assert.deepEqual(ents('not apple or samsung').excludeBrands, ['apple', 'samsung']);
    });
    it('NLU-17 recipients imply gender', () => {
      const mom = ents('gift for mom');
      assert.equal(mom.recipient, 'mom');
      assert.equal(mom.gender, 'women');
      const bro = ents('present for my brother');
      assert.equal(bro.recipient, 'brother');
      assert.equal(bro.gender, 'men');
    });
    it('NLU-18 occasion, rating, sort', () => {
      const e = ents('perfume for eid 4 stars+ best rated');
      assert.equal(e.occasion, 'eid');
      assert.equal(e.minRating, 4);
      assert.equal(e.sort, 'rating');
      assert.equal(e.category, 'fragrances');
    });
  });

  describe('intent classifier', () => {
    it('NLU-21 trained artifact meets the quality bar', () => {
      const artifact = JSON.parse(fs.readFileSync(MODEL_FILE, 'utf8'));
      assert.ok(artifact.metrics.testAccuracy >= 0.9, `accuracy ${artifact.metrics.testAccuracy}`);
      assert.ok(artifact.classes.length >= 15);
      for (const n of Object.values(artifact.samplesPerClass)) assert.ok(n >= 40);
      assert.ok(artifact.metrics.perClass.product_search.recall > 0.8);
      const info = nlu.modelInfo();
      assert.ok(info.vocabularySize > 1000);
      assert.ok(info.calibration.temperature > 0);
    });

    const cases = [
      ['hello there', 'greeting'], ['allah hafiz', 'goodbye'], ['thanks a lot', 'thanks'], ['what can you do', 'help'],
      ['show me running shoes', 'product_search'], ['which phone should i buy', 'recommendation'], ['my budget is 50k', 'budget_query'],
      ['compare the first two', 'compare'], ['tell me more about the second one', 'product_info'], ['show cheaper options', 'refine_cheaper'],
      ['something more premium', 'refine_premium'], ['only samsung', 'refine_filter'], ['i need a gift for my mom', 'gift_suggestion'],
      ['any discounts today', 'deals'], ['where is my order', 'order_status'], ["what's in my cart", 'cart_help'],
      ['how do i return an item', 'return_policy'], ['add the second one to my cart', 'add_to_cart'], ['show more', 'show_more'],
      ['tell me a joke', 'small_talk'], ['mera order kahan hai', 'order_status'], ['sasta dikhao', 'refine_cheaper'],
    ];
    for (const [text, intent] of cases) {
      it(`NLU-22 "${text}" -> ${intent}`, () => {
        const a = nlu.analyze(text);
        assert.equal(a.intent, intent);
        assert.ok(a.confidence > 0 && a.confidence <= 1);
        assert.ok(Array.isArray(a.alternatives));
      });
    }

    it('NLU-23 gibberish has low confidence', () => {
      const a = nlu.analyze('asdfgh qwerty zxcv');
      assert.ok(a.confidence < 0.45, `confidence ${a.confidence}`);
    });

    it('NLU-24 entities rescue low-confidence input', () => {
      const a = nlu.analyze('zzqx laptop');
      assert.equal(a.intent, 'product_search');
    });

    it('analysis is fast', () => {
      const t = Date.now();
      for (let i = 0; i < 50; i += 1) nlu.analyze('gaming laptop under 1.5 lakh not dell');
      assert.ok(Date.now() - t < 1500);
    });
  });
});
