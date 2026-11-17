// data access for the ai module (knex). engine code never builds sql itself.
const db = require('../../../db/connection');
const { productBaseQuery } = require('../../../../helpers/productQuery');

// catalog -------------------------------------------------------------------

const catalogSignature = async () => {
  const [row] = await db('products').select(db.raw('count(*)::int as count, max(updated_at) as updated'));
  return `${row.count}:${row.updated ? new Date(row.updated).getTime() : 0}`;
};

const loadCatalogRows = () => productBaseQuery().orderBy('p.id');

const loadTaxonomy = () =>
  db('categories as c')
    .join('departments as d', 'd.id', 'c.department_id')
    .select('c.id', 'c.slug', 'c.name', 'd.slug as departmentSlug', 'd.name as departmentName', 'd.id as departmentId')
    .orderBy(['d.sort_order', 'c.sort_order']);

const loadBrandNames = async () => (await db('brands').select('name')).map((b) => b.name);

const loadEmbeddings = (model) =>
  db('product_embeddings').where({ model }).select('product_id', 'dims', 'vector');

const upsertEmbeddings = async (rows) => {
  if (!rows.length) return;
  await db('product_embeddings')
    .insert(rows.map((r) => ({ ...r, updated_at: db.fn.now() })))
    .onConflict('product_id')
    .merge(['model', 'dims', 'vector', 'updated_at']);
};

const loadImageEmbeddings = (model) =>
  db('product_image_embeddings').where({ model }).select('product_id', 'vector');

const upsertImageEmbeddings = async (rows) => {
  if (!rows.length) return;
  await db('product_image_embeddings')
    .insert(rows.map((r) => ({ ...r, updated_at: db.fn.now() })))
    .onConflict('product_id')
    .merge(['model', 'dims', 'vector', 'updated_at']);
};

const countEmbeddings = async () => {
  const rows = await db('product_embeddings').select('model').count('* as n').groupBy('model');
  return rows.map((r) => ({ model: r.model, count: Number(r.n) }));
};

const productsWithImages = async (ids) => {
  if (!ids.length) return [];
  const [rows, images] = await Promise.all([
    productBaseQuery().whereIn('p.id', ids),
    db('product_images').whereIn('product_id', ids).orderBy(['product_id', 'sort_order']).select('product_id', 'url'),
  ]);
  const byProduct = new Map();
  for (const img of images) {
    if (!byProduct.has(img.product_id)) byProduct.set(img.product_id, []);
    byProduct.get(img.product_id).push(img.url);
  }
  const order = new Map(ids.map((id, i) => [Number(id), i]));
  return rows
    .map((r) => ({ row: r, images: byProduct.get(r.id) || [] }))
    .sort((a, b) => order.get(a.row.id) - order.get(b.row.id));
};

const ratingBreakdowns = async (ids) => {
  if (!ids.length) return new Map();
  const rows = await db('reviews').whereIn('product_id', ids).select('product_id', 'rating').count('* as n').groupBy('product_id', 'rating');
  const map = new Map();
  for (const r of rows) {
    if (!map.has(r.product_id)) map.set(r.product_id, { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 });
    map.get(r.product_id)[r.rating] = Number(r.n);
  }
  return map;
};

// reviews -------------------------------------------------------------------

const reviewStamp = async (productId) => {
  const [row] = await db('reviews').where({ product_id: productId })
    .select(db.raw('count(*)::int as count, max(updated_at) as updated'));
  return `${row.count}:${row.updated ? new Date(row.updated).getTime() : 0}`;
};

const reviewsFor = (productId) =>
  db('reviews').where({ product_id: productId }).select('id', 'rating', 'title', 'comment', 'helpful_count', 'is_verified', 'created_at')
    .orderBy('helpful_count', 'desc').limit(500);

const productExists = async (productId) => Boolean(await db('products').where({ id: productId }).first('id'));

// personalization signals ---------------------------------------------------

const userSignals = async (userId) => {
  const [user, interactions, wishlist, cart, purchases] = await Promise.all([
    db('users').where({ id: userId }).first('id', 'name', 'preferences'),
    db('user_interactions').where({ user_id: userId }).orderBy('created_at', 'desc').limit(300)
      .select('product_id', 'type', 'created_at'),
    db('wishlist_items').where({ user_id: userId }).select('product_id', 'created_at'),
    db('cart_items').where({ user_id: userId }).select('product_id', 'quantity', 'created_at'),
    db('order_items as oi').join('orders as o', 'o.id', 'oi.order_id').where('o.user_id', userId).whereNotNull('oi.product_id')
      .select('oi.product_id', 'o.placed_at as created_at'),
  ]);
  return { user, interactions, wishlist, cart, purchases };
};

// extra signals for the shopping-dna profile
const profileExtras = async (userId) => {
  const [orders, searches, conversations] = await Promise.all([
    db('orders').where({ user_id: userId }).select(db.raw('count(*)::int as count, count(coupon_code)::int as with_coupon')).first(),
    db('search_history').where({ user_id: userId }).orderBy('created_at', 'desc').limit(50).select('query'),
    db('ai_conversations').where({ user_id: userId }).orderBy('updated_at', 'desc').limit(30).select('context'),
  ]);
  return { orders, searches, conversations };
};

