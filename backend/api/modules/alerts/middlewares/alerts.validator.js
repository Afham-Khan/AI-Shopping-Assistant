const { idParam } = require('../../../../helpers/validators');

module.exports.upsert = {
  ...idParam('productId', 'body'),
  targetPrice: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isFloat: { options: { min: 1, max: 100000000 }, errorMessage: 'targetPrice must be a positive amount' },
    toFloat: true,
  },
  notifyRestock: {
    in: ['body'],
    optional: true,
    isBoolean: { options: { strict: true }, errorMessage: 'notifyRestock must be true or false' },
  },
};

module.exports.remove = idParam('productId');
