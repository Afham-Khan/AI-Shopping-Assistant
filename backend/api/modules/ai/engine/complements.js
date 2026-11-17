// shopper-sense rules shared by complete-the-look, cart insights, the gift finder and bundles:
// who an item is for (gender, children), novelty items, device compatibility (an iPhone 12 case does not fit an
// iPhone 13 Pro, a MagSafe pack does not work with a Samsung) and which products genuinely go together
// (a phone -> a case or earbuds, never another phone; a blender -> kitchen tools or ingredients, not a photo frame).
const { stars, plural } = require('./format');

// ------------------------------------------------------------------------------------------------ audience

const genderOf = (p) => {
  if (p.gender === 'men' || p.gender === 'women') return p.gender;
  if (/^womens-|^tops$/.test(p.category_slug || '')) return 'women';
  if (/^mens-/.test(p.category_slug || '')) return 'men';
  return 'unisex';
};
const OPPOSITE = { men: 'women', women: 'men' };
// true when the item is clearly for the other gender
const wrongGender = (p, gender) => Boolean(gender && OPPOSITE[gender] && genderOf(p) === OPPOSITE[gender]);

// children's products: "Girl Summer Dress", "Ideal For: Girls, ages 4 to 10"
const KIDS = /\b(?:girls?|boys?|kids?|children|toddlers?|baby|babies)\b|\bages? \d/i;
const isKidsItem = (p) => KIDS.test(`${p.title} ${p.specs?.['Ideal For'] || ''}`);
// the gender a children's item is for, if it says
const kidsGender = (p) => (/\bgirls?\b/i.test(`${p.title} ${p.specs?.['Ideal For'] || ''}`) ? 'women' : /\bboys?\b/i.test(`${p.title} ${p.specs?.['Ideal For'] || ''}`) ? 'men' : null);

// fun/costume pieces ("Party Glasses: fun novelty shapes, costume events") only suit parties
const isNovelty = (p) => /costume|novelty/i.test(`${p.specs?.Use || ''} ${p.specs?.Style || ''}`);

// ------------------------------------------------------------------------------------------------ accessories

// what kind of mobile accessory a product is
const accessoryKind = (p) => {
  if (p.category_slug !== 'mobile-accessories') return null;
  const t = `${p.title} ${p.specs?.Type || ''}`.toLowerCase();
  if (/pedestal|studio/.test(t)) return 'studio';
  if (/airpods|earphone|earbud|headphone|beats|\bbuds\b/.test(t)) return 'audio';
  if (/speaker|echo|homepod/.test(t)) return 'speaker';
  if (/\bcase\b|cover/.test(t)) return 'case';
  if (/power ?bank|battery pack/.test(t)) return 'power';
  if (/charg/.test(t)) return 'charger';
  if (/watch/.test(t)) return 'watch';
  if (/selfie|monopod|tripod|ring light|lamp/.test(t)) return 'camera';
  return 'other';
};

const DEVICE_ACCESSORIES = {
  smartphones: new Set(['audio', 'speaker', 'case', 'power', 'charger', 'watch', 'camera', 'other']),
  tablets: new Set(['audio', 'speaker', 'case', 'charger', 'other']),
  laptops: new Set(['audio', 'speaker']),
};
const DEVICES = new Set(Object.keys(DEVICE_ACCESSORIES));
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const appleOnly = (p) => {
  const c = String(p.specs?.Compatibility || '');
  return /iphone|ipad|\bmac\b|apple/i.test(c) && !/android|windows|universal|any /i.test(c);
};

// can this accessory be used with this device? (bluetooth audio works with anything)
const compatible = (device, acc) => {
  if (!DEVICES.has(device.category_slug) || acc.category_slug !== 'mobile-accessories') return true;
  const kind = accessoryKind(acc);
  if (kind === 'audio') return true;
  if (appleOnly(acc) && device.brand_name !== 'Apple') return false;
  // a case is made for one model: its compatibility must name this phone
  if (kind === 'case' && device.category_slug === 'smartphones') return norm(acc.specs?.Compatibility).includes(norm(device.title));
  return true;
};

