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

// provider override is for tests (a fake provider); production uses LLM_PROVIDER
const enhance = async (payload, { provider = active() } = {}) => {
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

module.exports = { enhance, info, active, grounded, buildPrompt, resetGuard };
