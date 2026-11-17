// template nlg with variation: short, friendly, bold for prices/key facts, explains the top pick
const L = require('../nlu/lexicon');
const { money, stars, list, pick, titleCase, truncate } = require('../format');
const { TYPE_WORDS } = require('../ranking/attributes');

// lowercase only generic sentence starters, never brand or product names
const GENERIC_START = /^(?:Great|Within|Rated|Comes|Bestseller|Similar|Matches|Suited|Nice|Above|Also|Popular|Trending|Goes|Bought|Reviewers|Related|Close|Top|Based|Because|Highest|Lowest|Cheapest)\b/;
const lower = (s) => (s && GENERIC_START.test(s) ? s.charAt(0).toLowerCase() + s.slice(1) : s || '');

const categoryNames = (slots, catalog) =>
  (slots.categories || []).map((c) => catalog?.taxonomy.find((t) => t.slug === c)?.name || L.CATEGORY_NAMES[c] || c);

// plural product-type words the shopper typed ("heels", "sneakers") read better than the category name ("shoes")
const TYPE_NOUNS = new Set(TYPE_WORDS.flatMap(([words]) => words).filter((w) => /^[a-z]+s$/.test(w)));
const typeNoun = (slots) => (slots.terms || []).find((t) => TYPE_NOUNS.has(t)) || null;

// "gaming Samsung smartphones in black for women"
const describe = (slots, catalog, { plural = true } = {}) => {
  const parts = [];
  const feats = (slots.features || []).map((f) => L.FEATURES[f]?.label || f).filter((f) => f.split(' ').length <= 2);
  if (feats.length) parts.push(feats.slice(0, 2).join(' & '));
  if (slots.brands?.length) parts.push(list(slots.brands.map((b) => titleCase(b)), 'or'));
  let noun = null;
  const cats = categoryNames(slots, catalog);
  // men's + women's shoes -> "shoes" (never "shoes or shoes")
  const nouns = [...new Set(cats.map((c) => c.replace(/^(Men's|Women's) /, '')))];
  if (cats.length) noun = typeNoun(slots) || (nouns.length > 2 ? 'items' : list(nouns, 'or'));
  else if (slots.department) noun = catalog?.taxonomy.find((t) => t.departmentSlug === slots.department)?.departmentName || 'products';
  else if (slots.keywords?.length) noun = slots.keywords.join(' ');
  noun = noun || (plural ? 'options' : 'option');
  parts.push(slots.categories?.length || slots.department ? noun.toLowerCase() : noun);
  let text = parts.join(' ');
  if (slots.color) text += ` in ${slots.color}`;
  if (slots.recipient) text += ['her', 'him', 'she'].includes(slots.recipient) ? ` for ${slots.recipient === 'she' ? 'her' : slots.recipient}` : ` for your ${slots.recipient}`;
  else if (slots.gender) text += ` for ${slots.gender}`;
  if (slots.occasion) text += slots.occasion === 'eid' ? ' for Eid' : ` for ${slots.occasion === 'gym' || slots.occasion === 'office' || slots.occasion === 'university' || slots.occasion === 'travel' ? '' : 'a '}${slots.occasion}`;
  return text.replace(/\s+/g, ' ').trim();
};

const budgetPhrase = (b) => {
  if (!b) return '';
  if (b.target) return `around **${money(b.target)}**`;
  if (b.min && b.max) return `between **${money(b.min)}** and **${money(b.max)}**`;
  if (b.max) return `under **${money(b.max)}**`;
  if (b.min) return `above **${money(b.min)}**`;
  return '';
};

const exclusionPhrase = (slots) => {
  const parts = [];
  if (slots.excludeBrands?.length) parts.push(`no ${list(slots.excludeBrands.map(titleCase), 'or')}`);
  if (slots.excludeColors?.length) parts.push(`nothing ${list(slots.excludeColors, 'or')}`);
  return parts.length ? ` (${parts.join(', ')})` : '';
};

// the reply always describes the FIRST card; `closest` words it honestly when that card only partly matches
const topPickLine = (item, seed, { closest = null } = {}) => {
  if (!item) return '';
  const p = item.product;
  const why = item.reasons?.find((r) => !/^Within your/.test(r)) || item.reasons?.[0];
  const opener = closest ? `The closest ${closest} is` : pick(['My top pick is', 'Best match:', 'I\'d start with', 'Top of the list is'], seed);
  return `${opener} **${p.title}** at **${money(p.price)}**${why ? ` — ${lower(why)}` : ''}.`;
};

// is a shown item an exact match for the explicit constraints (named type, colour)? null = nothing to check
const exactFit = (item) => {
  const f = item.fit;
  if (!f) return null;
  return f.typeOk !== false && f.avoidOk !== false && (f.colorTier == null || f.colorTier >= 1);
};

