const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const REFRESH_DAYS = () => Number(process.env.REFRESH_TOKEN_DAYS) || 30;

// keyed sha256 so a leaked table can't be brute-forced offline (6-digit otps especially)
const hashSecret = (value) =>
  crypto.createHmac('sha256', process.env.JWT_REFRESH_SECRET).update(String(value)).digest('hex');

const safeEqual = (a, b) => {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
};

const signAccessToken = (user) =>
  jwt.sign({ sub: String(user.id), role: user.role }, process.env.JWT_ACCESS_SECRET, {
    expiresIn: process.env.JWT_ACCESS_TTL || '15m',
  });

const createRefreshToken = () => {
  const token = crypto.randomBytes(48).toString('base64url');
  return {
    token,
    tokenHash: hashSecret(token),
    expiresAt: new Date(Date.now() + REFRESH_DAYS() * 24 * 60 * 60 * 1000),
  };
};

const generateOtp = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

// binding the token to the current hash makes it single-use: it dies once the password changes
const passwordFingerprint = (passwordHash) => hashSecret(passwordHash).slice(0, 16);

const signResetToken = (user) =>
  jwt.sign({ sub: String(user.id), purpose: 'reset', fp: passwordFingerprint(user.password_hash) },
    process.env.JWT_ACCESS_SECRET, { expiresIn: '15m' });

const verifyResetToken = (token) => {
  try {
    const payload = jwt.verify(token, process.env.JWT_ACCESS_SECRET);
    return payload.purpose === 'reset' ? payload : null;
  } catch {
    return null;
  }
};

module.exports = {
  hashSecret,
  safeEqual,
  signAccessToken,
  createRefreshToken,
  generateOtp,
  passwordFingerprint,
  signResetToken,
  verifyResetToken,
};
