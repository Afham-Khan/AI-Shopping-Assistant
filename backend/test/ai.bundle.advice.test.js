const assert = require('node:assert/strict');
const { niceCeil, TEMPLATES, chooseTemplate } = require('../api/modules/ai/engine/bundle');
const { api, db, registerUser } = require('./helpers');

const AI = '/api/v1/ai';

const dbReady = async () => {
  try {
    return Number((await db('products').count('* as c').first()).c) > 0;
  } catch {
    return false;
  }
};

describe('AI bundle budget advice (unit, no db)', () => {
  it('BAD-01 niceCeil rounds up to figures a shopper would type', () => {
    assert.equal(niceCeil(0), 0);
    assert.equal(niceCeil(299), 500);
    assert.equal(niceCeil(5298 * 1.15), 6500);
    assert.equal(niceCeil(24100), 25000);
    assert.equal(niceCeil(321998 * 1.15), 375000);
    assert.equal(niceCeil(1200000), 1200000);
    assert.equal(niceCeil(1200001), 1300000);
    for (const n of [1, 499, 9999, 54321, 99999, 250001, 999999, 4321987]) assert.ok(niceCeil(n) >= n);
  });

  it('BAD-02 every template carries a goal phrase and a label for the app', () => {
    for (const t of Object.values(TEMPLATES)) {
      assert.ok(typeof t.goal === 'string' && t.goal.length >= 4, `${t.title} needs a goal`);
      assert.ok(t.title.length >= 4);
    }
  });
});

