// product updates -> price history + price-drop / restock notifications for watchers.
// used by PATCH /admin/products/:id and `npm run demo:price-drop`.
const db = require('../../../db/connection');
const Alerts = require('../models/alerts.models');
const Notifications = require('../../notifications/models/notifications.models');

const rs = (n) => `Rs ${Math.round(Number(n) || 0).toLocaleString('en-US')}`;
const cut = (s, n) => (s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s);
const round2 = (n) => Math.round(n * 100) / 100;

// pure: before/after product state + watchers -> notification rows and the explicit watches that fired
const decideAlerts = (before, after, { watches = [], wishlisters = [] }) => {
  const oldPrice = Number(before.price);
  const newPrice = Number(after.price);
  const dropped = newPrice < oldPrice;
  const restocked = Number(before.stock) <= 0 && Number(after.stock) > 0;
  if (!dropped && !restocked) return { rows: [], firedWatchIds: [], counts: { priceDrop: 0, restock: 0 } };

  const dropPercent = dropped ? round2((1 - newPrice / oldPrice) * 100) : 0;
  const base = {
    productId: after.id, slug: after.slug, thumbnail: after.thumbnail_url || null, oldPrice, newPrice, dropPercent,
  };
  const rows = [];
  const fired = [];
  const counts = { priceDrop: 0, restock: 0 };
  const notified = new Set();

  const push = (userId, { target = null, reason, restockWanted }) => {
    const dropHit = dropped && (target === null || newPrice <= Number(target));
    const restockHit = restocked && restockWanted;
    if (!dropHit && !restockHit) return false;
    const title = cut(after.title, 90);
    if (restockHit) {
      counts.restock += 1;
      rows.push({
        userId,
        type: 'restock',
        title: dropHit ? `Back in stock and cheaper: ${title}` : `Back in stock: ${title}`,
        body: `${after.title} is available again at ${rs(newPrice)}${dropHit ? ` (was ${rs(oldPrice)})` : ''}. Grab it before it sells out.`,
        data: { ...base, targetPrice: target === null ? null : Number(target), reason, event: dropHit ? 'restock_price_drop' : 'restock' },
      });
    } else {
      counts.priceDrop += 1;
      const hitTarget = target !== null;
      rows.push({
        userId,
        type: 'price_drop',
        title: `Price drop: ${title}`,
        body: `Now ${rs(newPrice)} (was ${rs(oldPrice)}), ${Math.round(dropPercent)}% lower.${hitTarget ? ` It reached your target of ${rs(target)}.` : reason === 'wishlist' ? ' It is on your wishlist.' : ''}`,
        data: { ...base, targetPrice: hitTarget ? Number(target) : null, reason, event: 'price_drop' },
      });
    }
    notified.add(userId);
    return true;
  };

  for (const w of watches) {
    const target = w.target_price === null || w.target_price === undefined ? null : Number(w.target_price);
    if (push(w.user_id, { target, reason: 'watch', restockWanted: w.notify_restock !== false })) fired.push(w.id);
  }
  // wishlisters without an explicit watch get any drop and every restock
  for (const userId of new Set(wishlisters)) {
    if (watches.some((w) => w.user_id === userId) || notified.has(userId)) continue;
    push(userId, { target: null, reason: 'wishlist', restockWanted: true });
  }
  return { rows, firedWatchIds: fired, counts };
};

// keeps compare-at / discount consistent with the new price
const pricing = (before, changes) => {
  const price = changes.price !== undefined ? Number(changes.price) : Number(before.price);
  let compareAt;
  if (changes.compareAtPrice !== undefined) compareAt = changes.compareAtPrice === null ? null : Number(changes.compareAtPrice);
  else {
    compareAt = before.compare_at_price === null ? null : Number(before.compare_at_price);
    // a drop keeps the old price as the strike-through reference
    if (price < Number(before.price)) compareAt = Math.max(compareAt || 0, Number(before.price));
  }
  if (compareAt !== null && compareAt <= price) compareAt = null;
  const discount = compareAt ? round2((1 - price / compareAt) * 100) : 0;
  return { price, compareAt, discount };
};

// changes: { price?, compareAtPrice?, stock? }. Returns null when the product does not exist.
const applyProductUpdate = async (productId, changes, { source = 'admin' } = {}) => {
  const result = await db.transaction(async (trx) => {
    const before = await trx('products').where({ id: productId }).forUpdate()
      .first('id', 'title', 'slug', 'price', 'compare_at_price', 'discount_percent', 'stock', 'thumbnail_url');
    if (!before) return null;
    const { price, compareAt, discount } = pricing(before, changes);
    const stock = changes.stock !== undefined ? Number(changes.stock) : Number(before.stock);
    const [after] = await trx('products').where({ id: productId })
      .update({ price, compare_at_price: compareAt, discount_percent: discount, stock, updated_at: trx.fn.now() })
      .returning(['id', 'title', 'slug', 'price', 'compare_at_price', 'discount_percent', 'stock', 'thumbnail_url']);

    const priceChanged = Number(before.price) !== price || Number(before.compare_at_price || 0) !== Number(compareAt || 0);
    if (priceChanged) {
      await trx('price_history').insert({ product_id: productId, price, compare_at_price: compareAt, stock, source });
    }
    const watchers = await Alerts.watchersOf(productId, trx);
    const decision = decideAlerts(before, after, watchers);
    if (decision.rows.length) await Notifications.create(decision.rows, trx);
    await Alerts.touchNotified(decision.firedWatchIds, trx);
    return {
      product: after,
      changes: {
        price: Number(before.price) !== price ? { from: Number(before.price), to: price } : null,
        stock: Number(before.stock) !== stock ? { from: Number(before.stock), to: stock } : null,
      },
      priceHistoryRecorded: priceChanged,
      alerts: { ...decision.counts, notifiedUsers: decision.rows.length },
    };
  });
  return result;
};

module.exports = { applyProductUpdate, decideAlerts, pricing };
