const { password, phone } = require('../../../../helpers/validators');

const money = (field) => ({
  in: ['body'],
  optional: { options: { values: 'null' } },
  isFloat: { options: { min: 0, max: 100000000 }, errorMessage: `${field} must be a positive amount` },
  toFloat: true,
});

module.exports.updateProfile = {
  name: {
    in: ['body'],
    optional: true,
    isString: { errorMessage: 'Name must be text' },
    trim: true,
    isLength: { options: { min: 2, max: 120 }, errorMessage: 'Name must be 2-120 characters' },
  },
  phone: phone(true),
};

module.exports.preferences = {
  interests: {
    in: ['body'],
    optional: true,
    isArray: { options: { max: 30 }, errorMessage: 'interests must be a list of up to 30 category slugs' },
  },
  'interests.*': {
    in: ['body'],
    isString: { errorMessage: 'Each interest must be a category slug' },
    trim: true,
    toLowerCase: true,
    matches: { options: /^[a-z0-9-]{2,80}$/, errorMessage: 'Each interest must be a category slug' },
  },
  budget: { in: ['body'], optional: true, isObject: { errorMessage: 'budget must be an object { min, max }' } },
  'budget.min': money('budget.min'),
  'budget.max': money('budget.max'),
  gender: {
    in: ['body'],
    optional: true,
    isIn: { options: [['men', 'women', 'any']], errorMessage: 'gender must be men, women or any' },
  },
};

module.exports.changePassword = {
  currentPassword: { in: ['body'], isString: { errorMessage: 'Current password is required' }, notEmpty: { errorMessage: 'Current password is required' } },
  newPassword: password('newPassword'),
};

module.exports.memory = {
  enabled: { in: ['body'], isBoolean: { options: { strict: true }, errorMessage: 'enabled must be true or false' } },
};
