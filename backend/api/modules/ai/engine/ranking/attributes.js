// product attribute tags + use-case knowledge, so ranking understands "running shoes" = sneakers, never heels.
//
// deriveAttributes(p) runs once per product when the catalog index is built (deterministic: same product in,
// same tags out). it reads the title, category, tags, search keywords and a few spec fields and returns:
//   types  - what the product IS   (sneaker, heel, slipper, sandal, dress, gown, suit, charger, lamp, ...)
//   uses   - what it is FOR        (running, gym, sport, formal, office, party, wedding, casual, summer, ...)
//   colors - { primary, secondary[], all[], multi } colour families ("Red & Black" -> primary red, secondary black)
//   gender - 'men' | 'women' | 'unisex' | null (product field, else category: womens-* -> women)
//
// queryProfile(slots) turns what the shopper said into wanted/avoided tags (USE_CASES) and hard product types
// (TYPE_WORDS). constraintsFor(p, query) is what the ranker uses to keep clear constraint matches on top.
//
// to teach a new use-case or product type, add a line to USE_CASES / TYPE_WORDS / TYPE_RULES / USE_RULES below.
const L = require('../nlu/lexicon');
const { stem } = require('../nlu/normalizer');

// ------------------------------------------------------------------ product side

// type tags: matched on identity text (title, category, tags, keywords, type-ish specs) - never on prose
// such as "Air cushioning in the heel"
const TYPE_RULES = [
  ['sneaker', /\b(?:sneakers?|trainers?|athletic shoes|running shoes|gym shoes|sports shoes|casual sneaker|joggers?)\b/],
  ['heel', /\b(?:heels?|high heels|heel shoes|stilettos?|pumps?|block heels)\b/],
  ['slipper', /\b(?:slippers?|chappals?|flip flops?)\b/],
  ['sandal', /\b(?:sandals?)\b/],
  ['boot', /\b(?:boots?)\b/],
  ['cleat', /\b(?:cleats?)\b/],
  ['loafer', /\b(?:loafers?)\b/],
  ['dress', /\b(?:dress(?! watch| shirt| shoes)|dresses|frocks?|gowns?|maxi)\b/],
  ['gown', /\b(?:gowns?)\b/],
  ['suit', /\b(?:suits?|blazers?)\b/],
  ['skirt', /\b(?:skirts?)\b/],
  ['tshirt', /\b(?:t-?shirts?|tshirts?|tees?|graphic tee)\b/],
  ['shirt', /\b(?:shirts?)\b/],
  ['backpack', /\b(?:backpacks?)\b/],
  ['handbag', /\b(?:handbags?|purses?|tote bag|shoulder bag)\b/],
  ['smartwatch', /\b(?:smart ?watch(?:es)?|fitness tracker|apple watch)\b/],
  ['earphones', /\b(?:earbuds?|earphones?|airpods|neckband)\b/],
  ['headphones', /\b(?:headphones?|over ear)\b/],
  ['charger', /\b(?:chargers?|charging pad|charging mat|power adapter|wall adapter)\b/],
  ['case', /\b(?:phone case|phone cover|back cover|silicone case|mobile cover|protective case)\b/],
  ['lamp', /\b(?:lamps?|ring light|selfie light)\b/],
  ['speaker', /\b(?:speakers?|homepod|echo)\b/],
  ['kids', /\b(?:kids?|girls dress|girl frock|baby girl|children|ages \d+ to \d+|youth)\b/],
  ['fruit', /\b(?:fresh fruit|fruits|seasonal fruit|tropical fruit|summer fruit)\b/],
  ['vegetable', /\b(?:fresh vegetable|vegetables|veggies|sabzi)\b/],
];

