const jwt = require('jsonwebtoken');
const { unauthorized, forbidden } = require('../../helpers/errors');

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

// role check reads the db (not the token claim) so a demoted admin loses access immediately
module.exports.requireRole = (role) => [
  module.exports.requireAuth,
  async (req, res, next) => {
    try {
      // lazy require keeps this middleware usable without a db connection in unit tests
      const db = require('../db/connection');
      const user = await db('users').where({ id: req.userId }).first('role');
      if (!user) return next(unauthorized('Account no longer exists'));
      return user.role === role ? next() : next(forbidden('Admins only'));
    } catch (error) {
      return next(error);
    }
  },
];
