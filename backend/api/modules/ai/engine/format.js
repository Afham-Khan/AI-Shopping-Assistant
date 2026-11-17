// small formatting helpers shared by reasons, nlg and compare
const money = (n) => `Rs ${Math.round(Number(n) || 0).toLocaleString('en-US')}`;

const shortMoney = (n) => {
  const v = Number(n) || 0;
  if (v >= 1e5 && v % 1e5 === 0) return `Rs ${v / 1e5} lakh`;
  if (v >= 1000 && v % 1000 === 0) return `Rs ${v / 1000}k`;
  return money(v);
};

const stars = (r) => `${(Math.round(Number(r) * 10) / 10).toFixed(1)}★`;

const plural = (n, word, many = `${word}s`) => `${n} ${n === 1 ? word : many}`;

const titleCase = (s) => String(s || '').replace(/\b([a-z])/g, (m) => m.toUpperCase());

const list = (items, joiner = 'and') => {
  const a = items.filter(Boolean);
  if (a.length <= 1) return a[0] || '';
  return `${a.slice(0, -1).join(', ')} ${joiner} ${a[a.length - 1]}`;
};

const truncate = (s, n) => (s && s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s || '');

// deterministic pick so the same turn renders the same wording, varied across turns
const pick = (options, seed = Math.random() * 1e6) => options[Math.abs(Math.floor(seed)) % options.length];

module.exports = { money, shortMoney, stars, plural, titleCase, list, truncate, pick };