// use tags: what a product is good for, read from keywords, tags, highlights and occasion-style specs
const USE_RULES = [
  ['running', /\b(?:running|jogging|marathon|runners?)\b/],
  ['gym', /\b(?:gym|workout|fitness|training shoes|exercise)\b/],
  ['sport', /\b(?:sports?|athletic|basketball|baseball|football|cricket|tennis)\b/],
  ['formal', /\b(?:formal|dress watch|executive|semi formal|tailored)\b/],
  ['office', /\b(?:office|work wear|workwear|work shirt|work bag|business|interview|professional)\b/],
  ['party', /\b(?:party|parties|cocktail|night out|club|clubs|nightclubs?|date night|glam|celebrations?)\b/],
  ['evening', /\b(?:evening|gala|galas|prom|dinner)\b/],
  ['wedding', /\b(?:wedding|weddings|bridal|walima|mehndi|reception|nikah|shaadi|festive)\b/],
  ['club', /\b(?:club wear|nightclubs?|concerts?|edgy)\b/],
  ['casual', /\b(?:casual|everyday|daily wear|daily use|day-to-day|weekend)\b/],
  ['summer', /\b(?:summer|beach|hot weather|spring and summer)\b/],
  ['winter', /\b(?:winter|autumn|warm|flannel|wool)\b/],
  ['travel', /\b(?:travel|portable|lightweight|compact|tourist|vacation|road trip)\b/],
  ['student', /\b(?:students?|college|school|university|campus|online classes|e-learning)\b/],
  ['programming', /\b(?:programming|developers?|coding|software)\b/],
  ['gaming', /\b(?:gaming|gamers?|esports|rtx|gpu)\b/],
  ['home', /\b(?:home|indoor|house slippers)\b/],
  ['kids', /\b(?:kids?|girls?|boys|children|baby|ages \d+ to \d+|youth)\b/],
  ['luxury', /\b(?:luxury|luxurious|designer|swiss|premium)\b/],
  ['selfie', /\b(?:selfies?|selfie phone|selfie camera|front camera|vlogging)\b/],
];

const TYPE_SPEC_KEYS = /^(?:product type|type|style|sport|cut|set includes)$/i;
const USE_SPEC_KEYS = /^(?:occasion|ideal for|best for|style|sport|season|suitable for)$/i;

// colour families, longest phrases first so "off white" wins over "white" and "rose gold" is gold, not pink
const COLOR_PHRASES = Object.entries(L.COLORS)
  .flatMap(([family, words]) => words.map((w) => [w, family]))
  .concat([['onyx', 'black'], ['charcoal', 'black'], ['platinum', 'silver'], ['steel', 'silver'], ['golden', 'gold'], ['gray', 'grey'], ['ivory', 'white'], ['burgundy', 'red']])
  .filter(([, family]) => family !== 'multicolor')
  .sort((a, b) => b[0].length - a[0].length);

const colorsIn = (text) => {
  let t = ` ${String(text || '').toLowerCase().replace(/[^a-z ]+/g, ' ')} `;
  const found = [];
  for (const [phrase, family] of COLOR_PHRASES) {
    const re = new RegExp(`\\s${phrase}\\s`);
    if (re.test(t)) {
      if (!found.includes(family)) found.push(family);
      t = t.replace(new RegExp(`\\s${phrase}(?=\\s)`, 'g'), ' ');
    }
  }
  return found;
};

const specValues = (p, keys) => Object.entries(p.specs || {}).filter(([k]) => keys.test(k)).map(([, v]) => String(v)).join(' ');

const productColors = (p) => {
  const listed = colorsIn(p.color);
  const named = colorsIn(`${p.title} ${specValues(p, /^(?:colou?r|colourway|colorway|shade)$/i)}`);
  const primary = listed[0] || named[0] || null;
  const all = [...new Set([...listed, ...named])];
  return { primary, secondary: all.filter((c) => c !== primary), all, multi: all.length > 1 };
};

const genderOf = (p) => {
  if (p.gender === 'men' || p.gender === 'women' || p.gender === 'unisex') return p.gender;
  if (/^mens-/.test(p.category_slug || '')) return 'men';
  if (/^womens-/.test(p.category_slug || '')) return 'women';
  return null;
};

const tagsFrom = (rules, text) => new Set(rules.filter(([, re]) => re.test(text)).map(([tag]) => tag));

const deriveAttributes = (p) => {
  const identity = [p.title, p.category_name, p.category_slug, (p.tags || []).join(' , '), p.search_keywords, specValues(p, TYPE_SPEC_KEYS)]
    .filter(Boolean).join(' , ').toLowerCase();
  const types = tagsFrom(TYPE_RULES, identity);
  // a heel height (and not "flat") makes it a heel even when the title doesn't say so
  const heel = Object.entries(p.specs || {}).find(([k]) => /^heel(?: height)?$/i.test(k));
  if (heel && !/\bflat\b/i.test(String(heel[1]))) types.add('heel');
  if (heel && /\bflat\b/i.test(String(heel[1])) && !/\bheels?\b/.test(String(p.search_keywords || '').toLowerCase())) types.delete('heel');
  if (types.has('tshirt')) types.delete('shirt');
  const useText = [identity, (p.highlights || []).join(' , '), specValues(p, USE_SPEC_KEYS)].join(' , ').toLowerCase();
  const uses = tagsFrom(USE_RULES, useText);
  return { types, uses, colors: productColors(p), gender: genderOf(p) };
};

const attrsOf = (p) => {
  if (!p._attrs) Object.defineProperty(p, '_attrs', { value: deriveAttributes(p), enumerable: false, writable: true });
  return p._attrs;
};

