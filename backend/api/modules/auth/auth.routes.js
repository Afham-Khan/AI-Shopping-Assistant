const router = require('express').Router();
const controller = require('./controllers/auth.controller');
const schema = require('./middlewares/auth.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.post('/register', schema.registerLimiter, validate(schema.register), controller.register);
router.post('/login', schema.loginLimiter, validate(schema.login), controller.login);
router.post('/demo', schema.loginLimiter, controller.demo);
router.post('/refresh', validate(schema.refreshToken), controller.refresh);
router.post('/logout', validate(schema.refreshToken), controller.logout);
router.post('/forgot-password', schema.otpLimiter, validate(schema.forgotPassword), controller.forgotPassword);
router.post('/verify-otp', schema.verifyLimiter, validate(schema.verifyOtp), controller.verifyOtp);
router.post('/reset-password', validate(schema.resetPassword), controller.resetPassword);
router.get('/me', requireAuth, controller.me);

module.exports = router;
