const Search = require('../models/search.models');
const { ok, created } = require('../../../../helpers/response');

const FALLBACK_TRENDING = [
  'iphone', 'gaming laptop', 'wireless earbuds', 'running shoes', 'perfume for women',
  'smart watch', 'skin care', 'handbags', 'sunglasses', 'kitchen essentials',
];

const normalize = (q) => String(q).trim().replace(/\s+/g, ' ').toLowerCase();

module.exports.suggestions = async (req, res) => {
  const q = normalize(req.query.q).slice(0, 100);
  const [products, categories, mine, popular] = await Promise.all([
    Search.suggestProducts(q),
    Search.suggestCategories(q),
    req.userId ? Search.userQueries(req.userId, q) : [],
    Search.popularQueries(q),
  ]);
  const queries = [...new Set([...mine, ...popular].map((r) => r.query))].slice(0, 6);
  return ok(res, {
    products: products.map((p) => ({ id: p.id, title: p.title, thumbnail: p.thumbnail_url, price: p.price })),
    categories,
    queries,
  });
};

module.exports.trending = async (req, res) => {
  const rows = (await Search.trending()).map((r) => r.query);
  const merged = [...new Set([...rows, ...FALLBACK_TRENDING])].slice(0, 10);
  return ok(res, merged);
};

module.exports.history = async (req, res) =>
  ok(res, (await Search.history(req.userId)).map((r) => ({ query: r.query, createdAt: r.created_at })));

module.exports.addHistory = async (req, res) => {
  await Search.addHistory(req.userId, normalize(req.body.query), req.body.resultsCount ?? 0);
  return created(res, null);
};

module.exports.clearHistory = async (req, res) => {
  await Search.clearHistory(req.userId);
  return ok(res, null, { message: 'Search history cleared' });
};