// ------------------------------------------------------------------ query side

// use-cases: query triggers -> wanted tags (soft boost) and avoided product types (pushed below compliant ones)
const USE_CASES = {
  running: { triggers: ['running', 'run', 'jogging', 'jog', 'marathon', 'runner', 'joggers'], want: ['running', 'sneaker', 'sport', 'gym'], avoid: ['heel', 'slipper', 'sandal', 'cleat', 'boot', 'loafer'] },
  gym: { triggers: ['gym', 'workout', 'exercise', 'fitness', 'training', 'bodybuilding'], want: ['gym', 'sport', 'sneaker', 'running'], avoid: ['heel', 'slipper', 'sandal', 'loafer'] },
  sport: { triggers: ['sports', 'athletic', 'athletics'], want: ['sport', 'sneaker', 'gym'], avoid: ['heel', 'slipper'] },
  office: { triggers: ['office', 'formal', 'meeting', 'interview', 'job', 'business', 'work'], want: ['office', 'formal'], avoid: ['slipper', 'club', 'kids', 'cleat'] },
  wedding: { triggers: ['wedding', 'shaadi', 'shadi', 'nikah', 'nikkah', 'reception', 'walima', 'mehndi', 'barat', 'bridal', 'engagement', 'marriage'], want: ['wedding', 'formal', 'evening'], avoid: ['slipper', 'cleat', 'kids', 'club'] },
  party: { triggers: ['party', 'evening', 'cocktail', 'clubbing', 'dinner', 'date', 'prom', 'gala'], want: ['party', 'evening'], avoid: ['slipper', 'cleat', 'kids'] },
  casual: { triggers: ['casual', 'everyday', 'daily', 'weekend'], want: ['casual'], avoid: ['gown'] },
  summer: { triggers: ['summer', 'garmi', 'beach', 'hot'], want: ['summer'], avoid: ['winter'] },
  winter: { triggers: ['winter', 'sardi', 'cold', 'warm'], want: ['winter'], avoid: ['summer'] },
  travel: { triggers: ['travel', 'trip', 'vacation', 'holiday', 'journey', 'tour', 'road'], want: ['travel'], avoid: [] },
  student: { triggers: ['university', 'uni', 'college', 'school', 'campus', 'student', 'students', 'study'], want: ['student'], avoid: [] },
  programming: { triggers: ['programming', 'coding', 'developer', 'developers', 'software', 'code'], want: ['programming'], avoid: [] },
  gaming: { triggers: ['gaming', 'gamer', 'games', 'game', 'pubg', 'esports'], want: ['gaming'], avoid: [] },
  home: { triggers: ['home', 'indoor', 'house'], want: ['home'], avoid: [] },
  luxury: { triggers: ['luxury', 'luxurious', 'designer', 'branded', 'premium'], want: ['luxury'], avoid: [] },
  selfie: { triggers: ['selfie', 'selfies', 'vlog', 'vlogging', 'vlogger'], want: ['selfie'], avoid: [] },
};

// explicit product-type words: when the shopper names one, products of that type rank above the rest.
// [query words, product types that satisfy them, optional types to keep out ("slippers" are never heels)]
const TYPE_WORDS = [
  [['sneaker', 'sneakers', 'trainer', 'trainers', 'jogger', 'joggers', 'running shoes', 'sports shoes', 'athletic shoes'], ['sneaker'], ['heel', 'slipper']],
  [['heel', 'heels', 'high heels', 'stiletto', 'stilettos', 'pumps'], ['heel']],
  [['slipper', 'slippers', 'chappal', 'chappals', 'flip flops'], ['slipper', 'sandal'], ['heel']],
  [['sandal', 'sandals'], ['sandal', 'slipper']],
  [['boot', 'boots'], ['boot']],
  [['loafer', 'loafers'], ['loafer']],
  [['cleats'], ['cleat']],
  [['gown', 'gowns'], ['gown']],
  [['t shirt', 'tshirt', 'tshirts', 't-shirt', 'tee', 'tees'], ['tshirt']],
  [['backpack', 'backpacks'], ['backpack']],
  [['handbag', 'handbags', 'purse'], ['handbag']],
  [['smartwatch', 'smart watch', 'fitness tracker'], ['smartwatch']],
  [['earbuds', 'earphones', 'earphone', 'airpods'], ['earphones']],
  [['headphones', 'headphone', 'headset'], ['headphones']],
  [['charger', 'chargers'], ['charger']],
  [['phone case', 'case', 'cover'], ['case']],
  [['lamp', 'lamps'], ['lamp']],
  [['speaker', 'speakers'], ['speaker']],
  [['fruit', 'fruits', 'phal'], ['fruit']],
  [['vegetable', 'vegetables', 'veggies', 'sabzi'], ['vegetable']],
];

