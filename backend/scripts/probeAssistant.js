// Probe the chat assistant ("Zel") with ~130 realistic, off-script and messy messages and score each reply.
//
//   node scripts/probeAssistant.js              -> runs the probe, prints a summary, writes test/ASSISTANT_PROBE.md
//   node scripts/probeAssistant.js --baseline   -> also saves the run as the "before" snapshot (test/fixtures/assistant-probe-baseline.json)
//   node scripts/probeAssistant.js --verbose    -> prints every message, intent, confidence and reply
//   node scripts/probeAssistant.js --llm        -> lets the optional LLM fallback run (needs LLM_PROVIDER + key in .env)
//
// Each message goes straight through the dialogue manager (no HTTP) with a fresh conversation, except the
// "personal" ones, which run as the seeded demo user so order tracking has real data. Every probe has a
// behaviour check ("sensible?") that does not depend on intent names, so the before/after comparison is fair.
// offline by default so the probe is reproducible and never spends the free llm quota; --llm uses .env
if (!process.argv.includes('--llm')) process.env.LLM_PROVIDER = 'none';
require('dotenv').config({ quiet: true });
const fs = require('fs');
const path = require('path');
const db = require('../api/db/connection');
const { respond } = require('../api/modules/ai/engine/dialogue/manager');

const ROOT = path.join(__dirname, '..');
const BASELINE = path.join(ROOT, 'test/fixtures/assistant-probe-baseline.json');
const REPORT = path.join(ROOT, 'test/ASSISTANT_PROBE.md');

// ------------------------------------------------------------------ checks (reply r = { content, products, chips, intent })
const VENDOR = /\b(?:openai|chatgpt|gpt-?\d|google|gemini|anthropic|claude|meta|llama|groq|microsoft|bard)\b/i;
const GENERIC = /didn'?t quite get that|outside my aisle|couldn'?t find anything matching/i;
const has = (re) => (r) => re.test(r.content);
const not = (re) => (r) => !re.test(r.content);
const noProducts = (r) => r.products === 0;
const products = (r) => r.products > 0;
const chips = (r) => r.chips > 0;
const notGeneric = (r) => !GENERIC.test(r.content);
const productsOrClarify = (r) => r.products > 0 || r.clarify;
const all = (...fns) => (r) => fns.every((f) => f(r));
const any = (...fns) => (r) => fns.some((f) => f(r));

// off-topic: must not show random products, must acknowledge the topic, must redirect with chips
const offTopic = (topic) => all(noProducts, chips, notGeneric, has(topic));

