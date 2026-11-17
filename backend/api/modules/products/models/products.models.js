const db = require('../../../db/connection');
const { productBaseQuery, productCardQuery } = require('../../../../helpers/productQuery');
const { MAX_INT } = require('../../../../helpers/validators');

const escapeLike = (value) => value.replace(/[\\%_]/g, (c) => `\\${c}`);

const queryWords = (q) => (q.toLowerCase().match(/[a-z0-9]+/g) || []).filter((w) => w.length > 1).slice(0, 8);

// strict = every word must match (websearch syntax); relaxed = any word, used when strict finds nothing
const tsQuery = (f) => (f.relaxed
  ? ["to_tsquery('english', ?)", queryWords(f.q).join(' | ')]
  : ["websearch_to_tsquery('english', ?)", f.q]);

// skip lets facet queries ignore their own filter (brand facet shouldn't shrink when a brand is picked)
const applyFilters = (qb, f, { skip = [] } = {}) => {
  if (f.q) {
    const like = `%${escapeLike(f.q)}%`;
    const [tsSql, tsArg] = tsQuery(f);
    qb.where((w) =>
      w.whereRaw(`p.search_vector @@ ${tsSql}`, [tsArg])
        .orWhere('p.title', 'ilike', like)
        .orWhere('p.search_keywords', 'ilike', like)
        .orWhere('b.name', 'ilike', like));
  }
  if (f.department) qb.where('d.slug', f.department);
  if (f.categories?.length) qb.whereIn('c.slug', f.categories);
  if (f.brands?.length && !skip.includes('brand')) {
    qb.where((w) => w.whereIn(db.raw('lower(b.name)'), f.brands).orWhereIn('b.slug', f.brands));
  }
  if (!skip.includes('price')) {
    if (f.minPrice !== undefined) qb.where('p.price', '>=', f.minPrice);
    if (f.maxPrice !== undefined) qb.where('p.price', '<=', f.maxPrice);
  }
  if (f.minRating !== undefined) qb.where('p.rating', '>=', f.minRating);
  if (f.inStock) qb.where('p.stock', '>', 0);
  if (f.onSale) qb.whereNotNull('p.compare_at_price').where('p.discount_percent', '>', 0);
  if (f.gender) qb.whereIn('p.gender', [f.gender, 'unisex']);
  return qb;
};

const applySort = (qb, f, interests = []) => {
  switch (f.sort) {
    case 'price_asc': qb.orderBy('p.price', 'asc'); break;
    case 'price_desc': qb.orderBy('p.price', 'desc'); break;
    case 'rating': qb.orderBy([{ column: 'p.rating', order: 'desc' }, { column: 'p.rating_count', order: 'desc' }]); break;
    case 'newest': qb.orderBy('p.created_at', 'desc'); break;
    case 'popular': qb.orderBy([{ column: 'p.sold_count', order: 'desc' }, { column: 'p.view_count', order: 'desc' }]); break;
    case 'discount': qb.orderBy('p.discount_percent', 'desc'); break;
    default:
      if (f.q) {
        const [tsSql, tsArg] = tsQuery(f);
        qb.orderByRaw(`(p.title ILIKE ?) DESC, ts_rank_cd(p.search_vector, ${tsSql}) DESC`, [`${escapeLike(f.q)}%`, tsArg]);
      } else if (interests.length) {
        qb.orderByRaw('(c.slug = ANY(?)) DESC', [interests]);
      }
      qb.orderBy([{ column: 'p.is_featured', order: 'desc' }, { column: 'p.sold_count', order: 'desc' }, { column: 'p.rating', order: 'desc' }]);
  }
  return qb.orderBy('p.id', 'asc');
};

const filteredBase = () =>
  db('products as p')
    .leftJoin('brands as b', 'b.id', 'p.brand_id')
    .join('categories as c', 'c.id', 'p.category_id')
    .join('departments as d', 'd.id', 'c.department_id');

const runSearch = async (filters, { limit, offset, interests }) => {
  const rowsQuery = applySort(applyFilters(productCardQuery(), filters), filters, interests).limit(limit).offset(offset);
  const totalQuery = applyFilters(filteredBase(), filters).count('* as total').first();
  const brandsQuery = applyFilters(filteredBase(), filters, { skip: ['brand'] })
    .whereNotNull('b.name')
    .groupBy('b.name')
    .select('b.name')
    .count('* as count')
    .orderBy([{ column: 'count', order: 'desc' }, { column: 'b.name', order: 'asc' }])
    .limit(30);
  const priceQuery = applyFilters(filteredBase(), filters, { skip: ['price'] })
    .min('p.price as min').max('p.price as max').first();

  const [rows, { total }, brands, price] = await Promise.all([rowsQuery, totalQuery, brandsQuery, priceQuery]);
  return { rows, total, brands, priceRange: { min: price.min ?? 0, max: price.max ?? 0 } };
};

