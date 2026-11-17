const db = require('../../../db/connection');
const { isMemoryEnabled } = require('../../../../helpers/memory');

// purchases are order records, not browsing memory, so they are always kept
const ALWAYS_KEPT = new Set(['purchase']);

// rows: [{ userId, productId, type, source }]. Users who turned shopping memory off are not tracked.
const record = async (rows, trx = db) => {
  let list = (Array.isArray(rows) ? rows : [rows]).filter((r) => r.userId && r.productId);
  if (!list.length) return;
  const users = [...new Set(list.filter((r) => !ALWAYS_KEPT.has(r.type)).map((r) => r.userId))];
  const enabled = new Map(await Promise.all(users.map(async (id) => [id, await isMemoryEnabled(id)])));
  list = list.filter((r) => ALWAYS_KEPT.has(r.type) || enabled.get(r.userId));
  if (!list.length) return;
  await trx('user_interactions').insert(list.map((r) => ({
    user_id: r.userId,
    product_id: r.productId,
    type: r.type,
    source: r.source || null,
  })));
};

const productExists = async (id) => Boolean(await db('products').where({ id }).first('id'));

module.exports = { record, productExists };
