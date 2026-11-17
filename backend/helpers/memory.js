// shopping-memory consent: users.preferences.memory = { enabled } (absent = enabled).
// cached briefly because interaction logging asks on every product view.
const db = require('../api/db/connection');

const TTL_MS = 60 * 1000;
const cache = new Map(); // userId -> { at, enabled }

const isEnabledPrefs = (preferences) => preferences?.memory?.enabled !== false;

const isMemoryEnabled = async (userId) => {
  if (!userId) return false;
  const hit = cache.get(userId);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.enabled;
  const user = await db('users').where({ id: userId }).first('preferences');
  const enabled = user ? isEnabledPrefs(user.preferences) : false;
  cache.set(userId, { at: Date.now(), enabled });
  if (cache.size > 5000) cache.delete(cache.keys().next().value);
  return enabled;
};

// call after the flag changes so the next request sees it immediately
const setCached = (userId, enabled) => cache.set(userId, { at: Date.now(), enabled });

module.exports = { isMemoryEnabled, isEnabledPrefs, setCached };
