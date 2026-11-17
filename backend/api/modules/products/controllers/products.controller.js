const Products = require('../models/products.models');
const Interactions = require('../../interactions/models/interactions.models');
const { ok, created, paginated, parsePagination } = require('../../../../helpers/response');
const { toCard, toDetail, toReview } = require('../../../../helpers/serializers');
const { notFound, conflict } = require('../../../../helpers/errors');

const list = (value) =>
  (value ? String(value).split(',').map((v) => v.trim().toLowerCase()).filter(Boolean).slice(0, 20) : []);

const num = (value) => (value === undefined || value === '' ? undefined : Number(value));

// req.query is re-parsed on every access in express 5, so sanitized values are rebuilt here
const parseFilters = (query) => ({
  q: query.q ? String(query.q).trim().slice(0, 100) || undefined : undefined,
  department: query.department ? String(query.department).toLowerCase() : undefined,
  categories: list(query.category),
  brands: list(query.brand),
  minPrice: num(query.minPrice),
  maxPrice: num(query.maxPrice),
  minRating: num(query.minRating),
  inStock: query.inStock === 'true',
  onSale: query.onSale === 'true',
  gender: query.gender || undefined,
  sort: query.sort || 'relevance',
});

module.exports.list = async (req, res) => {
  const { page, limit, offset } = parsePagination(req.query);
  const filters = parseFilters(req.query);
  const interests = await Products.userInterests(req.userId);
  const { rows, total, brands, priceRange, relaxed } = await Products.search(filters, { limit, offset, interests });
  return paginated(res, rows.map(toCard), { page, limit, total, facets: { brands, priceRange }, ...(relaxed && { relaxedSearch: true }) });
};

module.exports.detail = async (req, res) => {
  const row = await Products.findByIdOrSlug(req.params.idOrSlug);
  if (!row) throw notFound('Product not found');
  const [images, ratingBreakdown] = await Promise.all([Products.images(row.id), Products.ratingBreakdown(row.id)]);
  await Promise.all([
    Products.incrementViews(row.id),
    req.userId && Interactions.record({ userId: req.userId, productId: row.id, type: 'view', source: 'product_detail' }),
  ]);
  return ok(res, toDetail(row, { images, ratingBreakdown }));
};

module.exports.reviews = async (req, res) => {
  const productId = Number(req.params.id);
  if (!(await Products.exists(productId))) throw notFound('Product not found');
  const { page, limit, offset } = parsePagination(req.query, { defaultLimit: 10, maxLimit: 50 });
  const { rows, total, summary } = await Products.listReviews(productId, { sort: req.query.sort || 'recent', limit, offset });
  return paginated(res, rows.map(toReview), { page, limit, total, summary });
};

module.exports.createReview = async (req, res) => {
  const productId = Number(req.params.id);
  if (!(await Products.exists(productId))) throw notFound('Product not found');
  if (await Products.hasReviewed(productId, req.userId)) throw conflict('You have already reviewed this product');
  try {
    const review = await Products.createReview({
      product_id: productId,
      user_id: req.userId,
      rating: req.body.rating,
      title: req.body.title || null,
      comment: req.body.comment,
    });
    return created(res, toReview(review), { message: 'Thanks for your review!' });
  } catch (error) {
    if (error.code === '23505') throw conflict('You have already reviewed this product');
    throw error;
  }
};

module.exports.recentlyViewed = async (req, res) => ok(res, (await Products.recentlyViewed(req.userId)).map(toCard));

const rs = (n) => `Rs ${Math.round(n).toLocaleString('en-US')}`;

// GET /products/:id/price-history?days=90 — real recorded changes (admin / demo updates), no simulation
module.exports.priceHistory = async (req, res) => {
  const productId = Number(req.params.id);
  const days = Number(req.query.days) || 90;
  const product = await Products.findByIdOrSlug(String(productId));
  if (!product) throw notFound('Product not found');
  const rows = await Products.priceHistory(productId, days);
  const points = rows.map((r) => ({ price: r.price, compareAtPrice: r.compare_at_price, stock: r.stock, source: r.source, recordedAt: r.recorded_at }));
  const prices = [...points.map((p) => p.price), product.price];
  const lowest = Math.min(...prices);
  const highest = Math.max(...prices);
  const average = Math.round((prices.reduce((a, b) => a + b, 0) / prices.length) * 100) / 100;
  const changes = points.filter((p, i) => i > 0 && p.price !== points[i - 1].price).length;
  const previous = [...points].reverse().find((p) => p.price !== product.price);
  const trend = !previous ? 'flat' : product.price < previous.price ? 'down' : 'up';
  let insight;
  if (!changes) insight = points.length ? `No price changes in the last ${days} days. Watch it to get alerted on a drop.` : 'Tracking starts with the next price change.';
  else if (product.price <= lowest) insight = `Lowest price in the last ${days} days.`;
  else if (product.price < average) insight = `${rs(average - product.price)} below its ${days}-day average.`;
  else insight = `${rs(product.price - lowest)} above its ${days}-day low of ${rs(lowest)}.`;
  return ok(res, {
    productId,
    currency: 'PKR',
    days,
    current: { price: product.price, compareAtPrice: product.compare_at_price, inStock: product.stock > 0 },
    stats: { lowest, highest, average, changes },
    trend,
    insight,
    points,
  });
};
