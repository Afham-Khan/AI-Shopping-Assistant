const db = require('../../../db/connection');
const { productCardQuery } = require('../../../../helpers/productQuery');

const list = (userId) =>
  productCardQuery()
    .join('wishlist_items as w', 'w.product_id', 'p.id')
    .where('w.user_id', userId)
    .select('w.created_at as added_at')
    .orderBy([{ column: 'w.created_at', order: 'desc' }, { column: 'w.id', order: 'desc' }]);

const ids = async (userId) =>
  (await db('wishlist_items').where({ user_id: userId }).orderBy('created_at', 'desc').select('product_id')).map((r) => r.product_id);

// returns true only when a new row was created
const add = async (userId, productId) => {
  const rows = await db('wishlist_items').insert({ user_id: userId, product_id: productId })
    .onConflict(['user_id', 'product_id']).ignore().returning('id');
  return rows.length > 0;
};

const remove = (userId, productId) => db('wishlist_items').where({ user_id: userId, product_id: productId }).del();

module.exports = { list, ids, add, remove };
