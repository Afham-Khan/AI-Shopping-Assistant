const { idParam, pagination } = require('../../../../helpers/validators');

module.exports.create = {
  ...idParam('addressId', 'body'),
  paymentMethod: { in: ['body'], isIn: { options: [['cod', 'card']], errorMessage: 'paymentMethod must be cod or card' } },
  card: {
    in: ['body'],
    custom: {
      options: (value, { req }) => req.body.paymentMethod !== 'card' || (value && typeof value === 'object'),
      errorMessage: 'card details are required for card payments',
    },
  },
  'card.last4': {
    in: ['body'],
    custom: {
      options: (value, { req }) => req.body.paymentMethod !== 'card' || (typeof value === 'string' && /^\d{4}$/.test(value)),
      errorMessage: 'card.last4 must be 4 digits',
    },
  },
  notes: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isString: { errorMessage: 'notes must be text' },
    trim: true,
    isLength: { options: { max: 500 }, errorMessage: 'notes must be at most 500 characters' },
  },
};

module.exports.list = {
  ...pagination,
  limit: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 50 }, errorMessage: 'limit must be between 1 and 50' } },
  status: {
    in: ['query'],
    optional: { options: { values: 'falsy' } },
    isIn: { options: [['active', 'delivered', 'cancelled']], errorMessage: 'status must be active, delivered or cancelled' },
  },
};

module.exports.id = idParam();
