const db = require('../../../db/connection');
const { ACTIVE_ORDER_STATUSES } = require('../../../../helpers/constants');

const STATUS_FILTERS = {
  active: ACTIVE_ORDER_STATUSES,
  delivered: ['delivered'],
  cancelled: ['cancelled'],
};

const findOwned = (id, userId, trx = db, { lock = false } = {}) => {
  const qb = trx('orders').where({ id, user_id: userId }).first();
  return lock ? qb.forUpdate() : qb;
};

const lockById = (id, trx) => trx('orders').where({ id }).forUpdate().first();

const items = (orderId, trx = db) => trx('order_items').where({ order_id: orderId }).orderBy('id');

const timeline = (orderId, trx = db) =>
  trx('order_status_history').where({ order_id: orderId }).orderBy([{ column: 'created_at', order: 'asc' }, { column: 'id', order: 'asc' }]);

const list = async (userId, { status, limit, offset }) => {
  const base = () => {
    const qb = db('orders').where({ user_id: userId });
    if (status) qb.whereIn('status', STATUS_FILTERS[status]);
    return qb;
  };
  const [rows, { total }] = await Promise.all([
    base().select('id', 'order_number', 'status', 'total', 'placed_at')
      .orderBy([{ column: 'placed_at', order: 'desc' }, { column: 'id', order: 'desc' }]).limit(limit).offset(offset),
    base().count('* as total').first(),
  ]);
  return { rows, total };
};

const itemsForOrders = (orderIds) =>
  orderIds.length
    ? db('order_items').whereIn('order_id', orderIds).select('order_id', 'quantity', 'thumbnail_url').orderBy('id')
    : [];

// orders young enough for the demo status simulation
const progressable = (userId, sinceDate) =>
  db('orders').where({ user_id: userId }).whereIn('status', ACTIVE_ORDER_STATUSES).where('placed_at', '>', sinceDate).select('id');

const insertOrder = async (row, trx) => (await trx('orders').insert(row).returning('*'))[0];
const insertItems = (rows, trx) => trx('order_items').insert(rows);
const insertHistory = (rows, trx) => trx('order_status_history').insert(Array.isArray(rows) ? rows : [rows]);
const update = async (id, changes, trx) =>
  (await trx('orders').where({ id }).update({ ...changes, updated_at: trx.fn.now() }).returning('*'))[0];

const orderNumberExists = async (orderNumber, trx = db) => Boolean(await trx('orders').where({ order_number: orderNumber }).first('id'));

// guarded decrement: returns 0 rows if stock fell below qty in the meantime
const decrementStock = (productId, quantity, trx) =>
  trx('products').where({ id: productId }).where('stock', '>=', quantity)
    .update({ stock: trx.raw('stock - ?', [quantity]), sold_count: trx.raw('sold_count + ?', [quantity]), updated_at: trx.fn.now() });

const restock = (productId, quantity, trx) =>
  trx('products').where({ id: productId })
    .update({ stock: trx.raw('stock + ?', [quantity]), sold_count: trx.raw('GREATEST(sold_count - ?, 0)', [quantity]), updated_at: trx.fn.now() });

const incrementCouponUsage = (code, trx) => trx('coupons').where({ code }).increment('used_count', 1);
const decrementCouponUsage = (code, trx) =>
  trx('coupons').where({ code }).where('used_count', '>', 0).decrement('used_count', 1);

const findAddress = (id, userId, trx = db) => trx('addresses').where({ id, user_id: userId }).first();

module.exports = {
  STATUS_FILTERS,
  findOwned,
  lockById,
  items,
  timeline,
  list,
  itemsForOrders,
  progressable,
  insertOrder,
  insertItems,
  insertHistory,
  update,
  orderNumberExists,
  decrementStock,
  restock,
  incrementCouponUsage,
  decrementCouponUsage,
  findAddress,
};
