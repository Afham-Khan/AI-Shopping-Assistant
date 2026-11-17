const db = require('../../../db/connection');

// rows: [{ userId, productId, type, source }]
const record = (rows, trx = db) => {
  const list = (Array.isArray(rows) ? rows : [rows]).filter((r) => r.userId && r.productId);
  if (!list.length) return Promise.resolve();
  return trx('user_interactions').insert(list.map((r) => ({
    user_id: r.userId,
    product_id: r.productId,
    type: r.type,
    source: r.source || null,
  })));
};

const productExists = async (id) => Boolean(await db('products').where({ id }).first('id'));

module.exports = { record, productExists };
