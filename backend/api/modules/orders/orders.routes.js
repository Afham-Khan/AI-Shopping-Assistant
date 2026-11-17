const router = require('express').Router();
const controller = require('./controllers/orders.controller');
const schema = require('./middlewares/orders.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.post('/', validate(schema.create), controller.create);
router.get('/', validate(schema.list), controller.list);
router.get('/:id', validate(schema.id), controller.detail);
router.post('/:id/cancel', validate(schema.id), controller.cancel);

module.exports = router;
