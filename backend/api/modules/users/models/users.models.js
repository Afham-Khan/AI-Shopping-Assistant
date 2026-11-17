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

// shopping memory --------------------------------------------------------------

const SIGNAL_WEIGHT = `CASE i.type WHEN 'purchase' THEN 3 WHEN 'cart' THEN 2 WHEN 'wishlist' THEN 2 WHEN 'like' THEN 2
  WHEN 'ai_click' THEN 1.5 WHEN 'click' THEN 1 WHEN 'view' THEN 0.7 ELSE 0 END`;

// fixed number of aggregate queries, whatever the history size
const memorySnapshot = async (userId) => {
  const positive = () => db('user_interactions as i').join('products as p', 'p.id', 'i.product_id').where('i.user_id', userId).whereNot('i.type', 'pass');
  const [categories, brands, prices, passes, searches, counts, last] = await Promise.all([
    positive().join('categories as c', 'c.id', 'p.category_id').groupBy('c.slug', 'c.name')
      .select('c.slug', 'c.name', db.raw(`sum(${SIGNAL_WEIGHT})::float as weight`)).orderBy('weight', 'desc').limit(5),
    positive().join('brands as b', 'b.id', 'p.brand_id').groupBy('b.name')
      .select('b.name', db.raw(`sum(${SIGNAL_WEIGHT})::float as weight`)).orderBy('weight', 'desc').limit(5),
    positive().select(
      db.raw('percentile_cont(0.2) within group (order by p.price)::float as low'),
      db.raw('percentile_cont(0.8) within group (order by p.price)::float as high'),
      db.raw('avg(p.price)::float as avg'),
      db.raw('count(*)::int as n'),
    ).first(),
    db('user_interactions as i').join('products as p', 'p.id', 'i.product_id').join('categories as c', 'c.id', 'p.category_id')
      .where({ 'i.user_id': userId, 'i.type': 'pass' }).groupBy('c.name').select('c.name').count('* as n').orderBy('n', 'desc').limit(3),
    db('search_history').where({ user_id: userId }).groupBy('query').select('query').max('created_at as at').orderBy('at', 'desc').limit(5),
    db.raw(`SELECT
        (SELECT count(*) FROM user_interactions WHERE user_id = :id)::int AS interactions,
        (SELECT count(*) FROM search_history WHERE user_id = :id)::int AS searches,
        (SELECT count(*) FROM ai_conversations WHERE user_id = :id AND context::text <> '{}')::int AS chats`, { id: userId }),
    db('user_interactions').where({ user_id: userId }).max('created_at as at').first(),
  ]);
  return { categories, brands, prices, passes, searches, counts: counts.rows[0], lastActivityAt: last?.at || null };
};

// the user's own data only: browsing signals, searches and chat context (messages and orders are kept)
const clearMemory = (userId) =>
  db.transaction(async (trx) => {
    const interactions = await trx('user_interactions').where({ user_id: userId }).del();
    const searches = await trx('search_history').where({ user_id: userId }).del();
    const chatContexts = await trx('ai_conversations').where({ user_id: userId }).whereRaw("context::text <> '{}'").update({ context: '{}' });
    return { interactions, searches, chatContexts };
  });

module.exports = {
  memorySnapshot,
  clearMemory,
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
