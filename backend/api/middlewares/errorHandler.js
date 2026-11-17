module.exports.notFoundHandler = (req, res) =>
  res.status(404).json({ success: false, message: `Route ${req.method} ${req.originalUrl} not found` });

// eslint-disable-next-line no-unused-vars
module.exports.errorHandler = (err, req, res, next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ success: false, message: 'Malformed JSON body' });
  }
  const status = err.status || 500;
  if (status >= 500) console.error('[ERROR]', req.method, req.originalUrl, err);
  return res.status(status).json({
    success: false,
    message: status >= 500 ? 'Something went wrong. Please try again.' : err.message,
    ...(err.code && { code: err.code }),
    ...(err.errors && { errors: err.errors }),
  });
};
