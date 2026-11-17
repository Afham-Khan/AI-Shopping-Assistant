const router = require('express').Router();
const controller = require('./controllers/alerts.controller');
const schema = require('./middlewares/alerts.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.get('/price-watch', controller.list);
router.post('/price-watch', validate(schema.upsert), controller.upsert);
router.delete('/price-watch/:productId', validate(schema.remove), controller.remove);

module.exports = router;
