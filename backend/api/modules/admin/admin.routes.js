const router = require('express').Router();
const controller = require('./controllers/admin.controller');
const schema = require('./middlewares/admin.validator');
const { validate } = require('../../middlewares/validate');
const { requireRole } = require('../../middlewares/auth');

router.use(requireRole('admin'));
router.patch('/products/:id', validate(schema.updateProduct), controller.updateProduct);

module.exports = router;
