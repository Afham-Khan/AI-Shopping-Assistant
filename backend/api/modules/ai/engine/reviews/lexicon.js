// afinn-style valence lexicon (-5..5) tuned for product reviews, plus modifiers
const raw = {
  5: 'outstanding superb excellent exceptional flawless perfect phenomenal fantastic brilliant masterpiece',
  4: 'amazing awesome love loved loving wonderful incredible impressive impressed delightful stunning gorgeous beautiful lovely terrific',
  3: 'great good nice happy pleased satisfied recommend recommended solid sturdy durable comfortable comfy reliable fast smooth fresh tasty delicious elegant stylish premium worth value bargain crisp vibrant soft cozy quick responsive accurate generous genuine authentic perfectly',
  2: 'fine decent like liked works working useful handy clean cute pretty easy light lightweight bright clear helpful efficient affordable cheap okay ok fair glad enjoy enjoyed recommendable sharp long-lasting lasting rich fits',
  1: 'adequate acceptable average standard simple neat',
  '-1': 'meh slow small tight loose heavy noisy plain basic',
  '-2': 'gripe struggles struggle grainy mediocre bad poor disappointing disappointed issue issues problem problems flimsy cheaply weak thin dull scratchy itchy greasy sticky cakey fades faded faulty late delay delayed overpriced expensive pricey uncomfortable hard difficult missing smell smells stiff blurry laggy lag dim',
  '-3': 'terrible awful horrible worst broken broke useless defective damaged waste fake unhappy dissatisfied annoying irritation rash leaking leaked cracked stopped rubbish ripped torn smelly stale rotten',
  '-4': 'disgusting pathetic scam fraud hate hated nightmare dangerous',
};

const LEXICON = new Map();
for (const [score, words] of Object.entries(raw)) for (const w of words.split(' ')) LEXICON.set(w, Number(score));

// multi-word expressions checked before single tokens
const PHRASES = new Map([
  ['value for money', 3], ['worth the price', 3], ['worth every penny', 4], ['not worth', -3], ['waste of money', -4],
  ['would buy again', 3], ['would not buy again', -3], ['would not recommend', -3], ['highly recommended', 4],
  ['as described', 2], ['not as described', -3], ['fast shipping', 3], ['fast delivery', 3], ['on time', 2],
  ['broke my skin out', -3], ['falls apart', -3], ['fell apart', -3], ['stopped working', -3], ['too small', -2],
  ['too big', -2], ['too thick', -2], ['too expensive', -2], ['better options', -1], ['think twice', -2],
  ['nothing special', -1], ['does the job', 2], ['love it', 4], ['no complaints', 3], ['true to size', 2],
  ['money back', -1], ['exactly as shown', 3], ['as shown', 2], ['as pictured', 2], ['quite different', -2], ['looks different', -2], ['different from the pictures', -2], ['caused irritation', -3], ['on the plus side', 0], ['better than expected', 3], ['expected a lot more', -3],
]);

const NEGATORS = new Set(['not', 'no', 'never', 'nothing', 'hardly', 'barely', 'without', 'nor', 'neither', 'cannot', 'dont', 'didnt', 'doesnt', 'isnt', 'wasnt', 'arent', 'wont', 'nahi']);
const INTENSIFIERS = new Map([
  ['very', 1.5], ['extremely', 1.8], ['really', 1.4], ['super', 1.5], ['so', 1.3], ['highly', 1.6], ['absolutely', 1.7],
  ['totally', 1.5], ['incredibly', 1.8], ['quite', 1.2], ['too', 1.3], ['bahut', 1.5], ['most', 1.3], ['truly', 1.4],
]);
const DIMINISHERS = new Map([['slightly', 0.5], ['somewhat', 0.6], ['bit', 0.6], ['little', 0.6], ['fairly', 0.8], ['kinda', 0.6], ['almost', 0.7]]);

module.exports = { LEXICON, PHRASES, NEGATORS, INTENSIFIERS, DIMINISHERS };
