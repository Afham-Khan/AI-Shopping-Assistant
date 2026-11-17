const router = require('express').Router();
const controller = require('./controllers/ai.controller');
const v = require('./middlewares/ai.validator');
const { requireAuth, optionalAuth } = require('../../middlewares/auth');
const { warmup } = require('./engine');

router.post('/chat', requireAuth, v.chat, controller.chat);
router.get('/conversations', requireAuth, controller.listConversations);
router.get('/conversations/:id', requireAuth, v.conversationId, controller.getConversation);
router.delete('/conversations/:id', requireAuth, v.conversationId, controller.deleteConversation);
router.post('/messages/:id/feedback', requireAuth, v.feedback, controller.feedback);

router.get('/recommendations', optionalAuth, v.recommendations, controller.recommendations);
router.get('/similar/:productId', v.similar, controller.similar);
router.get('/bought-together/:productId', v.boughtTogether, controller.boughtTogether);
router.post('/compare', optionalAuth, v.compare, controller.compare);
router.get('/review-summary/:productId', v.reviewSummary, controller.reviewSummary);
router.get('/search', optionalAuth, v.search, controller.search);

router.post('/nlu', v.nlu, controller.nlu);
router.get('/finder', controller.finderFlows);
router.post('/finder', optionalAuth, v.finder, controller.finder);
router.get('/insights', controller.insights);

router.get('/bundle/templates', controller.bundleTemplates);
router.post('/bundle', optionalAuth, v.bundle, controller.bundle);
router.post('/products/:id/ask', optionalAuth, v.ask, controller.askProduct);
router.get('/cart-insights', requireAuth, controller.cartInsights);
router.get('/profile', requireAuth, controller.profile);
router.post('/visual-search', optionalAuth, v.imageUpload, v.visual, controller.visualSearch);
router.get('/visual-search/text', v.visualText, controller.visualTextSearch);

router.get('/complete-look/:productId', v.completeLook, controller.completeLook);
router.get('/explain/:productId', v.explain, controller.explain);
router.post('/gift', optionalAuth, v.gift, controller.gift);

// build indexes after boot without delaying startup
if (process.env.NODE_ENV !== 'test') setTimeout(() => warmup(), 1500).unref();

module.exports = router;
