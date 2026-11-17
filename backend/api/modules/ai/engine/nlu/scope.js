// scope layer: rules that run next to the trained classifier for messages that leave the shopping script.
// safety first (crisis, abuse), then noise (gibberish, numbers-only, emoji-only, other scripts), then
// topic detectors for off-topic questions, store-faq questions, questions about the assistant, feelings and
// vague shopping. every detector is a pure function over the lower-cased raw text + the normalized text.
const { stem } = require('./normalizer');
const L = require('./lexicon');

const CRISIS_RE = /\b(?:kill(?:ing)? my ?self|suicid\w*|end (?:my|it) (?:life|all)|want to die|wanna die|(?:do not|don'?t) want to (?:live|be alive)|self[- ]?harm|hurt(?:ing)? my ?self|cut(?:ting)? my ?self|khud ?kushi|mar jana chaht[ai]|marna chaht[ai]|jeena nahi chaht[ai])\b/;
const PROFANITY_RE = /\b(?:f+u+c+k+\w*|fck\w*|fuk\w*|f off|wtf|stfu|shit\w*|bullshit|bitch\w*|bastard\w*|asshole\w*|arsehole|dickhead|motherf\w*|slut|whore|chutiy\w*|chutia|harami\w*|kamine?|kameen[ae]?|gandu|b[eh]+nchod|madarchod|bhosd\w*|damn you)\b/;
const INSULT_RE = /\b(?:stupid|dumb|idiot\w*|useless|useles|worthless|pathetic|trash|rubbish|garbage|you suck|u suck|hate you|annoying|nonsense|bakwas|bekaar|bekar|bewakoof|pagal|ullu|worst (?:bot|assistant|ai)|bad bot|waste of time|not helpful|shut ?up|chup kar\w*|get lost|go away)\b/;
const AT_BOT_RE = /\b(?:you|u|ur|your|you'?re|bot|zel|assistant|ai|tum|tu|aap|ap|this app|this thing)\b/;

const SHOP_RE = /\b(?:buy|buying|purchase|order|orders|cart|checkout|price|prices|cost|costs|cheap|cheaper|cheapest|expensive|under|budget|deal|deals|discount|sale|offers?|coupons?|gift|gifts|show|recommend|suggest|need|looking for|find me|deliver\w*|shipping|ship|return|refund|stock|available|sell|selling|shop|shopping|chahiye|want|dikhao|lena)\b/;

// [topic, regex, strong]: strong topics win even when a product word appears (if no shopping verb / budget)
const OOS_TOPICS = [
  ['weather', /\b(?:weather|wether|whether today|forecast|temperature (?:in|outside|today)|(?:will it|is it going to) (?:rain|snow|be hot|be cold)|rain(?:ing)? (?:today|tomorrow)|mausam|barish)\b/, true],
  ['sports', /\b(?:who won|hu won|won the (?:match|game|toss|cup)|score|scores|live match|match (?:today|yesterday|result)|world cup|psl|ipl|fifa|premier league|champions league|batsman|bowler|playing xi|cricket match|football match|vs india|vs pakistan)\b/, true],
  ['news', /\b(?:news|headlines?|current affairs|breaking|prime minister|president of|election|elections|politics|political|government|khabar|khabrain)\b/, true],
  ['study', /\b(?:home ?work|assignment|essay|thesis|dissertation|exam paper|write (?:a |an |my |me an? )?(?:essay|assignment|letter|application|report|story|poem|article|speech|cv|resume)|solve (?:this|my|the)|project report|likh do|likh dain)\b/, true],
  ['code', /\b(?:coding|programming|python|javascript|java\b|html|css|c\+\+|algorithm|debug|write (?:a |the |some )?code|code in|program in|leetcode)\b/, true],
  ['math', /\b(?:\d+(?:\.\d+)?\s*(?:plus|minus|times|into|multiplied by|divided by|[+*\/x-])\s*\d+|maths?\b|calculate|equation|square root|algebra)\b/, true],
  ['time', /\b(?:what time|time is it|current time|time (?:kya|kia) (?:hua|hai)|what(?: is|s)? the date|today'?s date|what day is (?:it|today)|aaj (?:kya|kia) date|which day is today)\b/, true],
  ['translate', /\b(?:translate|translation|transalte|how do (?:you|i) say|in french|in spanish|in arabic|in chinese|in german|meaning in urdu)\b/, true],
  ['finance', /\b(?:bitcoin|crypto\w*|ethereum|stock market|share price|forex|dollar rate|exchange rate|gold rate|psx|invest(?:ing|ment)? (?:in|tips|advice))\b/, true],
  ['booking', /\b(?:book (?:a |me a )?(?:flight|ticket|uber|careem|taxi|hotel|table)|set (?:an )?alarm|call my|send (?:a )?message to|remind me)\b/, true],
  ['entertainment', /\b(?:movies?|films?|netflix|series|drama|songs?|music|sing|singing|lyrics|play (?:a |some )?(?:song|music)|youtube|tiktok|anime|tell me a story|story sunao)\b/, false],
  ['food', /\b(?:recipe|recipes|how to cook|cooking|dinner|lunch|breakfast|what (?:should|can) i eat|hungry|biryani|pizza|restaurant)\b/, false],
  ['health', /\b(?:doctor|medicine|medical|headache|fever|disease|symptoms?|diet plan|lose weight|covid|pregnan\w*|blood pressure)\b/, false],
  ['people', /\b(?:who (?:is|was|are) (?!my\b|the best (?:brand|seller|phone|laptop))[a-z]+|tell me about [a-z]+ khan)\b/, false],
  ['knowledge', /\b(?:capital of|capitel of|population of|how far is|tallest|largest country|who invented|who discovered|when was|history of|meaning of life|speed of light|photosynthesis|planets?|universe|solar system|how do (?:airplanes|planes) fly|best university)\b/, true],
  ['love', /\b(?:marry me|girlfriend|boyfriend|date me|crush on)\b/, false],
];

const FAST_CITIES = ['karachi', 'lahore', 'islamabad', 'rawalpindi', 'pindi', 'isb', 'khi', 'lhr'];
const PK_CITIES = ['faisalabad', 'multan', 'peshawar', 'quetta', 'hyderabad', 'sialkot', 'gujranwala', 'sukkur', 'bahawalpur', 'abbottabad',
  'sargodha', 'mardan', 'larkana', 'gwadar', 'murree', 'jhelum', 'sahiwal', 'okara', 'gujrat', 'sheikhupura', 'rahim yar khan', 'mirpur',
  'muzaffarabad', 'swat', 'gilgit', 'skardu', 'kasur', 'chiniot', 'dera ghazi khan', 'dera ismail khan', 'nawabshah', 'mingora', 'attock',
  'wah cantt', 'taxila', 'kohat', 'bannu', 'turbat', 'khuzdar', 'jacobabad', 'mansehra', 'chitral', 'hunza'];
const ABROAD = /\b(?:international\w*|internationally|abroad|outside (?:of )?pakistan|overseas|worldwide|other countries|dubai|uae|usa|america|uk|london|england|canada|saudi|ksa|india|qatar|oman|australia|germany|china)\b/;
const DELIVERY_WORD = /\b(?:deliver\w*|delivry|ship|ships|shipping|shiping|courier|parcel|arrive|aayega|ayega|pohanch\w*)\b/;

const FAQ_TOPICS = [
  ['coupons', /\b(?:coupons?|cupon|promo ?codes?|promotion codes?|discount codes?|vouchers?|offer codes?|any codes?|voucher code)\b/],
  ['cod', /\b(?:cash on delivery|cash on delivry|c\.?o\.?d)\b/],
  ['card_safety', /\b(?:safe|secure|security|trust|fraud|scam|hack\w*)\b[^\n]*\b(?:card|pay|paying|payment|online)\b|\b(?:card|payment)\b[^\n]*\b(?:safe|secure|stored|store my)\b/],
  ['payment', /\b(?:payment|payments|paymnt|pay|paying|easypaisa|easy paisa|jazzcash|jazz cash|bank transfer|credit card|debit card|visa|mastercard|installments?|qist)\b/],
  ['international', null],
  ['delivery_days', /\b(?:sunday|saturday|weekends?|holidays?|eid|friday)\b/],
  ['shipping_fee', /\b(?:shipping|shiping|delivery|delivry)\s*(?:fee|fees|charge|charges|cost|costs|price|kitne|kitni)\b|\bfree (?:shipping|delivery|delivry)\b|\b(?:shipping|delivery) (?:is |hai )?free\b|\bhow much (?:is|for) (?:the )?(?:shipping|delivery)\b|\bminimum order\b/],
  ['delivery_time', /\b(?:how long|how many days|kitne din|kitne dino|kitny din|how much din|kab tak|when tak|delivery time|delivry time|shipping time|takes? to (?:deliver|arrive)|days? (?:for|to) (?:deliver\w*|arrive)|delivery takes?|how fast|how soon|when will (?:it|the order|my order|my parcel|it) (?:come|arrive)|estimated delivery)\b/],
  ['delivery_area', null],
  ['hours', /\b(?:working hours|opening hours|open(?:ing)? time|timings?|what time do you (?:open|close)|are you open|when are you open|24 ?\/ ?7|office hours|business hours)\b/],
  ['physical_store', /\b(?:physical (?:store|shop)|shop address|store address|outlet|showroom|visit (?:your|the) (?:store|shop|office)|where (?:is|are) (?:your|the) (?:store|shop|office|outlet)|real shop|offline store)\b/],
  ['contact', /\b(?:contact|customer (?:care|service|support)|support team|support|helpline|phone number|whatsapp number|email (?:you|support|address)|talk to (?:a |an )?(?:human|person|agent|real person)|complain|complaint|raabta)\b/],
  ['catalog', /\b(?:what (?:do|can) you (?:sell|offer)|what (?:do you|can i) (?:have|buy|get) (?:here|on zelora)|what (?:products|items|things|categories|brands) (?:do )?you (?:have|sell|stock|carry)|what categories|kya (?:bechte|milta)|what is available|what all do you have)\b/],
  ['warranty', /\bwarrant(?:y|ies)\b/],
  ['cancel', /\bcancel\w*\b/],
  ['returns', /\b(?:return|returns|refund|refunds|exchange|wapis|wapas)\b/],
];

const ABOUT_TOPICS = [
  ['creator', /\b(?:who (?:made|created|built|developed|designed|trained|programmed|owns)|hu made|your (?:creator|developer|maker|owner|company)|kis ?ne banaya|kisne banaya|made by|built by|developed by|which company)\b/],
  ['vendor', /\b(?:chat ?gpt|gpt|gemini|bard|openai|open ai|google|siri|alexa|cortana|claude|copilot|llama|meta ai|deepseek|grok)\b/],
  ['how', /\b(?:how (?:do|does) (?:you|it|this|zel) work|how (?:were|are) you (?:made|trained|built)|how do you (?:understand|know|think|pick|choose|recommend|learn)|kaise kaam|how does the assistant work|what technology|what model|how you work|explain how you)\b/],
  ['ai', /\b(?:what (?:is|s|does) (?:an? )?(?:ai|a i|artificial intelligence|machine learning|ml|nlp)\b|(?:ai|artificial intelligence) (?:kya|kia) (?:hai|hota)|define (?:ai|artificial intelligence))/],
  ['human', /\b(?:are (?:you|u) (?:a |an )?(?:human|real|person|robot|bot|machine|man|woman|girl|boy)|insaan ho|is zel a (?:human|person)|real person)\b/],
  ['age', /\b(?:how old are you|your age|your birthday|when were you (?:born|made))\b/],
  ['where', /\b(?:where do you live|where are you (?:from|located|based))\b/],
  ['memory', /\b(?:do you remember|do you learn from|do you store|do you save my|use the internet|are you online)\b/],
  ['intro', /\b(?:your name|who are (?:you|u)|kaun ho|which ho|what are (?:you|u)\b|wat r u|tell me about yourself|introduce yourself|about yourself)\b/],
];

const FEELING_TOPICS = [
  ['sad', /\b(?:sad|unhappy|depress\w*|down today|feeling down|upset|crying|cry|heart ?broken|broke up|left me|miss my|udaas|udas|dukhi|mood off|mood kharab|dil (?:udaas|toot)|nobody loves|feel empty|feel bad|bad day|terrible day|life is hard|i am sad)\b/],
  ['lonely', /\b(?:lonely|lonley|alone|akela|akeli|no friends)\b/],
  ['stressed', /\b(?:stress\w*|streesed|anxious|anxiety|worried|nervous|tension|pareshan|exams?|interview|scared|afraid|can'?t sleep|cannot sleep|tired|exhausted|thak gay[ai]|burn(?:ed|t)? out)\b/],
  ['angry', /\b(?:angry|frustrat\w*|annoyed|furious|gussa|i am angry|pissed)\b/],
  ['sick', /\b(?:sick|not feeling well|ill|fever|bimaar|beemar)\b/],
  ['happy', /\b(?:happy|so good|great day|excited|khush|passed my|got (?:a |the )?(?:new )?job|got promoted|my birthday|celebrat\w*|engaged|got married)\b/],
];

const VAGUE_RE = /\b(?:some(?:thing)?|any(?:thing)?|kuch|koi cheez|stuff)\b(?:\s+\w+){0,2}\s+(?:nice|good|cool|special|interesting|great|amazing|fun|unique|different|awesome|best|beautiful|exciting)\b|\b(?:surprise me|cheer me up|treat (?:my ?self|me)|(?:do not|don'?t|dont) know what to (?:buy|get|order)|no idea what to (?:buy|get)|not sure what to (?:buy|get)|confused what to buy|kya (?:lun|loon|khareedun)|show me anything|what should i (?:buy|get)(?: today)?$|something to buy|anything good|best thing you have|impress me|inspire me)\b/;

const PERSONAL_RE = /\b(?:my|mine|i ordered|i placed|mera|meri|mere|cw ?-?\d)\b/;
const HAS_LETTER = /[a-z]/;
const NON_LATIN = /[؀-ۿऀ-ॿ一-鿿Ѐ-ӿ]/;
const KEYBOARD_ROWS = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

const firstMatch = (list, text) => {
  for (const [key, re] of list) if (re && re.test(text)) return key;
  return null;
};

// both forms: raw catches roman-urdu spellings, normalized catches corrected typos
const views = (raw, normalized) => `${String(raw || '').toLowerCase().replace(/[’`]/g, "'")}\n${normalized || ''}`;

const keyboardMash = (w) => {
  if (w.length < 4) return false;
  if (/(.)\1{3,}/.test(w)) return true;
  if (!/[aeiouy]/.test(w)) return true;
  if (/[bcdfghjklmnpqrstvwxz]{5,}/.test(w)) return true;
  // 4+ letters in a row from one keyboard row ("asdf", "qwer", "hjkl")
  for (const row of KEYBOARD_ROWS) for (let i = 0; i + 4 <= row.length; i += 1) if (w.includes(row.slice(i, i + 4))) return true;
  return false;
};

const ROMAN_KNOWN = new Set([...Object.keys(L.ROMAN_URDU)]);

const isKnownWord = (w, vocab, modelVocab) => {
  if (L.STOPWORDS.has(w) || ROMAN_KNOWN.has(w)) return true;
  if (w.length <= 1) return false;
  if (modelVocab && (modelVocab.has(`w:${w}`) || modelVocab.has(`w:${stem(w)}`))) return true;
  if (!vocab) return true;
  return vocab.known.has(w) || vocab.known.has(stem(w)) || Boolean(vocab.corrector?.has(w)) || Boolean(vocab.corrector?.has(stem(w)));
};

// strong product evidence (keywords alone do not count: "elon musk" is not a product request)
const productEvidence = (e) => Boolean(e.categories.length || e.department || e.brands.length || e.features.length || e.color || e.occasion);

const detectNoise = ({ raw, tokens, entities, vocab, modelVocab }) => {
  const r = String(raw || '').trim();
  if (!tokens.length) {
    if (NON_LATIN.test(r)) return { kind: 'script' };
    return { kind: r.replace(/[\s\p{P}\p{S}]/gu, '').length ? 'emoji' : 'empty' };
  }
  const numeric = tokens.every((t) => /^\$?\d/.test(t) || ['rs', 'rupees', 'k', 'thousand', 'lakh'].includes(t));
  if (numeric && !HAS_LETTER.test(r.replace(/\b(?:rs|pkr|k|lac|lakh|rupees?)\b/gi, ''))) {
    const digits = r.replace(/[^\d]/g, '');
    return { kind: 'numbers', value: entities.budget?.target || entities.budget?.max || Number(digits) || null, digits };
  }
  const words = tokens.filter((t) => /^[a-z]+$/.test(t));
  if (!words.length || productEvidence(entities) || entities.budget || entities.ordinals.indices.length) return null;
  // gibberish = no recognisable word AND it looks like key-mashing (real but unknown words like "mouse" pass)
  if (words.some((w) => isKnownWord(w, vocab, modelVocab) && !keyboardMash(w))) return null;
  if (words.some(keyboardMash) || words.every((w) => w.length <= 2)) return { kind: 'gibberish' };
  return null;
};

const oosTopic = (text, e) => {
  for (const [key, re, strong] of OOS_TOPICS) {
    if (!re.test(text)) continue;
    const shopping = SHOP_RE.test(text) || e.budget;
    if (shopping) return null;
    if (!productEvidence(e)) return key;
    // strong topic + product word: still off-topic when it is chat ("who won the cricket match", long rambles)
    if (strong && (e._tokenCount > 14 || /\b(?:who|what do you think|kya khayal)\b/.test(text))) return key;
    return null;
  }
  return null;
};

const faqTopic = (text) => {
  if (ABROAD.test(text) && DELIVERY_WORD.test(text)) return 'international';
  for (const [key, re] of FAQ_TOPICS) {
    if (key === 'international') continue;
    if (key === 'delivery_area') {
      if (DELIVERY_WORD.test(text) && cityIn(text)) return 'delivery_area';
      continue;
    }
    if (key === 'delivery_days' && !DELIVERY_WORD.test(text) && !/\bopen\b/.test(text)) continue;
    if (key === 'delivery_time' && !DELIVERY_WORD.test(text) && !/\border\b/.test(text)) continue;
    if (re.test(text)) return key;
  }
  return null;
};

const cityIn = (text) => {
  for (const c of FAST_CITIES) if (new RegExp(`\\b${c}\\b`).test(text)) return { name: c, fast: true };
  for (const c of PK_CITIES) if (new RegExp(`\\b${c}\\b`).test(text)) return { name: c, fast: false };
  const m = text.match(/\b(?:deliver\w*|ship\w*)\s+(?:to|in|at)\s+([a-z]{3,}(?:\s[a-z]{3,})?)/);
  if (m && !/^(?:my|your|the|our|home|house|office|pakistan|all|every|any|other|me)\b/.test(m[1])) return { name: m[1].split(' ')[0], fast: false, unknown: true };
  return null;
};

const oosAny = (text) => OOS_TOPICS.find(([, re]) => re.test(text))?.[0] || null;

const detect = ({ raw, normalized, tokens, entities, vocab, modelVocab }) => {
  const text = views(raw, normalized);
  const e = { ...entities, _tokenCount: tokens.length };
  const noise = detectNoise({ raw, tokens, entities, vocab, modelVocab });
  const insult = INSULT_RE.test(text) && (AT_BOT_RE.test(text) || tokens.length <= 3);
  return {
    crisis: CRISIS_RE.test(text),
    profanity: PROFANITY_RE.test(text),
    insult,
    noise,
    oos: oosTopic(text, e),
    oosAny: oosAny(text),
    faq: faqTopic(text),
    about: firstMatch(ABOUT_TOPICS, text),
    feeling: firstMatch(FEELING_TOPICS, text),
    vague: VAGUE_RE.test(text) && !productEvidence(entities),
    personal: PERSONAL_RE.test(text),
    city: cityIn(text),
    abroad: ABROAD.test(text),
    shopping: SHOP_RE.test(text),
    strongProduct: productEvidence(entities),
  };
};

module.exports = {
  detect, oosTopic, faqTopic, cityIn, keyboardMash, views, productEvidence,
  CRISIS_RE, PROFANITY_RE, INSULT_RE, OOS_TOPICS, FAQ_TOPICS, ABOUT_TOPICS, FEELING_TOPICS, VAGUE_RE, FAST_CITIES, PK_CITIES,
};
