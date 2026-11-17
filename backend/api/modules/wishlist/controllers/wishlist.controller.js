const Wishlist = require('../models/wishlist.models');
const Products = require('../../products/models/products.models');
const Interactions = require('../../interactions/models/interactions.models');
const { ok } = require('../../../../helpers/response');
const { toCard } = require('../../../../helpers/serializers');
const { notFound } = require('../../../../helpers/errors');

module.exports.list = async (req, res) =>
  ok(res, (await Wishlist.list(req.userId)).map((row) => ({ ...toCard(row), addedAt: row.added_at })));

module.exports.ids = async (req, res) => ok(res, await Wishlist.ids(req.userId));

module.exports.add = async (req, res) => {
  const { productId } = req.body;
  if (!(await Products.exists(productId))) throw notFound('Product not found');
  const added = await Wishlist.add(req.userId, productId);
  if (added) await Interactions.record({ userId: req.userId, productId, type: 'wishlist', source: req.body.source || 'wishlist' });
  return ok(res, { productId }, { message: added ? 'Added to wishlist' : 'Already in wishlist' });
};

module.exports.remove = async (req, res) => {
  await Wishlist.remove(req.userId, req.params.productId);
  return ok(res, null, { message: 'Removed from wishlist' });
};
