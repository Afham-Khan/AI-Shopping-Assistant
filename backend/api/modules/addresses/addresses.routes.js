const router = require('express').Router();
const controller = require('./controllers/addresses.controller');
const schema = require('./middlewares/addresses.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.get('/', controller.list);
router.post('/', validate(schema.create), controller.create);
router.patch('/:id', validate(schema.update), controller.update);
router.delete('/:id', validate(schema.id), controller.remove);
router.post('/:id/default', validate(schema.id), controller.makeDefault);

module.exports = router;
