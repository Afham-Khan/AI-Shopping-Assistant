// entity extraction over normalized tokens: budget, taxonomy, brands, gender, occasion, color,
// features, rating, sort, ordinals, negations and leftover keywords
const L = require('./lexicon');
const { stem } = require('./normalizer');

const USD_TO_PKR = Number(process.env.AI_USD_TO_PKR) || 280;

const NEGATORS = new Set(['not', 'no', 'without', 'except', 'excluding', 'exclude', 'avoid', 'non', 'never', 'but']);
const MULTIPLIERS = { k: 1e3, thousand: 1e3, l: 1e5, lac: 1e5, lakh: 1e5, lakhs: 1e5, m: 1e6, million: 1e6 };
const UNIT_AFTER = new Set(['gb', 'tb', 'mb', 'mah', 'mp', 'inch', 'inches', 'hz', 'w', 'watt', 'kg', 'g', 'gram', 'grams', 'ml', 'litre', 'liter', 'cm', 'mm', 'year', 'years', 'month', 'months', 'day', 'days', 'km', 'cc', 'star', 'stars', 'pcs', 'pieces', 'percent', 'minutes', 'hours', 'pack']);
const LIQUID_CUES = /\b(?:litre|liter|bottle|water|oil|milk|juice|drink|drinks|soda)\b/;
const NUMBER_WORDS = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6 };
const ORDINAL_WORDS = { first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6, '1st': 1, '2nd': 2, '3rd': 3, '4th': 4, '5th': 5, '6th': 6, last: -1 };
const FRUIT_CUES = new Set(['fruit', 'fruits', 'fresh', 'kg', 'eat', 'grocery', 'groceries', 'apples', 'juice', 'organic']);

const MONEY = '(\\$)?(\\d+(?:\\.\\d+)?)(k|l|m|lac|lakh|lakhs)?(?:\\s+(thousand|lakh|million))?(?:\\s+rupees)?';
const MAX_CUE = '(?:under|below|less than|lower than|cheaper than|max|maximum|upto|up to|within|not more than|no more than|at most|budget(?: is| of)?|my budget(?: is)?|in|for|of|till|until|less)';
const MIN_CUE = '(?:above|over|more than|at least|atleast|minimum|min|starting from|starting at|greater than|higher than|from)';
const AROUND_CUE = '(?:around|about|approx|approximately|near|roughly|close to|nearly)';

const amountOf = (dollar, num, suffix, word) => {
  let value = Number.parseFloat(num);
  if (!Number.isFinite(value)) return null;
  if (suffix) value *= MULTIPLIERS[suffix] || 1;
  if (word) value *= MULTIPLIERS[word] || 1;
  if (dollar) value *= USD_TO_PKR;
  return Math.round(value);
};

// a bare number counts as money only with a currency/suffix or when it is clearly a price-sized value
const qualified = (m, text, endIndex) => {
  const [, dollar, num, suffix, word] = m;
  const after = text.slice(endIndex).trim().split(/\s+/)[0] || '';
  if (UNIT_AFTER.has(after)) return false;
  if (suffix === 'l' && LIQUID_CUES.test(text)) return false;
  if (dollar || suffix || word || /^rupees\b/.test(text.slice(endIndex).trim())) return true;
  if (/rupees\s*$/.test(text.slice(0, m.index))) return true;
  return Number.parseFloat(num) >= 500;
};

