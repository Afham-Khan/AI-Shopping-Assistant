const rateLimit = require('express-rate-limit');
const { email, password } = require('../../../../helpers/validators');

const requiredString = (field, max = 500) => ({
  in: ['body'],
  isString: { errorMessage: `${field} is required` },
  trim: true,
  notEmpty: { errorMessage: `${field} is required` },
  isLength: { options: { max }, errorMessage: `${field} is too long` },
});

// tests hammer these endpoints from one ip, so the ceiling is lifted there
const limiter = (limit, windowMinutes, message, options = {}) =>
  rateLimit({
    windowMs: windowMinutes * 60 * 1000,
    limit: process.env.NODE_ENV === 'test' ? 10000 : limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    ...options,
    handler: (req, res) => res.status(429).json({ success: false, message, code: 'RATE_LIMITED' }),
  });

// only failed sign-ins count, so a busy demo device isn't locked out
module.exports.loginLimiter = limiter(10, 15, 'Too many sign-in attempts. Try again in a few minutes', { skipSuccessfulRequests: true });
module.exports.registerLimiter = limiter(20, 60, 'Too many accounts created. Try again later');
module.exports.otpLimiter = limiter(5, 15, 'Too many code requests. Try again in a few minutes');
module.exports.verifyLimiter = limiter(10, 15, 'Too many attempts. Try again in a few minutes');

module.exports.register = {
  name: { ...requiredString('Name', 120), isLength: { options: { min: 2, max: 120 }, errorMessage: 'Name must be 2-120 characters' } },
  email: email(),
  password: password(),
};

module.exports.login = {
  email: email(),
  password: { in: ['body'], isString: { errorMessage: 'Password is required' }, notEmpty: { errorMessage: 'Password is required' }, isLength: { options: { max: 200 } } },
};

module.exports.refreshToken = { refreshToken: requiredString('refreshToken', 200) };

module.exports.forgotPassword = { email: email() };

module.exports.verifyOtp = {
  email: email(),
  otp: { in: ['body'], isString: { errorMessage: 'Code is required' }, trim: true, matches: { options: /^\d{6}$/, errorMessage: 'Code must be 6 digits' } },
};

module.exports.resetPassword = {
  resetToken: requiredString('resetToken', 1000),
  password: password(),
};
