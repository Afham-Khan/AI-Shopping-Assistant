const Interactions = require('../models/interactions.models');
const { ok } = require('../../../../helpers/response');
const { notFound } = require('../../../../helpers/errors');

module.exports.create = async (req, res) => {
  if (!req.userId) return ok(res, null);
  const { productId, type, source } = req.body;
  if (!(await Interactions.productExists(productId))) throw notFound('Product not found');
  await Interactions.record({ userId: req.userId, productId, type, source });
  return ok(res, null);
};
