const db = require('../../../db/connection');
const { productCardQuery } = require('../../../../helpers/productQuery');

const departments = () =>
  db('departments').select('id', 'name', 'slug', 'icon', 'image_url', 'description').orderBy(['sort_order', 'id']);

const categoriesWithCounts = () =>
  db('categories as c')
    .leftJoin('products as p', 'p.category_id', 'c.id')
    .groupBy('c.id')
    .select('c.id', 'c.department_id', 'c.name', 'c.slug', 'c.image_url', db.raw('count(p.id)::int as product_count'))
    .orderBy(['c.sort_order', 'c.name']);

const categoryBySlug = (slug) =>
  db('categories as c')
    .join('departments as d', 'd.id', 'c.department_id')
    .where('c.slug', slug)
    .select('c.id', 'c.name', 'c.slug', 'c.description', 'c.image_url', 'd.id as department_id', 'd.name as department_name', 'd.slug as department_slug')
    .first();

const categoryBrands = (categoryId) =>
  db('products as p')
    .join('brands as b', 'b.id', 'p.brand_id')
    .where('p.category_id', categoryId)
    .groupBy('b.name')
    .select('b.name')
    .count('* as count')
    .orderBy([{ column: 'count', order: 'desc' }, { column: 'b.name', order: 'asc' }]);

const categoryPriceRange = (categoryId) =>
  db('products').where({ category_id: categoryId }).min('price as min').max('price as max').first();

const banners = () =>
  db('banners').where({ is_active: true }).orderBy(['sort_order', 'id'])
    .select('id', 'title', 'subtitle', 'image_url', 'cta_label', 'target', 'theme');

const HOME_LIMIT = 10;

const flashDeals = () =>
  productCardQuery().where('p.stock', '>', 0).where('p.discount_percent', '>=', 10)
    .orderBy([{ column: 'p.discount_percent', order: 'desc' }, { column: 'p.id', order: 'asc' }]).limit(HOME_LIMIT);

const trending = (interests = []) => {
  const qb = productCardQuery().where('p.stock', '>', 0);
  if (interests.length) qb.orderByRaw('(c.slug = ANY(?)) DESC', [interests]);
  return qb.orderByRaw('(p.sold_count * 3 + p.view_count) DESC').orderBy('p.id').limit(HOME_LIMIT);
};

const topRated = () =>
  productCardQuery().where('p.rating_count', '>=', 3)
    .orderBy([{ column: 'p.rating', order: 'desc' }, { column: 'p.rating_count', order: 'desc' }, { column: 'p.id', order: 'asc' }]).limit(HOME_LIMIT);

const newArrivals = () =>
  productCardQuery().orderBy([{ column: 'p.created_at', order: 'desc' }, { column: 'p.id', order: 'desc' }]).limit(HOME_LIMIT);

module.exports = {
  departments,
  categoriesWithCounts,
  categoryBySlug,
  categoryBrands,
  categoryPriceRange,
  banners,
  flashDeals,
  trending,
  topRated,
  newArrivals,
};
