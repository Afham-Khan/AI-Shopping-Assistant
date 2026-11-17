const db = require('../../../db/connection');

const PUBLIC_COLUMNS = ['id', 'name', 'email', 'phone', 'avatar_url', 'role', 'preferences', 'is_onboarded', 'created_at'];

const findById = (id, trx = db) => trx('users').select(PUBLIC_COLUMNS).where({ id }).first();

// only auth flows need the hash; everything else uses PUBLIC_COLUMNS
const findWithHashByEmail = (email, trx = db) =>
  trx('users').select([...PUBLIC_COLUMNS, 'password_hash']).where({ email }).first();

const findWithHashById = (id, trx = db) =>
  trx('users').select([...PUBLIC_COLUMNS, 'password_hash']).where({ id }).first();

const emailExists = async (email) => Boolean(await db('users').where({ email }).first('id'));

const create = async ({ name, email, passwordHash }) => {
  const [user] = await db('users')
    .insert({ name, email, password_hash: passwordHash })
    .returning(PUBLIC_COLUMNS);
  return user;
};

const update = async (id, changes, trx = db) => {
  const [user] = await trx('users')
    .where({ id })
    .update({ ...changes, updated_at: trx.fn.now() })
    .returning(PUBLIC_COLUMNS);
  return user;
};

const updatePassword = (id, passwordHash, trx = db) =>
  trx('users').where({ id }).update({ password_hash: passwordHash, updated_at: trx.fn.now() });

const existingCategorySlugs = async (slugs) =>
  (await db('categories').whereIn('slug', slugs).select('slug')).map((r) => r.slug);

const stats = async (userId) => {
  const count = (table) => db(table).where({ user_id: userId }).count('* as n').first().then((r) => r.n);
  const [orders, wishlist, reviews, conversations] = await Promise.all([
    count('orders'), count('wishlist_items'), count('reviews'), count('ai_conversations'),
  ]);
  return { orders, wishlist, reviews, conversations };
};

module.exports = {
  PUBLIC_COLUMNS,
  findById,
  findWithHashByEmail,
  findWithHashById,
  emailExists,
  create,
  update,
  updatePassword,
  existingCategorySlugs,
  stats,
};
