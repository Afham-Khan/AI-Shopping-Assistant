const assert = require('node:assert/strict');
const { api, db, registerUser, productRow } = require('./helpers');

const PRODUCTS = '/api/v1/products';

const isSorted = (values, dir = 'asc') =>
  values.every((v, i) => i === 0 || (dir === 'asc' ? values[i - 1] <= v : values[i - 1] >= v));

describe('Products', () => {
  // product detail bumps view_count on seeded rows; undo it afterwards
  const views = new Map();
  const viewDetail = async (idOrSlug, productId, auth) => {
    const req = api.get(`${PRODUCTS}/${idOrSlug}`);
    if (auth) req.set(auth);
    const res = await req;
    if (res.status === 200) views.set(productId, (views.get(productId) || 0) + 1);
    return res;
  };
  after(async () => {
    for (const [id, n] of views) await db('products').where({ id }).decrement('view_count', n);
  });

  describe('listing', () => {
    it('PRD-01 default list returns cards with pagination and facets', async () => {
      const res = await api.get(PRODUCTS);
      assert.equal(res.status, 200);
      assert.equal(res.body.data.length, 20);
      const { meta } = res.body;
      assert.equal(meta.page, 1);
      assert.equal(meta.limit, 20);
      assert.ok(meta.total >= 190);
      assert.equal(meta.totalPages, Math.ceil(meta.total / 20));
      assert.ok(meta.facets.brands.length > 0);
      assert.ok(meta.facets.priceRange.max > meta.facets.priceRange.min);
      const card = res.body.data[0];
      ['id', 'title', 'slug', 'brand', 'category', 'price', 'compareAtPrice', 'discountPercent', 'rating', 'ratingCount', 'stock', 'inStock', 'thumbnail', 'tags']
        .forEach((k) => assert.ok(k in card, k));
    });

    it('PRD-02 validates query params', async () => {
      assert.equal((await api.get(`${PRODUCTS}?limit=61`)).status, 400);
      assert.equal((await api.get(`${PRODUCTS}?sort=bogus`)).status, 400);
      assert.equal((await api.get(`${PRODUCTS}?minRating=6`)).status, 400);
      assert.equal((await api.get(`${PRODUCTS}?minPrice=5000&maxPrice=100`)).status, 400);
    });

    it('PRD-03 filters by category', async () => {
      const res = await api.get(`${PRODUCTS}?category=smartphones&limit=60`);
      assert.equal(res.status, 200);
      assert.ok(res.body.data.every((p) => p.category.slug === 'smartphones'));
      const detail = await api.get('/api/v1/catalog/departments');
      const count = detail.body.data.flatMap((d) => d.categories).find((c) => c.slug === 'smartphones').productCount;
      assert.equal(res.body.meta.total, count);
    });

    it('PRD-04 filters by brand list without shrinking the brand facet', async () => {
      const res = await api.get(`${PRODUCTS}?category=smartphones&brand=apple,samsung&limit=60`);
      assert.equal(res.status, 200);
      assert.ok(res.body.data.length > 0);
      assert.ok(res.body.data.every((p) => ['Apple', 'Samsung'].includes(p.brand)));
      assert.ok(res.body.meta.facets.brands.some((b) => !['Apple', 'Samsung'].includes(b.name)));
    });

    it('PRD-05 filters by price range', async () => {
      const res = await api.get(`${PRODUCTS}?minPrice=10000&maxPrice=50000&limit=60`);
      assert.ok(res.body.data.length > 0);
      assert.ok(res.body.data.every((p) => p.price >= 10000 && p.price <= 50000));
    });

    it('PRD-06 filters by rating, stock, sale and gender', async () => {
      const rated = await api.get(`${PRODUCTS}?minRating=4&limit=60`);
      assert.ok(rated.body.data.every((p) => p.rating >= 4));
      const stocked = await api.get(`${PRODUCTS}?inStock=true&limit=60`);
      assert.ok(stocked.body.data.every((p) => p.inStock));
      const sale = await api.get(`${PRODUCTS}?onSale=true&limit=60`);
      assert.ok(sale.body.data.length > 0 && sale.body.data.every((p) => p.compareAtPrice > p.price && p.discountPercent > 0));
      const women = await api.get(`${PRODUCTS}?gender=women&department=fashion&limit=60`);
      assert.ok(women.body.data.length > 0);
      assert.ok(women.body.data.every((p) => !p.category.slug.startsWith('mens-')));
    });

    it('PRD-07 sorts correctly', async () => {
      const asc = (await api.get(`${PRODUCTS}?sort=price_asc&limit=60`)).body.data.map((p) => p.price);
      assert.ok(isSorted(asc, 'asc'));
      const desc = (await api.get(`${PRODUCTS}?sort=price_desc&limit=60`)).body.data.map((p) => p.price);
      assert.ok(isSorted(desc, 'desc'));
      const rating = (await api.get(`${PRODUCTS}?sort=rating&limit=60`)).body.data.map((p) => p.rating);
      assert.ok(isSorted(rating, 'desc'));
      const discount = (await api.get(`${PRODUCTS}?sort=discount&limit=60`)).body.data.map((p) => p.discountPercent);
      assert.ok(isSorted(discount, 'desc'));
    });

    it('PRD-08 paginates without overlap', async () => {
      const p1 = await api.get(`${PRODUCTS}?sort=price_asc&limit=10&page=1`);
      const p2 = await api.get(`${PRODUCTS}?sort=price_asc&limit=10&page=2`);
      const ids1 = p1.body.data.map((p) => p.id);
      assert.equal(p2.body.meta.page, 2);
      assert.equal(p1.body.meta.total, p2.body.meta.total);
      assert.ok(p2.body.data.every((p) => !ids1.includes(p.id)));
    });

    it('PRD-09 full-text search ranks title matches first', async () => {
      const res = await api.get(`${PRODUCTS}?q=iphone`);
      assert.equal(res.status, 200);
      assert.ok(res.body.data.length > 0);
      assert.match(res.body.data[0].title, /iphone/i);
    });

    it('PRD-10 partial words fall back to ILIKE', async () => {
      const res = await api.get(`${PRODUCTS}?q=lipst`);
      assert.ok(res.body.data.some((p) => p.title === 'Red Lipstick'));
    });

    it('PRD-15 relaxes to any-word matching when all-words finds nothing', async () => {
      const res = await api.get(`${PRODUCTS}?q=gaming%20laptop`);
      assert.equal(res.status, 200);
      assert.equal(res.body.meta.relaxedSearch, true);
      assert.ok(res.body.data.some((p) => p.category.slug === 'laptops'));
      const strict = await api.get(`${PRODUCTS}?q=apple%20iphone`);
      assert.equal(strict.body.meta.relaxedSearch, undefined);
    });
  });

  describe('detail & recently viewed', () => {
    let product;
    before(async () => { product = await db('products').where('external_id', 123).first(); });

    it('PRD-11 detail by id and slug match', async () => {
      const byId = await viewDetail(product.id, product.id);
      const bySlug = await viewDetail(product.slug, product.id);
      assert.equal(byId.status, 200);
      assert.equal(bySlug.status, 200);
      const d = byId.body.data;
      assert.equal(d.id, bySlug.body.data.id);
      assert.ok(d.images.length > 0);
      assert.deepEqual(Object.keys(d.ratingBreakdown).sort(), ['1', '2', '3', '4', '5']);
      assert.equal(typeof d.specs, 'object');
      assert.equal(d.department.slug, 'electronics');
      ['description', 'highlights', 'gender', 'color', 'weight', 'dimensions', 'warranty', 'shippingInfo', 'returnPolicy', 'soldCount']
        .forEach((k) => assert.ok(k in d, k));
    });

    it('PRD-12 unknown product is 404', async () => {
      assert.equal((await api.get(`${PRODUCTS}/999999`)).status, 404);
      assert.equal((await api.get(`${PRODUCTS}/no-such-product`)).status, 404);
      assert.equal((await api.get(`${PRODUCTS}/99999999999`)).status, 404);
    });

    it('PRD-13 recently-viewed is not swallowed by /:idOrSlug', async () => {
      assert.equal((await api.get(`${PRODUCTS}/recently-viewed`)).status, 401);
    });

    it('PRD-14 authed views feed recently-viewed and view_count', async () => {
      const session = await registerUser();
      const other = await db('products').where('external_id', 78).first();
      const beforeViews = (await productRow(other.id)).view_count;
      await viewDetail(product.id, product.id, session.auth);
      await viewDetail(other.slug, other.id, session.auth);
      const res = await api.get(`${PRODUCTS}/recently-viewed`).set(session.auth);
      assert.equal(res.status, 200);
      assert.deepEqual(res.body.data.map((p) => p.id), [other.id, product.id]);
      assert.equal((await productRow(other.id)).view_count, beforeViews + 1);
    });
  });

  describe('reviews', () => {
    let product;
    let session;
    before(async () => {
      product = await db('products').where('external_id', 130).first();
      session = await registerUser({ name: 'Zara Ahmed' });
    });

    it('RVW-01 lists reviews with summary', async () => {
      const res = await api.get(`${PRODUCTS}/${product.id}/reviews?limit=5`);
      assert.equal(res.status, 200);
      assert.ok(res.body.data.length > 0 && res.body.data.length <= 5);
      const { summary } = res.body.meta;
      assert.equal(summary.count, res.body.meta.total);
      assert.equal(Object.values(summary.breakdown).reduce((a, b) => a + b, 0), summary.count);
      const r = res.body.data[0];
      ['id', 'rating', 'title', 'comment', 'isVerified', 'helpfulCount', 'createdAt', 'user'].forEach((k) => assert.ok(k in r, k));
    });

    it('RVW-02 sorts by lowest rating', async () => {
      const res = await api.get(`${PRODUCTS}/${product.id}/reviews?sort=rating_low&limit=50`);
      assert.ok(isSorted(res.body.data.map((r) => r.rating), 'asc'));
    });

    it('RVW-03 creates an unverified review', async () => {
      const res = await api.post(`${PRODUCTS}/${product.id}/reviews`).set(session.auth)
        .send({ rating: 1, title: 'Not for me', comment: 'Battery life was poor for my usage.' });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.isVerified, false);
      assert.deepEqual(res.body.data.user, { name: 'Zara Ahmed', initials: 'ZA' });
    });

    it('RVW-04 recomputes the product rating', async () => {
      const summary = (await api.get(`${PRODUCTS}/${product.id}/reviews`)).body.meta.summary;
      const row = await productRow(product.id);
      assert.equal(row.rating_count, summary.count);
      assert.equal(row.rating, summary.average);
      assert.equal(row.rating_count, product.rating_count + 1);
    });

    it('RVW-05 rejects a second review', async () => {
      const res = await api.post(`${PRODUCTS}/${product.id}/reviews`).set(session.auth).send({ rating: 5, comment: 'Changed my mind, it is great.' });
      assert.equal(res.status, 409);
    });

    it('RVW-06 validates review input', async () => {
      const short = await api.post(`${PRODUCTS}/${product.id}/reviews`).set(session.auth).send({ rating: 4, comment: 'meh' });
      assert.equal(short.status, 400);
      const rating = await api.post(`${PRODUCTS}/${product.id}/reviews`).set(session.auth).send({ rating: 6, comment: 'Way too good to be true' });
      assert.equal(rating.status, 400);
      assert.equal((await api.post(`${PRODUCTS}/${product.id}/reviews`).send({ rating: 4, comment: 'Anonymous review here' })).status, 401);
      assert.equal((await api.post(`${PRODUCTS}/999999/reviews`).set(session.auth).send({ rating: 4, comment: 'Nothing to review here' })).status, 404);
      assert.equal((await api.get(`${PRODUCTS}/999999/reviews`)).status, 404);
    });
  });
});
