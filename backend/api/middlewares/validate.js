const { checkSchema, validationResult } = require('express-validator');

// usage: router.post('/', validate({ email: { in: ['body'], isEmail: { errorMessage: '...' } } }), handler)
module.exports.validate = (schema) => {
  const chains = checkSchema(schema);
  return async (req, res, next) => {
    await Promise.all(chains.map((chain) => chain.run(req)));
    const result = validationResult(req);
    if (result.isEmpty()) return next();
    const errors = result.array({ onlyFirstError: true }).map((e) => ({ field: e.path, message: e.msg }));
    return res.status(400).json({ success: false, message: errors[0].message, errors });
  };
};
