const { idParam } = require('../../../../helpers/validators');

module.exports.add = {
  ...idParam('productId', 'body'),
  source: { in: ['body'], optional: true, isString: true, trim: true, isLength: { options: { max: 30 } } },
};
module.exports.remove = idParam('productId');