const search = async (filters, options) => {
  const strict = await runSearch(filters, options);
  if (strict.total > 0 || !filters.q || queryWords(filters.q).length < 2) return strict;
  return { ...(await runSearch({ ...filters, relaxed: true }, options)), relaxed: true };
};

const findByIdOrSlug = async (idOrSlug) => {
  const qb = productBaseQuery();
  if (!/^\d+$/.test(idOrSlug)) return qb.where('p.slug', idOrSlug.toLowerCase()).first();
  const id = Number(idOrSlug);
  return id >= 1 && id <= MAX_INT ? qb.where('p.id', id).first() : undefined;
};

const exists = async (id) => Boolean(await db('products').where({ id }).first('id'));

const images = async (productId) =>
  (await db('product_images').where({ product_id: productId }).orderBy(['sort_order', 'id']).select('url')).map((r) => r.url);

const ratingBreakdown = async (productId, trx = db) => {
  const rows = await trx('reviews').where({ product_id: productId }).groupBy('rating').select('rating').count('* as n');
  const breakdown = { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 };
  rows.forEach((r) => { breakdown[r.rating] = r.n; });
  return breakdown;
};

const incrementViews = (id) => db('products').where({ id }).increment('view_count', 1);

const REVIEW_SORTS = {
  recent: [{ column: 'r.created_at', order: 'desc' }],
  helpful: [{ column: 'r.helpful_count', order: 'desc' }, { column: 'r.created_at', order: 'desc' }],
  rating_high: [{ column: 'r.rating', order: 'desc' }, { column: 'r.created_at', order: 'desc' }],
  rating_low: [{ column: 'r.rating', order: 'asc' }, { column: 'r.created_at', order: 'desc' }],
};

const reviewSelect = (trx = db) =>
  trx('reviews as r').join('users as u', 'u.id', 'r.user_id').select('r.*', 'u.name as user_name');

const listReviews = async (productId, { sort = 'recent', limit, offset }) => {
  const [rows, summary, breakdown] = await Promise.all([
    reviewSelect().where('r.product_id', productId).orderBy([...REVIEW_SORTS[sort], { column: 'r.id', order: 'desc' }]).limit(limit).offset(offset),
    db('reviews').where({ product_id: productId }).avg('rating as average').count('* as count').first(),
    ratingBreakdown(productId),
  ]);
  return {
    rows,
    total: summary.count,
    summary: { average: summary.average ? Math.round(summary.average * 100) / 100 : 0, count: summary.count, breakdown },
  };
};

const hasReviewed = async (productId, userId) => Boolean(await db('reviews').where({ product_id: productId, user_id: userId }).first('id'));

const hasDeliveredPurchase = async (productId, userId, trx = db) =>
  Boolean(await trx('order_items as oi')
    .join('orders as o', 'o.id', 'oi.order_id')
    .where({ 'o.user_id': userId, 'oi.product_id': productId, 'o.status': 'delivered' })
    .first('oi.id'));

const recomputeRating = (productId, trx = db) =>
  trx.raw(`
    UPDATE products SET
      rating = COALESCE((SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews WHERE product_id = :id), 0),
      rating_count = (SELECT COUNT(*) FROM reviews WHERE product_id = :id),
      updated_at = now()
    WHERE id = :id`, { id: productId });

const createReview = (row) =>
  db.transaction(async (trx) => {
    const isVerified = await hasDeliveredPurchase(row.product_id, row.user_id, trx);
    const [{ id }] = await trx('reviews').insert({ ...row, is_verified: isVerified }).returning('id');
    await recomputeRating(row.product_id, trx);
    return reviewSelect(trx).where('r.id', id).first();
  });

const recentlyViewed = async (userId, limit = 20) => {
  const recent = await db('user_interactions')
    .where({ user_id: userId, type: 'view' })
    .groupBy('product_id')
    .select('product_id')
    .max('created_at as last_viewed')
    .orderBy('last_viewed', 'desc')
    .limit(limit);
  return cardsByIds(recent.map((r) => r.product_id));
};

// keeps the caller's id order (recency, cart order...)
const cardsByIds = async (ids, trx = db) => {
  if (!ids.length) return [];
  const rows = await productCardQuery(trx).whereIn('p.id', ids);
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id)).filter(Boolean);
};

const userInterests = async (userId) => {
  if (!userId) return [];
  const user = await db('users').where({ id: userId }).first('preferences');
  return user?.preferences?.interests || [];
};

module.exports = {
  escapeLike,
  applyFilters,
  search,
  findByIdOrSlug,
  exists,
  images,
  ratingBreakdown,
  incrementViews,
  listReviews,
  hasReviewed,
  createReview,
  recomputeRating,
  recentlyViewed,
  cardsByIds,
  userInterests,
};
