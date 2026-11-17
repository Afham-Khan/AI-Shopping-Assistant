const { idParam, pagination } = require('../../../../helpers/validators');

const optionalQuery = (rules) => ({ in: ['query'], optional: { options: { values: 'falsy' } }, ...rules });
const slugList = (field) => optionalQuery({
  isString: { errorMessage: `${field} must be text` },
  isLength: { options: { max: 500 }, errorMessage: `${field} is too long` },
});

module.exports.list = {
  ...pagination,
  q: optionalQuery({ isString: { errorMessage: 'q must be text' }, isLength: { options: { max: 100 }, errorMessage: 'q must be at most 100 characters' } }),
  department: slugList('department'),
  category: slugList('category'),
  brand: slugList('brand'),
  minPrice: optionalQuery({ isFloat: { options: { min: 0 }, errorMessage: 'minPrice must be a positive number' } }),
  maxPrice: optionalQuery({
    isFloat: { options: { min: 0 }, errorMessage: 'maxPrice must be a positive number' },
    custom: {
      options: (value, { req }) => !req.query.minPrice || Number(value) >= Number(req.query.minPrice),
      errorMessage: 'maxPrice must be greater than minPrice',
    },
  }),
  minRating: optionalQuery({ isFloat: { options: { min: 0, max: 5 }, errorMessage: 'minRating must be between 0 and 5' } }),
  inStock: optionalQuery({ isIn: { options: [['true', 'false']], errorMessage: 'inStock must be true or false' } }),
  onSale: optionalQuery({ isIn: { options: [['true', 'false']], errorMessage: 'onSale must be true or false' } }),
  gender: optionalQuery({ isIn: { options: [['men', 'women', 'unisex']], errorMessage: 'gender must be men, women or unisex' } }),
  sort: optionalQuery({
    isIn: { options: [['relevance', 'price_asc', 'price_desc', 'rating', 'newest', 'popular', 'discount']], errorMessage: 'Invalid sort option' },
  }),
};

module.exports.detail = {
  idOrSlug: {
    in: ['params'],
    matches: { options: /^([1-9]\d{0,9}|[A-Za-z0-9-]{1,220})$/, errorMessage: 'Invalid product id or slug' },
  },
};

module.exports.reviews = {
  ...idParam(),
  page: pagination.page,
  limit: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 50 }, errorMessage: 'limit must be between 1 and 50' } },
  sort: optionalQuery({ isIn: { options: [['recent', 'helpful', 'rating_high', 'rating_low']], errorMessage: 'Invalid sort option' } }),
};

module.exports.createReview = {
  ...idParam(),
  rating: { in: ['body'], isInt: { options: { min: 1, max: 5 }, errorMessage: 'rating must be an integer from 1 to 5' }, toInt: true },
  title: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isString: { errorMessage: 'title must be text' },
    trim: true,
    isLength: { options: { max: 150 }, errorMessage: 'title must be at most 150 characters' },
  },
  comment: {
    in: ['body'],
    isString: { errorMessage: 'comment is required' },
    trim: true,
    isLength: { options: { min: 10, max: 2000 }, errorMessage: 'comment must be 10-2000 characters' },
  },
};

module.exports.priceHistory = {
  ...idParam(),
  days: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 365 }, errorMessage: 'days must be between 1 and 365' } },
};
