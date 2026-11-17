const db = require('../../../db/connection');
const { productCardQuery } = require('../../../../helpers/productQuery');

// one query: every watch with its product card fields
const listWatches = (userId) =>
  productCardQuery()
    .join('price_watches as w', 'w.product_id', 'p.id')
    .where('w.user_id', userId)
    .select('w.id as watch_id', 'w.target_price', 'w.notify_restock', 'w.initial_price', 'w.created_at as watch_created_at', 'w.last_notified_at')
    .orderBy([{ column: 'w.created_at', order: 'desc' }, { column: 'w.id', order: 'desc' }]);

const findWatch = (userId, productId) => db('price_watches').where({ user_id: userId, product_id: productId }).first();

const productForWatch = (productId) => db('products').where({ id: productId }).first('id', 'title', 'price', 'stock');

// initial_price is only set on insert so "dropped since you started watching" stays meaningful
const upsertWatch = ({ userId, productId, targetPrice, notifyRestock, initialPrice }) =>
  db('price_watches')
    .insert({ user_id: userId, product_id: productId, target_price: targetPrice, notify_restock: notifyRestock, initial_price: initialPrice })
    .onConflict(['user_id', 'product_id'])
    .merge(['target_price', 'notify_restock'])
    .returning('id');

const removeWatch = (userId, productId) => db('price_watches').where({ user_id: userId, product_id: productId }).del();

// watchers of one product: explicit watches + wishlisters (implicit "smart wishlist" watch)
const watchersOf = async (productId, trx = db) => {
  const [watches, wishlisters] = await Promise.all([
    trx('price_watches').where({ product_id: productId }).select('id', 'user_id', 'target_price', 'notify_restock'),
    trx('wishlist_items').where({ product_id: productId }).select('user_id'),
  ]);
  return { watches, wishlisters: wishlisters.map((w) => w.user_id) };
};

const touchNotified = (watchIds, trx = db) =>
  (watchIds.length ? trx('price_watches').whereIn('id', watchIds).update({ last_notified_at: trx.fn.now() }) : Promise.resolve());

module.exports = { listWatches, findWatch, productForWatch, upsertWatch, removeWatch, watchersOf, touchNotified };
