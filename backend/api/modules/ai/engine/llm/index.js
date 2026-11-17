// optional rag-style reply polish: the llm only rewrites the template reply from structured facts.
// output is validated (no new prices/numbers, length) and any failure silently keeps the local reply.
const providers = require('./providers');
const { createGuard } = require('./guard');

// one guard per process: rate limit + daily cap + response cache + circuit breaker
let guard = createGuard();
const resetGuard = (options) => {
  guard = createGuard(options);
  return guard;
};

const SYSTEM = [
  'You are Zel, the friendly shopping assistant for a Pakistani store (prices in PKR).',
  'Rewrite the DRAFT reply so it sounds natural, warm and concise (max 70 words).',
  'Strict rules: use ONLY the facts given. Never invent products, prices, specs, discounts or policies.',
  'Keep every price exactly as written (e.g. "Rs 45,999") and keep **bold** markdown on prices and product names.',
  'Do not list products the draft does not mention. Do not add greetings if the draft has none. Reply with the rewritten text only.',
].join(' ');

const active = () => {
  const name = (process.env.LLM_PROVIDER || 'none').toLowerCase();
  const provider = providers[name];
  return provider && provider.enabled() ? provider : null;
};

const info = () => {
  const name = (process.env.LLM_PROVIDER || 'none').toLowerCase();
  const provider = providers[name];
  return { provider: provider ? name : 'none', model: provider ? provider.model() : null, enabled: Boolean(provider && provider.enabled()), ...guard.info() };
};

// only product facts and the user's query — never personal data
const buildPrompt = ({ query, draft, intent, products = [], facts = [] }) => {
  const lines = products.slice(0, 6).map((p, i) =>
    `${i + 1}. ${p.title}${p.brand ? ` (${p.brand})` : ''} — Rs ${Math.round(p.price).toLocaleString('en-US')}, ${p.rating}★ (${p.ratingCount} reviews)${p.match?.reasons?.length ? `; why: ${p.match.reasons.join('; ')}` : ''}`);
  return [
    `Shopper asked: "${String(query).slice(0, 300)}"`,
    `Intent: ${intent}`,
    lines.length ? `Products shown (in order):\n${lines.join('\n')}` : 'No products shown.',
    facts.length ? `Facts:\n- ${facts.join('\n- ')}` : '',
    `DRAFT:\n${draft}`,
  ].filter(Boolean).join('\n\n');
};

const numbersIn = (text) => new Set((String(text).replace(/,/g, '').match(/\d+(?:\.\d+)?/g) || []).map(Number));

// grounding check: every number in the rewrite must exist in the draft or the facts
const grounded = (rewrite, draft, context) => {
  if (!rewrite || rewrite.length < 10 || rewrite.length > 700) return false;
  const allowed = new Set([...numbersIn(draft), ...numbersIn(context)]);
  for (const n of numbersIn(rewrite)) if (!allowed.has(n) && n > 10) return false;
  return true;
};

// ---------------------------------------------------------------- general (out-of-scope) answers
// persona-locked: Zel answers harmless general questions in one or two sentences, never live facts,
// never products/prices, never names an ai vendor; then steers back to shopping.
const PERSONA = [
  'You are Zel, the shopping assistant inside the Zelora app, a Pakistani online store. You were built by the Zelora team.',
  'The shopper asked something that is not about shopping. Reply in at most 2 short sentences (max 45 words).',
  'If it is harmless general knowledge you are sure about, answer it briefly. If it needs live or current information (weather, news, sports scores, prices, rates, today\'s events), say you cannot check live information.',
  'Never give medical, legal or financial advice. Never write essays, homework, or code.',
  'End by inviting them back to shopping in a friendly way.',
  'Never mention specific products, brands, prices, discounts, delivery times or store policies. Never name or hint at any AI company, model or chatbot; you are only Zel.',
  'Reply with the text only, no markdown headings.',
].join(' ');

const VENDOR_RE = /\b(?:openai|chat ?gpt|gpt-?\d|google|gemini|anthropic|claude|meta|llama|groq|microsoft|bard|mistral|deepseek|language model|llm)\b/i;

// the reply must be short, plain, persona-safe and must not invent prices or numbers about the store
const generalOk = (text) => Boolean(text)
  && text.length >= 8 && text.length <= 420
  && !VENDOR_RE.test(text)
  && !/(?:\brs\.?|\bpkr\b|rupees?|\$|€|£)\s*\d/i.test(text)
  && !/https?:\/\//i.test(text)
  && !/```/.test(text);

const general = async ({ query, fallback, topic = 'general' }, { provider = active() } = {}) => {
  if (!provider) return { content: fallback, source: 'local' };
  const user = `Shopper asked: "${String(query).slice(0, 300)}"\nTopic hint: ${topic}`;
  try {
    const result = await guard.run([provider.name, provider.model?.(), PERSONA, user], async () =>
      (await provider.complete({ system: PERSONA, user })).replace(/^["']|["']$/g, '').trim());
    if (result.skipped) return { content: fallback, source: 'local', skipped: result.skipped };
    if (generalOk(result.value)) return { content: result.value, source: provider.name, cached: result.from === 'cache' };
  } catch {
    // timeout, quota, network or bad key: the offline reply is always ready
  }
  return { content: fallback, source: 'local' };
};

// provider override is for tests (a fake provider); production uses LLM_PROVIDER
// rewording normal replies costs a network round-trip per message, so it is opt-in (LLM_REWRITE=on);
// the llm still answers out-of-scope questions through general()
const rewriteEnabled = () => (process.env.LLM_REWRITE || 'off').toLowerCase() === 'on';

const enhance = async (payload, options = {}) => {
  if (!('provider' in options) && !rewriteEnabled()) return { content: payload.draft, source: 'local' };
  const provider = 'provider' in options ? options.provider : active();
  if (!provider) return { content: payload.draft, source: 'local' };
  const user = buildPrompt(payload);
  try {
    // same prompt + facts -> cached rewrite; rate limit / daily cap / open circuit -> local reply
    const result = await guard.run([provider.name, provider.model?.(), SYSTEM, user], async () =>
      (await provider.complete({ system: SYSTEM, user })).replace(/^["']|["']$/g, '').trim());
    if (result.skipped) return { content: payload.draft, source: 'local', skipped: result.skipped };
    if (grounded(result.value, payload.draft, user)) return { content: result.value, source: provider.name, cached: result.from === 'cache' };
  } catch {
    // timeout, quota or network: the template reply is always good enough
  }
  return { content: payload.draft, source: 'local' };
};

module.exports = { enhance, general, generalOk, info, active, grounded, buildPrompt, resetGuard, PERSONA };
