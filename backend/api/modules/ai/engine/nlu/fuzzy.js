// typo tolerance: damerau-levenshtein (optimal string alignment) + trigram dice prefilter

const damerauLevenshtein = (a, b, maxDist = Infinity) => {
  if (a === b) return 0;
  const la = a.length;
  const lb = b.length;
  if (Math.abs(la - lb) > maxDist) return maxDist + 1;
  if (!la) return lb;
  if (!lb) return la;
  let prev2 = new Array(lb + 1).fill(0);
  let prev = Array.from({ length: lb + 1 }, (_, j) => j);
  let cur = new Array(lb + 1).fill(0);
  for (let i = 1; i <= la; i += 1) {
    cur[0] = i;
    let rowMin = cur[0];
    for (let j = 1; j <= lb; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    // early exit: no cell in this row can lead to a distance within budget
    if (rowMin > maxDist) return maxDist + 1;
    [prev2, prev, cur] = [prev, cur, prev2];
  }
  return prev[lb];
};

const trigrams = (word) => {
  const padded = `  ${word} `;
  const set = new Set();
  for (let i = 0; i < padded.length - 2; i += 1) set.add(padded.slice(i, i + 3));
  return set;
};

const diceSimilarity = (a, b) => {
  const ta = a instanceof Set ? a : trigrams(a);
  const tb = b instanceof Set ? b : trigrams(b);
  let shared = 0;
  for (const g of ta) if (tb.has(g)) shared += 1;
  return (2 * shared) / (ta.size + tb.size || 1);
};

// allowed edits grow with word length so short words are never "corrected" into others
const maxEditsFor = (len) => {
  if (len < 4) return 0;
  if (len <= 7) return 1;
  return 2;
};

// vocabulary with a trigram inverted index so lookups don't scan every word
class FuzzyVocabulary {
  constructor(words = []) {
    this.words = new Map(); // word -> priority
    this.grams = new Map(); // trigram -> Set(word)
    words.forEach((w) => this.add(w));
  }

  add(word, priority = 1) {
    if (!word || word.length < 3) return;
    const existing = this.words.get(word);
    if (existing !== undefined) {
      this.words.set(word, Math.max(existing, priority));
      return;
    }
    this.words.set(word, priority);
    for (const g of trigrams(word)) {
      if (!this.grams.has(g)) this.grams.set(g, new Set());
      this.grams.get(g).add(word);
    }
  }

  has(word) {
    return this.words.has(word);
  }

  // best correction within the edit budget, or null
  match(word) {
    const maxEdits = maxEditsFor(word.length);
    if (!maxEdits) return null;
    const grams = trigrams(word);
    const counts = new Map();
    for (const g of grams) {
      const bucket = this.grams.get(g);
      if (bucket) for (const w of bucket) counts.set(w, (counts.get(w) || 0) + 1);
    }
    let best = null;
    for (const [candidate, shared] of counts) {
      if (shared < 2 && word.length > 4) continue;
      // typos almost always keep the first letter (or swap the first two)
      if (candidate[0] !== word[0] && !(candidate[0] === word[1] && candidate[1] === word[0])) continue;
      // inflected forms (priced, discounted, pricier) are words, not typos
      if (word.length > candidate.length && word.startsWith(candidate.slice(0, Math.max(3, candidate.length - 1)))
        && /(?:ed|er|es|ier|ied|ing|ly|s|y|est)$/.test(word)) continue;
      const dist = damerauLevenshtein(word, candidate, maxEdits);
      if (dist > maxEdits) continue;
      const dice = (2 * shared) / (grams.size + trigrams(candidate).size);
      const firstLetter = candidate[0] === word[0] ? 0.15 : 0;
      const score = -dist + dice + firstLetter + 0.05 * this.words.get(candidate);
      if (!best || score > best.score) best = { word: candidate, distance: dist, score };
    }
    return best;
  }
}

module.exports = { damerauLevenshtein, trigrams, diceSimilarity, maxEditsFor, FuzzyVocabulary };
