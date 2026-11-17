const { idParam } = require('../../../../helpers/validators');

const amount = (field, nullable = false) => ({
  in: ['body'],
  optional: nullable ? { options: { values: 'null' } } : true,
  isFloat: { options: { min: 1, max: 100000000 }, errorMessage: `${field} must be a positive amount` },
  toFloat: true,
});

module.exports.updateProduct = {
  ...idParam(),
  price: amount('price'),
  compareAtPrice: amount('compareAtPrice', true),
  stock: {
    in: ['body'],
    optional: true,
    isInt: { options: { min: 0, max: 1000000 }, errorMessage: 'stock must be a whole number ≥ 0' },
    toInt: true,
  },
};
