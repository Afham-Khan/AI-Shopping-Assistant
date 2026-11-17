const router = require('express').Router();
const controller = require('./controllers/notifications.controller');
const schema = require('./middlewares/notifications.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.get('/', validate(schema.list), controller.list);
router.get('/unread-count', controller.unreadCount);
router.post('/read-all', controller.markAllRead);
router.post('/:id/read', validate(schema.id), controller.markRead);

module.exports = router;
