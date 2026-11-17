const db = require('../../../db/connection');
const { escapeLike } = require('../../products/models/products.models');

// "gam lap" -> 'gam:*AB & lap:*AB': prefix match on title/keywords only (descriptions are too noisy)
const prefixTsQuery = (q) => {
  const words = q.toLowerCase().match(/[a-z0-9]+/g) || [];
  return words.slice(0, 6).map((w) => `${w}:*AB`).join(' & ');
};

const suggestProducts = (q, limit = 6) => {
  const like = `%${escapeLike(q)}%`;
  const tsq = prefixTsQuery(q);
  return db('products as p')
    .leftJoin('brands as b', 'b.id', 'p.brand_id')
    .where((w) => {
      w.where('p.title', 'ilike', like).orWhere('b.name', 'ilike', like);
      if (tsq) w.orWhereRaw("p.search_vector @@ to_tsquery('english', ?)", [tsq]);
    })
    .select('p.id', 'p.title', 'p.thumbnail_url', 'p.price')
    .orderByRaw('(p.title ILIKE ?) DESC', [`${escapeLike(q)}%`])
    .orderBy([{ column: 'p.sold_count', order: 'desc' }, { column: 'p.id', order: 'asc' }])
    .limit(limit);
};

const suggestCategories = (q, limit = 4) => {
  const like = `%${escapeLike(q)}%`;
  return db('categories').where('name', 'ilike', like).orWhere('slug', 'ilike', like)
    .select('name', 'slug').orderBy('name').limit(limit);
};

const userQueries = (userId, q, limit = 3) =>
  db('search_history').where({ user_id: userId }).where('query', 'ilike', `${escapeLike(q)}%`)
    .groupBy('query').select('query').max('created_at as last').orderBy('last', 'desc').limit(limit);

const popularQueries = (q, limit = 5) =>
  db('search_history').where('query', 'ilike', `${escapeLike(q)}%`)
    .groupBy('query').select('query').count('* as n').orderBy([{ column: 'n', order: 'desc' }, { column: 'query', order: 'asc' }]).limit(limit);

const trending = (days = 30, limit = 10) =>
  db('search_history').where('created_at', '>', db.raw(`now() - interval '${Number(days)} days'`))
    .where('results_count', '>', 0)
    .groupBy('query').select('query').count('* as n')
    .orderBy([{ column: 'n', order: 'desc' }, { column: 'query', order: 'asc' }]).limit(limit);

const history = (userId, limit = 10) =>
  db('search_history').where({ user_id: userId }).groupBy('query')
    .select('query').max('created_at as created_at').orderBy('created_at', 'desc').limit(limit);

const addHistory = (userId, query, resultsCount) =>
  db('search_history').insert({ user_id: userId, query, results_count: resultsCount });

const clearHistory = (userId) => db('search_history').where({ user_id: userId }).del();

module.exports = { suggestProducts, suggestCategories, userQueries, popularQueries, trending, history, addHistory, clearHistory };
