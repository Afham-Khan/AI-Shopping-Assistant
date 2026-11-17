const crypto = require('crypto');
const db = require('../../../db/connection');
const Orders = require('../models/orders.models');
const Cart = require('../../cart/models/cart.models');
const Notifications = require('../../notifications/models/notifications.models');
const Interactions = require('../../interactions/models/interactions.models');
const { summarize, billableQuantity, rs } = require('../../cart/services/cart.service');
const { toAddress } = require('../../../../helpers/serializers');
const { badRequest, notFound, conflict } = require('../../../../helpers/errors');

const MINUTE = 60 * 1000;
const PROGRESSION_WINDOW_MS = 24 * 60 * MINUTE;
const FLOW = ['placed', 'confirmed', 'shipped', 'out_for_delivery', 'delivered'];

// demo simulation: minutes after placement at which each status is reached
const STEPS = [
  { status: 'confirmed', after: 1, title: 'Order confirmed', note: 'Seller confirmed your order', body: (n) => `Good news! Order ${n} has been confirmed and is being packed.` },
  { status: 'shipped', after: 3, title: 'Order shipped', note: 'Handed over to courier', body: (n) => `Order ${n} is on its way.` },
  { status: 'out_for_delivery', after: 6, title: 'Out for delivery', note: 'Rider is on the way', body: (n) => `Order ${n} is out for delivery. Keep your phone nearby.` },
  { status: 'delivered', after: 10, title: 'Order delivered', note: 'Delivered successfully', body: (n) => `Order ${n} was delivered. Enjoy! Tap to leave a review.` },
];

const FAST_CITIES = ['karachi', 'lahore', 'islamabad', 'rawalpindi'];

const estimatedDelivery = (order) => {
  if (order.status === 'cancelled') return null;
  if (order.delivered_at) return order.delivered_at;
  const city = String(order.shipping_address?.city || '').toLowerCase();
  const days = FAST_CITIES.includes(city) ? 2 : 4;
  return new Date(new Date(order.placed_at).getTime() + days * 24 * 60 * MINUTE).toISOString();
};

const generateOrderNumber = () => {
  const d = new Date();
  const ymd = `${String(d.getUTCFullYear()).slice(2)}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`;
  return `CW-${ymd}-${crypto.randomBytes(4).toString('hex').toUpperCase().slice(0, 6)}`;
};

const toDetail = (order, items, timeline) => ({
  id: order.id,
  orderNumber: order.order_number,
  status: order.status,
  paymentMethod: order.payment_method,
  paymentStatus: order.payment_status,
  cardLast4: order.card_last4,
  subtotal: order.subtotal,
  discount: order.discount,
  shippingFee: order.shipping_fee,
  total: order.total,
  couponCode: order.coupon_code,
  shippingAddress: order.shipping_address,
  notes: order.notes,
  placedAt: order.placed_at,
  deliveredAt: order.delivered_at,
  cancelledAt: order.cancelled_at,
  estimatedDelivery: estimatedDelivery(order),
  items: items.map((i) => ({
    productId: i.product_id,
    title: i.title,
    thumbnail: i.thumbnail_url,
    unitPrice: i.unit_price,
    quantity: i.quantity,
    lineTotal: i.line_total,
  })),
  timeline: timeline.map((t) => ({ status: t.status, note: t.note, createdAt: t.created_at })),
});

const loadDetail = async (order, trx = db) => {
  const [items, timeline] = await Promise.all([Orders.items(order.id, trx), Orders.timeline(order.id, trx)]);
  return toDetail(order, items, timeline);
};

const advance = async (orderId, now = Date.now()) =>
  db.transaction(async (trx) => {
    const order = await Orders.lockById(orderId, trx);
    const placedAt = new Date(order.placed_at).getTime();
    if (!FLOW.includes(order.status) || order.status === 'delivered' || now - placedAt > PROGRESSION_WINDOW_MS) return;
    const current = FLOW.indexOf(order.status);
    const due = STEPS.filter((s) => FLOW.indexOf(s.status) > current && placedAt + s.after * MINUTE <= now);
    if (!due.length) return;

    const at = (s) => new Date(placedAt + s.after * MINUTE);
    await Orders.insertHistory(due.map((s) => ({ order_id: order.id, status: s.status, note: s.note, created_at: at(s) })), trx);
    await Notifications.create(due.map((s) => ({
      userId: order.user_id,
      type: 'order',
      title: s.title,
      body: s.body(order.order_number),
      data: { orderId: order.id, orderNumber: order.order_number, status: s.status },
      createdAt: at(s),
    })), trx);
    const last = due[due.length - 1];
    const changes = { status: last.status };
    if (last.status === 'delivered') {
      changes.delivered_at = at(last);
      changes.payment_status = 'paid';
    }
    await Orders.update(order.id, changes, trx);
  });

const progressUserOrders = async (userId) => {
  const rows = await Orders.progressable(userId, new Date(Date.now() - PROGRESSION_WINDOW_MS));
  for (const { id } of rows) await advance(id);
};