const extractBudget = (text) => {
  const cue = (c) => new RegExp(`\\b${c}\\s+(?:rupees\\s+)?${MONEY}\\b`, 'g');
  const range = new RegExp(`(?:\\b(?:between|from)\\s+)?(?:rupees\\s+)?${MONEY}\\s+(?:and|to)\\s+(?:rupees\\s+)?${MONEY}\\b`, 'g');
  const spans = [];

  for (const m of text.matchAll(range)) {
    const a = amountOf(m[1], m[2], m[3], m[4]);
    const b = amountOf(m[5], m[6], m[7], m[8]);
    const hasBetween = /^(?:between|from)\b/.test(m[0]);
    const anyQualified = m[1] || m[3] || m[4] || m[5] || m[7] || m[8] || /rupees/.test(m[0]);
    if (!hasBetween && !anyQualified) continue;
    // "20 to 40k" -> the suffix applies to both ends
    let low = a;
    if (!m[3] && !m[4] && (m[7] || m[8]) && a < 1000) low = amountOf(m[1], m[2], m[7], m[8]);
    const [min, max] = low <= b ? [low, b] : [b, low];
    return { budget: { min, max }, span: m[0] };
  }

  const tryCue = (c, kind) => {
    for (const m of text.matchAll(cue(c))) {
      const numberMatch = [m[0], m[1], m[2], m[3], m[4]];
      numberMatch.index = m.index;
      const loose = /^(?:in|for|of|from|less)\b/.test(m[0]);
      if (loose && !qualified(numberMatch, text, m.index + m[0].length)) continue;
      const after = text.slice(m.index + m[0].length).trim().split(/\s+/)[0] || '';
      if (UNIT_AFTER.has(after)) continue;
      const value = amountOf(m[1], m[2], m[3], m[4]);
      if (!value) continue;
      spans.push({ kind, value, span: m[0] });
      return true;
    }
    return false;
  };

  if (tryCue(AROUND_CUE, 'around')) {
    const { value, span } = spans[0];
    return { budget: { min: Math.round(value * 0.8), max: Math.round(value * 1.2), target: value }, span };
  }
  const hasMax = tryCue(MAX_CUE, 'max');
  const hasMin = tryCue(MIN_CUE, 'min');
  if (hasMax || hasMin) {
    const max = spans.find((s) => s.kind === 'max');
    const min = spans.find((s) => s.kind === 'min');
    return {
      budget: { min: min ? min.value : null, max: max ? max.value : null },
      span: [min?.span, max?.span].filter(Boolean).join(' '),
    };
  }

  // bare amount ("mobile 30k") -> treat as a ceiling the user is aiming near
  const bare = new RegExp(`(?:^|\\s)(?:rupees\\s+)?${MONEY}(?=\\s|$)`, 'g');
  for (const m of text.matchAll(bare)) {
    const start = m.index + m[0].indexOf(m[0].trim());
    const numberMatch = [m[0], m[1], m[2], m[3], m[4]];
    numberMatch.index = start;
    if (!qualified(numberMatch, text, m.index + m[0].length)) continue;
    if (!m[1] && !m[3] && !m[4] && !/rupees/.test(m[0]) && Number.parseFloat(m[2]) < 1000) continue;
    const value = amountOf(m[1], m[2], m[3], m[4]);
    if (value) return { budget: { min: null, max: value, target: value }, span: m[0].trim() };
  }
  return { budget: null, span: '' };
};

const extractRating = (text) => {
  const patterns = [
    /\b([1-5](?:\.\d)?)\s*(?:\+\s*)?(?:star|stars|rating|rated)\b/,
    /\b(?:rated|rating|ratings|stars?)\s*(?:of\s+|above\s+|over\s+|at least\s+|atleast\s+|more than\s+)?([1-5](?:\.\d)?)\b/,
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m) {
      const value = Number.parseFloat(m[1]);
      if (value >= 1 && value <= 5) return { minRating: value, span: m[0] };
    }
  }
  return { minRating: null, span: '' };
};

const extractOrdinals = (tokens) => {
  const indices = [];
  let all = false;
  const push = (n) => {
    if (!indices.includes(n)) indices.push(n);
  };
  const hasCompare = tokens.some((t) => ['compare', 'vs', 'versus', 'comparison', 'difference'].includes(t));
  for (let i = 0; i < tokens.length; i += 1) {
    const t = tokens[i];
    const next = tokens[i + 1];
    const countAfter = next && (NUMBER_WORDS[next] || (/^[1-6]$/.test(next) ? Number(next) : 0));
    if ((t === 'first' || t === 'top') && countAfter > 1) {
      for (let k = 1; k <= countAfter; k += 1) push(k);
      i += 1;
      continue;
    }
    if (t === 'last' && countAfter > 1) {
      for (let k = countAfter; k >= 1; k -= 1) push(-k);
      i += 1;
      continue;
    }
    if (ORDINAL_WORDS[t] !== undefined) {
      if (t === 'last' && next && /^(?:week|month|year|time|order|night)$/.test(next)) continue;
      push(ORDINAL_WORDS[t]);
      continue;
    }
    if (['number', 'no', 'option', 'item', 'product', '#', 'pick', 'choice'].includes(t) && next && /^[1-6]$/.test(next)) {
      push(Number(next));
      i += 1;
      continue;
    }
    if (t === 'both' || ((t === 'these' || t === 'those' || t === 'the') && next === 'two')) {
      push(1);
      push(2);
      continue;
    }
    if (t === 'all' && next && ['of', 'three', 'four', 'these', 'them'].includes(next)) all = true;
    if (hasCompare && /^[1-6]$/.test(t) && !UNIT_AFTER.has(next || '')) push(Number(t));
  }
  const pronoun = /\b(?:it|this one|that one|this|that)\b/.test(tokens.join(' '));
  return { indices, all, pronoun };
};

