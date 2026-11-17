const router = require('express').Router();
const controller = require('./controllers/products.controller');
const schema = require('./middlewares/products.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth, optionalAuth } = require('../../middlewares/auth');

router.get('/', optionalAuth, validate(schema.list), controller.list);
// must stay above /:idOrSlug or "recently-viewed" would be treated as a slug
router.get('/recently-viewed', requireAuth, controller.recentlyViewed);
router.get('/:id/reviews', validate(schema.reviews), controller.reviews);
router.post('/:id/reviews', requireAuth, validate(schema.createReview), controller.createReview);
router.get('/:idOrSlug', optionalAuth, validate(schema.detail), controller.detail);

module.exports = router;
