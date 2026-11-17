const assert = require('node:assert/strict');
const { api, db, registerUser, PASSWORD } = require('./helpers');
const { decideAlerts, pricing, applyProductUpdate } = require('../api/modules/alerts/services/priceAlerts.service');

const ALERTS = '/api/v1/alerts/price-watch';

describe('Price watch, admin product updates and price history', function suite() {
  this.timeout(60000);
  let shopper;
  let other;
  let admin;
  let product; // in stock, nobody (seeded) watches or wishlists it
  let original;
  let historyFloor;

  before(async () => {
    shopper = await registerUser();
    other = await registerUser();
    admin = await registerUser();
    await db('users').where({ id: admin.user.id }).update({ role: 'admin' });
    product = await db('products as p')
      .where('p.stock', '>', 5).where('p.price', '>', 2000)
      .whereNotExists(db('wishlist_items as w').whereRaw('w.product_id = p.id'))
      .whereNotExists(db('price_watches as pw').whereRaw('pw.product_id = p.id'))
      .orderBy('p.id').first('p.*');
    original = { price: product.price, compare_at_price: product.compare_at_price, discount_percent: product.discount_percent, stock: product.stock, updated_at: product.updated_at };
    historyFloor = (await db('price_history').max('id as id').first()).id || 0;
  });

  after(async () => {
    // put the seeded product back exactly as it was and drop only the history rows this suite created
    await db('products').where({ id: product.id }).update(original);
    await db('price_history').where('product_id', product.id).where('id', '>', historyFloor).del();
  });

  describe('pure alert rules', () => {
    const before = { id: 1, title: 'Phone', slug: 'phone', price: 1000, stock: 5 };
    it('PW-U1 drop notifies a watcher with no target and wishlisters, but not a watcher above target', () => {
      const r = decideAlerts(before, { ...before, price: 900 }, {
        watches: [{ id: 1, user_id: 10, target_price: null, notify_restock: true }, { id: 2, user_id: 11, target_price: 800, notify_restock: true }],
        wishlisters: [12, 10],
      });
      assert.deepEqual(r.rows.map((x) => x.userId).sort(), [10, 12]);
      assert.deepEqual(r.firedWatchIds, [1]);
      assert.ok(r.rows.every((x) => x.type === 'price_drop'));
      assert.equal(r.rows.find((x) => x.userId === 12).data.reason, 'wishlist');
      assert.equal(r.counts.priceDrop, 2);
    });
    it('PW-U2 target reached fires; price rise never fires', () => {
      const hit = decideAlerts(before, { ...before, price: 790 }, { watches: [{ id: 2, user_id: 11, target_price: 800, notify_restock: true }] });
      assert.equal(hit.rows.length, 1);
      assert.match(hit.rows[0].body, /target/);
      const rise = decideAlerts(before, { ...before, price: 1200 }, { watches: [{ id: 3, user_id: 13, target_price: null, notify_restock: true }], wishlisters: [14] });
      assert.equal(rise.rows.length, 0);
    });
    it('PW-U3 restock notifies watchers who opted in', () => {
      const r = decideAlerts({ ...before, stock: 0 }, { ...before, stock: 3 }, {
        watches: [{ id: 1, user_id: 10, target_price: null, notify_restock: true }, { id: 2, user_id: 11, target_price: null, notify_restock: false }],
      });
      assert.deepEqual(r.rows.map((x) => [x.userId, x.type]), [[10, 'restock']]);
    });
    it('PW-U4 pricing keeps the old price as compare-at on a drop and clears it on a rise', () => {
      assert.deepEqual(pricing({ price: 1000, compare_at_price: null }, { price: 800 }), { price: 800, compareAt: 1000, discount: 20 });
      assert.deepEqual(pricing({ price: 800, compare_at_price: 1000 }, { price: 1200 }), { price: 1200, compareAt: null, discount: 0 });
    });
  });

  describe('/alerts/price-watch', () => {
    it('PW-01 requires auth', async () => {
      await api.get(ALERTS).expect(401);
    });

    it('PW-02 validates the body', async () => {
      await api.post(ALERTS).set(shopper.auth).send({}).expect(400);
      await api.post(ALERTS).set(shopper.auth).send({ productId: product.id, targetPrice: -5 }).expect(400);
      await api.post(ALERTS).set(shopper.auth).send({ productId: product.id, notifyRestock: 'yes' }).expect(400);
      await api.post(ALERTS).set(shopper.auth).send({ productId: 99999999 }).expect(404);
    });

    it('PW-03 rejects a target at or above the current price', async () => {
      const res = await api.post(ALERTS).set(shopper.auth).send({ productId: product.id, targetPrice: product.price }).expect(400);
      assert.equal(res.body.errors[0].field, 'targetPrice');
    });

    it('PW-04 creates (201) then updates (200) a watch and lists it', async () => {
      const target = Math.round(product.price * 0.9);
      const created = await api.post(ALERTS).set(shopper.auth).send({ productId: product.id, targetPrice: target }).expect(201);
      assert.equal(created.body.data.product.id, product.id);
      assert.equal(created.body.data.targetPrice, target);
      assert.equal(created.body.data.initialPrice, product.price);
      assert.equal(created.body.data.status.targetReached, false);
      const updated = await api.post(ALERTS).set(shopper.auth).send({ productId: product.id, targetPrice: target, notifyRestock: false }).expect(200);
      assert.equal(updated.body.data.notifyRestock, false);
      const list = await api.get(ALERTS).set(shopper.auth).expect(200);
      assert.equal(list.body.data.length, 1);
      assert.match(list.body.data[0].status.summary, /above your target/);
      // a watch with no target means "any drop"
      await api.post(ALERTS).set(other.auth).send({ productId: product.id }).expect(201);
    });
  });

  describe('PATCH /admin/products/:id', () => {
    it('ADM-01 customers get 403, guests 401', async () => {
      await api.patch(`/api/v1/admin/products/${product.id}`).send({ price: 10 }).expect(401);
      await api.patch(`/api/v1/admin/products/${product.id}`).set(shopper.auth).send({ price: 10 }).expect(403);
    });

    it('ADM-02 validates input and 404s unknown products', async () => {
      await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({}).expect(400);
      await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ price: -1 }).expect(400);
      await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ stock: 1.5 }).expect(400);
      await api.patch('/api/v1/admin/products/99999999').set(admin.auth).send({ price: 100 }).expect(404);
    });

    it('ADM-03 a small drop alerts the any-drop watcher only; the target watcher waits', async () => {
      const small = Math.round(product.price * 0.95);
      const res = await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ price: small }).expect(200);
      const d = res.body.data;
      assert.equal(d.product.price, small);
      assert.equal(d.product.compareAtPrice >= product.price, true);
      assert.deepEqual(d.changes.price, { from: product.price, to: small });
      assert.equal(d.priceHistoryRecorded, true);
      assert.equal(d.alerts.priceDrop, 1);
      const theirs = await api.get('/api/v1/notifications').set(other.auth).expect(200);
      const note = theirs.body.data.find((n) => n.type === 'price_drop');
      assert.ok(note);
      assert.equal(note.data.productId, product.id);
      assert.equal(note.data.newPrice, small);
      const mine = await api.get('/api/v1/notifications').set(shopper.auth).expect(200);
      assert.equal(mine.body.data.filter((n) => n.type === 'price_drop').length, 0);
    });

    it('ADM-04 reaching the target notifies the target watcher and stamps last_notified_at', async () => {
      const low = Math.round(product.price * 0.85);
      const res = await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ price: low }).expect(200);
      assert.equal(res.body.data.alerts.priceDrop, 2);
      const mine = await api.get('/api/v1/notifications').set(shopper.auth).expect(200);
      const note = mine.body.data.find((n) => n.type === 'price_drop');
      assert.match(note.body, /target/);
      const list = await api.get(ALERTS).set(shopper.auth).expect(200);
      assert.ok(list.body.data[0].lastNotifiedAt);
      assert.equal(list.body.data[0].status.targetReached, true);
    });

    it('ADM-05 restock alerts watchers who opted in (and wishlisters)', async () => {
      await api.post('/api/v1/wishlist').set(admin.auth).send({ productId: product.id }).expect(200);
      await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ stock: 0 }).expect(200);
      const res = await api.patch(`/api/v1/admin/products/${product.id}`).set(admin.auth).send({ stock: 7 }).expect(200);
      // other (notifyRestock default true) + admin's wishlist; shopper opted out
      assert.equal(res.body.data.alerts.restock, 2);
      assert.equal(res.body.data.priceHistoryRecorded, false);
      const theirs = await api.get('/api/v1/notifications').set(other.auth).expect(200);
      assert.ok(theirs.body.data.some((n) => n.type === 'restock' && n.data.productId === product.id));
      const mine = await api.get('/api/v1/notifications').set(shopper.auth).expect(200);
      assert.equal(mine.body.data.filter((n) => n.type === 'restock').length, 0);
    });

    it('ADM-06 the demo service path (npm run demo:price-drop) records history and alerts too', async () => {
      const r = await applyProductUpdate(product.id, { price: Math.round(product.price * 0.8) }, { source: 'demo' });
      assert.equal(r.priceHistoryRecorded, true);
      assert.ok(r.alerts.notifiedUsers >= 2);
      const last = await db('price_history').where({ product_id: product.id }).orderBy('id', 'desc').first();
      assert.equal(last.source, 'demo');
    });

    it('ADM-07 the seeded admin account can sign in', async () => {
      const res = await api.post('/api/v1/auth/login').send({ email: 'admin@zelora.app', password: 'Admin@1234' }).expect(200);
      assert.equal(res.body.data.user.role, 'admin');
      assert.ok(PASSWORD);
    });
  });

  describe('GET /products/:id/price-history', () => {
    it('PH-01 returns the real recorded changes with stats and an insight', async () => {
      const res = await api.get(`/api/v1/products/${product.id}/price-history?days=365`).expect(200);
      const d = res.body.data;
      assert.equal(d.productId, product.id);
      assert.equal(d.currency, 'PKR');
      assert.ok(d.points.length >= 4);
      assert.ok(d.points.some((p) => p.source === 'seed'));
      assert.ok(d.points.some((p) => p.source === 'admin'));
      assert.equal(d.stats.lowest, Math.round(product.price * 0.8));
      assert.equal(d.trend, 'down');
      assert.match(d.insight, /Lowest price/);
      for (let i = 1; i < d.points.length; i += 1) assert.ok(new Date(d.points[i].recordedAt) >= new Date(d.points[i - 1].recordedAt));
    });

    it('PH-02 validates and 404s', async () => {
      await api.get(`/api/v1/products/${product.id}/price-history?days=0`).expect(400);
      await api.get('/api/v1/products/99999999/price-history').expect(404);
    });

    it('PW-05 delete removes the watch; deleting again is 404', async () => {
      await api.delete(`${ALERTS}/${product.id}`).set(shopper.auth).expect(200);
      await api.delete(`${ALERTS}/${product.id}`).set(shopper.auth).expect(404);
      const list = await api.get(ALERTS).set(shopper.auth).expect(200);
      assert.equal(list.body.data.length, 0);
    });
  });
});
