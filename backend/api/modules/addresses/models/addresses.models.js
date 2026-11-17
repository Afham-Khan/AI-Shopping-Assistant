const db = require('../../../db/connection');

const listByUser = (userId) =>
  db('addresses').where({ user_id: userId }).orderBy([{ column: 'is_default', order: 'desc' }, { column: 'id', order: 'desc' }]);

const findOwned = (id, userId, trx = db) => trx('addresses').where({ id, user_id: userId }).first();

const countByUser = (userId, trx = db) =>
  trx('addresses').where({ user_id: userId }).count('* as n').first().then((r) => r.n);

const clearDefault = (userId, trx) =>
  trx('addresses').where({ user_id: userId, is_default: true }).update({ is_default: false });

// serialises address writes per user (row lock on the user) so two defaults can never coexist
const lockUserAddresses = (userId, trx) => trx('users').where({ id: userId }).forUpdate().first('id');

const insert = async (row, trx) => (await trx('addresses').insert(row).returning('*'))[0];

const update = async (id, changes, trx) =>
  (await trx('addresses').where({ id }).update({ ...changes, updated_at: trx.fn.now() }).returning('*'))[0];

const remove = (id, trx) => trx('addresses').where({ id }).del();

const latestOther = (userId, trx) => trx('addresses').where({ user_id: userId }).orderBy('id', 'desc').first();

module.exports = { listByUser, findOwned, countByUser, clearDefault, lockUserAddresses, insert, update, remove, latestOther };
