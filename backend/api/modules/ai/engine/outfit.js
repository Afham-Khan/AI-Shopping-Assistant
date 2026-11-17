// complete the look: for a fashion item, pick one strong match per complementary slot (shoes, bag,
// jewellery, watch, sunglasses...) scored by gender fit, colour harmony, price band, rating and style
// similarity (embeddings of style/occasion keywords). non-fashion items fall back to bought-together.
const { getCatalog } = require('./retrieval/catalog');
const { boughtTogether } = require('./ranking/recommender');
const { money, stars, plural, list } = require('./format');

const FASHION = new Set(['mens-shirts', 'mens-shoes', 'mens-watches', 'tops', 'womens-dresses', 'womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses']);

// slot order = how much the slot completes the outfit
const SLOTS = {
  'womens-dresses': ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses', 'fragrances'],
  tops: ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses'],
  'womens-shoes': ['womens-dresses', 'tops', 'womens-bags', 'womens-jewellery'],
  'womens-bags': ['womens-dresses', 'womens-shoes', 'womens-jewellery', 'womens-watches', 'sunglasses'],
  'womens-jewellery': ['womens-dresses', 'tops', 'womens-bags', 'womens-watches'],
  'womens-watches': ['womens-dresses', 'tops', 'womens-jewellery', 'womens-bags'],
  'mens-shirts': ['mens-shoes', 'mens-watches', 'sunglasses', 'fragrances'],
  'mens-shoes': ['mens-shirts', 'mens-watches', 'sunglasses'],
  'mens-watches': ['mens-shirts', 'mens-shoes', 'sunglasses', 'fragrances'],
  sunglasses: { women: ['womens-dresses', 'tops', 'womens-bags', 'womens-shoes'], men: ['mens-shirts', 'mens-shoes', 'mens-watches'], any: ['mens-shirts', 'tops', 'womens-bags', 'mens-watches'] },
};

const ROLE = {
  'womens-shoes': 'Shoes', 'mens-shoes': 'Shoes', 'womens-bags': 'Bag', 'womens-jewellery': 'Jewellery', 'womens-watches': 'Watch',
  'mens-watches': 'Watch', sunglasses: 'Sunglasses', fragrances: 'Fragrance', 'womens-dresses': 'Dress', tops: 'Top', 'mens-shirts': 'Shirt',
};

// ------------------------------------------------------------------------------- colour harmony

// hue in degrees, or a neutral/metal family
const COLOR_WORDS = [
  ['multicolor', { family: 'multi' }], ['multicolour', { family: 'multi' }], ['assorted', { family: 'multi' }], ['tortoise', { family: 'neutral', name: 'tortoise brown' }],
  ['rose gold', { family: 'metal', name: 'rose gold', warm: true }], ['gold', { family: 'metal', name: 'gold', warm: true }], ['golden', { family: 'metal', name: 'gold', warm: true }],
  ['silver', { family: 'metal', name: 'silver' }], ['platinum', { family: 'metal', name: 'silver' }], ['steel', { family: 'metal', name: 'silver' }],
  ['black', { family: 'neutral', name: 'black' }], ['onyx', { family: 'neutral', name: 'black' }], ['white', { family: 'neutral', name: 'white' }],
  ['ivory', { family: 'neutral', name: 'white' }], ['cream', { family: 'neutral', name: 'cream' }], ['beige', { family: 'neutral', name: 'beige' }],
  ['nude', { family: 'neutral', name: 'beige' }], ['grey', { family: 'neutral', name: 'grey' }], ['gray', { family: 'neutral', name: 'grey' }],
  ['charcoal', { family: 'neutral', name: 'grey' }], ['graphite', { family: 'neutral', name: 'grey' }], ['navy', { family: 'neutral', name: 'navy' }],
  ['brown', { family: 'neutral', name: 'brown' }], ['tan', { family: 'neutral', name: 'brown' }], ['clear', { family: 'neutral', name: 'clear' }],
  ['translucent', { family: 'neutral', name: 'clear' }], ['starlight', { family: 'neutral', name: 'cream' }],
  // hues on the painter's (RYB) wheel, where red-green, blue-orange and yellow-purple are complementary
  ['red', { hue: 0 }], ['maroon', { hue: 355 }], ['crimson', { hue: 355 }], ['coral', { hue: 30 }], ['orange', { hue: 60 }], ['amber', { hue: 90 }],
  ['mustard', { hue: 105 }], ['yellow', { hue: 120 }], ['olive', { hue: 150 }], ['green', { hue: 180 }], ['emerald', { hue: 190 }], ['teal', { hue: 210 }],
  ['blue', { hue: 240 }], ['purple', { hue: 300 }], ['violet', { hue: 300 }], ['lavender', { hue: 290 }], ['plum', { hue: 315 }], ['pink', { hue: 340 }], ['rose', { hue: 345 }],
];

