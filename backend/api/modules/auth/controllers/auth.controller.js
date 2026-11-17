const bcrypt = require('bcryptjs');
const Users = require('../../users/models/users.models');
const Auth = require('../models/auth.models');
const { ok, created } = require('../../../../helpers/response');
const { toUser } = require('../../../../helpers/serializers');
const { badRequest, unauthorized, conflict, notFound } = require('../../../../helpers/errors');
const { sendMail } = require('../../../../helpers/mailer');
const tokens = require('../../../../helpers/tokens');
const { DEMO_EMAIL, BCRYPT_COST, OTP_TTL_MINUTES, OTP_MAX_ATTEMPTS } = require('../../../../helpers/constants');

// computed once so unknown emails cost the same bcrypt time as real ones
const DUMMY_HASH = bcrypt.hashSync('timing-equaliser-1', BCRYPT_COST);

const stripHash = ({ password_hash: _, ...user }) => user;

const issueSession = async (user, req) => {
  const refresh = tokens.createRefreshToken();
  await Auth.saveRefreshToken(user.id, refresh, req.get('user-agent'));
  return { accessToken: tokens.signAccessToken(user), refreshToken: refresh.token };
};

const sessionPayload = async (user, req) => ({ user: toUser(stripHash(user)), ...(await issueSession(user, req)) });

module.exports.register = async (req, res) => {
  const { name, email, password } = req.body;
  if (await Users.emailExists(email)) throw conflict('An account with this email already exists');
  const passwordHash = await bcrypt.hash(password, BCRYPT_COST);
  let user;
  try {
    user = await Users.create({ name, email, passwordHash });
  } catch (error) {
    if (error.code === '23505') throw conflict('An account with this email already exists');
    throw error;
  }
  return created(res, await sessionPayload(user, req), { message: 'Welcome to Cartwise!' });
};

module.exports.login = async (req, res) => {
  const { email, password } = req.body;
  const user = await Users.findWithHashByEmail(email);
  const valid = await bcrypt.compare(password, user ? user.password_hash : DUMMY_HASH);
  if (!user || !valid) throw unauthorized('Incorrect email or password');
  return ok(res, await sessionPayload(user, req));
};

module.exports.demo = async (req, res) => {
  const user = await Users.findWithHashByEmail(DEMO_EMAIL);
  if (!user) throw notFound('Demo account is not seeded. Run npm run db:seed');
  return ok(res, await sessionPayload(user, req));
};

module.exports.refresh = async (req, res) => {
  const record = await Auth.findRefreshToken(tokens.hashSecret(req.body.refreshToken));
  if (!record) throw unauthorized('Invalid refresh token');
  if (record.revoked_at) {
    // a revoked token being replayed means it leaked: kill every session of that user
    await Auth.revokeAllForUser(record.user_id);
    const err = unauthorized('Refresh token was already used. Please sign in again');
    err.code = 'TOKEN_REUSED';
    throw err;
  }
  if (new Date(record.expires_at) <= new Date()) throw unauthorized('Refresh token expired. Please sign in again');

  const user = await Users.findById(record.user_id);
  if (!user) throw unauthorized('Invalid refresh token');
  const revoked = await Auth.revokeRefreshToken(record.id);
  if (!revoked) throw unauthorized('Refresh token was already used. Please sign in again');
  return ok(res, await issueSession(user, req));
};

module.exports.logout = async (req, res) => {
  await Auth.revokeByHash(tokens.hashSecret(req.body.refreshToken));
  return ok(res, null, { message: 'Signed out' });
};

module.exports.forgotPassword = async (req, res) => {
  const user = await Users.findWithHashByEmail(req.body.email);
  if (user) {
    const otp = tokens.generateOtp();
    await Auth.createPasswordReset(user.id, tokens.hashSecret(`${user.id}:${otp}`),
      new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000));
    // not awaited: smtp latency would otherwise reveal which emails exist
    sendMail({
      to: user.email,
      subject: 'Your Cartwise password reset code',
      text: `Hi ${user.name},\n\nYour Cartwise verification code is ${otp}. It expires in ${OTP_TTL_MINUTES} minutes.\n\nIf you did not request this, you can ignore this email.`,
    }).catch((error) => console.error('[MAIL ERROR]', error.message));
  }
  return ok(res, null, { message: 'If an account exists for this email, a verification code has been sent' });
};

module.exports.verifyOtp = async (req, res) => {
  const { email, otp } = req.body;
  const user = await Users.findWithHashByEmail(email);
  const reset = user && (await Auth.findActiveReset(user.id));
  if (!reset) throw badRequest('Invalid or expired code. Please request a new one');
  if (reset.attempts >= OTP_MAX_ATTEMPTS) throw badRequest('Too many attempts. Please request a new code');

  if (!tokens.safeEqual(reset.otp_hash, tokens.hashSecret(`${user.id}:${otp}`))) {
    await Auth.incrementResetAttempts(reset.id);
    const left = OTP_MAX_ATTEMPTS - reset.attempts - 1;
    throw badRequest(left > 0 ? `Incorrect code. ${left} attempt${left === 1 ? '' : 's'} left` : 'Too many attempts. Please request a new code');
  }
  await Auth.markResetUsed(reset.id);
  return ok(res, { resetToken: tokens.signResetToken(user) });
};

module.exports.resetPassword = async (req, res) => {
  const payload = tokens.verifyResetToken(req.body.resetToken);
  const user = payload && (await Users.findWithHashById(Number(payload.sub)));
  if (!user || payload.fp !== tokens.passwordFingerprint(user.password_hash)) {
    throw badRequest('Reset link is invalid or has expired');
  }
  const passwordHash = await bcrypt.hash(req.body.password, BCRYPT_COST);
  await Users.updatePassword(user.id, passwordHash);
  await Auth.revokeAllForUser(user.id);
  await Auth.markAllResetsUsed(user.id);
  return ok(res, null, { message: 'Password updated. Please sign in with your new password' });
};

module.exports.me = async (req, res) => {
  const user = await Users.findById(req.userId);
  if (!user) throw unauthorized('Account no longer exists');
  return ok(res, toUser(user));
};