// baskets for item-item co-occurrence: orders, carts and wishlists
const basketRows = async () => {
  const [orders, carts, wishlists] = await Promise.all([
    db('order_items').whereNotNull('product_id').select('order_id as basket', 'product_id'),
    db('cart_items').select('user_id as basket', 'product_id'),
    db('wishlist_items').select('user_id as basket', 'product_id'),
  ]);
  return { orders, carts, wishlists };
};

// commerce lookups for the dialogue --------------------------------------------

const latestOrder = async (userId, orderNumber = null) => {
  const q = db('orders').where({ user_id: userId });
  if (orderNumber) q.andWhereRaw('lower(order_number) = ?', [orderNumber.toLowerCase()]);
  const order = await q.orderBy('placed_at', 'desc').first();
  if (!order) return null;
  const [items, counts] = await Promise.all([
    db('order_items').where({ order_id: order.id }).select('product_id', 'title', 'quantity', 'line_total').limit(5),
    db('orders').where({ user_id: userId }).count('* as n').first(),
  ]);
  return { order, items, totalOrders: Number(counts.n) };
};

const cartSnapshot = async (userId) => {
  const [items, cart] = await Promise.all([
    productBaseQuery().join('cart_items as ci', 'ci.product_id', 'p.id').where('ci.user_id', userId)
      .select('ci.quantity'),
    db('carts').where({ user_id: userId }).first('coupon_code'),
  ]);
  return { items, couponCode: cart?.coupon_code || null };
};

const couponByCode = (code) => (code ? db('coupons').whereRaw('upper(code) = ?', [String(code).toUpperCase()]).first() : Promise.resolve(null));

const activeCoupons = () =>
  db('coupons').where({ is_active: true })
    .andWhere((q) => q.whereNull('expires_at').orWhere('expires_at', '>', db.fn.now()))
    .select('code', 'description', 'discount_type', 'value', 'min_order_amount').orderBy('value', 'desc').limit(3);

const recordSearch = (userId, query, resultsCount) =>
  db('search_history').insert({ user_id: userId, query: query.slice(0, 200), results_count: resultsCount });

// conversations ---------------------------------------------------------------

const createConversation = async (userId, title = 'New chat') => {
  const [row] = await db('ai_conversations').insert({ user_id: userId, title, context: {} }).returning('*');
  return row;
};

const findConversation = (userId, id) => db('ai_conversations').where({ id, user_id: userId }).first();

const updateConversation = (id, patch) =>
  db('ai_conversations').where({ id }).update({ ...patch, updated_at: db.fn.now() });

const listConversations = (userId) =>
  db('ai_conversations as c')
    .where('c.user_id', userId)
    .select('c.id', 'c.title', 'c.updated_at', 'c.created_at')
    .select(db.raw(`(select m.content from ai_messages m where m.conversation_id = c.id order by m.created_at desc, m.id desc limit 1) as last_message`))
    .orderBy('c.updated_at', 'desc')
    .limit(100);

const deleteConversation = (userId, id) => db('ai_conversations').where({ id, user_id: userId }).del();

const conversationMessages = (conversationId) =>
  db('ai_messages').where({ conversation_id: conversationId }).orderBy([{ column: 'created_at' }, { column: 'id' }]);

const insertMessages = (rows) => db('ai_messages').insert(rows).returning('*');

const findMessageForUser = (userId, messageId) =>
  db('ai_messages as m').join('ai_conversations as c', 'c.id', 'm.conversation_id')
    .where({ 'm.id': messageId, 'c.user_id': userId }).first('m.id', 'm.role');

const upsertFeedback = (messageId, userId, rating) =>
  db('ai_feedback').insert({ message_id: messageId, user_id: userId, rating })
    .onConflict(['message_id', 'user_id']).merge(['rating', 'created_at']);

const aiStats = async () => {
  const [conv, msg, fb] = await Promise.all([
    db('ai_conversations').count('* as n').first(),
    db('ai_messages').count('* as n').first(),
    db('ai_feedback').select(db.raw('count(*)::int as total, count(*) filter (where rating > 0)::int as positive')).first(),
  ]);
  return {
    conversations: Number(conv.n),
    messages: Number(msg.n),
    feedbackCount: fb.total,
    positiveFeedbackRate: fb.total ? +(fb.positive / fb.total).toFixed(3) : null,
  };
};

module.exports = {
  db,
  catalogSignature, loadCatalogRows, loadTaxonomy, loadBrandNames, loadEmbeddings, upsertEmbeddings, countEmbeddings,
  loadImageEmbeddings, upsertImageEmbeddings,
  productsWithImages, ratingBreakdowns, reviewStamp, reviewsFor, productExists,
  userSignals, profileExtras, basketRows, latestOrder, cartSnapshot, couponByCode, activeCoupons, recordSearch,
  createConversation, findConversation, updateConversation, listConversations, deleteConversation,
  conversationMessages, insertMessages, findMessageForUser, upsertFeedback, aiStats,
};