const colorText = (p) => [p.color, p.specs?.Colour, p.specs?.Colourway, p.specs?.['Frame Colour']].filter(Boolean).join(' ').toLowerCase();

// "Red and black" -> { primary: {hue:0}, accents: [black] }
const parseColor = (p) => {
  const text = colorText(p);
  if (!text) return null;
  const found = [];
  let rest = ` ${text} `;
  for (const [word, info] of COLOR_WORDS) {
    const re = new RegExp(`\\b${word}\\b`);
    if (re.test(rest)) {
      found.push({ word, ...info, name: info.name || word });
      rest = rest.replace(re, ' ');
    }
  }
  if (!found.length) return null;
  const chromatic = found.find((c) => c.hue !== undefined);
  return { label: p.color || text, primary: chromatic || found[0], all: found };
};

const hueGap = (a, b) => {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
};

// pure: two parsed colours -> { score 0..1, rule, reason }
const colorHarmony = (a, b) => {
  if (!a || !b) return { score: 0.6, rule: 'unknown', reason: null };
  const x = a.primary;
  const y = b.primary;
  const neutral = (c) => c.family === 'neutral' || c.family === 'metal';
  if (neutral(x) && neutral(y)) {
    if (x.family === 'metal' && y.family === 'metal' && x.name !== y.name && !(x.warm && y.warm)) return { score: 0.6, rule: 'mixed-metals', reason: `Mixing ${x.name} and ${y.name} is a bolder choice` };
    return { score: 0.9, rule: 'neutral', reason: `${cap(y.name)} and ${x.name} is a timeless neutral pairing` };
  }
  if (neutral(y)) return { score: 0.88, rule: 'neutral', reason: `${cap(y.name)} goes with ${x.name || 'any colour'}` };
  if (neutral(x)) {
    if (y.family === 'multi') return { score: 0.8, rule: 'neutral', reason: `A colourful piece pops against ${x.name}` };
    return { score: 0.85, rule: 'accent', reason: `${cap(y.name)} adds a pop of colour to ${x.name}` };
  }
  if (x.family === 'multi' || y.family === 'multi') return { score: 0.55, rule: 'busy', reason: null };
  const gap = hueGap(x.hue, y.hue);
  if (gap <= 15) return { score: 0.8, rule: 'monochrome', reason: `Tone-on-tone ${y.name} matches the ${x.name}` };
  if (gap <= 60) return { score: 0.86, rule: 'analogous', reason: `${cap(y.name)} and ${x.name} sit side by side on the colour wheel` };
  if (gap >= 150) return { score: 0.74, rule: 'complementary', reason: `${cap(y.name)} is complementary to ${x.name}: high contrast` };
  if (gap >= 105 && gap <= 135) return { score: 0.6, rule: 'triadic', reason: null };
  return { score: 0.42, rule: 'clash', reason: null };
};

const cap = (s) => String(s || '').replace(/^\w/, (c) => c.toUpperCase());

// ------------------------------------------------------------------------------- style keywords

const STYLE_TERMS = ['party', 'parties', 'evening', 'dinner', 'wedding', 'festive', 'formal', 'office', 'work', 'business', 'casual', 'everyday',
  'brunch', 'summer', 'winter', 'beach', 'travel', 'sport', 'sporty', 'athletic', 'gym', 'elegant', 'classic', 'chic', 'luxury', 'bold', 'minimal',
  'boho', 'vintage', 'retro', 'glam', 'statement', 'smart', 'street', 'outdoor', 'gala', 'special occasions', 'date night', 'traditional'];

const styleText = (p) => [p.specs?.Style, p.specs?.Occasion, p.specs?.['Ideal For'], (p.tags || []).join(' '), (p.highlights || []).join(' ')].filter(Boolean).join('. ');

const styleTerms = (p) => {
  const text = ` ${`${styleText(p)} ${p.title}`.toLowerCase()} `;
  return new Set(STYLE_TERMS.filter((t) => text.includes(` ${t}`)).map((t) => (t === 'parties' ? 'party' : t)));
};

// ------------------------------------------------------------------------------- scoring

const genderOf = (p) => {
  if (p.gender === 'men' || p.gender === 'women') return p.gender;
  if (p.category_slug.startsWith('womens-') || p.category_slug === 'tops') return 'women';
  if (p.category_slug.startsWith('mens-')) return 'men';
  return 'unisex';
};

const genderFit = (base, cand) => {
  const a = genderOf(base);
  const b = genderOf(cand);
  if (a === 'unisex' || b === 'unisex') return 0.75;
  return a === b ? 1 : 0;
};

// accessories usually cost less than the hero piece, so the ideal band is a bit below the base price
const priceBand = (base, cand) => {
  const ratio = (cand.price + 1) / (base.price + 1);
  return Math.max(0, 1 - Math.abs(Math.log(ratio / 0.8)) / Math.log(8));
};