describe('AI bundle budget advice (integration)', function advice() {
  this.timeout(120000);

  before(async function setup() {
    if (!(await dbReady())) return this.skip();
    return null;
  });

  describe('GET /ai/bundle/templates', () => {
    let templates;
    before(async () => {
      const res = await api.get(`${AI}/bundle/templates`).expect(200);
      templates = res.body.data;
    });

    it('BAD-03 lists every ready-made goal with a suggested budget and its roles', () => {
      assert.ok(Array.isArray(templates));
      assert.deepEqual(templates.map((t) => t.id).sort(), Object.keys(TEMPLATES).sort());
      templates.forEach((t) => {
        assert.ok(t.goal && t.label, `${t.id} goal/label`);
        assert.ok(Number.isInteger(t.suggestedBudget) && t.suggestedBudget > 0, `${t.id} suggestedBudget`);
        assert.ok(Array.isArray(t.roles) && t.roles.length >= 3);
        t.roles.forEach((r) => {
          assert.ok(typeof r.role === 'string' && typeof r.required === 'boolean');
          assert.ok(r.minPrice === null || r.minPrice > 0);
        });
        assert.ok(t.roles.some((r) => r.required));
      });
    });

    it('BAD-04 suggested budget is the required roles at their cheapest plus ~15% headroom, rounded up', () => {
      templates.forEach((t) => {
        const min = t.roles.filter((r) => r.required).reduce((s, r) => s + (r.minPrice || 0), 0);
        assert.ok(t.suggestedBudget >= Math.ceil(min * 1.15), `${t.id}: ${t.suggestedBudget} < 115% of ${min}`);
        assert.ok(t.suggestedBudget <= min * 1.15 + 100000, `${t.id}: ${t.suggestedBudget} is not a tight round-up of ${min * 1.15}`);
        assert.equal(t.suggestedBudget, niceCeil(min * 1.15));
      });
    });

    it('BAD-05 each template goal routes back to its own template', async () => {
      for (const t of templates) {
        assert.equal(await chooseTemplate(t.goal, { categories: [] }), t.id, `"${t.goal}" should pick ${t.id}`);
      }
    });

    it('BAD-06 is public (no login) and cheap to call repeatedly', async () => {
      const again = await api.get(`${AI}/bundle/templates`).expect(200);
      assert.deepEqual(again.body.data, templates);
    });

    it('BAD-07 the POST /bundle route still works next to it and validates as before', async () => {
      await api.post(`${AI}/bundle`).send({ goal: 'gym', budget: 10 }).expect(400);
    });
  });

  describe('POST /ai/bundle budgetAdvice', () => {
    it('BAD-08 tight budget: required roles are skipped and the explanation says so honestly', async () => {
      const res = await api.post(`${AI}/bundle`).send({ goal: 'gaming setup', budget: 150000 }).expect(200);
      const b = res.body.data;
      const adv = b.budgetAdvice;
      assert.ok(adv, 'budgetAdvice present');
      // backwards compatible fields are all still there
      ['title', 'template', 'goal', 'total', 'budget', 'remaining', 'items', 'skippedRoles', 'explanation', 'savingsTips'].forEach((k) => assert.ok(k in b, k));
      assert.equal(b.template, 'gaming_setup');
      assert.ok(b.total <= 150000);
      // the laptop is the one required role that cannot fit
      const laptop = adv.cheapestByRole.find((r) => r.role === 'Gaming laptop');
      assert.ok(laptop && laptop.price > 150000, 'cheapest gaming laptop is above the budget');
      assert.ok(b.skippedRoles.includes('Gaming laptop'));
      assert.ok(adv.missingRequired.includes('Gaming laptop'));
      assert.match(adv.message, /No gaming laptop fits Rs 150,000/);
      assert.ok(adv.message.includes(`Rs ${laptop.price.toLocaleString('en-US')}`), 'message names the cheapest price');
      assert.match(adv.message, /Raise the budget to about Rs [\d,]+ to include it\./);
      assert.ok(b.explanation.includes(adv.message), 'explanation carries the same honest message');
      assert.ok(adv.suggestedBudget > laptop.price);
      assert.ok(adv.message.includes(`Rs ${adv.suggestedBudget.toLocaleString('en-US')}`));
    });

    it('BAD-09 minimums are sums of the cheapest viable product per role, backed by real products', async () => {
      const res = await api.post(`${AI}/bundle`).send({ goal: 'home office', budget: 150000 }).expect(200);
      const adv = res.body.data.budgetAdvice;
      assert.ok(adv.cheapestByRole.length >= 3);
      adv.cheapestByRole.forEach((r) => {
        assert.ok(r.role && r.price > 0 && Number.isInteger(r.productId));
      });
      const ids = adv.cheapestByRole.map((r) => r.productId);
      assert.equal(new Set(ids).size, ids.length, 'a product fills one role only');
      const rows = await db('products').whereIn('id', ids).select('id', 'price', 'stock');
      assert.equal(rows.length, ids.length);
      rows.forEach((row) => assert.ok(row.stock > 0));
      assert.equal(adv.minimumForAll, adv.cheapestByRole.reduce((s, r) => s + r.price, 0));
      assert.ok(adv.minimumForRequired > 0 && adv.minimumForRequired <= adv.minimumForAll);
      const requiredRoles = ['Laptop', 'Office chair'];
      assert.equal(adv.minimumForRequired, adv.cheapestByRole.filter((r) => requiredRoles.includes(r.role)).reduce((s, r) => s + r.price, 0));
      assert.ok(adv.suggestedBudget >= adv.minimumForRequired * 1.15);
      // the cheapest product for a role really is the cheapest in-stock product that could fill it
      const chair = adv.cheapestByRole.find((r) => r.role === 'Office chair');
      const cheaperChair = await db('products as p').join('categories as c', 'c.id', 'p.category_id')
        .where('c.slug', 'furniture').where('p.stock', '>', 0).whereRaw('lower(p.title) like ?', ['%chair%']).where('p.price', '<', chair.price)
        .first('p.id');
      assert.equal(cheaperChair, undefined, 'no cheaper chair exists');
    });

    it('BAD-10 following the advice works: the suggested budget includes every required role', async () => {
      for (const goal of ['gaming setup', 'home office', 'university starter kit', 'skincare routine']) {
        const tight = (await api.post(`${AI}/bundle`).send({ goal, budget: 1000 }).expect(200)).body.data;
        assert.ok(tight.budgetAdvice.missingRequired.length, `${goal}: tight budget misses essentials`);
        assert.ok(tight.budgetAdvice.suggestedBudget > 1000);
        const fixed = (await api.post(`${AI}/bundle`).send({ goal, budget: tight.budgetAdvice.suggestedBudget }).expect(200)).body.data;
        assert.deepEqual(fixed.budgetAdvice.missingRequired, [], `${goal}: suggested budget should include the essentials`);
        const required = fixed.items.filter((i) => i.required);
        assert.ok(required.length >= 2, `${goal}: required items present`);
        assert.ok(fixed.total <= fixed.budget);
        assert.doesNotMatch(fixed.explanation, /No .* fits/);
      }
    });

    it('BAD-11 the suggested budget matches the template listing for the same goal', async () => {
      const list = (await api.get(`${AI}/bundle/templates`).expect(200)).body.data;
      const gaming = list.find((t) => t.id === 'gaming_setup');
      const b = (await api.post(`${AI}/bundle`).send({ goal: gaming.goal, budget: 1000 }).expect(200)).body.data;
      assert.equal(b.budgetAdvice.suggestedBudget, gaming.suggestedBudget);
    });

    it('BAD-12 generous budget: nothing is missing and the message says everything fits', async () => {
      const b = (await api.post(`${AI}/bundle`).send({ goal: 'gym starter pack', budget: 300000 }).expect(200)).body.data;
      assert.deepEqual(b.budgetAdvice.missingRequired, []);
      assert.deepEqual(b.skippedRoles, []);
      assert.match(b.budgetAdvice.message, /Everything fits/);
      assert.ok(b.budgetAdvice.minimumForAll <= b.total);
      assert.doesNotMatch(b.explanation, /Raise the budget/);
    });

    it('BAD-13 essentials fit but an optional piece does not: no raise-the-budget scare for required roles', async () => {
      const templates = (await api.get(`${AI}/bundle/templates`).expect(200)).body.data;
      const gaming = templates.find((t) => t.id === 'gaming_setup');
      const b = (await api.post(`${AI}/bundle`).send({ goal: gaming.goal, budget: gaming.suggestedBudget }).expect(200)).body.data;
      assert.deepEqual(b.budgetAdvice.missingRequired, []);
      if (b.skippedRoles.length) {
        assert.match(b.budgetAdvice.message, /Your essentials fit/);
        assert.ok(b.budgetAdvice.message.includes(`Rs ${b.budgetAdvice.minimumForAll.toLocaleString('en-US')}`));
      }
    });

    it('BAD-14 chat bundle replies carry the advice when the essentials do not fit', async () => {
      const session = await registerUser({ email: `test+bad${Date.now()}@cartwise.test` });
      const res = await api.post(`${AI}/chat`).set(session.auth).send({ message: 'build me a gaming setup under 100k' }).expect(200);
      const msg = res.body.data.message;
      assert.equal(msg.meta.intent, 'bundle');
      assert.ok(msg.meta.bundle.budgetAdvice.missingRequired.length);
      assert.match(msg.content, /Raise the budget to about Rs [\d,]+/);
      assert.ok(msg.meta.suggestions.some((x) => x.includes(`${msg.meta.bundle.budgetAdvice.suggestedBudget / 1000}k`)));
    });
  });
});
