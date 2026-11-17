const bcrypt = require('bcryptjs');
const Users = require('../models/users.models');
const { ok } = require('../../../../helpers/response');
const { toUser } = require('../../../../helpers/serializers');
const { badRequest, unauthorized } = require('../../../../helpers/errors');
const { BCRYPT_COST } = require('../../../../helpers/constants');
const { isEnabledPrefs, setCached } = require('../../../../helpers/memory');
const { invalidate } = require('../../ai/engine/ranking/personalization');

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

const rs = (n) => `Rs ${Math.round(n).toLocaleString('en-US')}`;
const roundPrice = (v) => (v >= 10000 ? Math.round(v / 1000) * 1000 : Math.round(v / 100) * 100);
const shareOf = (rows) => {
  const total = rows.reduce((a, r) => a + r.weight, 0) || 1;
  return (r) => +(r.weight / total).toFixed(2);
};
const listText = (items) => (items.length <= 1 ? items[0] || '' : `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`);

// GET /users/me/memory: what Zelora remembers, in plain words
module.exports.getMemory = async (req, res) => {
  const user = await Users.findById(req.userId);
  if (!user) throw unauthorized('Account no longer exists');
  const enabled = isEnabledPrefs(user.preferences);
  const m = await Users.memorySnapshot(req.userId);
  const catShare = shareOf(m.categories);
  const brandShare = shareOf(m.brands);
  const topCategories = m.categories.map((c) => ({ slug: c.slug, name: c.name, share: catShare(c) }));
  const topBrands = m.brands.map((b) => ({ name: b.name, share: brandShare(b) }));
  const budgetBand = m.prices?.n
    ? { min: roundPrice(m.prices.low), max: roundPrice(m.prices.high), avg: Math.round(m.prices.avg), label: roundPrice(m.prices.low) === roundPrice(m.prices.high) ? `around ${rs(roundPrice(m.prices.low))}` : `${rs(roundPrice(m.prices.low))} to ${rs(roundPrice(m.prices.high))}` }
    : null;
  const recentSearches = m.searches.map((s) => s.query);
  const summary = [];
  if (!enabled) summary.push('Shopping memory is off: Zelora is not using or saving your browsing for recommendations.');
  if (topCategories.length) summary.push(`You browse mostly ${listText(topCategories.slice(0, 3).map((c) => c.name))}.`);
  if (topBrands.length) summary.push(`Brands you keep coming back to: ${listText(topBrands.slice(0, 3).map((b) => b.name))}.`);
  if (budgetBand) summary.push(`Your usual price range is ${budgetBand.label}.`);
  if (m.passes.length) summary.push(`You usually skip ${listText(m.passes.slice(0, 2).map((p) => p.name))} in Discover.`);
  if (recentSearches.length) summary.push(`Recent searches: ${recentSearches.slice(0, 3).map((q) => `"${q}"`).join(', ')}.`);
  if (user.preferences?.interests?.length) summary.push(`You picked ${user.preferences.interests.length} favourite categories during onboarding (kept even if you clear memory).`);
  if (summary.length === (enabled ? 0 : 1)) summary.push('Nothing remembered yet. Browse, search or chat and Zelora will learn your taste.');
  return ok(res, {
    enabled,
    summary,
    topCategories,
    topBrands,
    budgetBand,
    recentSearches,
    counts: m.counts,
    lastActivityAt: m.lastActivityAt,
  });
};

// PUT /users/me/memory { enabled }
module.exports.setMemory = async (req, res) => {
  const current = await Users.findById(req.userId);
  if (!current) throw unauthorized('Account no longer exists');
  const { enabled } = req.body;
  const preferences = { ...current.preferences, memory: { enabled, updatedAt: new Date().toISOString() } };
  await Users.update(req.userId, { preferences });
  setCached(req.userId, enabled);
  invalidate(req.userId);
  return ok(res, { enabled }, { message: enabled ? 'Shopping memory is on' : 'Shopping memory is off' });
};

// DELETE /users/me/memory: wipes this user's browsing signals, search history and chat context
module.exports.clearMemory = async (req, res) => {
  const cleared = await Users.clearMemory(req.userId);
  invalidate(req.userId);
  return ok(res, { cleared }, { message: 'Shopping memory cleared' });
};
