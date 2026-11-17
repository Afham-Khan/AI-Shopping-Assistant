const router = require('express').Router();
const controller = require('./controllers/users.controller');
const schema = require('./middlewares/users.validator');
const { validate } = require('../../middlewares/validate');
const { requireAuth } = require('../../middlewares/auth');

router.use(requireAuth);
router.patch('/me', validate(schema.updateProfile), controller.updateProfile);
router.put('/me/preferences', validate(schema.preferences), controller.updatePreferences);
router.post('/me/change-password', validate(schema.changePassword), controller.changePassword);
router.get('/me/stats', controller.stats);

module.exports = router;