// honest wording when the catalogue can't fully satisfy the request ("only 2 of these come in red")
const fitNote = (slots, items) => {
  const checks = items.map(exactFit);
  if (!items.length || checks.every((c) => c === null)) return { note: '', closest: null, none: false };
  const k = checks.filter(Boolean).length;
  const top = items[0].fit || {};
  const colorPartial = slots.color && top.colorTier != null && top.colorTier < 3;
  const closest = slots.color && (k === 0 || colorPartial) ? `in ${slots.color}` : k === 0 ? 'match' : null;
  if (k === 0) return { note: `I couldn't find an exact match${slots.color ? ` in ${slots.color}` : ''}, so here are the closest options.`, closest, none: true };
  if (k < items.length) {
    const what = slots.color ? `${k === 1 ? 'comes' : 'come'} in ${slots.color}` : `${k === 1 ? 'is an exact match' : 'are exact matches'}`;
    return { note: `${k === 1 ? 'Only one' : `Only ${k}`} of these ${what}; the rest are the closest alternatives.`, closest, none: false };
  }
  return { note: '', closest, none: false };
};

const searchReply = ({ slots, result, catalog, seed, intent, shownFrom = 0 }) => {
  const n = result.items.length;
  const fit = fitNote(slots, result.items);
  // not every card is an exact match: don't promise "5 dresses in red" / "5 running shoes" above cards that aren't
  const partial = Boolean(fit.note);
  const what = describe(partial ? { ...slots, color: null, features: [], terms: [] } : slots, catalog);
  const budget = budgetPhrase(slots.budget);
  const lines = [];
  if (result.relaxed.length) lines.push(result.relaxed.map((r) => r.message).join(' '));
  if (fit.none) lines.push(fit.note);
  const intro = {
    refine_cheaper: pick([`Here are more affordable ${what}`, `Cheaper ${what} coming up`, `Okay, going lower on price — ${what}`], seed),
    refine_premium: pick([`Stepping up to more premium ${what}`, `Here are higher-end ${what}`, `Premium ${what} for you`], seed),
    show_more: n === 1 ? `Here is one more of the ${what}` : `Here are ${n} more ${what}`,
    recommendation: n === 1 ? `My recommendation from the ${what}` : pick([`Here's what I'd recommend — ${n} ${what}`, `My recommendations: ${n} ${what}`, `These ${n} ${what} stand out`], seed),
    gift_suggestion: pick([`Here are ${n} gift ideas ${slots.recipient ? `for your ${slots.recipient}` : ''}`, `Some thoughtful gift picks${slots.recipient ? ` for your ${slots.recipient}` : ''}`], seed),
  }[intent] || (n === 1 ? `Only one match for ${what}` : partial ? `Here are ${n} ${what}` : pick([`Here are ${n} ${what}`, `I found ${result.total} ${what}; here are the top ${n}`, `Take a look at these ${n} ${what}`], seed));
  const sortText = slots.sort ? { price_asc: ', cheapest first', price_desc: ', priciest first', rating: ', best rated first', popular: ', most popular first', newest: ', newest first', discount: ', biggest discounts first' }[slots.sort] || '' : '';
  lines.push(`${intro.replace(/\s+/g, ' ').trim()}${budget && !result.relaxed.some((r) => r.type === 'budget') ? ` ${budget}` : ''}${exclusionPhrase(slots)}${sortText}:`);
  if (shownFrom === 0 || intent !== 'show_more') lines.push(topPickLine(result.items[0], seed, { closest: fit.closest }));
  if (!fit.none && fit.note) lines.push(fit.note);
  return lines.filter(Boolean).join(' ');
};

const noMatchReply = (slots) => {
  const term = (slots.keywords || []).join(' ');
  return `I couldn't find anything matching **${term || 'that'}** in our catalog. Try a category like phones, perfumes or kitchen items — or describe what it's for.`;
};

const greeting = (name, seed) => pick([
  `Hi${name ? ` ${name}` : ''}! I'm Zel, Zelora's shopping assistant. Tell me what you're shopping for — like *gaming laptop under 300k* or *a gift for my mom*.`,
  `Hello${name ? ` ${name}` : ''}! What can I help you find today? I understand budgets, brands and even Roman Urdu.`,
  `Hey${name ? ` ${name}` : ''}! Looking for something specific, or want me to suggest a few things?`,
], seed);

const HELP = [
  "I'm **Zel**, your Zelora shopping assistant. I can:",
  '• find products from plain language — *red running shoes for women under 15k*',
  '• recommend picks for you and suggest **gifts** by recipient, occasion and budget',
  '• **compare** products and pick the best value',
  '• summarize **reviews** and answer about any product I show',
  '• check your **order status**, **cart total**, today\'s **deals** and **return policy**',
  'I understand typos and Roman Urdu too (*sasta mobile chahiye 30k tak*).',
].join('\n');