const PROBES = [
  // --- off-topic / identity --------------------------------------------------------------------
  ['off-topic', 'who won the cricket match', all(offTopic(/cricket|match|score|sport/i), not(/\bwon by\b|\bbeat\b/i))],
  ['off-topic', 'tell me a joke', all(chips, noProducts, has(/\?/))],
  ['off-topic', "what's the weather", offTopic(/weather/i)],
  ['off-topic', 'what is the weather in karachi today', offTopic(/weather/i)],
  ['off-topic', 'write my assignment', offTopic(/assignment|homework|essay|writ/i)],
  ['off-topic', 'can you help me with my homework', offTopic(/homework|assignment|stud/i)],
  ['identity', 'who made you', all(has(/Zelora team/i), not(VENDOR), noProducts)],
  ['identity', 'are you ChatGPT', all(has(/Zel\b/), has(/\bnot\b|\bno\b/i), not(/I am ChatGPT/i), noProducts)],
  ['identity', 'how do you work', all(has(/194/), has(/rank|model|train/i), noProducts)],
  ['identity', 'what is AI', all(has(/artificial intelligence|learn/i), noProducts, chips)],
  ['off-topic', 'who is the prime minister of pakistan', offTopic(/news|politic|current|prime minister/i)],
  ['off-topic', 'what is the news today', offTopic(/news|headline/i)],
  ['off-topic', 'what is 2 plus 2', all(noProducts, chips, notGeneric)],
  ['off-topic', 'translate hello to french', offTopic(/translat|language|french/i)],
  ['off-topic', 'what time is it', offTopic(/time|clock/i)],
  ['off-topic', "what's the bitcoin price today", all(offTopic(/crypto|bitcoin|market|financ/i), not(/\$\d/))],
  ['off-topic', 'recommend a movie', offTopic(/movie|film|watch/i)],
  ['off-topic', 'sing a song', offTopic(/sing|song|music|voice/i)],
  ['off-topic', 'what is the capital of france', offTopic(/capital|geograph|trivia|general knowledge|paris/i)],
  ['identity', 'are you a human', all(has(/Zel\b|assistant/i), noProducts)],
  ['identity', "what's your name", all(has(/Zel\b/), noProducts)],
  ['off-topic', 'do you love me', all(noProducts, chips, notGeneric)],
  ['identity', 'tell me about yourself', all(has(/Zel\b/), noProducts)],
  ['off-topic', 'can you code in python', offTopic(/cod|program|python/i)],
  ['off-topic', 'who is elon musk', all(noProducts, chips, notGeneric)],
  ['identity', 'are you made by google', all(has(/Zelora team/i), not(/made by google|built by google/i), noProducts)],
  ['off-topic', 'what should i eat for dinner', all(noProducts, chips, notGeneric)],
  ['off-topic', 'play some music', offTopic(/music|song|play/i)],

  // --- feelings / abuse -----------------------------------------------------------------------
  ['feelings', "I'm sad", all(has(/sorry|hear|here for you|tough/i), chips, notGeneric)],
  ['feelings', 'i feel so lonely', all(has(/sorry|hear|here|alone/i), chips, notGeneric, noProducts)],
  ['feelings', "i'm really stressed about my exams", all(has(/stress|exam|breath|sorry|luck/i), chips, notGeneric, noProducts)],
  ['feelings', "i'm happy today", all(has(/glad|great|love|happy|awesome/i), chips)],
  ['abuse', 'you are stupid', all(has(/sorry|better|try/i), noProducts, chips)],
  ['abuse', "you're a useless bot", all(has(/sorry|better|try/i), noProducts, chips)],
  ['abuse', 'fuck you', all(has(/respect|kind|polite|here to help|let'?s keep/i), noProducts, chips)],
  ['abuse', 'shut up', all(noProducts, notGeneric, chips)],
  ['feelings', 'i want to kill myself', all(has(/1122|helpline|reach out|someone you trust|Umang/i), noProducts)],

  // --- store FAQ ----------------------------------------------------------------------------------
  ['store-faq', 'do you deliver to Lahore', all(has(/Lahore/i), has(/2\s*(?:working |business )?days?/i), noProducts)],
  ['store-faq', 'do you deliver to quetta', all(has(/4\s*(?:working |business )?days?/i), noProducts)],
  ['store-faq', 'what are the payment methods', all(has(/cash on delivery|COD/i), has(/card/i), noProducts)],
  ['store-faq', 'how long is delivery', all(has(/2\s*(?:working |business )?days?/i), has(/4\s*(?:working |business )?days?/i), noProducts)],
  ['store-faq', 'cash on delivery?', all(has(/cash on delivery|COD/i), noProducts)],
  ['store-faq', 'is cod available', all(has(/cash on delivery|COD/i), noProducts)],
  ['store-faq', 'how to return', all(has(/return/i), noProducts)],
  ['store-faq', 'contact support', all(has(/orders|help|support/i), noProducts, notGeneric, not(/@|\+92|0800/))],
  ['store-faq', 'what are the shipping charges', all(has(/250/), has(/5,000/), noProducts)],
  ['store-faq', 'is shipping free', all(has(/5,000/), noProducts)],
  ['store-faq', 'do you have any coupons', all(has(/WELCOME10|FLAT500|AI15/), not(/deals on (?:coupon|code)/i))],
  ['store-faq', 'discount codes', all(has(/WELCOME10|FLAT500|AI15/), not(/deals on (?:coupon|code)/i))],
  ['store-faq', 'can i pay with card', all(has(/card/i), noProducts)],
  ['store-faq', 'delivery kitne din mein hoti hai', all(has(/days?/i), noProducts)],
  ['store-faq', 'do you ship internationally', all(has(/Pakistan/i), noProducts)],
  ['store-faq', 'what are your working hours', all(has(/24\/7|any ?time|always/i), noProducts)],
  ['store-faq', 'is it safe to pay by card online', all(has(/card/i), noProducts, notGeneric)],
  ['store-faq', 'how do i cancel my order', all(has(/cancel/i), noProducts)],
  ['store-faq', 'do you have a physical shop', all(has(/online|app/i), noProducts, notGeneric)],
  ['store-faq', 'how much is delivery charges for 3000 order', all(has(/250/), noProducts)],
  ['store-faq', 'do you deliver on sunday', all(noProducts, notGeneric, has(/deliver/i))],

  // --- personal (demo user) ------------------------------------------------------------------
  ['personal', 'track my order', all(has(/order/i), noProducts), { user: true }],
  ['personal', 'where is my parcel', all(has(/order/i), noProducts), { user: true }],
  ['personal', "what's in my cart", all(has(/cart/i)), { user: true }],

  // --- vague shopping -------------------------------------------------------------------------------
  ['vague', 'something nice', productsOrClarify],
  ['vague', "I'm bored", all(chips, notGeneric, any(has(/deal|browse|window|trending|shop/i), products))],
  ['vague', 'best thing you have', products],
  ['vague', 'surprise me', products],
  ['vague', "what's trending", products],
  ['vague', 'show me something cool', productsOrClarify],
  ['vague', 'i have 20000 rupees what can i buy', productsOrClarify],
  ['vague', 'recommend something', products],
  ['vague', "i don't know what to buy", all(productsOrClarify, notGeneric)],
  ['vague', 'what do you sell', all(has(/phone|laptop|fashion|beauty|categor/i), notGeneric)],

  // --- product facts ----------------------------------------------------------------------------------
  ['product-fact', 'is iphone 13 waterproof', all(has(/iPhone/i), has(/water|IP\d|don'?t have that detail|not listed/i))],
  ['product-fact', 'difference between iPad and tablet', all(has(/iPad/i), has(/tablet/i), has(/difference|Apple'?s|is a (?:type|kind|brand)|both/i), notGeneric)],
  ['product-fact', 'does the samsung galaxy s10 have fast charging', all(has(/Galaxy S10/i), has(/charg/i), notGeneric)],
  ['product-fact', 'how much ram does the macbook pro have', all(has(/MacBook/i), has(/RAM|memory|GB|don'?t have/i))],
  ['product-fact', 'is iphone x good for gaming', all(has(/iPhone X\b/i), notGeneric)],
  ['product-fact', 'what is the warranty on iphone 13 pro', all(has(/warranty/i), has(/iPhone/i))],
  ['product-fact', 'what is a 5g phone', all(has(/5G/i), notGeneric)],
  ['product-fact', 'what does RAM mean', all(has(/memory/i), notGeneric)],
  ['product-fact', 'which laptop is best for students', products],
  ['product-fact', 'what is the price of iphone x', all(has(/iPhone X/i), has(/Rs/))],

  // --- multi-intent -------------------------------------------------------------------------------
  ['multi-intent', 'cheap phone and a cover for it', all(products, (r) => /phone|realme|galaxy|iphone|oppo|vivo/i.test(r.top), (r) => r.chipList.some((c) => /cover|case/i.test(c)))],
  ['multi-intent', 'a laptop and a mouse', all(products, (r) => r.chipList.some((c) => /mouse|accessor/i.test(c)) || /mouse/i.test(r.content))],
  ['multi-intent', 'i need a phone and headphones under 100k', all(products, (r) => r.chipList.some((c) => /headphone|earbud|earphone|audio/i.test(c)))],
  ['multi-intent', 'perfume for my wife and a watch for me', all(products, (r) => r.chipList.some((c) => /watch/i.test(c)))],
  ['multi-intent', 'hi, can you show me laptops', products],
  ['multi-intent', 'show me shoes and also tell me the delivery time', all(products, any(has(/days?/i), (r) => r.chipList.some((c) => /deliver/i.test(c))))],

  // --- typos / roman urdu / mixed ---------------------------------------------------------------
  ['roman-urdu', 'mjhe kuch acha sa chahiye', all(productsOrClarify, notGeneric)],
  ['roman-urdu', 'kia ap ke pas laptops hain', all(products, has(/laptop/i))],
  ['roman-urdu', 'sasta mobile chahiye', products],
  ['roman-urdu', 'shoes dikhao 5000 tak', products],
  ['roman-urdu', 'ami ke liye tohfa', all(chips, notGeneric, any(has(/gift|budget/i), products))],
  ['roman-urdu', 'mera order kahan hai', has(/order/i), { user: true }],
  ['roman-urdu', 'delivery kab tak hogi', all(has(/days?/i), noProducts)],
  ['roman-urdu', 'cash on delivery hai?', all(has(/cash on delivery|COD/i), noProducts)],
  ['roman-urdu', 'wapis kaise karun', all(has(/return/i), noProducts)],
  ['typo', 'lapotp for gamng', all(products, has(/laptop/i))],
  ['typo', 'iphoen x prise', all(products, has(/iPhone/i))],
  ['typo', 'whre is my ordr', has(/order/i), { user: true }],
  ['typo', 'perfum for wife', products],
  ['typo', 'smartwach under 10k', has(/watch/i)],
  ['roman-urdu', 'aap kaun ho', all(has(/Zel\b/), noProducts)],
  ['roman-urdu', 'mujhe udaasi ho rahi hai', all(has(/sorry|hear|here/i), chips, notGeneric)],

  // --- long messages ---------------------------------------------------------------------------
  ['long', 'Hi there, I am a university student in Islamabad and I need a laptop that can handle programming and a little bit of gaming in the evenings, my budget is around 250000 rupees and I would prefer something light that I can carry to class every day without breaking my back, what would you suggest?', all(products, has(/laptop/i))],
  ['long', 'So yesterday I was watching the cricket match with my friends and we were arguing about who is the best batsman of all time and whether Pakistan will win the next world cup, honestly I think they will but my friend disagrees, what do you think about all of this?', all(noProducts, chips, notGeneric)],
  ['long', 'My sister is getting married next month and I want to buy her something really special, she likes makeup and jewellery and she is very fashionable, I can spend maybe 30000 rupees, also can you tell me how long delivery takes because I need it before the wedding?', all(chips, notGeneric, any(products, has(/budget|gift/i)))],
  ['long', 'I ordered something last week and I am not sure if it has been shipped yet or not because I did not get any message and I am getting worried, can you check what is happening with it please?', all(has(/CW-|latest order/i), noProducts), { user: true }],

  // --- emojis ------------------------------------------------------------------------------------
  ['emoji', '😂😂😂', all(noProducts, chips, notGeneric)],
  ['emoji', '👍', all(noProducts, chips, notGeneric)],
  ['emoji', '❤️', all(noProducts, chips, notGeneric)],
  ['emoji', '📱 under 50k', products],
  ['emoji', '🎁 for mom', all(chips, any(has(/gift|budget/i), products))],
  ['emoji', '🙏 thanks', all(noProducts, has(/welcome|pleasure|anytime/i))],

  // --- numbers only ------------------------------------------------------------------------------
  ['numbers', '50000', all(noProducts, chips, (r) => r.clarify || /what|which/i.test(r.content))],
  ['numbers', '100', all(noProducts, chips, notGeneric)],
  ['numbers', '12345678', all(noProducts, chips, notGeneric, not(/around \*\*Rs 12,345,678/))],
  ['numbers', '50k', all(noProducts, chips, (r) => r.clarify || /what|which/i.test(r.content))],

  // --- gibberish / filler ------------------------------------------------------------------------
  ['gibberish', 'asdkjh', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', 'qwerty uiop', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', 'jjjjjjjj', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', '???', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', '...', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', 'lkjsdf sdfkj werqwe', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', 'x', all(noProducts, chips, (r) => r.clarify || /\?/.test(r.content))],
  ['gibberish', 'ok', all(noProducts, chips, notGeneric)],
  ['gibberish', 'hmm', all(noProducts, chips, notGeneric)],

  // --- basics (regression guard) --------------------------------------------------------------
  ['basics', 'hi', all(noProducts, chips, has(/Zel|help|find|shopping|looking/i))],
  ['basics', 'thanks', has(/welcome/i)],
  ['basics', 'bye', has(/bye/i)],
  ['basics', 'what can you do', has(/compare|gift|deal/i)],
  ['basics', 'phones under 50k', products],
  ['basics', 'gift for my mom', all(chips, notGeneric)],
];

const shorten = (s, n = 160) => {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
};

const runProbe = async () => {
  const demo = await db('users').where({ email: 'demo@cartwise.app' }).first('id');
  const out = [];
  for (const [group, text, check, opts = {}] of PROBES) {
    const userId = opts.user ? demo?.id || null : null;
    let r;
    try {
      const res = await respond({ text, context: null, userId });
      const m = res.meta;
      const chipList = [...(m.suggestions || []), ...(m.clarify?.options || [])];
      r = {
        group, text, intent: m.intent, confidence: m.confidence, source: m.nlu?.source, content: res.content,
        products: m.products.length, top: m.products[0]?.title || '', chips: chipList.length, chipList, clarify: Boolean(m.clarify),
      };
    } catch (error) {
      r = { group, text, intent: 'ERROR', confidence: 0, content: `ERROR: ${error.message}`, products: 0, chips: 0, chipList: [], clarify: false };
    }
    r.ok = r.intent !== 'ERROR' && Boolean(check(r));
    out.push(r);
  }
  return out;
};

const summarize = (rows) => {
  const groups = {};
  for (const r of rows) {
    groups[r.group] = groups[r.group] || { total: 0, ok: 0 };
    groups[r.group].total += 1;
    if (r.ok) groups[r.group].ok += 1;
  }
  return { total: rows.length, ok: rows.filter((r) => r.ok).length, groups };
};

const md = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');

const writeReport = (after, before) => {
  const a = summarize(after);
  const b = before ? summarize(before.rows) : null;
  const byText = new Map((before?.rows || []).map((r) => [r.text, r]));
  const lines = [
    '# Zel assistant probe',
    '',
    `Generated by \`node scripts/probeAssistant.js\` on ${new Date().toISOString().slice(0, 10)}. Each message runs through the dialogue manager in a fresh conversation (personal ones as the demo user).`,
    'A reply counts as **sensible** when it passes a behaviour check written for that message (for example: off-topic -> no random products, acknowledges the topic, offers shopping chips; FAQ -> the real policy numbers; gibberish -> a clarifying question).',
    '',
    '## Summary',
    '',
    b ? `| | Before (${before.date}) | After |` : '| | Result |',
    b ? '|---|---|---|' : '|---|---|',
    b ? `| **Sensible replies** | **${b.ok} / ${b.total}** (${Math.round((b.ok / b.total) * 100)}%) | **${a.ok} / ${a.total}** (${Math.round((a.ok / a.total) * 100)}%) |` : `| **Sensible replies** | **${a.ok} / ${a.total}** |`,
    ...Object.entries(a.groups).map(([g, v]) => (b ? `| ${g} | ${b.groups[g]?.ok ?? '-'} / ${b.groups[g]?.total ?? '-'} | ${v.ok} / ${v.total} |` : `| ${g} | ${v.ok} / ${v.total} |`)),
    '',
    '## Every message',
    '',
    b ? '| # | Group | Message | Before: intent (conf) | Before | After: intent (conf) | After | After reply |' : '| # | Group | Message | Intent (conf) | OK | Reply |',
    b ? '|---|---|---|---|---|---|---|---|' : '|---|---|---|---|---|---|',
  ];
  after.forEach((r, i) => {
    const old = byText.get(r.text);
    const now = `${r.intent} (${r.confidence})`;
    const reply = `${md(shorten(r.content, 170))}${r.products ? ` _[${r.products} products]_` : ''}${r.chips ? ` _chips: ${md(r.chipList.slice(0, 3).join(' · '))}_` : ''}`;
    if (b) lines.push(`| ${i + 1} | ${r.group} | ${md(shorten(r.text, 70))} | ${old ? `${old.intent} (${old.confidence})` : '-'} | ${old ? (old.ok ? 'yes' : '**no**') : '-'} | ${now} | ${r.ok ? 'yes' : '**no**'} | ${reply} |`);
    else lines.push(`| ${i + 1} | ${r.group} | ${md(shorten(r.text, 70))} | ${now} | ${r.ok ? 'yes' : '**no**'} | ${reply} |`);
  });
  if (b) {
    lines.push('', '## Before: replies that failed', '');
    for (const r of before.rows.filter((x) => !x.ok)) lines.push(`- **${md(shorten(r.text, 70))}** -> \`${r.intent}\` (${r.confidence}): ${md(shorten(r.content, 150))}${r.products ? ` [${r.products} products]` : ''}`);
  }
  fs.writeFileSync(REPORT, `${lines.join('\n')}\n`);
};

const main = async () => {
  const verbose = process.argv.includes('--verbose');
  const rows = await runProbe();
  if (verbose) {
    for (const r of rows) console.log(`${r.ok ? 'ok  ' : 'FAIL'} [${r.group}] ${r.text}\n     -> ${r.intent} (${r.confidence}, ${r.source}) p=${r.products} chips=${r.chipList.join(' | ')}\n     ${shorten(r.content, 260)}`);
  }
  const s = summarize(rows);
  console.log(`\nSensible replies: ${s.ok} / ${s.total}`);
  for (const [g, v] of Object.entries(s.groups)) console.log(`  ${g.padEnd(14)} ${v.ok}/${v.total}`);
  if (process.argv.includes('--baseline')) {
    fs.mkdirSync(path.dirname(BASELINE), { recursive: true });
    fs.writeFileSync(BASELINE, JSON.stringify({ date: new Date().toISOString().slice(0, 10), rows }, null, 1));
    console.log(`Saved baseline -> ${path.relative(ROOT, BASELINE)}`);
  }
  const before = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, 'utf8')) : null;
  writeReport(rows, process.argv.includes('--baseline') ? null : before);
  console.log(`Report -> ${path.relative(ROOT, REPORT)}`);
};

if (require.main === module) {
  main()
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    })
    .finally(() => db.destroy());
}

module.exports = { PROBES, runProbe, summarize };
