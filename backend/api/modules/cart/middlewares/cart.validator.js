const { idParam } = require('../../../../helpers/validators');
const { MAX_CART_QTY } = require('../../../../helpers/constants');

module.exports.addItem = {
  ...idParam('productId', 'body'),
  quantity: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isInt: { options: { min: 1, max: MAX_CART_QTY }, errorMessage: `quantity must be between 1 and ${MAX_CART_QTY}` },
    toInt: true,
  },
  source: { in: ['body'], optional: true, isString: true, trim: true, isLength: { options: { max: 30 } } },
};

module.exports.updateItem = {
  ...idParam('productId'),
  quantity: {
    in: ['body'],
    isInt: { options: { min: 0, max: MAX_CART_QTY }, errorMessage: `quantity must be between 0 and ${MAX_CART_QTY}` },
    toInt: true,
  },
};

module.exports.productId = idParam('productId');

module.exports.coupon = {
  code: {
    in: ['body'],
    isString: { errorMessage: 'Coupon code is required' },
    trim: true,
    toUpperCase: true,
    matches: { options: /^[A-Z0-9_-]{2,40}$/, errorMessage: 'Enter a valid coupon code' },
  },
};
