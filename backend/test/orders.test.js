const assert = require('node:assert/strict');
const { api, db, registerUser, addAddress, findProduct, productRow } = require('./helpers');

const ORDERS = '/api/v1/orders';
const MINUTE = 60 * 1000;

const backdate = async (orderId, minutes) => {
  const placedAt = new Date(Date.now() - minutes * MINUTE);
  await db('orders').where({ id: orderId }).update({ placed_at: placedAt });
  await db('order_status_history').where({ order_id: orderId, status: 'placed' }).update({ created_at: placedAt });
};

describe('Orders', () => {
  let buyer;
  let stranger;
  let address;
  let strangerAddress;
  let mid;
  let cheap;
  let order;

  const addToCart = (productId, quantity = 1) => api.post('/api/v1/cart/items').set(buyer.auth).send({ productId, quantity }).expect(200);

  before(async () => {
    [buyer, stranger] = await Promise.all([registerUser(), registerUser()]);
    address = await addAddress(buyer.auth, { city: 'Lahore', province: 'Punjab' });
    strangerAddress = await addAddress(stranger.auth);
    mid = await findProduct((q) => q.where('stock', '>=', 20).whereBetween('price', [6000, 12000]).orderBy('id', 'desc'));
    cheap = await findProduct((q) => q.where('stock', '>=', 20).whereBetween('price', [500, 1500]).orderBy('id', 'desc'));
  });

  it('ORD-01 rejects checkout with an empty cart', async () => {
    const res = await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'cod' });
    assert.equal(res.status, 400);
    assert.match(res.body.message, /empty/);
  });

  it('ORD-02 validates checkout input', async () => {
    assert.equal((await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'bitcoin' })).status, 400);
    assert.equal((await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'card' })).status, 400);
    assert.equal((await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'card', card: { last4: '12' } })).status, 400);
    assert.equal((await api.post(ORDERS).set(buyer.auth).send({ addressId: 'x', paymentMethod: 'cod' })).status, 400);
    assert.equal((await api.post(ORDERS).send({ addressId: address.id, paymentMethod: 'cod' })).status, 401);
  });

  it("ORD-03 refuses another user's address", async () => {
    await addToCart(cheap.id);
    const res = await api.post(ORDERS).set(buyer.auth).send({ addressId: strangerAddress.id, paymentMethod: 'cod' });
    assert.equal(res.status, 404);
    await api.delete('/api/v1/cart').set(buyer.auth).expect(200);
  });

  describe('checkout and cancel', () => {
    let midBefore;
    let couponBefore;
    let cartSummary;

    it('ORD-04 places an order transactionally', async () => {
      await addToCart(mid.id, 2);
      await addToCart(cheap.id, 1);
      const cart = (await api.post('/api/v1/cart/coupon').set(buyer.auth).send({ code: 'FLAT500' }).expect(200)).body.data;
      cartSummary = cart.summary;
      midBefore = await productRow(mid.id);
      couponBefore = await db('coupons').where({ code: 'FLAT500' }).first();

      const res = await api.post(ORDERS).set(buyer.auth)
        .send({ addressId: address.id, paymentMethod: 'card', card: { last4: '4242' }, notes: 'Ring the bell' });
      assert.equal(res.status, 201);
      order = res.body.data;
      assert.match(order.orderNumber, /^CW-\d{6}-[0-9A-F]{6}$/);
      assert.equal(order.status, 'placed');
      assert.equal(order.paymentStatus, 'paid');
      assert.equal(order.cardLast4, '4242');
      assert.equal(order.couponCode, 'FLAT500');
      assert.equal(order.subtotal, cartSummary.subtotal);
      assert.equal(order.discount, 500);
      assert.equal(order.shippingFee, cartSummary.shippingFee);
      assert.equal(order.total, cartSummary.total);
      assert.equal(order.shippingAddress.city, 'Lahore');
      assert.equal(order.items.length, 2);
      assert.deepEqual(order.timeline.map((t) => t.status), ['placed']);
      assert.ok(new Date(order.estimatedDelivery) > new Date(order.placedAt));

      const midAfter = await productRow(mid.id);
      assert.equal(midAfter.stock, midBefore.stock - 2);
      assert.equal(midAfter.sold_count, midBefore.sold_count + 2);
      assert.equal((await db('coupons').where({ code: 'FLAT500' }).first()).used_count, couponBefore.used_count + 1);
      const cartAfter = (await api.get('/api/v1/cart').set(buyer.auth)).body.data;
      assert.equal(cartAfter.items.length, 0);
      assert.equal(cartAfter.summary.coupon, null);
      const note = await db('notifications').where({ user_id: buyer.user.id, title: 'Order placed' }).first();
      assert.equal(note.data.orderId, order.id);
      const purchases = await db('user_interactions').where({ user_id: buyer.user.id, type: 'purchase' }).count('* as n').first();
      assert.equal(purchases.n, 2);
    });

    it('ORD-05 rejects quantities above current stock', async () => {
      await addToCart(mid.id, 1);
      const stock = (await productRow(mid.id)).stock;
      await db('cart_items').where({ user_id: buyer.user.id, product_id: mid.id }).update({ quantity: stock + 1 });
      const res = await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'cod' });
      assert.equal(res.status, 409);
      assert.equal((await productRow(mid.id)).stock, stock);
      await api.delete('/api/v1/cart').set(buyer.auth).expect(200);
    });

    it('ORD-06 lists orders with filters', async () => {
      const res = await api.get(`${ORDERS}?status=active`).set(buyer.auth);
      assert.equal(res.status, 200);
      const row = res.body.data.find((o) => o.id === order.id);
      assert.equal(row.itemCount, 3);
      assert.equal(row.total, order.total);
      assert.ok(row.previewImages.length > 0);
      assert.equal((await api.get(`${ORDERS}?status=delivered`).set(buyer.auth)).body.data.length, 0);
      assert.equal((await api.get(`${ORDERS}?status=weird`).set(buyer.auth)).status, 400);
    });

    it('ORD-07 hides orders from other users', async () => {
      assert.equal((await api.get(`${ORDERS}/${order.id}`).set(stranger.auth)).status, 404);
      assert.equal((await api.post(`${ORDERS}/${order.id}/cancel`).set(stranger.auth)).status, 404);
      assert.equal((await api.get(`${ORDERS}/${order.id}`).set(buyer.auth)).status, 200);
    });

    it('ORD-08 cancels and restocks', async () => {
      const res = await api.post(`${ORDERS}/${order.id}/cancel`).set(buyer.auth);
      assert.equal(res.status, 200);
      assert.equal(res.body.data.status, 'cancelled');
      assert.equal(res.body.data.paymentStatus, 'refunded');
      assert.ok(res.body.data.cancelledAt);
      assert.equal(res.body.data.estimatedDelivery, null);
      assert.equal(res.body.data.timeline.at(-1).status, 'cancelled');
      const midAfter = await productRow(mid.id);
      assert.equal(midAfter.stock, midBefore.stock);
      assert.equal(midAfter.sold_count, midBefore.sold_count);
      assert.equal((await db('coupons').where({ code: 'FLAT500' }).first()).used_count, couponBefore.used_count);
    });

    it('ORD-09 cannot cancel twice', async () => {
      assert.equal((await api.post(`${ORDERS}/${order.id}/cancel`).set(buyer.auth)).status, 409);
    });
  });

  describe('status progression', () => {
    let progressing;

    before(async () => {
      await addToCart(cheap.id, 1);
      progressing = (await api.post(ORDERS).set(buyer.auth).send({ addressId: address.id, paymentMethod: 'cod' }).expect(201)).body.data;
    });

    it('ORD-10 advances to shipped after 3+ minutes', async () => {
      await backdate(progressing.id, 4);
      const res = await api.get(`${ORDERS}/${progressing.id}`).set(buyer.auth);
      assert.equal(res.body.data.status, 'shipped');
      assert.deepEqual(res.body.data.timeline.map((t) => t.status), ['placed', 'confirmed', 'shipped']);
      const titles = (await db('notifications').where({ user_id: buyer.user.id }).select('title')).map((n) => n.title);
      assert.ok(titles.includes('Order confirmed') && titles.includes('Order shipped'));
    });

    it('ORD-11 is delivered after 10 minutes and can no longer be cancelled', async () => {
      await backdate(progressing.id, 11);
      const list = await api.get(`${ORDERS}?status=delivered`).set(buyer.auth);
      assert.ok(list.body.data.some((o) => o.id === progressing.id));
      const res = await api.get(`${ORDERS}/${progressing.id}`).set(buyer.auth);
      assert.equal(res.body.data.status, 'delivered');
      assert.equal(res.body.data.paymentStatus, 'paid');
      assert.ok(res.body.data.deliveredAt);
      assert.equal(res.body.data.timeline.length, 5);
      assert.equal((await api.post(`${ORDERS}/${progressing.id}/cancel`).set(buyer.auth)).status, 409);
    });

    it('RVW-07 a delivered purchase makes the review verified', async () => {
      const res = await api.post(`/api/v1/products/${cheap.id}/reviews`).set(buyer.auth)
        .send({ rating: 5, title: 'Great', comment: 'Arrived quickly and works as described.' });
      assert.equal(res.status, 201);
      assert.equal(res.body.data.isVerified, true);
    });
  });
});
