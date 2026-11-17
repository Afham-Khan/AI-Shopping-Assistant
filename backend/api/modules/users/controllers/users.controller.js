const bcrypt = require('bcryptjs');
const Users = require('../models/users.models');
const { ok } = require('../../../../helpers/response');
const { toUser } = require('../../../../helpers/serializers');
const { badRequest, unauthorized } = require('../../../../helpers/errors');
const { BCRYPT_COST } = require('../../../../helpers/constants');

module.exports.updateProfile = async (req, res) => {
  const changes = {};
  if (req.body.name !== undefined) changes.name = req.body.name;
  if (req.body.phone !== undefined) changes.phone = req.body.phone || null;
  if (!Object.keys(changes).length) throw badRequest('Nothing to update');
  const user = await Users.update(req.userId, changes);
  if (!user) throw unauthorized('Account no longer exists');
  return ok(res, toUser(user));
};

module.exports.updatePreferences = async (req, res) => {
  const current = await Users.findById(req.userId);
  if (!current) throw unauthorized('Account no longer exists');
  const { interests, budget, gender } = req.body;
  const preferences = { ...current.preferences };

  if (interests !== undefined) {
    const unique = [...new Set(interests)];
    const known = await Users.existingCategorySlugs(unique);
    const unknown = unique.filter((slug) => !known.includes(slug));
    if (unknown.length) {
      throw badRequest(`Unknown categories: ${unknown.join(', ')}`, [{ field: 'interests', message: 'Unknown category slug' }]);
    }
    preferences.interests = unique;
  }
  if (budget !== undefined) {
    const min = Number(budget.min ?? 0);
    const max = Number(budget.max ?? min);
    if (min > max) throw badRequest('Budget min cannot exceed max', [{ field: 'budget', message: 'min must be ≤ max' }]);
    preferences.budget = { min, max };
  }
  if (gender !== undefined) preferences.gender = gender;

  const user = await Users.update(req.userId, { preferences, is_onboarded: true });
  return ok(res, toUser(user));
};

module.exports.changePassword = async (req, res) => {
  const user = await Users.findWithHashById(req.userId);
  if (!user) throw unauthorized('Account no longer exists');
  if (!(await bcrypt.compare(req.body.currentPassword, user.password_hash))) {
    throw badRequest('Current password is incorrect', [{ field: 'currentPassword', message: 'Current password is incorrect' }]);
  }
  if (req.body.currentPassword === req.body.newPassword) {
    throw badRequest('New password must be different', [{ field: 'newPassword', message: 'New password must be different' }]);
  }
  await Users.updatePassword(user.id, await bcrypt.hash(req.body.newPassword, BCRYPT_COST));
  return ok(res, null, { message: 'Password changed' });
};

module.exports.stats = async (req, res) => ok(res, await Users.stats(req.userId));