const placeOrder = async (userId, { addressId, paymentMethod, card, notes }) =>
  db.transaction(async (trx) => {
    const address = await Orders.findAddress(addressId, userId, trx);
    if (!address) throw notFound('Address not found');

    const rows = await Cart.items(userId, trx, { lock: true });
    if (!rows.length) throw badRequest('Your cart is empty');
    const short = rows.find((r) => r.stock < r.quantity);
    if (short) {
      throw conflict(short.stock > 0
        ? `Only ${short.stock} left of ${short.title}. Please update your cart`
        : `${short.title} is out of stock. Please remove it from your cart`);
    }

    const code = await Cart.couponCode(userId, trx);
    const coupon = code ? await Cart.findCoupon(code, trx) : null;
    const lines = rows.map((r) => ({ price: r.price, compareAtPrice: r.compare_at_price, quantity: billableQuantity(r) }));
    const summary = summarize(lines, coupon);
    if (coupon && summary.couponError) throw badRequest(`Coupon ${coupon.code} can no longer be applied: ${summary.couponError}`);

    let orderNumber = generateOrderNumber();
    while (await Orders.orderNumberExists(orderNumber, trx)) orderNumber = generateOrderNumber();

    const { id: _id, isDefault: _d, ...shippingAddress } = toAddress(address);
    const order = await Orders.insertOrder({
      order_number: orderNumber,
      user_id: userId,
      status: 'placed',
      payment_method: paymentMethod,
      payment_status: paymentMethod === 'card' ? 'paid' : 'pending',
      card_last4: paymentMethod === 'card' ? card.last4 : null,
      subtotal: summary.subtotal,
      discount: summary.discount,
      shipping_fee: summary.shippingFee,
      total: summary.total,
      coupon_code: summary.coupon ? coupon.code : null,
      shipping_address: JSON.stringify(shippingAddress),
      notes: notes || null,
    }, trx);

    await Orders.insertItems(rows.map((r, i) => ({
      order_id: order.id,
      product_id: r.id,
      title: r.title,
      thumbnail_url: r.thumbnail_url,
      unit_price: r.price,
      quantity: lines[i].quantity,
      line_total: Math.round(r.price * lines[i].quantity * 100) / 100,
    })), trx);

    for (const [i, r] of rows.entries()) {
      const updated = await Orders.decrementStock(r.id, lines[i].quantity, trx);
      if (!updated) throw conflict(`${r.title} just sold out. Please update your cart`);
    }

    await Orders.insertHistory({ order_id: order.id, status: 'placed', note: 'Order placed', created_at: order.placed_at }, trx);
    await Interactions.record(rows.map((r) => ({ userId, productId: r.id, type: 'purchase', source: 'checkout' })), trx);
    await Cart.clearItems(userId, trx);
    await Cart.setCoupon(userId, null, trx);
    if (order.coupon_code) await Orders.incrementCouponUsage(order.coupon_code, trx);
    await Notifications.create({
      userId,
      type: 'order',
      title: 'Order placed',
      body: `Thanks! Your order ${orderNumber} of ${rs(order.total)} has been placed.`,
      data: { orderId: order.id, orderNumber, status: 'placed' },
    }, trx);

    return loadDetail(order, trx);
  });

const getDetail = async (userId, orderId) => {
  const order = await Orders.findOwned(orderId, userId);
  if (!order) throw notFound('Order not found');
  await advance(order.id);
  return loadDetail(await Orders.findOwned(orderId, userId));
};

const cancel = async (userId, orderId) => {
  const existing = await Orders.findOwned(orderId, userId);
  if (!existing) throw notFound('Order not found');
  await advance(existing.id);

  return db.transaction(async (trx) => {
    const order = await Orders.findOwned(orderId, userId, trx, { lock: true });
    if (!['placed', 'confirmed'].includes(order.status)) {
      throw conflict(`This order is already ${order.status.replace(/_/g, ' ')} and can no longer be cancelled`);
    }
    const items = await Orders.items(order.id, trx);
    for (const item of items) {
      if (item.product_id) await Orders.restock(item.product_id, item.quantity, trx);
    }
    if (order.coupon_code) await Orders.decrementCouponUsage(order.coupon_code, trx);
    const updated = await Orders.update(order.id, {
      status: 'cancelled',
      cancelled_at: trx.fn.now(),
      payment_status: order.payment_status === 'paid' ? 'refunded' : order.payment_status,
    }, trx);
    await Orders.insertHistory({ order_id: order.id, status: 'cancelled', note: 'Cancelled by customer' }, trx);
    await Notifications.create({
      userId,
      type: 'order',
      title: 'Order cancelled',
      body: `Order ${order.order_number} has been cancelled${order.payment_status === 'paid' ? ' and your payment will be refunded' : ''}.`,
      data: { orderId: order.id, orderNumber: order.order_number, status: 'cancelled' },
    }, trx);
    return loadDetail(updated, trx);
  });
};

module.exports = { STEPS, FLOW, placeOrder, getDetail, cancel, progressUserOrders, advance, estimatedDelivery, generateOrderNumber };
