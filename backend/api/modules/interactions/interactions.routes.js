const router = require('express').Router();
const controller = require('./controllers/interactions.controller');
const schema = require('./middlewares/interactions.validator');
const { validate } = require('../../middlewares/validate');
const { optionalAuth } = require('../../middlewares/auth');

router.post('/', optionalAuth, validate(schema.create), controller.create);

module.exports = router;
