// deterministic PRNG so every seed run produces identical data (keeps the seed idempotent)
const mulberry32 = (seed) => () => {
  let t = (seed += 0x6d2b79f5);
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const hashString = (s) => {
  let h = 2166136261;
  for (let i = 0; i < s.length; i += 1) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
};

const createRng = (seed) => {
  const next = mulberry32(typeof seed === 'string' ? hashString(seed) : seed);
  const rng = {
    next,
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    pick: (list) => list[Math.floor(next() * list.length)],
    chance: (p) => next() < p,
    shuffle: (list) => {
      const copy = [...list];
      for (let i = copy.length - 1; i > 0; i -= 1) {
        const j = Math.floor(next() * (i + 1));
        [copy[i], copy[j]] = [copy[j], copy[i]];
      }
      return copy;
    },
    sample: (list, n) => rng.shuffle(list).slice(0, n),
    // independent stream keyed by name, unaffected by how much the parent has been consumed
    fork: (key) => createRng(`fork-${key}`),
    gaussian: () => {
      const u = next() || 1e-9;
      return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * next());
    },
  };
  return rng;
};

module.exports = { createRng, hashString };