// ------------------------------------------------------------------------------------------------ what goes with what

// stricter than "related": categories a shopper would actually add next to the base item
const GOES_WITH = {
  smartphones: ['mobile-accessories'],
  tablets: ['mobile-accessories'],
  laptops: ['mobile-accessories'],
  'mobile-accessories': ['mobile-accessories'],
  'mens-shirts': ['mens-shoes', 'mens-watches', 'sunglasses', 'fragrances'],
  'mens-shoes': ['mens-shirts', 'mens-watches', 'sunglasses'],
  'mens-watches': ['mens-shirts', 'mens-shoes', 'sunglasses', 'fragrances'],
  tops: ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses'],
  'womens-dresses': ['womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses', 'fragrances'],
  'womens-shoes': ['womens-dresses', 'tops', 'womens-bags', 'womens-jewellery'],
  'womens-bags': ['womens-jewellery', 'womens-watches', 'sunglasses', 'womens-shoes'],
  'womens-jewellery': ['womens-dresses', 'tops', 'womens-bags', 'fragrances'],
  'womens-watches': ['womens-jewellery', 'womens-bags', 'womens-dresses'],
  sunglasses: ['mens-watches', 'womens-bags', 'mens-shirts', 'tops'],
  beauty: ['beauty', 'skin-care', 'fragrances'],
  fragrances: ['beauty', 'skin-care'],
  'skin-care': ['skin-care', 'beauty', 'fragrances'],
  furniture: ['home-decoration', 'furniture'],
  'home-decoration': ['furniture', 'home-decoration'],
  'kitchen-accessories': ['kitchen-accessories', 'groceries'],
  groceries: ['groceries', 'kitchen-accessories'],
  'sports-accessories': ['sports-accessories', 'groceries'],
  motorcycle: ['sunglasses'],
  vehicle: ['mobile-accessories', 'sunglasses'],
};

const SPORT = /cricket|basketball|baseball|golf|tennis|football|volleyball|badminton|shuttlecock/i;
const sportOf = (p) => (`${p.title} ${(p.tags || []).join(' ')}`.match(SPORT)?.[0] || '').toLowerCase().replace('shuttlecock', 'badminton');
const GENERIC_TAGS = new Set(['electronics', 'fashion', 'beauty', 'groceries', 'furniture', 'watches', 'sports equipment', 'fashion accessories', 'personal care', 'clothing', 'footwear', 'eyewear']);
const subtypes = (p) => new Set((p.tags || []).map((t) => t.toLowerCase())
  .filter((t) => t !== p.category_slug && !GENERIC_TAGS.has(t) && t !== String(p.brand_name || '').toLowerCase()));
const sameSubtype = (a, b) => [...subtypes(a)].some((t) => subtypes(b).has(t));

// would a shopper buy b instead of a (another phone, another pair of earbuds, another perfume)?
const isSubstitute = (a, b) => {
  if (a.category_slug !== b.category_slug || a.category_slug === 'groceries') return false;
  if (DEVICES.has(a.category_slug) || ['fragrances', 'mens-shoes', 'womens-shoes', 'mens-watches', 'womens-watches', 'mens-shirts', 'womens-dresses', 'tops', 'furniture'].includes(a.category_slug)) return true;
  if (a.category_slug === 'mobile-accessories') return accessoryKind(a) === accessoryKind(b);
  // "Baseball Bat" and "Metal Baseball Bat" are the same thing; a bat and a ball are not
  if (a.category_slug === 'sports-accessories') return Boolean(sportOf(a)) && sportOf(a) === sportOf(b) && a.title.split(' ').pop().toLowerCase() === b.title.split(' ').pop().toLowerCase();
  return sameSubtype(a, b);
};

