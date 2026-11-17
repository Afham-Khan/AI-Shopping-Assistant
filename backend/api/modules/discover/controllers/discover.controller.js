const db = require('../../../db/connection');
const Discover = require('../models/discover.models');
const Cart = require('../../cart/models/cart.models');
const Interactions = require('../../interactions/models/interactions.models');
const engine = require('../../ai/engine');
const { invalidate } = require('../../ai/engine/ranking/personalization');
const { ok } = require('../../../../helpers/response');
const { notFound, conflict } = require('../../../../helpers/errors');
const { isMemoryEnabled } = require('../../../../helpers/memory');
const { MAX_CART_QTY } = require('../../../../helpers/constants');

const tasteOf = async (userId) => engine.discoverTaste({ userId, swipes: await Discover.swipes(userId) });

module.exports.deck = async (req, res) => {
  const limit = Number(req.query.limit) || 20;
  const exclude = new Set(req.userId ? await Discover.recentlySwiped(req.userId) : []);
  const deck = await engine.discoverDeck({ userId: req.userId || null, exclude, limit });
  return ok(res, { products: deck.cards, personalized: deck.personalized, strategy: deck.strategy, excludedRecent: exclude.size });
};

// like -> wishlist-strength signal, pass -> negative signal, bag -> add to cart
module.exports.swipe = async (req, res) => {
  const { productId, action } = req.body;
  const product = await Discover.productForSwipe(productId);
  if (!product) throw notFound('Product not found');
  let message;
  if (action === 'bag') {
    if (product.stock <= 0) throw conflict(`${product.title} is out of stock`);
    const existing = await Cart.findItem(req.userId, productId);
    const quantity = Math.min((existing?.quantity || 0) + 1, product.stock, MAX_CART_QTY);
    await db.transaction(async (trx) => {
      await Cart.touch(req.userId, trx);
      await Cart.upsertItem(req.userId, productId, quantity, trx);
      await Interactions.record({ userId: req.userId, productId, type: 'cart', source: Discover.SWIPE_SOURCE }, trx);
    });
    message = 'Added to bag';
  } else {
    await Interactions.record({ userId: req.userId, productId, type: action, source: Discover.SWIPE_SOURCE });
    message = action === 'like' ? 'Saved to your taste' : 'Got it, fewer like this';
  }
  invalidate(req.userId);

  const [taste, swiped] = await Promise.all([tasteOf(req.userId), Discover.recentlySwiped(req.userId)]);
  let next = [];
  if (action !== 'pass') {
    const skip = new Set([productId, ...swiped]);
    next = ((await engine.similar(productId, 8)) || []).filter((p) => !skip.has(p.id)).slice(0, 3);
  }
  return ok(res, { action, productId, taste, next, memoryEnabled: await isMemoryEnabled(req.userId) }, { message });
};

module.exports.taste = async (req, res) => ok(res, await tasteOf(req.userId));

module.exports.reels = async (req, res) =>
  ok(res, await engine.discoverReels({ userId: req.userId || null, perDepartment: Number(req.query.perDepartment) || 6 }));
