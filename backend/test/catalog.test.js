const assert = require('node:assert/strict');
const { api } = require('./helpers');

const CATALOG = '/api/v1/catalog';

describe('Catalog', () => {
  it('CAT-01 lists departments with nested categories and counts', async () => {
    const res = await api.get(`${CATALOG}/departments`);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.length, 7);
    const electronics = res.body.data.find((d) => d.slug === 'electronics');
    assert.equal(electronics.icon, 'devices');
    assert.ok(electronics.categories.some((c) => c.slug === 'smartphones'));
    res.body.data.forEach((d) => {
      assert.equal(d.productCount, d.categories.reduce((s, c) => s + c.productCount, 0));
      assert.ok(d.productCount > 0);
    });
  });

  it('CAT-02 returns category detail with brand facets and price range', async () => {
    const res = await api.get(`${CATALOG}/categories/smartphones`);
    assert.equal(res.status, 200);
    const c = res.body.data;
    assert.equal(c.department.slug, 'electronics');
    assert.ok(c.brands.length > 0);
    assert.ok(c.brands.every((b) => typeof b.name === 'string' && b.count > 0));
    assert.ok(c.priceRange.min > 0 && c.priceRange.min <= c.priceRange.max);
  });

  it('CAT-03 unknown category is 404', async () => {
    assert.equal((await api.get(`${CATALOG}/categories/time-machines`)).status, 404);
  });

  it('CAT-04 home feed has every section', async () => {
    const res = await api.get(`${CATALOG}/home`);
    assert.equal(res.status, 200);
    const home = res.body.data;
    assert.ok(home.banners.length >= 4);
    assert.ok(home.banners.some((b) => b.target.type === 'assistant'));
    assert.equal(home.departments.length, 7);
    assert.equal(home.departments[0].categories, undefined);
    ['flashDeals', 'trending', 'topRated', 'newArrivals'].forEach((key) => assert.ok(home[key].length > 0, key));
    assert.ok(home.flashDeals.every((p) => p.discountPercent >= 10 && p.inStock));
    assert.ok(new Date(home.dealEndsAt) > new Date());
  });
});
