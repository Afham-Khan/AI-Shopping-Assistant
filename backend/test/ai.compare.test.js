const assert = require('node:assert/strict');
const { buildComparison, parseQuantity } = require('../api/modules/ai/engine/compare');

const phone = (id, over) => ({
  id, title: `Phone ${id}`, brand_name: 'Brand', price: 100000, rating: 4, rating_count: 10, discount_percent: 0, stock: 10,
  warranty: '1 year warranty', return_policy: '7 days return policy', specs: {}, ...over,
});

describe('AI compare (unit, no db)', () => {
  it('CMP-01 parses unit-tagged quantities', () => {
    assert.deepEqual(parseQuantity('Quad: 64 MP + 8 MP + 2 MP'), { unit: 'mp', value: 64 });
    assert.deepEqual(parseQuantity('1 TB SSD'), { unit: 'gb', value: 1024 });
    assert.deepEqual(parseQuantity('2 year warranty'), { unit: 'month', value: 24 });
    assert.equal(parseQuantity('Graphite'), null);
  });

  const products = [
    phone(1, { title: 'Budget Phone', price: 40000, rating: 3.9, rating_count: 20, specs: { RAM: '4 GB', Weight: '200 g', Battery: '5000 mAh' } }),
    phone(2, { title: 'Value Phone', price: 70000, rating: 4.6, rating_count: 50, discount_percent: 15, specs: { RAM: '8 GB', Weight: '180 g', Battery: '4500 mAh' } }),
    phone(3, { title: 'Flagship Phone', price: 300000, rating: 4.7, rating_count: 30, warranty: '2 year warranty', specs: { ram: '12 GB', Weight: '170 g', Battery: '4000 mAh' } }),
  ];

  it('CMP-02 rows mark numeric winners in the right direction', () => {
    const { rows } = buildComparison(products);
    const row = (label) => rows.find((r) => r.label.toLowerCase() === label.toLowerCase());
    assert.equal(row('Price').bestIndex, 0);
    assert.equal(row('Rating').bestIndex, 2);
    assert.equal(row('RAM').bestIndex, 2); // case-insensitive key union
    assert.equal(row('Weight').bestIndex, 2); // lower is better
    assert.equal(row('Battery').bestIndex, 0);
    assert.equal(row('Brand').bestIndex, null);
    assert.equal(row('Warranty').bestIndex, 2);
    rows.forEach((r) => assert.equal(r.values.length, 3));
  });

  it('CMP-03 verdict picks', () => {
    const { verdict } = buildComparison(products);
    const pick = (label) => verdict.picks.find((p) => p.label === label);
    assert.equal(pick('Best value').productId, 2);
    assert.equal(pick('Top rated').productId, 3);
    assert.equal(pick('Budget pick').productId, 1);
    assert.equal(pick('Premium pick').productId, 3);
    verdict.picks.forEach((p) => assert.ok(p.reason.length > 10));
  });

  it('CMP-04 summary names the best value product', () => {
    const { verdict } = buildComparison(products);
    assert.match(verdict.summary, /Value Phone is the best value/);
  });
});
