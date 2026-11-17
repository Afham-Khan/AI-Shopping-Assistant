// speech-transcript cleanup (voice input): spoken numbers -> digits, filler words, address fillers
// ("yaar", "bhai" used as "hey man") and stutter repeats. runs on lower-cased text inside baseClean.

const UNITS = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
  thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
  twenty: 20, thirty: 30, forty: 40, fourty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
  // roman urdu
  ek: 1, do: 2, teen: 3, char: 4, chaar: 4, paanch: 5, panch: 5, chay: 6, chhe: 6, chhay: 6, saat: 7, aath: 8, nau: 9, das: 10,
  gyarah: 11, barah: 12, pandrah: 15, bees: 20, pachees: 25, pachis: 25, tees: 30, chalees: 40, chalis: 40, pachas: 50, pachaas: 50,
  sattar: 70, assi: 80, nabbe: 90, derh: 1.5, dedh: 1.5, dhai: 2.5, adhai: 2.5,
};
const HUNDRED = new Set(['hundred', 'sau']);
const SCALES = { k: 1e3, thousand: 1e3, hazar: 1e3, hazaar: 1e3, hzar: 1e3, lakh: 1e5, lakhs: 1e5, lac: 1e5, lacs: 1e5, million: 1e6 };
const CURRENCY_AFTER = /^\s*(?:rupees|rupay|rupaye|rs|pkr)\b/;

const NUM_WORD = [...Object.keys(UNITS), ...HUNDRED, ...Object.keys(SCALES)].sort((a, b) => b.length - a.length).join('|');
const RUN = new RegExp(`\\b(?:${NUM_WORD}|\\d+(?:\\.\\d+)?)(?:\\s+(?:and\\s+)?(?:${NUM_WORD}|\\d+(?:\\.\\d+)?))*\\b`, 'g');

const parseRun = (words) => {
  let total = 0;
  let current = 0;
  for (const w of words) {
    if (w === 'and') continue;
    if (HUNDRED.has(w)) current = (current || 1) * 100;
    else if (SCALES[w]) {
      total += (current || 1) * SCALES[w];
      current = 0;
    } else if (UNITS[w] !== undefined) current += UNITS[w];
    else current += Number.parseFloat(w);
  }
  return Math.round(total + current);
};

// "fifty thousand" -> 50000, "derh lakh" -> 150000, "pachas hazar" -> 50000; a run converts only when it has a
// scale word or is followed by a currency, so "the first one" or "do you have" stay untouched
const spokenNumbers = (s) => s
  .replace(/\ba\s+(hundred|thousand|lakh|million)\b/g, '1 $1')
  .replace(RUN, (run, offset, whole) => {
    // "and" joins a number only after hundred/scale ("one hundred and fifty"); otherwise it separates two
    // numbers ("between twenty and forty thousand")
    const segments = [{ words: [], sep: '' }];
    for (const w of run.split(/\s+/)) {
      const seg = segments[segments.length - 1];
      const prev = seg.words[seg.words.length - 1];
      if (w === 'and' && !(HUNDRED.has(prev) || SCALES[prev])) segments.push({ words: [], sep: ' and ' });
      else if (/^\d/.test(w) && UNITS[prev] !== undefined) {
        // "bana do 4 lakh": a spoken word right before digits is a verb/article, not part of the number
        seg.words.pop();
        if (seg.words.length) segments.push({ words: [prev], sep: ' ', literal: true });
        else Object.assign(seg, { words: [prev], literal: true });
        segments.push({ words: [w], sep: ' ' });
      } else seg.words.push(w);
    }
    // "twenty and forty thousand": the shared scale applies to the bare first number too
    const lastWords = segments[segments.length - 1].words;
    const sharedScale = segments.length > 1 && SCALES[lastWords[lastWords.length - 1]] ? lastWords[lastWords.length - 1] : null;
    if (sharedScale) {
      for (const seg of segments.slice(0, -1)) {
        if (seg.sep !== ' ' && !seg.literal && seg.words.length && !seg.words.some((w) => SCALES[w] || HUNDRED.has(w))) seg.words.push(sharedScale);
      }
    }
    return segments.map(({ words, sep, literal }, i) => {
      const text = words.join(' ');
      const hasWord = words.some((w) => UNITS[w] !== undefined || HUNDRED.has(w));
      const hasScale = words.some((w) => HUNDRED.has(w) || SCALES[w]);
      const currencyNext = i === segments.length - 1 && CURRENCY_AFTER.test(whole.slice(offset + run.length));
      let out = text;
      if (!literal && (hasWord || hasScale) && (hasScale || currencyNext) && (hasWord || words.length >= 2)) out = String(parseRun(words));
      return `${sep}${out}`;
    }).join('');
  })
  .replace(/(\d)\s+k\b/g, '$1k');

const FILLERS = /\b(?:u+m+|u+h+m*|h+m+|e+r+m+|uhh+|ahh*|ohh*|mm+|er|you know|i mean|basically|matlab|waise|wese)\b/g;
// "acha" opens a sentence ("acha mujhe phone chahiye") but is also an adjective ("acha laptop", "acha sa phone"),
// so it only counts as a filler before a pronoun/connector or punctuation
const LEADING = /^[\s,.!?]*(?:(?:(?:acha|accha|achha|achcha|achchha)(?=\s*[,.!?]|\s+(?:to|toh|so|ok|okay|theek|thik|yaar|yar|bhai|mujhe|mujhay|mjhe|main|mai|hum|hamein|ye|yeh|wo|woh|phir|ab|chalo|suno|i|we|can|please|show|tell|dikhao|batao)\b)|ok|okay|okk|theek hai|thik hai|thik he|theek he|so|well|haan|han|ji)\b[\s,.!?]*(?:(?:to|toh|so|then|phir)\b[\s,.!?]*)?)+(?=\S)/;
const ADDRESS = /\b(?:yaa+r|yar|yaara|bhai|bhaiya|bro|dude)\b/g;
const KEEP_BEFORE = /\b(?:my|mera|mere|meri|apne|apna|apni|for|ek|kisi|a|the|your|his|her|our)\s*$/;
const KEEP_AFTER = /^\s*(?:ke|ki|k|kay|ka|ko|kelye|keliye|liye|lye|se|who|is|loves|likes|ne|wants)\b/;
const TRAILING_NA = /\b(dikhao|dikha|dikhado|batao|bata|karo|kardo|krdo|do|dedo|chahiye|lao|samjhao|bhejo)\s+(?:na|naa)\s*([?.!]*)\s*$/;

const cleanSpeech = (input) => {
  let s = spokenNumbers(input);
  const withoutFillers = s.replace(FILLERS, ' ');
  // a lone "hmm" is still a (small-talk) message
  if (withoutFillers.trim()) s = withoutFillers;
  s = s.replace(LEADING, '');
  // "yaar"/"bhai" as a form of address is noise; as a recipient ("bhai ke liye", "my bro") it is kept
  s = s.replace(ADDRESS, (word, offset, whole) => {
    const before = whole.slice(0, offset);
    const after = whole.slice(offset + word.length);
    if (KEEP_BEFORE.test(before) || KEEP_AFTER.test(after)) return word;
    return ' ';
  });
  s = s.replace(TRAILING_NA, '$1$2');
  // stutters: "phone phone", "the the"
  s = s.replace(/\b([a-z]+)(?:[\s,]+\1\b)+/g, '$1');
  return s.replace(/\s{2,}/g, ' ').trim();
};

module.exports = { cleanSpeech, spokenNumbers, parseRun };
