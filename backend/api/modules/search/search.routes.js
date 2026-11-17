const router = require('express').Router();
const controller = require('./controllers/search.controller');
const schema = require('./middlewares/search.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth, optionalAuth } = require('../../middlewares/auth');

router.get('/suggestions', optionalAuth, validate(schema.suggestions), controller.suggestions);
router.get('/trending', controller.trending);
router.get('/history', requireAuth, controller.history);
router.post('/history', requireAuth, validate(schema.addHistory), controller.addHistory);
router.delete('/history', requireAuth, controller.clearHistory);

module.exports = router;
