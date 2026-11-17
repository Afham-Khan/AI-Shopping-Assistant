// gift finder: recipient (gender + age band), occasion, budget and interests -> a curated, diverse gift
// collection with reasons. shared by POST /ai/gift and the chat gift flow.
const L = require('./nlu/lexicon');
const { analyze } = require('./nlu');
const { getCatalog } = require('./retrieval/catalog');
const { money, shortMoney, stars, plural, list, titleCase } = require('./format');
const { isKidsItem, kidsGender, isNovelty, accessoryKind, genderOf } = require('./complements');

// never a good blind gift: model-specific accessories, chargers, studio gear, household consumables
const UNGIFTABLE = /\bcase\b|\bcover\b|charger|battery pack|power ?bank|pedestal|tissue/i;
// fine for a child: sport and play, tablets, headphones and children's clothing
const kidFriendly = (p) => isKidsItem(p) || ['sports-accessories', 'tablets'].includes(p.category_slug) || accessoryKind(p) === 'audio';

const AGE_BY_RECIPIENT = {
  kid: 'kid', son: 'kid', daughter: 'kid', nephew: 'kid', niece: 'kid',
  grandma: 'senior', grandmother: 'senior', grandpa: 'senior', grandfather: 'senior',
};

// interest words -> catalog categories ({ women, men } picks the gendered variant); an optional 4th regex says which
// products really serve the interest (default: the interest regex itself over title, "ideal for", type and tags)
const INTERESTS = [
  [/\b(?:make ?up|cosmetics?|lipstick|beauty|mascara|nails?)\b/, 'makeup', ['beauty']],
  [/\b(?:skin ?care|skincare|skin|self ?care|spa|pamper)\b/, 'skincare', ['skin-care']],
  [/\b(?:perfumes?|fragrances?|scents?|cologne|attar|itar|khushbu)\b/, 'fragrances', ['fragrances']],
  [/\b(?:jewell?e?ry|necklace|earrings?|rings?|bracelets?)\b/, 'jewellery', ['womens-jewellery']],
  [/\b(?:bags?|handbags?|purses?|clutch)\b/, 'bags', ['womens-bags']],
  [/\b(?:watch|watches|timepieces?)\b/, 'watches', [{ women: 'womens-watches', men: 'mens-watches' }]],
  [/\b(?:shoes|sneakers|heels|footwear)\b/, 'shoes', [{ women: 'womens-shoes', men: 'mens-shoes' }]],
  [/\b(?:fashion|style|clothes|clothing|dress(?:es)?|outfits?|shopping)\b/, 'fashion', [{ women: 'womens-dresses', men: 'mens-shirts' }, { women: 'tops', men: 'mens-shoes' }, 'sunglasses']],
  [/\b(?:sunglasses|shades|eyewear)\b/, 'sunglasses', ['sunglasses']],
  [/\b(?:tech|gadgets?|electronics|phones?|mobiles?|music|headphones|earbuds|apple)\b/, 'tech', ['mobile-accessories', 'tablets', 'smartphones']],
  [/\b(?:gam(?:ing|es?|ers?)|playstation|pubg)\b/, 'gaming', ['mobile-accessories', 'tablets', 'laptops'], /\bgam(?:ing|es?|ers?)\b|headphone|earphone|earbud|airpods|beats|ipad|tablet/],
  [/\b(?:study|studies|student|university|college|coding|programming|work|office)\b/, 'study & work', ['laptops', 'tablets', 'mobile-accessories']],
  [/\b(?:photography|photos?|camera|vlogg?ing)\b/, 'photography', ['smartphones', 'mobile-accessories']],
  [/\b(?:fitness|gym|workout|sports?|cricket|football|tennis|running|yoga|golf|basketball)\b/, 'sports', ['sports-accessories']],
  [/\b(?:cook(?:ing)?|bak(?:ing|e)|kitchen|chef|food)\b/, 'cooking', ['kitchen-accessories']],
  [/\b(?:home|decor|interior|plants?|gardening|cosy|cozy)\b/, 'home decor', ['home-decoration', 'furniture']],
  [/\b(?:coffee|tea|chocolates?|snacks?|sweets?|honey)\b/, 'treats', ['groceries']],
  [/\b(?:travel(?:ling)?|trips?|travelling)\b/, 'travel', ['sunglasses', 'mobile-accessories', 'womens-bags']],
  [/\b(?:bikes?|motorcycles?|riding)\b/, 'riding', ['motorcycle', 'sports-accessories']],
  [/\b(?:cars?|driving)\b/, 'cars', ['mobile-accessories', 'sunglasses']],
];

