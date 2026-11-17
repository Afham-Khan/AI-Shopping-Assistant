const supertest = require('supertest');
const app = require('../app');
const db = require('../api/db/connection');

const api = supertest(app);
const TEST_EMAIL_PATTERN = 'test+%@cartwise.test';
const PASSWORD = 'Passw0rd!';

let counter = 0;
const uniqueEmail = () => {
  counter += 1;
  return `test+${Date.now()}${counter}@cartwise.test`;
};

const bearer = (token) => ({ Authorization: `Bearer ${token}` });

const registerUser = async (overrides = {}) => {
  const body = { name: 'Test Shopper', email: uniqueEmail(), password: PASSWORD, ...overrides };
  const res = await api.post('/api/v1/auth/register').send(body);
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  const { user, accessToken, refreshToken } = res.body.data;
  return { user, accessToken, refreshToken, email: body.email, password: body.password, auth: bearer(accessToken) };
};

const addAddress = async (auth, overrides = {}) => {
  const res = await api.post('/api/v1/addresses').set(auth).send({
    fullName: 'Test Shopper', phone: '+92 300 0000000', line1: 'House 1, Street 2', city: 'Karachi', province: 'Sindh', ...overrides,
  });
  if (res.status !== 201) throw new Error(`address failed: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data;
};

// seeded products matching a condition, read straight from the db so tests don't hardcode ids
const findProduct = (build) => build(db('products').select('*')).first();

const productRow = (id) => db('products').where({ id }).first();

// restores stock of anything a test bought, then removes the test users (cascade) and refreshes ratings they touched
const cleanupTestData = async () => {
  const users = await db('users').whereLike('email', TEST_EMAIL_PATTERN).select('id');
  if (!users.length) return;
  const ids = users.map((u) => u.id);
  await db.transaction(async (trx) => {
    const items = await trx('order_items as oi').join('orders as o', 'o.id', 'oi.order_id')
      .whereIn('o.user_id', ids).whereNot('o.status', 'cancelled').whereNotNull('oi.product_id')
      .select('oi.product_id', 'oi.quantity');
    for (const item of items) {
      await trx('products').where({ id: item.product_id }).update({
        stock: trx.raw('stock + ?', [item.quantity]),
        sold_count: trx.raw('GREATEST(sold_count - ?, 0)', [item.quantity]),
      });
    }
    const coupons = await trx('orders').whereIn('user_id', ids).whereNot('status', 'cancelled').whereNotNull('coupon_code').select('coupon_code');
    for (const { coupon_code: code } of coupons) {
      await trx('coupons').where({ code }).where('used_count', '>', 0).decrement('used_count', 1);
    }
    const reviewed = (await trx('reviews').whereIn('user_id', ids).distinct('product_id')).map((r) => r.product_id);
    await trx('users').whereIn('id', ids).del();
    if (reviewed.length) {
      await trx.raw(`
        UPDATE products p SET
          rating = COALESCE((SELECT ROUND(AVG(r.rating)::numeric, 2) FROM reviews r WHERE r.product_id = p.id), 0),
          rating_count = (SELECT COUNT(*) FROM reviews r WHERE r.product_id = p.id)
        WHERE p.id = ANY(?)`, [reviewed]);
    }
  });
};

module.exports = { api, db, PASSWORD, uniqueEmail, bearer, registerUser, addAddress, findProduct, productRow, cleanupTestData };
