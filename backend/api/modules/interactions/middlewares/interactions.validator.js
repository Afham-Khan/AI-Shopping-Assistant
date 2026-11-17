const { idParam } = require('../../../../helpers/validators');

module.exports.create = {
  ...idParam('productId', 'body'),
  type: {
    in: ['body'],
    isIn: { options: [['view', 'click', 'wishlist', 'cart', 'ai_click']], errorMessage: 'type must be one of view, click, wishlist, cart, ai_click' },
  },
  source: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isString: { errorMessage: 'source must be text' },
    trim: true,
    isLength: { options: { max: 30 }, errorMessage: 'source must be at most 30 characters' },
  },
};
