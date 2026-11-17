const db = require('../../../db/connection');
const Cart = require('../models/cart.models');
const { toCard } = require('../../../../helpers/serializers');
const { FREE_SHIPPING_THRESHOLD, SHIPPING_FEE, MAX_CART_QTY } = require('../../../../helpers/constants');

const rs = (amount) => `Rs ${Math.round(amount).toLocaleString('en-US')}`;

// pure: returns { discount } or { error } so cart, checkout and the seed price orders identically
const evaluateCoupon = (coupon, subtotal, now = new Date()) => {
  if (!coupon || !coupon.is_active) return { error: 'Invalid coupon code' };
  if (coupon.starts_at && new Date(coupon.starts_at) > now) return { error: 'This coupon is not active yet' };
  if (coupon.expires_at && new Date(coupon.expires_at) <= now) return { error: 'This coupon has expired' };
  if (coupon.usage_limit !== null && coupon.usage_limit !== undefined && coupon.used_count >= coupon.usage_limit) {
    return { error: 'This coupon has reached its usage limit' };
  }
  if (subtotal <= 0) return { error: 'Add items to your cart before applying a coupon' };
  const min = Number(coupon.min_order_amount) || 0;
  if (subtotal < min) {
    return { error: `Add ${rs(min - subtotal)} more to use ${coupon.code} (minimum order ${rs(min)})` };
  }
  let discount = coupon.discount_type === 'percent'
    ? Math.round((subtotal * Number(coupon.value)) / 100)
    : Math.round(Number(coupon.value));
  if (coupon.max_discount !== null && coupon.max_discount !== undefined) discount = Math.min(discount, Number(coupon.max_discount));
  return { discount: Math.min(discount, subtotal) };
};

// lines: [{ price, compareAtPrice, quantity }] with quantity already capped to what can be bought
const summarize = (lines, coupon) => {
  const subtotal = lines.reduce((sum, l) => sum + l.price * l.quantity, 0);
  const itemCount = lines.reduce((sum, l) => sum + l.quantity, 0);
  const productSavings = lines.reduce((sum, l) => sum + (l.compareAtPrice > l.price ? (l.compareAtPrice - l.price) * l.quantity : 0), 0);
  const result = coupon ? evaluateCoupon(coupon, subtotal) : { discount: 0 };
  const discount = result.discount || 0;
  const shippingFee = itemCount === 0 || subtotal - discount >= FREE_SHIPPING_THRESHOLD ? 0 : SHIPPING_FEE;
  return {
    itemCount,
    subtotal: round2(subtotal),
    discount,
    shippingFee,
    total: round2(subtotal - discount + shippingFee),
    freeShippingThreshold: FREE_SHIPPING_THRESHOLD,
    coupon: coupon && !result.error ? { code: coupon.code, description: coupon.description } : null,
    couponError: coupon ? result.error || null : null,
    savings: round2(productSavings + discount),
  };
};

const round2 = (n) => Math.round(n * 100) / 100;

const billableQuantity = (row) => Math.max(0, Math.min(row.quantity, row.stock, MAX_CART_QTY));

// loads the cart, silently caps quantities to current stock and drops a coupon that no longer applies
const buildCart = async (userId, trx = db) => {
  const rows = await Cart.items(userId, trx);
  const overStock = rows.filter((r) => r.stock > 0 && r.quantity > Math.min(r.stock, MAX_CART_QTY));
  await Promise.all(overStock.map((r) => Cart.setQuantity(userId, r.id, Math.min(r.stock, MAX_CART_QTY), trx)));

  const code = await Cart.couponCode(userId, trx);
  const coupon = code ? await Cart.findCoupon(code, trx) : null;
  const lines = rows.map((r) => ({ price: r.price, compareAtPrice: r.compare_at_price, quantity: billableQuantity(r) }));
  const { couponError, ...summary } = summarize(lines, coupon);
  if (code && couponError) await Cart.setCoupon(userId, null, trx);

  return {
    items: rows.map((r, i) => ({
      productId: r.id,
      product: toCard(r),
      quantity: r.stock > 0 ? lines[i].quantity : r.quantity,
      lineTotal: round2(r.price * lines[i].quantity),
    })),
    summary,
  };
};

module.exports = { evaluateCoupon, summarize, buildCart, billableQuantity, rs };
