const db = require('../api/db/connection');

// base select used anywhere products are listed so every caller gets the same card fields
module.exports.productBaseQuery = (trx = db) =>
  trx('products as p')
    .leftJoin('brands as b', 'b.id', 'p.brand_id')
    .join('categories as c', 'c.id', 'p.category_id')
    .join('departments as d', 'd.id', 'c.department_id')
    .select(
      'p.*',
      'b.name as brand_name',
      'c.name as category_name',
      'c.slug as category_slug',
      'd.id as department_id',
      'd.name as department_name',
      'd.slug as department_slug',
    );

const CARD_COLUMNS = [
  'p.id', 'p.title', 'p.slug', 'p.category_id', 'p.price', 'p.compare_at_price', 'p.discount_percent',
  'p.rating', 'p.rating_count', 'p.stock', 'p.thumbnail_url', 'p.tags',
];

// lean variant of productBaseQuery with only the columns toCard needs (lists, cart, wishlist)
module.exports.productCardQuery = (trx = db) =>
  trx('products as p')
    .leftJoin('brands as b', 'b.id', 'p.brand_id')
    .join('categories as c', 'c.id', 'p.category_id')
    .join('departments as d', 'd.id', 'c.department_id')
    .select(...CARD_COLUMNS, 'b.name as brand_name', 'c.name as category_name', 'c.slug as category_slug');

module.exports.CARD_COLUMNS = CARD_COLUMNS;