const OCCASION_CATEGORIES = {
  wedding: ['womens-jewellery', 'mens-watches', 'womens-watches', 'fragrances', 'home-decoration', 'kitchen-accessories'],
  anniversary: ['womens-jewellery', 'womens-watches', 'mens-watches', 'fragrances'],
  eid: ['fragrances', 'womens-jewellery', 'womens-dresses', 'mens-shirts', 'mens-watches'],
  party: ['fragrances', 'womens-jewellery', 'beauty', 'sunglasses'],
  university: ['mobile-accessories', 'tablets', 'laptops'],
  office: ['mens-watches', 'womens-watches', 'mobile-accessories', 'womens-bags'],
  travel: ['sunglasses', 'mobile-accessories', 'womens-bags'],
  gym: ['sports-accessories'],
  birthday: [],
  casual: [],
};
const OCCASION_ALIASES = { graduation: 'university', housewarming: 'home', valentine: 'party', valentines: 'party', 'new home': 'home', farewell: 'office', christmas: 'party' };
const EXTRA_OCCASION = { home: ['home-decoration', 'kitchen-accessories', 'furniture'] };

// how naturally a category reads as a gift (prior, 0..1)
const GIFTABILITY = {
  fragrances: 1, 'womens-jewellery': 1, 'womens-watches': 0.95, 'mens-watches': 0.95, 'womens-bags': 0.9, sunglasses: 0.8,
  beauty: 0.8, 'skin-care': 0.75, 'mobile-accessories': 0.8, tablets: 0.75, 'home-decoration': 0.75, 'kitchen-accessories': 0.6,
  'sports-accessories': 0.7, 'womens-dresses': 0.6, tops: 0.55, 'mens-shirts': 0.55, 'mens-shoes': 0.5, 'womens-shoes': 0.5,
  smartphones: 0.7, laptops: 0.6, furniture: 0.35, groceries: 0.3, motorcycle: 0.2, vehicle: 0.05,
};
const NEVER_UNLESS_ASKED = new Set(['vehicle', 'motorcycle', 'groceries', 'furniture']);
const KID_CATEGORIES = ['sports-accessories', 'tablets', 'mobile-accessories'];

const normRecipient = (raw) => {
  const w = String(raw || '').toLowerCase().trim().replace(/^(?:my|for|mera|meri|mere)\s+/, '').replace(/\s+/g, ' ');
  const mapped = L.ROMAN_URDU[w] || w;
  if (L.RECIPIENTS[mapped] !== undefined) return mapped;
  const hit = Object.keys(L.RECIPIENTS).find((r) => new RegExp(`\\b${r}\\b`).test(mapped));
  if (hit) return hit;
  if (/\b(?:girl|woman|lady|female)\b/.test(mapped)) return 'her';
  if (/\b(?:boy|man|guy|male)\b/.test(mapped)) return 'him';
  return mapped || null;
};

const ageBandOf = (recipient, age) => {
  if (Number.isFinite(age)) return age < 13 ? 'kid' : age < 20 ? 'teen' : age < 60 ? 'adult' : 'senior';
  return AGE_BY_RECIPIENT[recipient] || 'adult';
};

const resolveSlug = (entry, gender) => {
  if (typeof entry === 'string') return [entry];
  return gender ? [entry[gender]] : [entry.women, entry.men];
};

// interest phrases -> [{ label, categories }]
const mapInterests = (interests, gender) => {
  const out = [];
  for (const raw of interests) {
    const text = String(raw || '').toLowerCase();
    if (!text.trim() || /\b(?:surprise|anything|no idea|not sure|koi bhi|whatever)\b/.test(text)) continue;
    let matched = false;
    for (const [re, label, cats, fits] of INTERESTS) {
      if (!re.test(text)) continue;
      out.push({ label, raw: raw.trim(), categories: cats.flatMap((c) => resolveSlug(c, gender)), re: fits || re });
      matched = true;
    }
    if (!matched) {
      // fall back to the nlu taxonomy ("sneakers", "ipad", "kitchen stuff")
      const e = analyze(text).entities;
      if (e.categories.length) out.push({ label: raw.trim(), raw: raw.trim(), categories: e.categories });
      else out.push({ label: raw.trim(), raw: raw.trim(), categories: [], semantic: true });
    }
  }
  return out;
};

const budgetFit = (price, budget) => {
  if (!budget?.max) return 0.7;
  if (price > budget.max) return 0;
  // gifts that use a good part of the budget feel generous; tiny items less so
  return 0.35 + 0.65 * Math.min(1, price / (0.85 * budget.max));
};

const pronoun = (gender) => (gender === 'women' ? 'her' : gender === 'men' ? 'him' : 'them');
const possessive = (gender) => (gender === 'women' ? 'her' : gender === 'men' ? 'his' : 'their');

