const Coupons = require('../models/coupons.models');
const { ok } = require('../../../../helpers/response');

module.exports.list = async (req, res) =>
  ok(res, (await Coupons.listActive()).map((c) => ({
    code: c.code,
    description: c.description,
    discountType: c.discount_type,
    value: c.value,
    minOrderAmount: c.min_order_amount,
    maxDiscount: c.max_discount,
    expiresAt: c.expires_at,
  })));
