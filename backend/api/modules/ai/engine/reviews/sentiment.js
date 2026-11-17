// lexicon sentiment with negation scope, intensifiers/diminishers and "but" contrast weighting
const { LEXICON, PHRASES, NEGATORS, INTENSIFIERS, DIMINISHERS } = require('./lexicon');

const tokenize = (text) =>
  String(text || '').toLowerCase().replace(/n't\b/g, ' not').replace(/[^a-z0-9\s'-]/g, ' ').split(/\s+/).filter(Boolean)
    .map((t) => t.replace(/'/g, ''));

const splitSentences = (text) =>
  String(text || '').split(/(?<=[.!?])\s+|\n+|;\s*/).map((s) => s.trim()).filter((s) => s.length > 1);

// returns { score: -1..1, raw, hits: [{ word, value }] }
const scoreSentence = (text) => {
  const tokens = tokenize(text);
  const hits = [];
  let total = 0;
  let contrastAt = tokens.findIndex((t) => t === 'but' || t === 'however' || t === 'although' || t === 'though');
  if (contrastAt === -1) contrastAt = Infinity;
  for (let i = 0; i < tokens.length; i += 1) {
    let value = null;
    let span = 1;
    for (const len of [4, 3, 2]) {
      const phrase = tokens.slice(i, i + len).join(' ');
      if (PHRASES.has(phrase)) {
        value = PHRASES.get(phrase);
        span = len;
        break;
      }
    }
    if (value === null) value = LEXICON.get(tokens[i]) ?? LEXICON.get(tokens[i].replace(/(?:ed|s)$/, '')) ?? null;
    if (value === null || value === 0) continue;
    let v = value;
    // modifiers within the 3 preceding tokens
    for (let k = Math.max(0, i - 3); k < i; k += 1) {
      const t = tokens[k];
      if (NEGATORS.has(t) && !PHRASES.has(tokens.slice(i, i + span).join(' '))) v = -v * 0.75;
      else if (INTENSIFIERS.has(t) && k === i - 1) v *= INTENSIFIERS.get(t);
      else if (DIMINISHERS.has(t) && k >= i - 2) v *= DIMINISHERS.get(t);
    }
    // the clause after "but" carries the writer's real opinion
    if (contrastAt !== Infinity) v *= i > contrastAt ? 1.5 : 0.6;
    hits.push({ word: tokens.slice(i, i + span).join(' '), value: +v.toFixed(2) });
    total += v;
    i += span - 1;
  }
  // squash to -1..1 (vader-style normalization)
  const score = total / Math.sqrt(total * total + 15);
  return { score: +score.toFixed(3), raw: +total.toFixed(2), hits };
};

const scoreText = (text) => {
  const sentences = splitSentences(text).map((s) => ({ text: s, ...scoreSentence(s) }));
  const raw = sentences.reduce((s, x) => s + x.raw, 0);
  return { score: +(raw / Math.sqrt(raw * raw + 15)).toFixed(3), sentences };
};

module.exports = { scoreSentence, scoreText, splitSentences, tokenize };
