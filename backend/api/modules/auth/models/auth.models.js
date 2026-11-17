const db = require('../../../db/connection');

const saveRefreshToken = (userId, { tokenHash, expiresAt }, userAgent, trx = db) =>
  trx('refresh_tokens').insert({
    user_id: userId,
    token_hash: tokenHash,
    expires_at: expiresAt,
    user_agent: userAgent ? String(userAgent).slice(0, 250) : null,
  });

const findRefreshToken = (tokenHash, trx = db) =>
  trx('refresh_tokens').where({ token_hash: tokenHash }).first();

// returns 1 only for the request that actually revoked it, so concurrent refreshes can't both win
const revokeRefreshToken = (id, trx = db) =>
  trx('refresh_tokens').where({ id }).whereNull('revoked_at').update({ revoked_at: trx.fn.now() });

const revokeByHash = (tokenHash) =>
  db('refresh_tokens').where({ token_hash: tokenHash }).whereNull('revoked_at').update({ revoked_at: db.fn.now() });

const revokeAllForUser = (userId, trx = db) =>
  trx('refresh_tokens').where({ user_id: userId }).whereNull('revoked_at').update({ revoked_at: trx.fn.now() });

const createPasswordReset = async (userId, otpHash, expiresAt) =>
  db.transaction(async (trx) => {
    await trx('password_resets').where({ user_id: userId }).whereNull('used_at').update({ used_at: trx.fn.now() });
    await trx('password_resets').insert({ user_id: userId, otp_hash: otpHash, expires_at: expiresAt });
  });

const findActiveReset = (userId) =>
  db('password_resets')
    .where({ user_id: userId })
    .whereNull('used_at')
    .where('expires_at', '>', db.fn.now())
    .orderBy('id', 'desc')
    .first();

const incrementResetAttempts = (id) => db('password_resets').where({ id }).increment('attempts', 1);

const markResetUsed = (id) => db('password_resets').where({ id }).update({ used_at: db.fn.now() });

const markAllResetsUsed = (userId, trx = db) =>
  trx('password_resets').where({ user_id: userId }).whereNull('used_at').update({ used_at: trx.fn.now() });

module.exports = {
  saveRefreshToken,
  findRefreshToken,
  revokeRefreshToken,
  revokeByHash,
  revokeAllForUser,
  createPasswordReset,
  findActiveReset,
  incrementResetAttempts,
  markResetUsed,
  markAllResetsUsed,
};
