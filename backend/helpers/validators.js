// reusable express-validator schema fragments
const MAX_INT = 2147483647;

const idParam = (name = 'id', location = 'params') => ({
  [name]: {
    in: [location],
    isInt: { options: { min: 1, max: MAX_INT }, errorMessage: `${name} must be a positive integer` },
    toInt: true,
  },
});

const pagination = {
  page: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 100000 }, errorMessage: 'page must be a positive integer' } },
  limit: { in: ['query'], optional: true, isInt: { options: { min: 1, max: 60 }, errorMessage: 'limit must be between 1 and 60' } },
};

const email = (location = 'body') => ({
  in: [location],
  trim: true,
  isEmail: { errorMessage: 'Enter a valid email address' },
  isLength: { options: { max: 190 }, errorMessage: 'Email is too long' },
  customSanitizer: { options: (v) => (typeof v === 'string' ? v.toLowerCase() : v) },
});

const password = (field = 'password') => ({
  in: ['body'],
  isString: { errorMessage: `${field} is required` },
  isLength: { options: { min: 8, max: 72 }, errorMessage: 'Password must be 8-72 characters' },
  matches: { options: /^(?=.*[A-Za-z])(?=.*\d)/, errorMessage: 'Password must contain a letter and a number' },
});

const phone = (optional = false) => ({
  in: ['body'],
  ...(optional && { optional: { options: { values: 'null' } } }),
  trim: true,
  matches: { options: /^\+?[0-9][0-9\s-]{6,19}$/, errorMessage: 'Enter a valid phone number' },
});

module.exports = { MAX_INT, idParam, pagination, email, password, phone };
