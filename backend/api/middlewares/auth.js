const jwt = require('jsonwebtoken');
const { unauthorized } = require('../../helpers/errors');

const readToken = (req) => {
  const header = req.headers.authorization || '';
  return header.startsWith('Bearer ') ? header.slice(7) : null;
};

const verify = (token) => jwt.verify(token, process.env.JWT_ACCESS_SECRET);

// sets req.userId or rejects with 401; the app refreshes its token on code TOKEN_EXPIRED
module.exports.requireAuth = (req, res, next) => {
  const token = readToken(req);
  if (!token) return next(unauthorized());
  try {
    req.userId = Number(verify(token).sub);
    return next();
  } catch (error) {
    const expired = error.name === 'TokenExpiredError';
    const err = unauthorized(expired ? 'Session expired' : 'Invalid token');
    err.code = expired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN';
    return next(err);
  }
};

// guests pass through; a valid token still personalizes the response
module.exports.optionalAuth = (req, res, next) => {
  const token = readToken(req);
  if (token) {
    try {
      req.userId = Number(verify(token).sub);
    } catch {
      req.userId = undefined;
    }
  }
  next();
};
