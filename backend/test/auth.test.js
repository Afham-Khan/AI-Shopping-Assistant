const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { api, db, uniqueEmail, bearer, registerUser, PASSWORD } = require('./helpers');
const { hashSecret } = require('../helpers/tokens');
const { outbox } = require('../helpers/mailer');

const AUTH = '/api/v1/auth';

describe('General', () => {
  it('GEN-01 health check', async () => {
    const res = await api.get('/api/v1/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.data.status, 'ok');
  });

  it('GEN-02 unknown route returns 404 envelope', async () => {
    const res = await api.get('/api/v1/nope');
    assert.equal(res.status, 404);
    assert.equal(res.body.success, false);
  });

  it('GEN-03 malformed JSON returns 400', async () => {
    const res = await api.post(`${AUTH}/login`).set('Content-Type', 'application/json').send('{"email":');
    assert.equal(res.status, 400);
    assert.equal(res.body.message, 'Malformed JSON body');
  });
});

describe('Auth', () => {
  describe('register & login', () => {
    const email = uniqueEmail();

    it('AUTH-01 registers and lower-cases the email', async () => {
      const res = await api.post(`${AUTH}/register`).send({ name: 'Sara Test', email: email.toUpperCase(), password: PASSWORD });
      assert.equal(res.status, 201);
      const { user, accessToken, refreshToken } = res.body.data;
      assert.equal(user.email, email);
      assert.equal(user.isOnboarded, false);
      assert.ok(accessToken && refreshToken);
      assert.equal(JSON.stringify(res.body).includes('password'), false);
    });

    it('AUTH-02 rejects duplicate email', async () => {
      const res = await api.post(`${AUTH}/register`).send({ name: 'Sara Test', email, password: PASSWORD });
      assert.equal(res.status, 409);
    });

    it('AUTH-03 validates register input', async () => {
      const weak = await api.post(`${AUTH}/register`).send({ name: 'Sara', email: uniqueEmail(), password: 'password' });
      assert.equal(weak.status, 400);
      assert.equal(weak.body.errors[0].field, 'password');
      const badEmail = await api.post(`${AUTH}/register`).send({ name: 'Sara', email: 'not-an-email', password: PASSWORD });
      assert.equal(badEmail.status, 400);
      assert.equal(badEmail.body.errors[0].field, 'email');
      const shortName = await api.post(`${AUTH}/register`).send({ name: 'S', email: uniqueEmail(), password: PASSWORD });
      assert.equal(shortName.status, 400);
    });

    it('AUTH-04 logs in with correct credentials', async () => {
      const res = await api.post(`${AUTH}/login`).send({ email: email.toUpperCase(), password: PASSWORD });
      assert.equal(res.status, 200);
      assert.equal(res.body.data.user.email, email);
      assert.ok(res.body.data.accessToken);
    });

    it('AUTH-05 rejects wrong password and unknown email identically', async () => {
      const wrong = await api.post(`${AUTH}/login`).send({ email, password: 'Wrong1234' });
      const unknown = await api.post(`${AUTH}/login`).send({ email: uniqueEmail(), password: 'Wrong1234' });
      assert.equal(wrong.status, 401);
      assert.equal(unknown.status, 401);
      assert.equal(wrong.body.message, unknown.body.message);
    });
  });

  describe('access tokens', () => {
    let session;
    before(async () => { session = await registerUser(); });

    it('AUTH-06 /me requires a valid token', async () => {
      assert.equal((await api.get(`${AUTH}/me`)).status, 401);
      const garbage = await api.get(`${AUTH}/me`).set(bearer('garbage'));
      assert.equal(garbage.status, 401);
      assert.equal(garbage.body.code, 'INVALID_TOKEN');
    });

    it('AUTH-07 expired token returns TOKEN_EXPIRED', async () => {
      const expired = jwt.sign({ sub: String(session.user.id), exp: Math.floor(Date.now() / 1000) - 10 }, process.env.JWT_ACCESS_SECRET);
      const res = await api.get(`${AUTH}/me`).set(bearer(expired));
      assert.equal(res.status, 401);
      assert.equal(res.body.code, 'TOKEN_EXPIRED');
    });

    it('AUTH-08 /me returns the user', async () => {
      const res = await api.get(`${AUTH}/me`).set(session.auth);
      assert.equal(res.status, 200);
      assert.equal(res.body.data.id, session.user.id);
      assert.deepEqual(Object.keys(res.body.data).sort(), ['avatarUrl', 'createdAt', 'email', 'id', 'isOnboarded', 'name', 'phone', 'preferences', 'role']);
    });
  });

  describe('refresh tokens', () => {
    let session;
    let rotated;
    before(async () => { session = await registerUser(); });

    it('AUTH-09 rotates refresh tokens', async () => {
      const res = await api.post(`${AUTH}/refresh`).send({ refreshToken: session.refreshToken });
      assert.equal(res.status, 200);
      rotated = res.body.data;
      assert.notEqual(rotated.refreshToken, session.refreshToken);
      assert.equal((await api.get(`${AUTH}/me`).set(bearer(rotated.accessToken))).status, 200);
    });

    it('AUTH-10 replaying a used refresh token revokes the whole family', async () => {
      const replay = await api.post(`${AUTH}/refresh`).send({ refreshToken: session.refreshToken });
      assert.equal(replay.status, 401);
      assert.equal(replay.body.code, 'TOKEN_REUSED');
      const latest = await api.post(`${AUTH}/refresh`).send({ refreshToken: rotated.refreshToken });
      assert.equal(latest.status, 401);
    });

    it('AUTH-11 rejects unknown or missing refresh tokens', async () => {
      assert.equal((await api.post(`${AUTH}/refresh`).send({ refreshToken: 'unknown-token' })).status, 401);
      assert.equal((await api.post(`${AUTH}/refresh`).send({})).status, 400);
    });

    it('AUTH-12 logout revokes the refresh token', async () => {
      const fresh = await registerUser();
      const out = await api.post(`${AUTH}/logout`).send({ refreshToken: fresh.refreshToken });
      assert.equal(out.status, 200);
      assert.equal(out.body.data, null);
      assert.equal((await api.post(`${AUTH}/refresh`).send({ refreshToken: fresh.refreshToken })).status, 401);
    });
  });

  describe('password reset', () => {
    let session;
    let resetToken;
    const NEW_PASSWORD = 'NewPassw0rd';
    const lastOtpFor = (email) => {
      const mail = [...outbox].reverse().find((m) => m.to === email);
      return mail && mail.text.match(/\b(\d{6})\b/)[1];
    };
    const wrongOtp = (otp) => String((Number(otp) + 1) % 1000000).padStart(6, '0');

    before(async () => { session = await registerUser(); });

    it('AUTH-13 unknown email gets the same 200 and no mail', async () => {
      const before = outbox.length;
      const res = await api.post(`${AUTH}/forgot-password`).send({ email: uniqueEmail() });
      assert.equal(res.status, 200);
      assert.equal(res.body.data, null);
      assert.equal(outbox.length, before);
    });

    it('AUTH-14 known email receives a 6-digit code', async () => {
      const res = await api.post(`${AUTH}/forgot-password`).send({ email: session.email });
      assert.equal(res.status, 200);
      assert.match(lastOtpFor(session.email), /^\d{6}$/);
    });

    it('AUTH-15 wrong code reports attempts left', async () => {
      const res = await api.post(`${AUTH}/verify-otp`).send({ email: session.email, otp: wrongOtp(lastOtpFor(session.email)) });
      assert.equal(res.status, 400);
      assert.match(res.body.message, /4 attempts left/);
    });

    it('AUTH-16 locks after 5 wrong attempts even with the right code', async () => {
      const locked = await registerUser();
      await api.post(`${AUTH}/forgot-password`).send({ email: locked.email });
      const otp = lastOtpFor(locked.email);
      for (let i = 0; i < 5; i += 1) await api.post(`${AUTH}/verify-otp`).send({ email: locked.email, otp: wrongOtp(otp) });
      const res = await api.post(`${AUTH}/verify-otp`).send({ email: locked.email, otp });
      assert.equal(res.status, 400);
      assert.match(res.body.message, /Too many attempts/);
    });

    it('AUTH-17 validates otp format', async () => {
      const res = await api.post(`${AUTH}/verify-otp`).send({ email: session.email, otp: '12ab' });
      assert.equal(res.status, 400);
      assert.equal(res.body.errors[0].field, 'otp');
    });

    it('AUTH-18 correct code allows resetting the password', async () => {
      const verify = await api.post(`${AUTH}/verify-otp`).send({ email: session.email, otp: lastOtpFor(session.email) });
      assert.equal(verify.status, 200);
      resetToken = verify.body.data.resetToken;
      const reset = await api.post(`${AUTH}/reset-password`).send({ resetToken, password: NEW_PASSWORD });
      assert.equal(reset.status, 200);
      assert.equal((await api.post(`${AUTH}/login`).send({ email: session.email, password: session.password })).status, 401);
      assert.equal((await api.post(`${AUTH}/login`).send({ email: session.email, password: NEW_PASSWORD })).status, 200);
      assert.equal((await api.post(`${AUTH}/refresh`).send({ refreshToken: session.refreshToken })).status, 401);
    });

    it('AUTH-19 reset token is single use', async () => {
      const res = await api.post(`${AUTH}/reset-password`).send({ resetToken, password: 'Another1234' });
      assert.equal(res.status, 400);
    });
  });

  it('AUTH-20 demo login signs in the seeded account', async () => {
    const res = await api.post(`${AUTH}/demo`);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.user.email, 'demo@cartwise.app');
    assert.equal(res.body.data.user.isOnboarded, true);
    // the demo user is seeded data: drop the session row this test created
    await db('refresh_tokens').where({ token_hash: hashSecret(res.body.data.refreshToken) }).del();
  });
});