// args: { recipient, gender?, occasion?, budget? {min,max}|number, interests?: string[], categories?: string[], age?, text?, limit? }
const buildGift = async (args) => {
  const catalog = await getCatalog();
  const recipient = normRecipient(args.recipient);
  const gender = args.gender || (recipient ? L.RECIPIENTS[recipient] : null) || null;
  const ageBand = ageBandOf(recipient, args.age);
  const rawOccasion = args.occasion ? String(args.occasion).toLowerCase().trim() : null;
  const occasion = rawOccasion ? (OCCASION_ALIASES[rawOccasion] || Object.keys(L.OCCASIONS).find((k) => k === rawOccasion || L.OCCASIONS[k].triggers.includes(rawOccasion)) || rawOccasion) : null;
  let budget = args.budget ?? null;
  if (typeof budget === 'number') budget = { min: null, max: budget };
  const interests = mapInterests(args.interests || [], gender);
  const interestCats = new Map();
  for (const i of interests) for (const c of i.categories) if (!interestCats.has(c)) interestCats.set(c, i.label);
  for (const c of args.categories || []) if (!interestCats.has(c)) interestCats.set(c, catalog.taxonomy.find((t) => t.slug === c)?.name.toLowerCase() || c);

  const genericKey = ageBand === 'kid' ? 'kid' : gender || 'any';
  const generic = new Set(L.GIFT_CATEGORIES[genericKey] || L.GIFT_CATEGORIES.any);
  const occasionCats = new Set([...(OCCASION_CATEGORIES[occasion] || []), ...(EXTRA_OCCASION[occasion] || [])]);

  // an interest can also be met by what a product is for ("Gigabyte Aorus tee — ideal for gamers")
  const interestText = (p) => interests.find((i) => i.re && i.re.test(`${p.title} ${p.specs?.['Ideal For'] || ''} ${p.specs?.Type || ''} ${(p.tags || []).join(' ')}`.toLowerCase())) || null;

  const semanticText = [args.text, 'gift', occasion, recipient, ...interests.map((i) => i.raw)].filter(Boolean).join(' ');
  const { scores: semantic } = await catalog.semanticScores(semanticText);
  const maxSem = Math.max(1e-6, ...[...semantic.values()]);

  const opposite = gender === 'women' ? 'men' : gender === 'men' ? 'women' : null;
  const wants = (re) => interests.some((i) => re.test(i.label) || re.test(i.raw));
  const partyish = /party|birthday/.test(rawOccasion || '') || wants(/party|fun|costume/);
  const eligible = (p, strict) => {
    if (p.stock <= 0) return false;
    if (UNGIFTABLE.test(p.title)) return false;
    if (isNovelty(p) && !partyish) return false;
    if (['camera', 'studio'].includes(accessoryKind(p)) && !wants(/photo|travel|tech|vlog|camera|selfie/)) return false;
    // children get children's things; adults never get children's clothing
    if (ageBand === 'kid') {
      if (!kidFriendly(p)) return false;
      if (isKidsItem(p) && gender && kidsGender(p) && kidsGender(p) !== gender) return false;
    } else if (isKidsItem(p)) return false;
    if (budget?.max && p.price > budget.max) return false;
    if (budget?.min && p.price < budget.min) return false;
    if (opposite && (p.gender === opposite || p.category_slug.startsWith(`${opposite === 'men' ? 'mens' : 'womens'}-`))) return false;
    if (NEVER_UNLESS_ASKED.has(p.category_slug) && !interestCats.has(p.category_slug)) return false;
    if (!strict) return true;
    // interests lead, but giftable generic picks can fill the rest of the collection
    return interestCats.has(p.category_slug) || generic.has(p.category_slug) || occasionCats.has(p.category_slug) || interestText(p) || (ageBand === 'kid' && (KID_CATEGORIES.includes(p.category_slug) || isKidsItem(p)));
  };

  let pool = catalog.products.filter((p) => eligible(p, true));
  let relaxed = false;
  if (pool.length < 4) {
    pool = catalog.products.filter((p) => eligible(p, false));
    relaxed = true;
  }

  const scored = pool.map((p) => {
    const byText = interestText(p);
    // a product made for the interest beats one that only shares its broad category (a gamer tee vs a smart speaker)
    const interest = byText ? 1 : interestCats.has(p.category_slug) ? 0.6 : 0;
    const occ = occasionCats.has(p.category_slug) ? 1 : 0;
    const catFit = interest ? 1 : occ ? 0.75 : generic.has(p.category_slug) ? 0.55 : 0.3;
    const sem = (semantic.get(p.id) || 0) / maxSem;
    // a child's own things (a girls' dress for a daughter) beat generic sports gear
    const kidFit = ageBand === 'kid' ? (isKidsItem(p) ? 1.25 : KID_CATEGORIES.includes(p.category_slug) ? 1 : 0.3) : 1;
    // recipient's gender unknown (boss, friend, colleague): prefer pieces anyone can use
    const neutral = !gender && genderOf(p) !== 'unisex' ? 0.65 : 1;
    const score = (0.3 * catFit + 0.25 * interest + 0.12 * occ + 0.24 * budgetFit(p.price, budget) + 0.18 * p._quality + 0.08 * p._popularity
      + 0.1 * (GIFTABILITY[p.category_slug] ?? 0.5) + 0.12 * sem + 0.04 * p._discount) * kidFit * neutral;
    return { p, score, interest, occ, interestLabel: interestCats.get(p.category_slug) || byText?.label };
  }).sort((a, b) => b.score - a.score);

  // at most 2 per category so the collection feels curated, not a single-category list
  const limit = args.limit || 8;
  const counts = new Map();
  const picked = [];
  // a single interest category may fill up to 3 slots; everything else at most 2
  const capFor = (slug) => (interestCats.size === 1 && interestCats.has(slug) ? 3 : 2);
  for (const s of scored) {
    const c = counts.get(s.p.category_slug) || 0;
    if (c >= capFor(s.p.category_slug)) continue;
    counts.set(s.p.category_slug, c + 1);
    picked.push(s);
    if (picked.length >= limit) break;
  }
  // few suitable categories (a child's gift, a small budget): fill up with the next best rather than show 2 ideas
  if (picked.length < Math.min(limit, 6)) {
    for (const s of scored) {
      if (picked.length >= Math.min(limit, 6)) break;
      if (!picked.includes(s) && (counts.get(s.p.category_slug) || 0) < capFor(s.p.category_slug) + 2) {
        counts.set(s.p.category_slug, (counts.get(s.p.category_slug) || 0) + 1);
        picked.push(s);
      }
    }
  }

  const who = recipient && !['her', 'him', 'them'].includes(recipient) ? `your ${recipient}` : pronoun(gender);
  const occasionLabel = occasion ? (occasion === 'eid' ? 'Eid' : titleCase(occasion)) : null;
  const items = picked.map((s) => ({
    product: s.p,
    score: +Math.max(0, Math.min(1, s.score)).toFixed(3),
    reasons: [
      s.interest ? `Matches ${possessive(gender)} love of ${s.interestLabel}` : null,
      occasionLabel && (s.occ || !s.interest) ? `${s.occ ? 'A classic' : 'A thoughtful'} ${occasionLabel === 'Eid' ? 'Eid' : occasionLabel.toLowerCase()} gift` : null,
      budget?.max ? `Within your ${money(budget.max)} budget` : null,
      s.p.sold_count >= catalog.bestsellerCut ? `Popular pick, ${s.p.sold_count} sold` : null,
      s.p.rating >= 4 && s.p.rating_count >= 3 ? `Rated ${stars(s.p.rating)} by ${plural(s.p.rating_count, 'shopper')}` : null,
      s.p.discount_percent >= 10 ? `${Math.round(s.p.discount_percent)}% off right now` : null,
    ].filter(Boolean).slice(0, 4),
  }));

  const cats = [...new Set(items.map((i) => i.product.category_name.toLowerCase()))].slice(0, 3);
  const title = `${occasionLabel ? `${occasionLabel} gifts` : 'Gift ideas'} for ${who}${budget?.max ? ` under ${shortMoney(budget.max)}` : ''}`;
  let note = items.length
    ? `A curated mix of ${list(cats)}${budget?.max ? `, all within ${money(budget.max)}` : ''}${interests.length ? `, picked around ${possessive(gender)} interest in ${list(interests.map((i) => i.label))}` : ''}.`
    : `I couldn't find gifts${budget?.max ? ` under ${money(budget.max)}` : ''} for that combination. Try a higher budget or a different interest.`;
  if (relaxed && items.length) note += ' I widened the search a little to find enough good options.';
  // a two-item combo that still fits the budget
  if (budget?.max && items.length >= 2) {
    const top = items[0].product;
    const partner = items.slice(1).map((i) => i.product)
      .filter((p) => p.category_slug !== top.category_slug && top.price + p.price <= budget.max)
      .sort((a, b) => b.price - a.price)[0];
    if (partner) note += ` Want to go bigger? ${top.title} + ${partner.title} together come to ${money(top.price + partner.price)}.`;
  }
  return {
    title,
    note,
    items,
    criteria: {
      recipient, gender, ageBand, occasion, budget,
      interests: interests.map((i) => ({ input: i.raw, matched: i.label, categories: i.categories })),
      categories: [...new Set(items.map((i) => i.product.category_slug))],
    },
    relaxed,
  };
};

module.exports = { buildGift, mapInterests, normRecipient, ageBandOf };
