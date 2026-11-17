const db = require('../../../db/connection');

const SWIPE_SOURCE = 'discover';
const SWIPE_TYPES = ['like', 'pass', 'cart'];

// product ids the user swiped in the last `days` days (never re-shown in the deck)
const recentlySwiped = async (userId, days = 14) =>
  (await db('user_interactions')
    .where({ user_id: userId, source: SWIPE_SOURCE })
    .whereIn('type', SWIPE_TYPES)
    .where('created_at', '>', db.raw(`now() - (? * interval '1 day')`, [days]))
    .distinct('product_id')).map((r) => r.product_id);

const swipes = (userId, days = 60) =>
  db('user_interactions')
    .where({ user_id: userId, source: SWIPE_SOURCE })
    .whereIn('type', SWIPE_TYPES)
    .where('created_at', '>', db.raw(`now() - (? * interval '1 day')`, [days]))
    .orderBy('created_at', 'desc')
    .limit(500)
    .select('product_id', 'type', 'created_at');

const productForSwipe = (productId) => db('products').where({ id: productId }).first('id', 'title', 'stock');

module.exports = { recentlySwiped, swipes, productForSwipe, SWIPE_SOURCE };