const slotsFor = (base) => {
  const s = SLOTS[base.category_slug];
  if (!s) return [];
  if (Array.isArray(s)) return s;
  const g = genderOf(base);
  return s[g === 'unisex' ? 'any' : g];
};

const completeLook = async (productId, { limit = 8 } = {}) => {
  const catalog = await getCatalog();
  const base = catalog.byId.get(Number(productId));
  if (!base) return null;

  if (!FASHION.has(base.category_slug)) {
    const items = (await boughtTogether(base.id, limit)) || [];
    return { base, kind: 'complementary', title: `Goes well with ${base.title}`, look: [], items, palette: null };
  }

  const slots = slotsFor(base);
  const baseColor = parseColor(base);
  const baseStyle = styleTerms(base);
  const query = [...baseStyle].join(' ') || styleText(base) || base.title;
  const { scores: semantic } = await catalog.semanticScores(`${query} outfit accessories`);
  const maxSem = Math.max(1e-6, ...[...semantic.values()]);

  const scored = catalog.products
    .filter((p) => p.id !== base.id && p.stock > 0 && slots.includes(p.category_slug))
    .map((p) => {
      const gender = genderFit(base, p);
      if (gender === 0) return null;
      const harmony = colorHarmony(baseColor, parseColor(p));
      const price = priceBand(base, p);
      const sem = (semantic.get(p.id) || 0) / maxSem;
      const shared = [...styleTerms(p)].filter((t) => baseStyle.has(t));
      const style = Math.min(1, 0.6 * sem + 0.4 * Math.min(1, shared.length / 2) + 0.2 * Math.max(0, catalog.similarity(base.id, p.id)));
      const score = 0.2 * gender + 0.24 * harmony.score + 0.16 * price + 0.15 * p._quality + 0.2 * style + 0.05 * p._popularity;
      return { p, score, gender, harmony, price, style, shared };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);

  const bySlot = new Map();
  for (const s of scored) {
    if (!bySlot.has(s.p.category_slug)) bySlot.set(s.p.category_slug, []);
    bySlot.get(s.p.category_slug).push(s);
  }

  const reasonsFor = (s) => [
    s.harmony.reason,
    s.gender === 1 ? `Matches the ${genderOf(base) === 'women' ? "women's" : "men's"} style of the ${base.category_name.toLowerCase().replace(/^(women|men)'s /, '')}` : null,
    s.shared.length ? `Also suits ${list(s.shared.slice(0, 2))}` : null,
    s.price > 0.7 ? `Similar price band (${money(s.p.price)})` : s.p.price < base.price * 0.5 ? `Affordable add-on at ${money(s.p.price)}` : null,
    s.p.rating >= 4 && s.p.rating_count >= 3 ? `Rated ${stars(s.p.rating)} by ${plural(s.p.rating_count, 'shopper')}` : null,
  ].filter(Boolean).slice(0, 4);

  const look = [];
  for (const slug of slots) {
    const ranked = bySlot.get(slug) || [];
    if (!ranked.length) continue;
    const [top, ...rest] = ranked;
    look.push({ role: ROLE[slug] || top.p.category_name, category: { slug, name: top.p.category_name }, item: { product: top.p, score: +Math.min(1, top.score).toFixed(3), reasons: reasonsFor(top) }, alternatives: rest.slice(0, 2).map((r) => r.p) });
  }
  // flat list: the slot winners first, then strong runners-up for a scrollable rail
  const used = new Set(look.map((l) => l.item.product.id));
  const extras = scored.filter((s) => !used.has(s.p.id)).slice(0, Math.max(0, limit - look.length))
    .map((s) => ({ product: s.p, score: +Math.min(1, s.score).toFixed(3), reasons: reasonsFor(s) }));
  const items = [...look.map((l) => l.item), ...extras].slice(0, limit);
  return {
    base,
    kind: 'outfit',
    title: `Complete the look: ${base.title}`,
    look,
    items,
    palette: baseColor ? { color: baseColor.label, family: baseColor.primary.hue !== undefined ? 'colour' : baseColor.primary.family, tip: paletteTip(baseColor) } : null,
  };
};

const paletteTip = (c) => {
  const x = c.primary;
  if (x.family === 'neutral') return `${cap(x.name)} is a neutral base: pair it with one bold accent colour or keep it all neutral.`;
  if (x.family === 'metal') return `Echo the ${x.name} tone in your jewellery and watch.`;
  if (x.family === 'multi') return 'A busy pattern looks best with plain, neutral accessories.';
  return `${cap(x.name)} works with neutrals (black, white, beige) or neighbouring shades for a softer look.`;
};

module.exports = { completeLook, colorHarmony, parseColor, FASHION, SLOTS };