// builds the entity frame; vocab = Vocabulary instance
const extractEntities = (norm, vocab) => {
  const { tokens, text } = norm;
  const { budget, span: budgetSpan } = extractBudget(text);
  const { minRating, span: ratingSpan } = extractRating(text);
  const ordinals = extractOrdinals(tokens);

  const consumed = new Set();
  const markSpan = (span) => {
    if (!span) return;
    const spanTokens = span.split(/\s+/);
    for (let i = 0; i <= tokens.length - spanTokens.length; i += 1) {
      if (spanTokens.every((s, k) => tokens[i + k] === s)) {
        for (let k = 0; k < spanTokens.length; k += 1) consumed.add(i + k);
        return;
      }
    }
  };
  markSpan(budgetSpan);
  markSpan(ratingSpan);

  const e = {
    department: null, category: null, categories: [], brands: [], excludeBrands: [],
    budget, gender: null, recipient: null, occasion: null, color: null, excludeColors: [],
    features: [], minRating, sort: null, keywords: [], terms: [], ordinals, corrections: norm.corrections || [],
  };
  const generics = [];
  const departments = [];
  let lastEntityEnd = -1;
  // a negator scopes over the next entity (and others chained with or/nor)
  const isNegated = (start, end) => {
    for (let k = start - 1; k >= Math.max(0, start - 3); k -= 1) {
      if (NEGATORS.has(tokens[k])) return true;
      if (k < lastEntityEnd && !['or', 'nor'].includes(tokens[lastEntityEnd])) return false;
    }
    // postfix negation (roman urdu "apple nahi chahiye" -> "apple not want")
    const after = tokens[end];
    const after2 = tokens[end + 1];
    return after === 'not' && (!after2 || ['want', 'please', 'show', 'i'].includes(after2));
  };
  const hasFruitCue = tokens.some((t) => FRUIT_CUES.has(t));
  const catSpans = [];
  // a category phrase can carry a use-case: "running shoes" -> feature running
  const featuresInside = (text) => {
    for (const w of text.split(' ')) {
      for (const key of ['running', 'gaming']) {
        if (L.FEATURES[key].triggers.includes(w) && !e.features.includes(key)) e.features.push(key);
      }
    }
  };

  for (const match of vocab.spot(tokens)) {
    let used = false;
    for (const a of match.annotations) {
      switch (a.type) {
        case 'brand': {
          if (a.value === 'apple' && (hasFruitCue || match.text === 'apples')) break;
          const list = isNegated(match.start, match.end) ? e.excludeBrands : e.brands;
          if (!list.includes(a.value)) list.push(a.value);
          used = true;
          break;
        }
        case 'category':
          if (!e.categories.includes(a.value)) e.categories.push(a.value);
          // specific words ("mascara", "earbuds") still help lexical ranking inside the category
          for (const t of match.text.split(' ')) if (!e.terms.includes(t)) e.terms.push(t);
          catSpans.push({ family: a.value.replace(/^(?:mens|womens)-/, ''), slugs: [a.value], start: match.start, end: match.end });
          featuresInside(match.text);
          used = true;
          break;
        case 'generic':
          generics.push(a.value);
          // "heels", "sneakers", "running shoes": the exact word tells ranking which kind of shoe
          for (const t of match.text.split(' ')) if (!e.terms.includes(t)) e.terms.push(t);
          catSpans.push({ family: a.value, generic: a.value, start: match.start, end: match.end });
          featuresInside(match.text);
          used = true;
          break;
        case 'department':
          departments.push(a.value);
          used = true;
          break;
        case 'color':
          if (isNegated(match.start, match.end)) {
            if (!e.excludeColors.includes(a.value)) e.excludeColors.push(a.value);
          } else if (!e.color) e.color = a.value;
          used = true;
          break;
        case 'feature':
          if (!e.features.includes(a.value)) e.features.push(a.value);
          // keep the exact word: "programming" and "office" both map to the work feature but want different laptops
          if (!e.terms.includes(match.text)) e.terms.push(match.text);
          used = true;
          break;
        case 'occasion':
          if (!e.occasion) e.occasion = a.value;
          if (!e.terms.includes(match.text)) e.terms.push(match.text);
          used = true;
          break;
        case 'recipient':
          if (!e.recipient) e.recipient = a.value;
          if (a.gender && !e.gender) e.gender = a.gender;
          used = true;
          break;
        case 'gender':
          e.gender = a.value;
          used = true;
          break;
        case 'sort':
          if (!e.sort) e.sort = a.value;
          used = true;
          break;
        default:
      }
    }
    if (used) {
      for (let k = match.start; k < match.end; k += 1) consumed.add(k);
      lastEntityEnd = match.end;
    }
  }

  // generic words (shoes, watch) resolve via gender
  for (const g of generics) {
    const map = L.GENDERED[g];
    const resolved = e.gender ? map[e.gender] : map.any;
    for (const slug of [].concat(resolved)) if (!e.categories.includes(slug)) e.categories.push(slug);
  }
  // one product named with two category words: the head noun wins.
  // "sports bike" / "basketball shoes" -> the last word; "charger for iphone" / "lamp for my study table" -> the part before "for"
  const familyOf = (slug) => slug.replace(/^(?:mens|womens)-/, '');
  const families = [...new Set(catSpans.map((s) => s.family))];
  if (families.length >= 2 && !tokens.some((t) => ['and', 'or', 'vs', 'versus', 'plus', 'with', '&'].includes(t))) {
    const drop = new Set();
    const forIdx = tokens.indexOf('for');
    const before = catSpans.filter((s) => forIdx >= 0 && s.end <= forIdx);
    const after = catSpans.filter((s) => forIdx >= 0 && s.start > forIdx);
    if (before.length && after.length) {
      for (const s of after) if (!before.some((b) => b.family === s.family)) drop.add(s.family);
    } else {
      const spans = catSpans.slice().sort((a, b) => a.start - b.start);
      for (let i = 0; i + 1 < spans.length; i += 1) {
        if (spans[i + 1].start === spans[i].end && spans[i + 1].family !== spans[i].family) drop.add(spans[i].family);
      }
    }
    if (drop.size && drop.size < families.length) e.categories = e.categories.filter((c) => !drop.has(familyOf(c)));
  }
  // "shirt for my sister" -> tops
  if (e.gender === 'women' && e.categories.includes('mens-shirts')) {
    e.categories = e.categories.map((c) => (c === 'mens-shirts' ? 'tops' : c));
  }
  if (e.gender === 'men') e.categories = e.categories.filter((c) => !(c.startsWith('womens-') && e.categories.length > 1));
  if (e.gender === 'women') e.categories = e.categories.filter((c) => !(c.startsWith('mens-') && e.categories.length > 1));
  e.categories = [...new Set(e.categories)];
  e.category = e.categories[0] || null;

  if (e.category) {
    const info = vocab.departmentOf(e.category);
    e.department = info ? info.departmentSlug : null;
  } else if (departments.length) {
    const dept = vocab.departmentByKey(departments[0]);
    e.department = dept ? dept.slug : null;
  }

  // leftover meaningful tokens drive lexical search ("mascara", "kiwi")
  const ordinalWords = new Set([...Object.keys(ORDINAL_WORDS), ...Object.keys(NUMBER_WORDS), 'both', '#']);
  e.keywords = tokens
    .filter((t, i) => !consumed.has(i))
    .filter((t) => !L.STOPWORDS.has(t) && !ordinalWords.has(t) && !NEGATORS.has(t) && !/^\$?\d/.test(t) && t.length > 1)
    .filter((t) => !/^(?:cheap|cheaper|expensive|premium|good|best|great|nice|recommend|suggest|compare|cart|add|gift|deal|deals|discount|order|return|similar|options?|more|less|other|another|else|instead|only|new|thanks|hello|hi|bye|stuff|plus|star|stars|rated|rating|show|see|tell|top|which|better|vs|versus|difference|between|details|detail|info|someone|person|quality|affordable|range|kind|sort|type|want|please|help|limit|budget|matter|whatever|ones|stuff|anything)$/.test(t))
    .map(stem);
  e.keywords = [...new Set(e.keywords)];
  return e;
};

module.exports = { extractEntities, extractBudget, extractRating, extractOrdinals, USD_TO_PKR };
