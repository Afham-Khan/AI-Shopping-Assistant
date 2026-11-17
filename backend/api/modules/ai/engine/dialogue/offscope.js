// replies for everything off the shopping script: off-topic questions, questions about Zel, feelings,
// abuse, crisis and unreadable input. short, honest (never pretends to know live facts), on brand, and
// always hands the shopper a way back to shopping with chips.
const { pick, money, shortMoney } = require('../format');

const SHOP_CHIPS = ['Recommend something', "Today's deals", 'Gift ideas'];
const CATEGORY_OPTIONS = ['Phones', 'Laptops', 'Fashion', 'Beauty', 'Home & kitchen', 'Gifts'];

// tiny, safe arithmetic for "what is 2 plus 2" (two numbers, one operator)
const arithmetic = (text) => {
  const m = String(text).match(/(-?\d+(?:\.\d+)?)\s*(plus|\+|minus|-|times|x|\*|into|multiplied by|divided by|\/)\s*(-?\d+(?:\.\d+)?)/);
  if (!m) return null;
  const a = Number(m[1]);
  const b = Number(m[3]);
  const op = m[2];
  let v;
  if (op === 'plus' || op === '+') v = a + b;
  else if (op === 'minus' || op === '-') v = a - b;
  else if (op === 'divided by' || op === '/') v = b === 0 ? null : a / b;
  else v = a * b;
  if (v === null || !Number.isFinite(v)) return null;
  return { expr: `${m[1]} ${['plus', '+'].includes(op) ? '+' : ['minus', '-'].includes(op) ? '−' : ['divided by', '/'].includes(op) ? '÷' : '×'} ${m[3]}`, value: Math.round(v * 1000) / 1000 };
};

