const db = require('../../../db/connection');
const Addresses = require('../models/addresses.models');
const { ok, created } = require('../../../../helpers/response');
const { toAddress } = require('../../../../helpers/serializers');
const { notFound, badRequest } = require('../../../../helpers/errors');

const MAX_ADDRESSES = 20;

const FIELD_MAP = {
  label: 'label', fullName: 'full_name', phone: 'phone', line1: 'line1', line2: 'line2',
  city: 'city', province: 'province', postalCode: 'postal_code', country: 'country',
};

const DEFAULTS = { label: 'Home', country: 'Pakistan' };

const toRow = (body) =>
  Object.entries(FIELD_MAP).reduce((row, [key, column]) => {
    if (body[key] !== undefined) row[column] = body[key] === '' || body[key] === null ? DEFAULTS[column] ?? null : body[key];
    return row;
  }, {});

module.exports.list = async (req, res) => ok(res, (await Addresses.listByUser(req.userId)).map(toAddress));

module.exports.create = async (req, res) => {
  const address = await db.transaction(async (trx) => {
    await Addresses.lockUserAddresses(req.userId, trx);
    const count = await Addresses.countByUser(req.userId, trx);
    if (count >= MAX_ADDRESSES) throw badRequest(`You can save up to ${MAX_ADDRESSES} addresses`);
    const isDefault = count === 0 || req.body.isDefault === true;
    if (isDefault) await Addresses.clearDefault(req.userId, trx);
    return Addresses.insert({ ...toRow(req.body), user_id: req.userId, is_default: isDefault }, trx);
  });
  return created(res, toAddress(address));
};

module.exports.update = async (req, res) => {
  const address = await db.transaction(async (trx) => {
    await Addresses.lockUserAddresses(req.userId, trx);
    const existing = await Addresses.findOwned(req.params.id, req.userId, trx);
    if (!existing) throw notFound('Address not found');
    const changes = toRow(req.body);
    // un-defaulting is ignored: there must always be a default while addresses exist
    if (req.body.isDefault === true && !existing.is_default) {
      await Addresses.clearDefault(req.userId, trx);
      changes.is_default = true;
    }
    if (!Object.keys(changes).length) return existing;
    return Addresses.update(existing.id, changes, trx);
  });
  return ok(res, toAddress(address));
};

module.exports.remove = async (req, res) => {
  await db.transaction(async (trx) => {
    await Addresses.lockUserAddresses(req.userId, trx);
    const existing = await Addresses.findOwned(req.params.id, req.userId, trx);
    if (!existing) throw notFound('Address not found');
    await Addresses.remove(existing.id, trx);
    if (existing.is_default) {
      const next = await Addresses.latestOther(req.userId, trx);
      if (next) await Addresses.update(next.id, { is_default: true }, trx);
    }
  });
  return ok(res, null, { message: 'Address removed' });
};

module.exports.makeDefault = async (req, res) => {
  const address = await db.transaction(async (trx) => {
    await Addresses.lockUserAddresses(req.userId, trx);
    const existing = await Addresses.findOwned(req.params.id, req.userId, trx);
    if (!existing) throw notFound('Address not found');
    if (existing.is_default) return existing;
    await Addresses.clearDefault(req.userId, trx);
    return Addresses.update(existing.id, { is_default: true }, trx);
  });
  return ok(res, toAddress(address));
};
