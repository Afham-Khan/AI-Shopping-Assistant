const Alerts = require('../models/alerts.models');
const { ok, created } = require('../../../../helpers/response');
const { toCard } = require('../../../../helpers/serializers');
const { notFound, badRequest } = require('../../../../helpers/errors');

const rs = (n) => `Rs ${Math.round(n).toLocaleString('en-US')}`;

// PriceWatch = { id, product: ProductCard, targetPrice, notifyRestock, initialPrice, createdAt, lastNotifiedAt, status }
const toWatch = (row) => {
  const target = row.target_price === null ? null : Number(row.target_price);
  const initial = row.initial_price === null ? null : Number(row.initial_price);
  const dropSinceWatch = initial !== null ? Math.max(0, Math.round((initial - row.price) * 100) / 100) : 0;
  let summary;
  if (row.stock <= 0) summary = row.notify_restock ? 'Out of stock: we will tell you when it is back' : 'Out of stock';
  else if (target !== null && row.price <= target) summary = `At or below your target of ${rs(target)}`;
  else if (target !== null) summary = `${rs(row.price - target)} above your target of ${rs(target)}`;
  else if (dropSinceWatch > 0) summary = `${rs(dropSinceWatch)} cheaper since you started watching`;
  else summary = 'Watching for any price drop';
  return {
    id: row.watch_id,
    product: toCard(row),
    targetPrice: target,
    notifyRestock: row.notify_restock,
    initialPrice: initial,
    createdAt: row.watch_created_at,
    lastNotifiedAt: row.last_notified_at,
    status: {
      currentPrice: row.price,
      inStock: row.stock > 0,
      targetReached: target !== null && row.price <= target,
      dropSinceWatch,
      summary,
    },
  };
};

module.exports.list = async (req, res) => ok(res, (await Alerts.listWatches(req.userId)).map(toWatch));

module.exports.upsert = async (req, res) => {
  const { productId } = req.body;
  const targetPrice = req.body.targetPrice ?? null;
  const notifyRestock = req.body.notifyRestock ?? true;
  const product = await Alerts.productForWatch(productId);
  if (!product) throw notFound('Product not found');
  if (targetPrice !== null && product.stock > 0 && targetPrice >= product.price) {
    throw badRequest(`targetPrice must be below the current price (${rs(product.price)})`, [{ field: 'targetPrice', message: 'Must be below the current price' }]);
  }
  const existing = await Alerts.findWatch(req.userId, productId);
  await Alerts.upsertWatch({ userId: req.userId, productId, targetPrice, notifyRestock, initialPrice: product.price });
  const watch = (await Alerts.listWatches(req.userId)).find((w) => w.id === productId);
  const send = existing ? ok : created;
  return send(res, toWatch(watch), { message: existing ? 'Price watch updated' : `Watching ${product.title}` });
};

module.exports.remove = async (req, res) => {
  const removed = await Alerts.removeWatch(req.userId, req.params.productId);
  if (!removed) throw notFound('You are not watching this product');
  return ok(res, null, { message: 'Price watch removed' });
};