const SMALL_TALK = [
  [/how are you|kaise ho|kya haal|kaisa hai|how is your day|how's it going|how is it going|what'?s up|wassup/, ["I'm doing great and ready to shop! What are you looking for today?", "All good here, thanks for asking! What can I find for you?"]],
  [/joke/, ['Why did the shopping cart go to therapy? It had too much baggage! Speaking of carts, want me to find you something?']],
  [/weather|mausam/, ["I can't check the weather, but I can find you sunglasses for sunny days. What do you need?"]],
  [/love you|love me|marry|married|cute|crush/, ["That's sweet! My heart belongs to great deals though. Can I find you something nice?"]],
  [/bored/, ["Let's fix that with some window shopping! Want to see today's biggest deals or what's trending?"]],
  [/stupid|bad bot|useless/, ["Sorry I missed the mark. Try telling me the product, budget or brand you want and I'll do better."]],
  [/good bot|smart|clever|awesome|amazing|you are funny|you'?re funny|nice talking/, ['Thank you, that made my day! Want to put me to work on something?']],
  [/\b(?:lol|haha\w*|hehe\w*|lmao|rofl)\b/, ['Glad I made you smile! Want me to find something fun next?', 'Ha! Happy shopper, happy Zel. What should we look for?']],
  [/^(?:ok|okay|k|kk|cool|nice|fine|alright|hmm+|hm+|sure|got it|wow|great|acha|achha|theek|thik|ok cool|hmm ok|nice nice|good|ok then)\b/, ["Got it! Whenever you're ready, tell me what you're looking for, or pick one below.", "Sure thing! What should we shop for next?"]],
  [/are you there|you there|anyone there|hello\?/, ["I'm here! What can I help you find?"]],
  [/never ?mind|forget it|nothing|kuch nahi|not now/, ["No problem! I'm here whenever you need me."]],
  [/do you (?:sleep|eat|dance|play|watch|like)|favou?rite|can you dance|feelings/, ["I don't sleep, eat or dance, but I never get tired of finding great deals! What are you after today?"]],
];

const smallTalk = (text, seed = 0) => {
  const t = String(text || '').toLowerCase().trim();
  for (const [re, replies] of SMALL_TALK) if (re.test(t)) return pick(replies, seed);
  return "I'm better at shopping than small talk, but I'm all ears! Tell me what you're looking for, or try one of these.";
};

const fallback = () => "Sorry, I didn't quite get that. You can ask me things like *phones under 50k*, *compare the first two* or *where is my order*.";

const STATUS_TEXT = {
  placed: 'has been **placed** and is awaiting confirmation',
  confirmed: 'is **confirmed** and being packed',
  shipped: 'has **shipped** and is on its way',
  out_for_delivery: 'is **out for delivery** — it should reach you today',
  delivered: 'was **delivered**',
  cancelled: 'was **cancelled**',
};

const fmtDate = (d) => (d ? new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : '');

const productInfoReply = (p, summary, seed) => {
  const lines = [];
  const price = `**${money(p.price)}**${p.discount_percent >= 5 ? ` (${Math.round(p.discount_percent)}% off)` : ''}`;
  lines.push(`**${p.title}**${p.brand_name ? ` by ${p.brand_name}` : ''} — ${price}. ${p.rating_count ? `Rated **${stars(p.rating)}** from ${p.rating_count} reviews.` : 'No ratings yet.'}`);
  if (p.highlights?.length) lines.push(`Highlights: ${p.highlights.slice(0, 3).join('; ')}.`);
  const specs = Object.entries(p.specs || {}).slice(0, 4).map(([k, v]) => `${k}: ${truncate(String(v), 40)}`);
  if (specs.length) lines.push(`Key specs — ${specs.join(' · ')}.`);
  if (summary?.reviewCount) {
    const pros = summary.pros.slice(0, 2).map((x) => x.aspect.toLowerCase());
    const cons = summary.cons.slice(0, 1).map((x) => x.aspect.toLowerCase());
    lines.push(`Reviews are **${summary.sentiment.label.toLowerCase()}**${pros.length ? `; people like the ${list(pros)}` : ''}${cons.length ? `, some mention ${cons[0]}` : ''}.`);
  }
  lines.push(p.stock > 0 ? pick(['Want me to add it to your cart?', 'Shall I add it to your cart or show similar items?'], seed) : 'It is currently out of stock — want similar items?');
  return lines.join(' ');
};

module.exports = {
  describe, budgetPhrase, searchReply, noMatchReply, greeting, HELP, smallTalk, fallback, STATUS_TEXT, fmtDate, productInfoReply, lower, categoryNames,
  topPickLine, fitNote, exactFit,
};
