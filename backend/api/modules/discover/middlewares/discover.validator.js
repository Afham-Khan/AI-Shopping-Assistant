const { idParam } = require('../../../../helpers/validators');

module.exports.deck = {
  limit: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 40 }, errorMessage: 'limit must be between 1 and 40' } },
};

module.exports.swipe = {
  ...idParam('productId', 'body'),
  action: { in: ['body'], isIn: { options: [['like', 'pass', 'bag']], errorMessage: 'action must be like, pass or bag' } },
};

module.exports.reels = {
  perDepartment: { in: ['query'], optional: true, isInt: { options: { min: 5, max: 8 }, errorMessage: 'perDepartment must be between 5 and 8' } },
};
