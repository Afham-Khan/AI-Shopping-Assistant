const assert = require('node:assert/strict');
const { knapsack, TEMPLATES } = require('../api/modules/ai/engine/bundle');
const { questionType, specIntent, buildPassages, looksLikeQuestion } = require('../api/modules/ai/engine/qa');
const { detectCategory } = require('../api/modules/ai/engine/visual');
const { PERSONAS } = require('../api/modules/ai/engine/shoppingDna');
const nlu = require('../api/modules/ai/engine/nlu');

const cand = (id, price, utility) => ({ p: { id, price }, utility });

describe('AI phase 2 features (unit, no db)', () => {
  describe('bundle optimizer', () => {
    it('FEA-01 knapsack maximizes value within budget, one item per role', () => {
      const groups = [
        { required: true, weight: 3, candidates: [cand(1, 300, 0.9), cand(2, 150, 0.6)] },
        { required: true, weight: 1, candidates: [cand(3, 100, 0.8), cand(4, 40, 0.5)] },
        { required: false, weight: 1, candidates: [cand(5, 80, 0.9)] },
      ];
      const { selected } = knapsack(groups, 450);
      const ids = selected.map((s) => s && s.p.id);
      const total = selected.filter(Boolean).reduce((s, x) => s + x.p.price, 0);
      assert.ok(total <= 450);
      assert.equal(ids[0], 1); // the heavy-weight role gets the best item
      assert.ok(ids[1] === 3 || ids[1] === 4);
    });

    it('FEA-02 required roles are always filled when feasible; optional ones skipped if needed', () => {
      const groups = [
        { required: true, weight: 1, candidates: [cand(1, 90, 0.5)] },
        { required: false, weight: 5, candidates: [cand(2, 50, 1)] },
      ];
      const { selected } = knapsack(groups, 100);
      assert.equal(selected[0].p.id, 1);
      assert.equal(selected[1], null);
    });

    it('FEA-03 infeasible required set returns null', () => {
      assert.equal(knapsack([{ required: true, weight: 1, candidates: [cand(1, 500, 1)] }], 100), null);
    });

    it('FEA-04 templates are well formed and the bundle intent is trained', () => {
      assert.ok(Object.keys(TEMPLATES).length >= 8);
      for (const t of Object.values(TEMPLATES)) {
        assert.ok(t.roles.some((r) => r.required));
        assert.ok(t.triggers.length && t.description);
      }
      assert.equal(nlu.analyze('build me a gaming setup under 400k').intent, 'bundle');
      assert.equal(nlu.analyze('gaming setup bana do 4 lakh mein').entities.budget.max, 400000);
    });
  });

  describe('product q&a', () => {
    it('FEA-05 question types and spec intents', () => {
      assert.equal(questionType('does it have fast charging'), 'yesno');
      assert.equal(questionType('how much ram does it have'), 'lookup');
      assert.equal(questionType('how good is the camera'), 'opinion');
      assert.equal(specIntent('how much ram does it have'), 'ram');
      assert.equal(specIntent('is the screen bright'), 'display');
      assert.equal(specIntent('tell me something'), null);
      assert.equal(looksLikeQuestion('does the second one have a good camera?'), true);
      assert.equal(looksLikeQuestion('show me laptops'), false);
    });

    it('FEA-06 passages cover specs, policies, description and review sentences', () => {
      const passages = buildPassages(
        { specs: { RAM: '8 GB' }, highlights: ['Big battery'], warranty: '1 year warranty', return_policy: '7 days', description: 'A phone. It is fast.', color: 'Black' },
        [{ rating: 5, comment: 'Battery lasts all day. Camera is decent in daylight.' }],
      );
      assert.ok(passages.some((p) => p.source === 'spec' && p.text === 'RAM: 8 GB'));
      assert.ok(passages.some((p) => p.text.startsWith('Warranty:')));
      assert.equal(passages.filter((p) => p.source === 'description').length, 2);
      assert.equal(passages.filter((p) => p.source === 'review').length, 2);
    });
  });

  describe('visual + profile', () => {
    it('FEA-07 zero-shot detection is a softmax over scaled cosine', () => {
      const unit = (i) => Float32Array.from({ length: 4 }, (_, k) => (k === i ? 1 : 0));
      const cats = [{ slug: 'a', name: 'A', vec: unit(0) }, { slug: 'b', name: 'B', vec: unit(1) }];
      const r = detectCategory(Float32Array.from([0.9, 0.1, 0, 0]), cats);
      assert.equal(r.category.slug, 'a');
      assert.ok(r.confidence > 0.99);
      assert.ok(Math.abs(r.top.reduce((s, x) => s + x.p, 0) - 1) < 1e-9);
    });

    it('FEA-08 persona prototypes respond to their traits', () => {
      const t = { price: 0.1, brand: 0, deal: 0, quality: 0.2, trend: 0.1, breadth: 0.1, research: 0.1 };
      const d = { electronics: 0, fashion: 0, beauty: 0, home: 0, groceries: 0, sports: 0, automotive: 0 };
      const best = (traits, depts) => PERSONAS.map((p) => ({ title: p.title, v: p.score(traits, depts, { branded: 10 }) })).sort((a, b) => b.v - a.v)[0].title;
      assert.equal(best(t, { ...d, electronics: 0.9 }), 'The Tech Enthusiast');
      assert.equal(best({ ...t, price: 0.95, deal: 0.9 }, d), 'The Smart Saver');
      assert.equal(best({ ...t, brand: 0.95 }, d), 'The Brand Loyalist');
      assert.equal(best(t, { ...d, beauty: 0.9 }), 'The Beauty Buff');
    });
  });
});
