const db = require('../../../db/connection');

const create = (rows, trx = db) => {
  const list = Array.isArray(rows) ? rows : [rows];
  return trx('notifications').insert(list.map((n) => ({
    user_id: n.userId,
    type: n.type,
    title: n.title,
    body: n.body,
    data: JSON.stringify(n.data || {}),
    ...(n.createdAt && { created_at: n.createdAt }),
  })));
};

const listByUser = async (userId, { limit, offset }) => {
  const [rows, { total }, { unread }] = await Promise.all([
    db('notifications').where({ user_id: userId }).orderBy([{ column: 'created_at', order: 'desc' }, { column: 'id', order: 'desc' }]).limit(limit).offset(offset),
    db('notifications').where({ user_id: userId }).count('* as total').first(),
    db('notifications').where({ user_id: userId }).whereNull('read_at').count('* as unread').first(),
  ]);
  return { rows, total, unread };
};

const unreadCount = (userId) =>
  db('notifications').where({ user_id: userId }).whereNull('read_at').count('* as n').first().then((r) => r.n);

const findOwned = (id, userId) => db('notifications').where({ id, user_id: userId }).first('id', 'read_at');

const markRead = (id) => db('notifications').where({ id }).whereNull('read_at').update({ read_at: db.fn.now() });

const markAllRead = (userId) =>
  db('notifications').where({ user_id: userId }).whereNull('read_at').update({ read_at: db.fn.now() });

module.exports = { create, listByUser, unreadCount, findOwned, markRead, markAllRead };
