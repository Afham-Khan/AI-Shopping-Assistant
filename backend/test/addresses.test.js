const assert = require('node:assert/strict');
const { api, registerUser, addAddress } = require('./helpers');

const ADDR = '/api/v1/addresses';

describe('Addresses', () => {
  let owner;
  let other;
  let first;
  let second;
  before(async () => {
    [owner, other] = await Promise.all([registerUser(), registerUser()]);
  });

  it('ADR-01 first address becomes default', async () => {
    first = await addAddress(owner.auth, { label: 'Home' });
    assert.equal(first.isDefault, true);
    assert.equal(first.country, 'Pakistan');
    assert.deepEqual(Object.keys(first).sort(), ['city', 'country', 'fullName', 'id', 'isDefault', 'label', 'line1', 'line2', 'phone', 'postalCode', 'province']);
  });

  it('ADR-02 a new default replaces the old one', async () => {
    second = await addAddress(owner.auth, { label: 'Office', city: 'Lahore', isDefault: true });
    assert.equal(second.isDefault, true);
    const list = (await api.get(ADDR).set(owner.auth)).body.data;
    assert.equal(list.filter((a) => a.isDefault).length, 1);
  });

  it('ADR-03 lists default first', async () => {
    const res = await api.get(ADDR).set(owner.auth);
    assert.equal(res.status, 200);
    assert.equal(res.body.data[0].id, second.id);
  });

  it('ADR-04 sets default explicitly', async () => {
    const res = await api.post(`${ADDR}/${first.id}/default`).set(owner.auth);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.isDefault, true);
    const list = (await api.get(ADDR).set(owner.auth)).body.data;
    assert.deepEqual(list.filter((a) => a.isDefault).map((a) => a.id), [first.id]);
  });

  it('ADR-05 updates fields and refuses nulling required ones', async () => {
    const res = await api.patch(`${ADDR}/${second.id}`).set(owner.auth).send({ line2: 'Floor 3', postalCode: '54000' });
    assert.equal(res.status, 200);
    assert.equal(res.body.data.line2, 'Floor 3');
    assert.equal(res.body.data.city, 'Lahore');
    const bad = await api.patch(`${ADDR}/${second.id}`).set(owner.auth).send({ city: null });
    assert.equal(bad.status, 400);
  });

  it('ADR-06 deleting the default promotes another address', async () => {
    const res = await api.delete(`${ADDR}/${first.id}`).set(owner.auth);
    assert.equal(res.status, 200);
    const list = (await api.get(ADDR).set(owner.auth)).body.data;
    assert.equal(list.length, 1);
    assert.equal(list[0].id, second.id);
    assert.equal(list[0].isDefault, true);
  });

  it('ADR-07 other users cannot touch my address', async () => {
    assert.equal((await api.patch(`${ADDR}/${second.id}`).set(other.auth).send({ label: 'Mine' })).status, 404);
    assert.equal((await api.delete(`${ADDR}/${second.id}`).set(other.auth)).status, 404);
    assert.equal((await api.post(`${ADDR}/${second.id}/default`).set(other.auth)).status, 404);
    assert.equal((await api.get(ADDR).set(other.auth)).body.data.length, 0);
  });

  it('ADR-08 validates input and ids', async () => {
    const missing = await api.post(ADDR).set(owner.auth).send({ fullName: 'A B' });
    assert.equal(missing.status, 400);
    assert.equal((await api.patch(`${ADDR}/abc`).set(owner.auth).send({ label: 'x' })).status, 400);
    assert.equal((await api.delete(`${ADDR}/0`).set(owner.auth)).status, 400);
    assert.equal((await api.get(ADDR)).status, 401);
  });
});
