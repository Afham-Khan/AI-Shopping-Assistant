// free-tier safety for the optional llm: token-bucket rate limit (per minute) + daily cap, an lru
// response cache (same prompt + facts -> same answer, no call) and a circuit breaker that skips the llm
// for a while after repeated failures. every refusal simply means "keep the local reply".
const crypto = require('crypto');

const envNum = (name, fallback) => {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v >= 0 ? v : fallback;
};

class TokenBucket {
  constructor({ capacity, perMinute, now }) {
    this.capacity = capacity;
    this.ratePerMs = perMinute / 60000;
    this.now = now;
    this.tokens = capacity;
    this.at = now();
  }

  take() {
    const t = this.now();
    this.tokens = Math.min(this.capacity, this.tokens + (t - this.at) * this.ratePerMs);
    this.at = t;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

class LruCache {
  constructor({ size, ttlMs, now }) {
    this.size = size;
    this.ttlMs = ttlMs;
    this.now = now;
    this.map = new Map();
  }

  get(key) {
    const hit = this.map.get(key);
    if (!hit) return undefined;
    if (this.now() - hit.at > this.ttlMs) {
      this.map.delete(key);
      return undefined;
    }
    // refresh recency
    this.map.delete(key);
    this.map.set(key, hit);
    return hit.value;
  }

  set(key, value) {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, { value, at: this.now() });
    while (this.map.size > this.size) this.map.delete(this.map.keys().next().value);
  }
}

class CircuitBreaker {
  constructor({ threshold, cooldownMs, now }) {
    this.threshold = threshold;
    this.cooldownMs = cooldownMs;
    this.now = now;
    this.failures = 0;
    this.openedAt = null;
  }

  get state() {
    if (this.openedAt === null) return 'closed';
    return this.now() - this.openedAt >= this.cooldownMs ? 'half-open' : 'open';
  }

  allow() {
    return this.state !== 'open';
  }

  success() {
    this.failures = 0;
    this.openedAt = null;
  }

  failure() {
    this.failures += 1;
    // a failed trial call while half-open re-opens immediately
    if (this.failures >= this.threshold || this.openedAt !== null) {
      this.openedAt = this.now();
      this.failures = this.threshold;
    }
  }
}

const dayKey = (t) => new Date(t).toISOString().slice(0, 10);

const createGuard = (options = {}) => {
  const now = options.now || Date.now;
  const perMinute = options.perMinute ?? envNum('LLM_RATE_PER_MIN', 12);
  const dailyLimit = options.dailyLimit ?? envNum('LLM_DAILY_LIMIT', 800);
  const bucket = new TokenBucket({ capacity: Math.max(1, perMinute), perMinute, now });
  const cache = new LruCache({ size: options.cacheSize ?? envNum('LLM_CACHE_SIZE', 200), ttlMs: options.cacheTtlMs ?? envNum('LLM_CACHE_TTL_MS', 6 * 3600 * 1000), now });
  const breaker = new CircuitBreaker({ threshold: options.breakerThreshold ?? envNum('LLM_BREAKER_THRESHOLD', 3), cooldownMs: options.breakerCooldownMs ?? envNum('LLM_BREAKER_COOLDOWN_MS', 5 * 60 * 1000), now });
  const stats = { day: dayKey(now()), usedToday: 0, cacheHits: 0, calls: 0, failures: 0, skipped: { rateLimited: 0, dailyLimit: 0, circuitOpen: 0 } };

  const rollDay = () => {
    const d = dayKey(now());
    if (d !== stats.day) {
      stats.day = d;
      stats.usedToday = 0;
    }
  };

  const keyOf = (parts) => crypto.createHash('sha256').update(JSON.stringify(parts)).digest('hex');

  // fn: () => Promise<value>. resolves { value, from: 'cache'|'llm' } or { skipped: reason }; rejects when fn fails
  const run = async (keyParts, fn) => {
    rollDay();
    const key = keyOf(keyParts);
    const cached = cache.get(key);
    if (cached !== undefined) {
      stats.cacheHits += 1;
      return { value: cached, from: 'cache' };
    }
    if (!breaker.allow()) {
      stats.skipped.circuitOpen += 1;
      return { skipped: 'circuit_open' };
    }
    if (stats.usedToday >= dailyLimit) {
      stats.skipped.dailyLimit += 1;
      return { skipped: 'daily_limit' };
    }
    if (!bucket.take()) {
      stats.skipped.rateLimited += 1;
      return { skipped: 'rate_limited' };
    }
    stats.usedToday += 1;
    stats.calls += 1;
    try {
      const value = await fn();
      breaker.success();
      cache.set(key, value);
      return { value, from: 'llm' };
    } catch (error) {
      stats.failures += 1;
      breaker.failure();
      throw error;
    }
  };

  const info = () => {
    rollDay();
    return {
      usedToday: stats.usedToday,
      dailyLimit,
      perMinute,
      cacheHits: stats.cacheHits,
      cacheSize: cache.map.size,
      circuit: breaker.state,
      failures: stats.failures,
      skipped: { ...stats.skipped },
    };
  };

  return { run, info, cache, breaker, bucket };
};

module.exports = { createGuard, TokenBucket, LruCache, CircuitBreaker };
