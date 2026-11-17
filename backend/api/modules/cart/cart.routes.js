const router = require('express').Router();
const controller = require('./controllers/cart.controller');
const schema = require('./middlewares/cart.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.get('/', controller.get);
router.delete('/', controller.clear);
router.post('/items', validate(schema.addItem), controller.addItem);
router.patch('/items/:productId', validate(schema.updateItem), controller.updateItem);
router.delete('/items/:productId', validate(schema.productId), controller.removeItem);
router.post('/coupon', validate(schema.coupon), controller.applyCoupon);
router.delete('/coupon', controller.removeCoupon);

module.exports = router;
