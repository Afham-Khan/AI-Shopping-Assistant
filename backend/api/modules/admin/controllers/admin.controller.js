const { applyProductUpdate } = require('../../alerts/services/priceAlerts.service');
const { productCardQuery } = require('../../../../helpers/productQuery');
const { ok } = require('../../../../helpers/response');
const { toCard } = require('../../../../helpers/serializers');
const { notFound, badRequest } = require('../../../../helpers/errors');

// PATCH /admin/products/:id { price?, compareAtPrice?, stock? } -> price history + watcher alerts
module.exports.updateProduct = async (req, res) => {
  const changes = {};
  for (const key of ['price', 'compareAtPrice', 'stock']) if (req.body[key] !== undefined) changes[key] = req.body[key];
  if (!Object.keys(changes).length) throw badRequest('Send at least one of price, compareAtPrice, stock');
  const result = await applyProductUpdate(req.params.id, changes, { source: 'admin' });
  if (!result) throw notFound('Product not found');
  const row = await productCardQuery().where('p.id', req.params.id).first();
  const { alerts } = result;
  const message = alerts.notifiedUsers
    ? `Product updated. ${alerts.notifiedUsers} watcher${alerts.notifiedUsers === 1 ? '' : 's'} notified`
    : 'Product updated';
  return ok(res, { product: toCard(row), changes: result.changes, priceHistoryRecorded: result.priceHistoryRecorded, alerts }, { message });
};