const pkTime = () => {
  const now = new Date();
  const time = now.toLocaleTimeString('en-US', { timeZone: 'Asia/Karachi', hour: 'numeric', minute: '2-digit' });
  const date = now.toLocaleDateString('en-GB', { timeZone: 'Asia/Karachi', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  return { time, date };
};

const JOKES = [
  'Why did the shopping cart go to therapy? It had too much baggage!',
  'I tried to catch some fog yesterday. Mist. Luckily our deals are easier to catch.',
  "Why don't phones ever get lonely? They always have their contacts.",
  'My wallet is like an onion: opening it makes me cry. Good thing I know where the discounts are!',
  'Why did the laptop go to the doctor? It had a byte. Want me to find you a healthy one?',
];

const OOS = {
  weather: () => ({
    content: "I can't check the weather: I don't have live data, only Zelora's catalog. If it's sunny out there, I can find you a good pair of sunglasses; if not, maybe something cosy for home?",
    suggestions: ['Sunglasses', 'Home decor', "Today's deals"],
  }),
  sports: () => ({
    content: "I don't follow live scores, so I can't tell you who won, and I'd only be guessing. What I can do is kit you out for the next match: cricket bats, balls, helmets and more.",
    suggestions: ['Cricket gear', 'Sports equipment', "Today's deals"],
  }),
  news: () => ({
    content: "I don't have news or current affairs: I only know Zelora's store, so I won't guess about politics or headlines. Want to see what's trending in the shop instead?",
    suggestions: ['Trending products', "Today's deals", 'Gift ideas'],
  }),
  study: () => ({
    content: "I can't write assignments or homework for you: that part's all yours (and you've got this!). What I can do is set you up to study: a good laptop, a tablet for notes, or headphones to focus.",
    suggestions: ['Laptops for students', 'Tablets', 'Headphones'],
  }),
  code: () => ({
    content: "Coding help isn't something I do: I'm built only for shopping on Zelora. But if you need a machine that compiles fast, I know some great laptops for programming.",
    suggestions: ['Laptops for programming', 'Gaming laptops', 'Help'],
  }),
  math: ({ text }) => {
    const r = arithmetic(text);
    return r
      ? { content: `${r.expr} = **${r.value}**. Maths is easy; finding the best phone for your budget is my real talent!`, suggestions: ['Phones under 50k', "Today's deals", 'Recommend something'] }
      : { content: "Maths isn't really my thing: prices are! I can tell you exactly what fits your budget, though. Give me a number and a category.", suggestions: ['Phones under 50k', 'Laptops under 200k', 'Gifts under 5k'] };
  },
  time: () => {
    const { time, date } = pkTime();
    return { content: `It's **${time}** (Pakistan time) on ${date}. Perfect time for a little shopping: want to see today's deals?`, suggestions: ["Today's deals", 'Recommend something', 'Gift ideas'] };
  },
  translate: () => ({
    content: "I'm not a translator, but I do understand English and Roman Urdu when you shop: try *sasta mobile chahiye* or *ami ke liye tohfa*.",
    suggestions: ['sasta mobile chahiye', 'Gift for mom', 'Help'],
  }),
  finance: () => ({
    content: "I don't track crypto, stocks or exchange rates, and I can't give financial advice. What I *can* track is product prices: watch any product and I'll alert you when it drops.",
    suggestions: ["Today's deals", 'Phones under 50k', 'Help'],
  }),
  booking: () => ({
    content: "I can't book rides, set alarms or send messages: I live inside the Zelora shop. I can find products, compare them, suggest gifts and check your orders.",
    suggestions: ['Where is my order?', 'Recommend something', 'Help'],
  }),
  entertainment: ({ text }) => (/\b(?:song|songs|music|sing|singing|lyrics)\b/.test(text)
    ? { content: "I can't sing or play music (my voice is all text!), but I can find you earbuds, headphones or a smart speaker to play yours.", suggestions: ['Headphones', 'Earbuds', 'Smart speakers'] }
    : /\b(?:story|stories)\b/.test(text)
      ? { content: "Here's a short one: a shopper wanted the perfect gift, told Zel who it was for and the budget, and found it in ten seconds. The end! Want to write your own story?", suggestions: ['Gift ideas', 'Recommend something', "Today's deals"] }
      : { content: "I can't recommend movies or shows, but I can set up your movie night: a tablet for the big screen, headphones, or snacks from our pantry aisle.", suggestions: ['Tablets', 'Headphones', 'Snacks'] }),
  food: () => ({
    content: "I can't cook (no hands!), but our **Fresh & Pantry** aisle and **kitchen accessories** can help you make dinner happen.",
    suggestions: ['Fresh & pantry', 'Kitchen accessories', "Today's deals"],
  }),
  health: () => ({
    content: "I'm not able to give medical advice: please check with a doctor or pharmacist. If you're looking for skin care or fitness gear, I'm happy to help with that.",
    suggestions: ['Skin care', 'Sports equipment', 'Help'],
  }),
  people: () => ({
    content: "I don't have information about people or public figures: I only know Zelora's products, so I'd rather not guess. Ask me about any product, price or order instead!",
    suggestions: ['Recommend something', "Today's deals", 'Help'],
  }),
  knowledge: () => ({
    content: "That's a general knowledge question, and I'm built only for shopping on Zelora, so I'd rather not guess. Ask me anything about products, prices, delivery or your orders!",
    suggestions: ['Recommend something', 'How long is delivery?', "Today's deals"],
  }),
  love: () => ({
    content: "That's sweet! My heart belongs to great deals, though. Can I find you something nice?",
    suggestions: SHOP_CHIPS,
  }),
  general: () => ({
    content: "That's outside what I know: I'm Zel, built just for shopping on Zelora, so I won't guess. I can find products, compare them, suggest gifts or check your order.",
    suggestions: ['Recommend something', 'Gift ideas', 'Where is my order?'],
  }),
};

const outOfScope = (topic, t) => {
  const r = (OOS[topic] || OOS.general)(t);
  return { ...r, scope: { kind: 'out_of_scope', topic: topic || 'general' } };
};

const joke = (seed) => ({
  content: `${pick(JOKES, seed)} Speaking of shopping, want me to find you something?`,
  suggestions: ['Another joke', "Today's deals", 'Recommend something'],
});

const ABOUT = {
  creator: () => "I'm **Zel**, Zelora's shopping assistant, built by the Zelora team. I was trained on Zelora's own shopping conversations and catalog, so I'm all about helping you find the right product at the right price.",
  vendor: () => "Nope, I'm **Zel**, Zelora's own shopping assistant, built by the Zelora team. I'm not a general chatbot: I run on a model trained just for shopping on Zelora, so I'm best at finding, comparing and explaining products.",
  how: ({ catalog }) => `Here's the short, honest version:\n1. **I understand your message**: I fix typos, read Roman Urdu, and a trained intent model works out what you want (plus budget, brand, colour and who it's for).\n2. **I search all ${catalog.products.length} products** in Zelora's catalog, by keywords and by meaning.\n3. **I rank and explain**: by how well each fits, ratings, price and your taste, and I tell you why each pick made the list.`,
  ai: () => "**AI (artificial intelligence)** is software that learns patterns from examples instead of following only hand-written rules. I'm a small, practical example: I learned from thousands of example shopping messages to understand what you mean, then I search and rank Zelora's products for you.",
  human: () => "I'm not a human: I'm **Zel**, Zelora's virtual shopping assistant, built by the Zelora team. I'm quick, though: tell me what you need and I'll find it in seconds.",
  age: ({ catalog }) => `I'm still new: I live in the Zelora app and was built by the Zelora team. Young, but I already know all ${catalog.products.length} products by heart!`,
  where: () => "I live right here inside the Zelora app, available 24/7 wherever you are in Pakistan.",
  memory: () => "I remember what we've talked about in this chat (so *the second one* or *cheaper* make sense), and if you're signed in I use your browsing and orders to personalise picks. I don't browse the internet: I only know Zelora's store.",
  intro: () => "I'm **Zel**, Zelora's shopping assistant, built by the Zelora team. I can find products from plain language, compare them, suggest gifts, explain specs, and check your orders, cart and deals.",
};

const aboutAssistant = (topic, t) => ({
  content: (ABOUT[topic] || ABOUT.intro)(t),
  suggestions: topic === 'how' ? ['Phones under 50k', 'Compare iPhone X and Galaxy S10', 'Gift for my sister'] : ['How do you work?', 'Phones under 50k', 'Gift ideas', "Today's deals"],
  scope: { kind: 'about', topic: topic || 'intro' },
});

const CRISIS = "I'm really sorry you're feeling this way, and I'm glad you told me. You deserve support right now: please reach out to someone you trust, or a professional. In Pakistan, **Umang** runs a free 24/7 mental-health helpline (umang.com.pk), and in an emergency you can call **1122** (Rescue) or **115** (Edhi). If you're outside Pakistan, please call your local emergency number. I'm only a shopping assistant, but you're not alone.";

const FEELINGS = {
  crisis: () => ({ content: CRISIS, suggestions: [] }),
  sad: () => ({
    content: "I'm sorry you're feeling down. I'm just a shopping assistant, but I'm here, and talking to a friend or someone you trust can really help. If you'd like a small distraction, I can show you something to brighten your day.",
    suggestions: ['Something to cheer me up', 'Gift ideas', "Today's deals"],
  }),
  lonely: () => ({
    content: "I'm sorry you're feeling lonely, and you're not alone in feeling that way. Reaching out to a friend or family member, even with a short message, can really help. I'm here to chat about shopping anytime, too.",
    suggestions: ['Something to cheer me up', 'Gift for a friend', "Today's deals"],
  }),
  stressed: () => ({
    content: "That sounds like a lot. Take a deep breath: you've got this, one step at a time. If it helps, I can find something useful for studying or relaxing, or we can just browse for a bit.",
    suggestions: ['Laptops for students', 'Headphones', 'Something to cheer me up'],
  }),
  angry: () => ({
    content: "Sorry you're frustrated. If something went wrong with an order or a product, tell me and I'll help sort it out.",
    suggestions: ['Where is my order?', 'Return policy', 'Contact support'],
  }),
  sick: () => ({
    content: "Sorry you're not feeling well. I hope you feel better soon: rest up, and please see a doctor if it doesn't improve. I'll be here when you're ready to shop.",
    suggestions: ['Skin care', 'Fresh & pantry', "Today's deals"],
  }),
  happy: () => ({
    content: "Love to hear that! Want to celebrate with a little treat while the mood is good?",
    suggestions: ['Treat myself', "Today's deals", 'Trending products'],
  }),
  general: () => ({
    content: "Thanks for sharing that with me. I'm a shopping assistant, so I can't do much about feelings, but I'm here whenever you want to browse, compare or find a gift.",
    suggestions: SHOP_CHIPS,
  }),
};

const feelings = (topic, t) => ({ ...(FEELINGS[topic] || FEELINGS.general)(t), scope: { kind: 'feelings', topic: topic || 'general' } });

const abuse = (kind, t) => {
  if (kind === 'profanity') {
    return {
      content: "Let's keep it friendly: I'm here to help. If I got something wrong, tell me what you're looking for and I'll fix it.",
      suggestions: ['Phones under 50k', 'Gift ideas', 'Help'],
      scope: { kind: 'abuse', topic: 'profanity' },
    };
  }
  if (/\b(?:shut ?up|chup|go away|get lost)\b/.test(t.text) || /\b(?:shut ?up|chup)\b/.test(String(t.raw).toLowerCase())) {
    return {
      content: "Okay, I'll keep quiet until you need me. Just type what you're looking for anytime.",
      suggestions: ['Recommend something', "Today's deals", 'Help'],
      scope: { kind: 'abuse', topic: 'dismiss' },
    };
  }
  return {
    content: pick([
      "Sorry I missed the mark. Tell me the product, budget or brand you want and I'll do better.",
      "Fair enough, I'm still learning. Try me with something like *phones under 50k* or *gift for my sister* and let me prove it.",
    ], t.seed),
    suggestions: ['Phones under 50k', 'Gift for my sister', 'Help'],
    scope: { kind: 'abuse', topic: 'insult' },
  };
};

const clarifyOptions = () => ({ question: 'What are you shopping for?', options: CATEGORY_OPTIONS });

// unreadable input: ask instead of guessing products
const unclear = (kind, t) => {
  const base = { clarify: clarifyOptions(), pending: { type: 'shopping_what' }, suggestions: [], scope: { kind: 'unclear', topic: kind } };
  if (kind === 'script') {
    return { ...base, content: 'I understand English and Roman Urdu (Urdu written in English letters). Try something like *mera order kahan hai* or *sasta mobile chahiye*. What are you shopping for?' };
  }
  if (kind === 'emoji') return { ...base, content: 'Nice emoji! I speak words better, though. What are you shopping for today?' };
  if (kind === 'empty') return { ...base, content: 'Looks like your message got lost on the way! What can I help you find?' };
  if (kind === 'numbers') {
    const { n, min, max, digits } = t.number;
    if (n && n < min) {
      return { ...base, content: `Is **${money(n)}** your budget? Our most affordable items start at **${money(min)}**. Tell me what you're looking for and I'll find the best match, or pick a category.`, clarify: { question: 'What are you shopping for?', options: [`Things under ${shortMoney(Math.max(1000, Math.ceil((min * 3) / 1000) * 1000))}`, 'Phones', 'Beauty', 'Groceries', 'Gifts'] } };
    }
    return {
      ...base,
      content: `**${digits}** doesn't look like a budget I can shop with${n > max ? ` (our priciest item is ${money(max)})` : ''}. Is it an order number? Order numbers look like *CW-251117-AB12CD*. Otherwise, tell me what you're looking for.`,
      clarify: { question: 'What did you mean?', options: ['Where is my order?', 'Phones', 'Laptops', 'Cars'] },
      pending: null,
    };
  }
  if (kind === 'gibberish') {
    return { ...base, content: "Hmm, I couldn't make sense of that one. Maybe a typo? What are you shopping for today?" };
  }
  return {
    ...base,
    content: "I'm not sure I followed. Could you say it another way? For example *phones under 50k*, *gift for my sister* or *where is my order*. Or pick a category:",
  };
};

module.exports = { outOfScope, aboutAssistant, feelings, abuse, unclear, joke, arithmetic, CRISIS, JOKES };
