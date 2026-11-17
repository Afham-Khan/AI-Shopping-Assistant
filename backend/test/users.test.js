const assert = require('node:assert/strict');
const { api, registerUser } = require('./helpers');

const USERS = '/api/v1/users';

describe('Users', () => {
  let session;
  before(async () => { session = await registerUser(); });

  it('USR-01 requires auth', async () => {
    assert.equal((await api.patch(`${USERS}/me`).send({ name: 'X' })).status, 401);
    assert.equal((await api.put(`${USERS}/me/preferences`).send({})).status, 401);
    assert.equal((await api.get(`${USERS}/me/stats`)).status, 401);
  });

  it('USR-02 updates profile', async () => {
    const res = await api.patch(`${USERS}/me`).set(session.auth).send({ name: '  Hira Malik ', phone: '+92 333 1234567' });
    assert.equal(res.status, 200);
    assert.equal(res.body.data.name, 'Hira Malik');
    assert.equal(res.body.data.phone, '+92 333 1234567');
  });

  it('USR-03 validates profile input', async () => {
    assert.equal((await api.patch(`${USERS}/me`).set(session.auth).send({ name: 'H' })).status, 400);
    assert.equal((await api.patch(`${USERS}/me`).set(session.auth).send({ phone: 'call me' })).status, 400);
    assert.equal((await api.patch(`${USERS}/me`).set(session.auth).send({})).status, 400);
  });

  it('USR-04 saves preferences and marks onboarded', async () => {
    const res = await api.put(`${USERS}/me/preferences`).set(session.auth)
      .send({ interests: ['smartphones', 'laptops', 'smartphones'], budget: { min: 10000, max: 150000 }, gender: 'women' });
    assert.equal(res.status, 200);
    assert.equal(res.body.data.isOnboarded, true);
    assert.deepEqual(res.body.data.preferences, { interests: ['smartphones', 'laptops'], budget: { min: 10000, max: 150000 }, gender: 'women' });
  });

  it('USR-05 rejects invalid preferences', async () => {
    const unknown = await api.put(`${USERS}/me/preferences`).set(session.auth).send({ interests: ['flying-cars'] });
    assert.equal(unknown.status, 400);
    const budget = await api.put(`${USERS}/me/preferences`).set(session.auth).send({ budget: { min: 5000, max: 100 } });
    assert.equal(budget.status, 400);
    const gender = await api.put(`${USERS}/me/preferences`).set(session.auth).send({ gender: 'robot' });
    assert.equal(gender.status, 400);
  });

  it('USR-06 change-password rejects a wrong current password', async () => {
    const res = await api.post(`${USERS}/me/change-password`).set(session.auth).send({ currentPassword: 'Nope12345', newPassword: 'Brand9New' });
    assert.equal(res.status, 400);
    assert.equal(res.body.errors[0].field, 'currentPassword');
  });

  it('USR-07 changes the password', async () => {
    const res = await api.post(`${USERS}/me/change-password`).set(session.auth).send({ currentPassword: session.password, newPassword: 'Brand9New' });
    assert.equal(res.status, 200);
    const login = await api.post('/api/v1/auth/login').send({ email: session.email, password: 'Brand9New' });
    assert.equal(login.status, 200);
  });

  it('USR-08 returns stats', async () => {
    const res = await api.get(`${USERS}/me/stats`).set(session.auth);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, { orders: 0, wishlist: 0, reviews: 0, conversations: 0 });
  });
});
