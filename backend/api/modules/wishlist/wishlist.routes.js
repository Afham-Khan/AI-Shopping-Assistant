const router = require('express').Router();
const controller = require('./controllers/wishlist.controller');
const schema = require('./middlewares/wishlist.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.get('/', controller.list);
router.get('/ids', controller.ids);
router.post('/', validate(schema.add), controller.add);
router.delete('/:productId', validate(schema.remove), controller.remove);

module.exports = router;
