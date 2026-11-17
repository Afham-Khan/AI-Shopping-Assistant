const router = require('express').Router();
const controller = require('./controllers/discover.controller');
const schema = require('./middlewares/discover.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth, optionalAuth } = require('../../middlewares/auth');

router.get('/deck', optionalAuth, validate(schema.deck), controller.deck);
router.post('/swipe', requireAuth, validate(schema.swipe), controller.swipe);
router.get('/taste', requireAuth, controller.taste);
router.get('/reels', optionalAuth, validate(schema.reels), controller.reels);

module.exports = router;