// broad words that widen the category filter to every product of that type (frocks live under "tops")
const EXPAND_WORDS = [[['dress', 'dresses', 'frock', 'frocks', 'gown', 'gowns', 'maxi'], 'dress']];

const tokenize = (s) => String(s || '').toLowerCase().split(/[^a-z0-9-]+/).filter(Boolean);

const queryWords = (slots) => {
  const raw = [...(slots.terms || []), ...(slots.keywords || [])].join(' ');
  return { text: ` ${tokenize(raw).join(' ')} `, stems: new Set(tokenize(raw).map(stem)) };
};

const hasWord = (q, w) => (w.includes(' ') ? q.text.includes(` ${w} `) : q.text.includes(` ${w} `) || q.stems.has(stem(w)));

const FEATURE_USES = { running: 'running', gaming: 'gaming', work: 'office', lightweight: 'travel', luxury: 'luxury' };
const OCCASION_USES = { gym: 'gym', office: 'office', wedding: 'wedding', party: 'party', travel: 'travel', university: 'student', casual: 'casual', eid: 'wedding', anniversary: 'party' };

const queryProfile = (slots = {}) => {
  const q = queryWords(slots);
  const uses = new Set();
  for (const f of slots.features || []) if (FEATURE_USES[f]) uses.add(FEATURE_USES[f]);
  if (slots.occasion && OCCASION_USES[slots.occasion]) uses.add(OCCASION_USES[slots.occasion]);
  for (const [key, u] of Object.entries(USE_CASES)) if (u.triggers.some((t) => hasWord(q, t))) uses.add(key);
  // "programming" / "coding" arrive as the generic "work" feature: keep the specific use, drop office
  if (uses.has('programming') || uses.has('student')) uses.delete('office');
  const types = new Set();
  const typeAvoid = new Set();
  for (const [words, tags, keepOut = []] of TYPE_WORDS) {
    if (!words.some((w) => hasWord(q, w))) continue;
    tags.forEach((t) => types.add(t));
    keepOut.forEach((t) => typeAvoid.add(t));
  }
  const expand = new Set();
  for (const [words, tag] of EXPAND_WORDS) if (words.some((w) => hasWord(q, w))) expand.add(tag);
  const want = new Set();
  const avoid = new Set();
  for (const u of uses) {
    USE_CASES[u].want.forEach((t) => want.add(t));
    USE_CASES[u].avoid.forEach((t) => avoid.add(t));
  }
  for (const t of types) avoid.delete(t); // "heels for running" -> the shopper named heels, respect it
  for (const t of typeAvoid) if (!types.has(t)) avoid.add(t);
  return {
    uses: [...uses], want, avoid, types, expand,
    color: slots.color || null,
    gender: slots.gender && slots.gender !== 'any' ? slots.gender : null,
  };
};

// ------------------------------------------------------------------ matching

const hasAny = (set, items) => {
  for (const x of items) if (set.has(x)) return true;
  return false;
};

// 3 exact (only that colour) > 2 dominant (listed colour, multi-colour item) > 1 secondary ("Off White & Red") > 0
const colorTier = (p, color) => {
  if (!color) return null;
  const c = attrsOf(p).colors;
  if (c.primary === color) return c.multi ? 2 : 3;
  return c.all.includes(color) ? 1 : 0;
};

const genderFits = (p, gender) => {
  if (!gender) return true;
  const g = attrsOf(p).gender;
  return !g || g === 'unisex' || g === gender;
};

// how well a product fits the explicit constraints of the query
const constraintsFor = (p, query) => {
  const a = attrsOf(p);
  const tags = new Set([...a.types, ...a.uses]);
  const useHits = query.uses.filter((u) => USE_CASES[u].want.some((t) => tags.has(t))).length;
  return {
    avoidOk: !hasAny(tags, query.avoid),
    typeOk: !query.types.size || hasAny(a.types, query.types),
    colorTier: colorTier(p, query.color),
    genderOk: genderFits(p, query.gender),
    useFit: query.uses.length ? useHits / query.uses.length : null,
  };
};

// single sortable number: gender > avoided type > named type > colour tier (higher is better)
const tierOf = (c) => (c.genderOk ? 1000 : 0) + (c.avoidOk ? 100 : 0) + (c.typeOk ? 10 : 0) + (c.colorTier ?? 0);

module.exports = {
  deriveAttributes, attrsOf, productColors, colorsIn, genderOf, queryProfile, constraintsFor, tierOf, colorTier, genderFits,
  USE_CASES, TYPE_WORDS, TYPE_RULES, USE_RULES, EXPAND_WORDS,
};
