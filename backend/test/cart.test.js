const assert = require('node:assert/strict');
const { api, db, registerUser, findProduct } = require('./helpers');

const CART = '/api/v1/cart';

describe('Cart', () => {
  let session;
  let cheap;
  let mid;
  let scarce;
  let soldOut;
  const add = (productId, quantity) => api.post(`${CART}/items`).set(session.auth).send({ productId, quantity });

  before(async () => {
    session = await registerUser();
    cheap = await findProduct((q) => q.where('stock', '>=', 20).whereBetween('price', [500, 1500]).whereNotNull('compare_at_price').orderBy('id'));
    mid = await findProduct((q) => q.where('stock', '>=', 20).whereBetween('price', [6000, 12000]).orderBy('id'));
    scarce = await findProduct((q) => q.whereBetween('stock', [2, 8]).orderBy('id'));
    soldOut = await findProduct((q) => q.where('stock', 0).orderBy('id'));
  });

  it('CRT-01 empty cart has a zero summary', async () => {
    const res = await api.get(CART).set(session.auth);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, {
      items: [],
      summary: { itemCount: 0, subtotal: 0, discount: 0, shippingFee: 0, total: 0, freeShippingThreshold: 5000, coupon: null, savings: 0 },
    });
  });

  it('CRT-02 adding the same product accumulates quantity', async () => {
    await add(cheap.id, 1).expect(200);
    const res = await add(cheap.id, 2).expect(200);
    const item = res.body.data.items.find((i) => i.productId === cheap.id);
    assert.equal(item.quantity, 3);
    assert.equal(item.lineTotal, cheap.price * 3);
    assert.equal(item.product.id, cheap.id);
  });

  it('CRT-05 charges shipping below Rs 5,000', async () => {
    const { summary } = (await api.get(CART).set(session.auth)).body.data;
    assert.ok(summary.subtotal < 5000);
    assert.equal(summary.shippingFee, 250);
    assert.equal(summary.total, summary.subtotal + 250);
  });

  it('CRT-12 savings include compare-at differences', async () => {
    const { summary } = (await api.get(CART).set(session.auth)).body.data;
    assert.equal(summary.savings, (cheap.compare_at_price - cheap.price) * 3);
  });

  it('CRT-07 FLAT500 needs a Rs 5,000 order', async () => {
    const res = await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'flat500' });
    assert.equal(res.status, 400);
    assert.match(res.body.message, /Add Rs [\d,]+ more/);
  });

  it('CRT-06 WELCOME10 takes 10% capped at Rs 2,000 and free shipping kicks in', async () => {
    await add(mid.id, 1).expect(200);
    const res = await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'welcome10' });
    assert.equal(res.status, 200);
    const { summary } = res.body.data;
    const subtotal = cheap.price * 3 + mid.price;
    const discount = Math.min(Math.round(subtotal * 0.1), 2000);
    assert.equal(summary.subtotal, subtotal);
    assert.equal(summary.discount, discount);
    assert.equal(summary.shippingFee, subtotal - discount >= 5000 ? 0 : 250);
    assert.equal(summary.total, subtotal - discount + summary.shippingFee);
    assert.equal(summary.coupon.code, 'WELCOME10');
    assert.equal(summary.itemCount, 4);
  });

  it('CRT-08 rejects expired and unknown coupons', async () => {
    const expired = await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'SUMMER25' });
    assert.equal(expired.status, 400);
    assert.match(expired.body.message, /expired/);
    const unknown = await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'FREESTUFF' });
    assert.equal(unknown.status, 400);
    assert.match(unknown.body.message, /Invalid coupon/);
  });

  it('CRT-09 drops a coupon whose minimum is no longer met', async () => {
    await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'FLAT500' }).expect(200);
    const res = await api.delete(`${CART}/items/${mid.id}`).set(session.auth).expect(200);
    assert.equal(res.body.data.summary.coupon, null);
    assert.equal(res.body.data.summary.discount, 0);
    const stored = await db('carts').where({ user_id: session.user.id }).first();
    assert.equal(stored.coupon_code, null);
  });

  it('CRT-03 caps quantity at available stock', async () => {
    const res = await add(scarce.id, 10).expect(200);
    const item = res.body.data.items.find((i) => i.productId === scarce.id);
    assert.equal(item.quantity, scarce.stock);
    assert.match(res.body.message, /Only \d+ can be added/);
  });

  it('CRT-04 caps at 10 per item and validates quantity', async () => {
    await add(cheap.id, 10).expect(200);
    const res = await add(cheap.id, 5).expect(200);
    assert.equal(res.body.data.items.find((i) => i.productId === cheap.id).quantity, 10);
    assert.equal((await add(cheap.id, 11)).status, 400);
    assert.equal((await add(cheap.id, 0)).status, 400);
    assert.equal((await api.patch(`${CART}/items/${cheap.id}`).set(session.auth).send({ quantity: 11 })).status, 400);
  });

  it('CRT-10 PATCH quantity 0 removes the item; missing item is 404', async () => {
    const res = await api.patch(`${CART}/items/${scarce.id}`).set(session.auth).send({ quantity: 0 }).expect(200);
    assert.ok(!res.body.data.items.some((i) => i.productId === scarce.id));
    assert.equal((await api.patch(`${CART}/items/${scarce.id}`).set(session.auth).send({ quantity: 1 })).status, 404);
    const patched = await api.patch(`${CART}/items/${cheap.id}`).set(session.auth).send({ quantity: 2 }).expect(200);
    assert.equal(patched.body.data.items[0].quantity, 2);
  });

  it('CRT-11 refuses out-of-stock products', async () => {
    const res = await add(soldOut.id, 1);
    assert.equal(res.status, 409);
    assert.equal((await add(999999, 1)).status, 404);
  });

  it('CRT-13 clears the cart and coupon', async () => {
    await api.post(`${CART}/coupon`).set(session.auth).send({ code: 'WELCOME10' }).expect(200);
    const res = await api.delete(CART).set(session.auth).expect(200);
    assert.deepEqual(res.body.data.items, []);
    assert.equal(res.body.data.summary.coupon, null);
    assert.equal((await api.get(CART)).status, 401);
  });
});

describe('Coupons', () => {
  it('CPN-01 lists only active coupons', async () => {
    const res = await api.get('/api/v1/coupons');
    assert.equal(res.status, 200);
    const codes = res.body.data.map((c) => c.code);
    ['WELCOME10', 'FLAT500', 'AI15'].forEach((c) => assert.ok(codes.includes(c), c));
    assert.ok(!codes.includes('SUMMER25'));
    const ai = res.body.data.find((c) => c.code === 'AI15');
    assert.deepEqual({ type: ai.discountType, value: ai.value, min: ai.minOrderAmount, max: ai.maxDiscount }, { type: 'percent', value: 15, min: 20000, max: 5000 });
  });
});
