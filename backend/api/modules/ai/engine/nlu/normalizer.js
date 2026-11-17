// text normalization: casing, unicode, contractions, number formats, roman-urdu, spelling correction
const { ROMAN_URDU, IDIOMS, STOPWORDS } = require('./lexicon');

const MAX_LEN = 500;

const cleanNumbers = (s) => {
  let out = s;
  // 1,50,000 / 50,000 -> 150000 / 50000 (repeat for indian grouping)
  for (let i = 0; i < 3; i += 1) out = out.replace(/(\d),(?=\d{2,3}\b)/g, '$1');
  return out
    .replace(/\b(?:rs|pkr)\.?\s*(?=\d)/g, 'rs ')
    .replace(/(\d)\s*\/-/g, '$1')
    .replace(/(\d)\s*(rs|pkr|rupees|rupay)\b/g, '$1 $2')
    .replace(/\busd\s*(?=\d)/g, '$')
    .replace(/(\d+(?:\.\d+)?)\s*(?:usd|dollars?|bucks)\b/g, '$$$1')
    // 16gb -> 16 gb, but keep money suffixes (50k, 1.5l, 2lac) and ordinals (2nd)
    .replace(/(\d)(?!(?:k|l|m|lac|lakh|lakhs|st|nd|rd|th)\b)([a-z]+)/g, '$1 $2');
};

const baseClean = (raw) => {
  let s = String(raw ?? '').slice(0, MAX_LEN).toLowerCase();
  s = s.normalize('NFKD').replace(/[̀-ͯ]/g, '');
  s = s
    .replace(/[‘’`´]/g, "'")
    .replace(/₨/g, ' rs ')
    .replace(/[★⭐]/g, ' star ')
    .replace(/\bcan'?t\b/g, 'can not')
    .replace(/\bwon'?t\b/g, 'will not')
    .replace(/n't\b/g, ' not')
    .replace(/'(?:s|re|ll|ve|d|m)\b/g, '')
    .replace(/&/g, ' and ')
    // 20k-40k is a range, other hyphens just join words
    .replace(/(\d(?:k|l|lac|lakh)?)\s*-\s*(?=\$?\d)/g, '$1 to ')
    .replace(/(\w)-(\w)/g, '$1 $2');
  s = cleanNumbers(s);
  for (const [pattern, replacement] of IDIOMS) s = s.replace(pattern, replacement);
  return s;
};

const TOKEN_RE = /\$\d+(?:\.\d+)?k?|\d+(?:\.\d+)?(?:k|l|m|lac|lakh|lakhs|st|nd|rd|th)?|[a-z]+|[#+]/g;

const tokenize = (s) => s.match(TOKEN_RE) || [];

// corrector: { has(word), match(word) } (FuzzyVocabulary); known: Set of words never corrected
const normalize = (raw, { corrector = null, known = null } = {}) => {
  const cleaned = baseClean(raw);
  const tokens = [];
  const corrections = [];
  for (const token of tokenize(cleaned)) {
    const mapped = ROMAN_URDU[token];
    if (mapped) {
      tokens.push(...mapped.split(' '));
      continue;
    }
    if (
      corrector && /^[a-z]+$/.test(token) && token.length >= 4 &&
      !STOPWORDS.has(token) && !corrector.has(token) && !corrector.has(stem(token)) &&
      !(known && (known.has(token) || known.has(stem(token))))
    ) {
      // stretched words (giftt, orderr, addd) usually just repeat the last letter
      const squeezed = token.replace(/(.)\1+$/, '$1');
      if (squeezed !== token && (corrector.has(squeezed) || (known && known.has(squeezed)))) {
        corrections.push({ from: token, to: squeezed });
        tokens.push(squeezed);
        continue;
      }
      const fix = corrector.match(token);
      if (fix && fix.word !== token) {
        corrections.push({ from: token, to: fix.word });
        tokens.push(fix.word);
        continue;
      }
    }
    tokens.push(token);
  }
  return { original: String(raw ?? '').slice(0, MAX_LEN), text: tokens.join(' '), tokens, corrections };
};

// light plural stemmer shared by retrieval and classifier features
const stem = (word) => {
  if (word.length <= 3 || /\d/.test(word)) return word;
  if (word.endsWith('ies') && word.length > 4) return `${word.slice(0, -3)}y`;
  if (/(?:ss|us|is)$/.test(word)) return word;
  if (/(?:ches|shes|xes|zes|sses)$/.test(word)) return word.slice(0, -2);
  if (word.endsWith('s')) return word.slice(0, -1);
  return word;
};

module.exports = { normalize, baseClean, tokenize, stem, MAX_LEN };
