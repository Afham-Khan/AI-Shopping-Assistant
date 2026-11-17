const db = require('../../../db/connection');
const Cart = require('../models/cart.models');
const Interactions = require('../../interactions/models/interactions.models');
const { buildCart, evaluateCoupon, summarize, billableQuantity } = require('../services/cart.service');
const { ok } = require('../../../../helpers/response');
const { notFound, conflict, badRequest } = require('../../../../helpers/errors');
const { MAX_CART_QTY } = require('../../../../helpers/constants');

const sendCart = async (res, userId, message) => ok(res, await buildCart(userId), message ? { message } : {});

module.exports.get = async (req, res) => sendCart(res, req.userId);

module.exports.addItem = async (req, res) => {
  const { productId } = req.body;
  const quantity = req.body.quantity ?? 1;
  const product = await Cart.productStock(productId);
  if (!product) throw notFound('Product not found');
  if (product.stock <= 0) throw conflict(`${product.title} is out of stock`);

  const existing = await Cart.findItem(req.userId, productId);
  const wanted = (existing?.quantity || 0) + quantity;
  const finalQty = Math.min(wanted, product.stock, MAX_CART_QTY);
  await db.transaction(async (trx) => {
    await Cart.touch(req.userId, trx);
    await Cart.upsertItem(req.userId, productId, finalQty, trx);
    await Interactions.record({ userId: req.userId, productId, type: 'cart', source: req.body.source || 'cart' }, trx);
  });
  const message = finalQty < wanted
    ? `Only ${finalQty} can be added (${finalQty === MAX_CART_QTY ? `limit ${MAX_CART_QTY} per item` : 'limited stock'})`
    : 'Added to cart';
  return sendCart(res, req.userId, message);
};

module.exports.updateItem = async (req, res) => {
  const productId = req.params.productId;
  const { quantity } = req.body;
  const existing = await Cart.findItem(req.userId, productId);
  if (!existing) throw notFound('Item is not in your cart');
  if (quantity === 0) {
    await Cart.removeItem(req.userId, productId);
    return sendCart(res, req.userId, 'Removed from cart');
  }
  const product = await Cart.productStock(productId);
  if (product.stock <= 0) throw conflict(`${product.title} is out of stock`);
  const finalQty = Math.min(quantity, product.stock, MAX_CART_QTY);
  await Cart.setQuantity(req.userId, productId, finalQty);
  return sendCart(res, req.userId, finalQty < quantity ? `Only ${finalQty} available` : undefined);
};

module.exports.removeItem = async (req, res) => {
  await Cart.removeItem(req.userId, req.params.productId);
  return sendCart(res, req.userId, 'Removed from cart');
};

module.exports.clear = async (req, res) => {
  await db.transaction(async (trx) => {
    await Cart.clearItems(req.userId, trx);
    await Cart.setCoupon(req.userId, null, trx);
  });
  return sendCart(res, req.userId, 'Cart cleared');
};

module.exports.applyCoupon = async (req, res) => {
  const coupon = await Cart.findCoupon(req.body.code);
  const rows = await Cart.items(req.userId);
  const lines = rows.map((r) => ({ price: r.price, compareAtPrice: r.compare_at_price, quantity: billableQuantity(r) }));
  const { subtotal } = summarize(lines, null);
  const result = evaluateCoupon(coupon, subtotal);
  if (result.error) throw badRequest(result.error, [{ field: 'code', message: result.error }]);
  await Cart.setCoupon(req.userId, coupon.code);
  return sendCart(res, req.userId, `${coupon.code} applied`);
};

module.exports.removeCoupon = async (req, res) => {
  await Cart.setCoupon(req.userId, null);
  return sendCart(res, req.userId, 'Coupon removed');
};
