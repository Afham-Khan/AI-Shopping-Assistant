const router = require('express').Router();
const controller = require('./controllers/catalog.controller');
const schema = require('./middlewares/catalog.validator');
const { validate } = require('../../middlewares/validate');
const { optionalAuth } = require('../../middlewares/auth');

router.get('/departments', controller.departments);
router.get('/categories/:slug', validate(schema.category), controller.category);
router.get('/home', optionalAuth, controller.home);
router.get('/room', optionalAuth, controller.room);

module.exports = router;
