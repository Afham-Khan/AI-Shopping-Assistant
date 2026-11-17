const db = require('../../../db/connection');
const { productCardQuery } = require('../../../../helpers/productQuery');

const items = (userId, trx = db, { lock = false } = {}) => {
  const qb = productCardQuery(trx)
    .join('cart_items as ci', 'ci.product_id', 'p.id')
    .where('ci.user_id', userId)
    .select('ci.quantity', 'p.sold_count')
    .orderBy([{ column: 'ci.created_at', order: 'asc' }, { column: 'ci.id', order: 'asc' }]);
  // checkout locks the product rows so stock can't be oversold by a parallel order
  return lock ? qb.forUpdate('p') : qb;
};

const findItem = (userId, productId, trx = db) =>
  trx('cart_items').where({ user_id: userId, product_id: productId }).first();

const upsertItem = (userId, productId, quantity, trx = db) =>
  trx('cart_items')
    .insert({ user_id: userId, product_id: productId, quantity })
    .onConflict(['user_id', 'product_id'])
    .merge({ quantity, updated_at: trx.fn.now() });

const setQuantity = (userId, productId, quantity, trx = db) =>
  trx('cart_items').where({ user_id: userId, product_id: productId }).update({ quantity, updated_at: trx.fn.now() });

const removeItem = (userId, productId, trx = db) => trx('cart_items').where({ user_id: userId, product_id: productId }).del();

const clearItems = (userId, trx = db) => trx('cart_items').where({ user_id: userId }).del();

const couponCode = async (userId, trx = db) => (await trx('carts').where({ user_id: userId }).first('coupon_code'))?.coupon_code || null;

const setCoupon = (userId, code, trx = db) =>
  trx('carts').insert({ user_id: userId, coupon_code: code })
    .onConflict('user_id').merge({ coupon_code: code, updated_at: trx.fn.now() });

const touch = (userId, trx = db) =>
  trx('carts').insert({ user_id: userId }).onConflict('user_id').merge({ updated_at: trx.fn.now() });

const findCoupon = (code, trx = db) => trx('coupons').whereRaw('upper(code) = ?', [code.toUpperCase()]).first();

const productStock = (productId) => db('products').where({ id: productId }).first('id', 'stock', 'title');

module.exports = { items, findItem, upsertItem, setQuantity, removeItem, clearItems, couponCode, setCoupon, touch, findCoupon, productStock };
