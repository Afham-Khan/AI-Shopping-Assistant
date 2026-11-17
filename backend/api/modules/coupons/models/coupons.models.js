const db = require('../../../db/connection');

const listActive = () =>
  db('coupons')
    .where({ is_active: true })
    .where((w) => w.whereNull('starts_at').orWhere('starts_at', '<=', db.fn.now()))
    .where((w) => w.whereNull('expires_at').orWhere('expires_at', '>', db.fn.now()))
    .where((w) => w.whereNull('usage_limit').orWhereRaw('used_count < usage_limit'))
    .select('code', 'description', 'discount_type', 'value', 'min_order_amount', 'max_discount', 'expires_at')
    .orderBy('min_order_amount', 'asc');

module.exports = { listActive };