// does p genuinely go with base? (category, sport, device compatibility, gender, children, not a substitute)
const goesWith = (base, p) => {
  if (p.id === base.id || isSubstitute(base, p)) return false;
  if (isNovelty(p) && !isNovelty(base)) return false;
  if (!compatible(base, p) || !compatible(p, base)) return false;
  if (isKidsItem(p) !== isKidsItem(base) && (isKidsItem(p) || ['tops', 'womens-dresses', 'womens-shoes', 'mens-shoes'].includes(p.category_slug))) return false;
  const g = genderOf(base);
  if (g !== 'unisex' && wrongGender(p, g)) return false;
  if (base.category_slug === 'sports-accessories' && p.category_slug === 'sports-accessories') return Boolean(sportOf(base)) && sportOf(base) === sportOf(p);
  if (base.category_slug === 'sports-accessories' && p.category_slug === 'groceries') return /protein|water|juice|drink/i.test(p.title);
  if (DEVICES.has(base.category_slug) && p.category_slug === 'mobile-accessories') return DEVICE_ACCESSORIES[base.category_slug].has(accessoryKind(p));
  // accessory -> accessory: power and sound go with anything, camera gear only with camera gear; never a case
  // (without the phone we can't know it fits) and never another accessory of the same kind
  if (base.category_slug === 'mobile-accessories' && p.category_slug === 'mobile-accessories') {
    const a = accessoryKind(base);
    const b = accessoryKind(p);
    return a !== b && (['charger', 'power', 'audio', 'speaker'].includes(b) || (a === 'camera' && b === 'camera'));
  }
  return (GOES_WITH[base.category_slug] || []).includes(p.category_slug);
};

const qualityReason = (p) => (p.rating >= 4 && p.rating_count >= 3 ? `Rated ${stars(p.rating)} by ${plural(p.rating_count, 'shopper')}` : null);

// items that go with base: association-rule picks (seed, e.g. from bought-together) that pass goesWith first,
// then the best-rated complementary products, at most 2 per category. options.accept adds an extra filter.
const complementaryFor = (base, catalog, { limit = 6, seed = [], exclude = new Set(), accept = () => true } = {}) => {
  const ok = (p) => p && p.stock > 0 && !exclude.has(p.id) && goesWith(base, p) && accept(p);
  const out = [];
  const have = new Set();
  const counts = new Map();
  // at most 2 per category (per accessory kind for gadgets, so a phone can get a case, a charger and earbuds)
  const push = (item) => {
    const c = `${item.product.category_slug}:${accessoryKind(item.product) || ''}`;
    if (have.has(item.product.id) || (counts.get(c) || 0) >= 2) return;
    have.add(item.product.id);
    counts.set(c, (counts.get(c) || 0) + 1);
    out.push(item);
  };
  for (const s of seed) if (out.length < limit && ok(s.product)) push(s);
  if (out.length < limit) {
    const order = GOES_WITH[base.category_slug] || [];
    const fill = catalog.products
      .filter(ok)
      .map((p) => {
        const rank = Math.max(0, order.indexOf(p.category_slug));
        const cheaper = p.price <= base.price ? 1 : 0.4;
        return { p, score: 0.3 * (1 - rank * 0.15) + 0.3 * (p._quality ?? 0.5) + 0.2 * (p._popularity ?? 0) + 0.15 * cheaper + 0.05 * (p._discount ?? 0) };
      })
      .sort((a, b) => b.score - a.score);
    for (const f of fill) {
      if (out.length >= limit) break;
      push({ product: f.p, score: +Math.max(0, Math.min(1, f.score * 0.8)).toFixed(3), reasons: [`Goes well with ${String(base.category_name || 'it').toLowerCase()}`, qualityReason(f.p)].filter(Boolean) });
    }
  }
  return out.slice(0, limit);
};

module.exports = {
  genderOf, wrongGender, isKidsItem, kidsGender, isNovelty, accessoryKind, compatible, isSubstitute, goesWith, complementaryFor, sportOf, sameSubtype, GOES_WITH,
};
