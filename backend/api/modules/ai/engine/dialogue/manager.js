// dialogue manager: intent + entities + persisted state -> handler -> reply, products, chips, actions
const models = require('../../models/ai.models');
const L = require('../nlu/lexicon');
const { analyze, publicEntities } = require('../nlu');
const { getCatalog } = require('../retrieval/catalog');
const { retrieve, applyFilters, filtersFromSlots } = require('../retrieval/search');
const { getProfile } = require('../ranking/personalization');
const { recommendations, similar, boughtTogether } = require('../ranking/recommender');
const { compareProducts } = require('../compare');
const { reviewSummary } = require('../reviews/summary');
const llm = require('../llm');
const { buildBundle } = require('../bundle');
const qa = require('../qa');
const nlg = require('./nlg');
const S = require('./state');
const { recommendedList, serializeBundle } = require('../serialize');
const { explainProduct } = require('../explain');
const { buildGift } = require('../gift');
const { completeLook, FASHION } = require('../outfit');
const { money, stars, list, titleCase, truncate, plural, shortMoney } = require('../format');
const faq = require('./faq');
const off = require('./offscope');
const { conceptQuery } = require('../concepts');
const { findNamedProduct } = require('../retrieval/named');

const CHAT_LIMIT = 5;
const FREE_SHIPPING = 5000;
const NO_LIMIT = /\b(?:no limit|any budget|doesn'?t matter|does not matter|koi bhi|anything|no budget|whatever)\b/;
const SEARCH_FAMILY = new Set(['product_search', 'recommendation', 'budget_query', 'refine_cheaper', 'refine_premium', 'refine_filter', 'show_more', 'gift_suggestion', 'deals']);
// off-script routing helpers (the optional llm only answers out_of_scope, with its own persona prompt)
const SLOT_PENDING = new Set(['gift_recipient', 'gift_budget', 'gift_interest', 'bundle_budget', 'which_product']);
const FACT_Q = /^(?:is|does|do|can|has|have|will|are|kya|how (?:much|many|long|good|big|heavy|fast)|what(?: is|s)? (?:the )?(?:price|cost|warranty|battery|ram|storage|camera|screen|display|size|weight|colou?r|return|rating|processor|specs?))\b|\b(?:waterproof|water resistant|warranty|battery life|in stock|price|prise|cost|how much is|kitne ka|worth it|good for)\b/;
const MULTI_SPLIT = /\s*,?\s+(?:and also|and then|and|aur|plus|as well as|also|along with|&)\s+/i;
const LLM_INTENTS = new Set(['bundle', 'product_question', 'product_search', 'recommendation', 'budget_query', 'refine_cheaper', 'refine_premium', 'refine_filter', 'show_more', 'gift_suggestion', 'deals', 'compare', 'product_info', 'greeting', 'help', 'small_talk']);
const ORDINAL_NAMES = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
const EXPLAIN_RE = /\b(?:explain|simplify|in simple (?:words|terms|language)|plain (?:english|language|words)|(?:specs?|specifications?) mean|what do (?:the|these|its|their) specs|break down the specs|layman)\b/;
const GIFT_LIKES_RE = /\b(?:loves?|likes?|into|enjoys?|interested in|fan of|pasand)\b/;

const hasProductSignal = (e) => Boolean(e.categories.length || e.department || e.brands.length || e.keywords.length || e.features.length);

const simpleItem = (p, catalog, extra = []) => ({
  product: p,
  score: +(0.6 * p._quality + 0.4 * p._popularity).toFixed(3),
  reasons: [
    ...extra,
    p.rating >= 4 && p.rating_count >= 3 ? `Rated ${stars(p.rating)} by ${plural(p.rating_count, 'shopper')}` : null,
    p.discount_percent >= 10 && p.compare_at_price ? `${Math.round(p.discount_percent)}% off — save ${money(p.compare_at_price - p.price)}` : null,
    p.sold_count >= (catalog?.bestsellerCut || Infinity) ? `Bestseller — ${p.sold_count} sold` : null,
  ].filter(Boolean).slice(0, 4),
});

// ordinals / pronouns / names -> product ids from the previous turn
const resolveRefs = (e, ctx, catalog) => {
  const shown = ctx.lastProducts || [];
  const ids = [];
  if (e.ordinals.all) ids.push(...shown);
  for (const n of e.ordinals.indices) {
    const id = n > 0 ? shown[n - 1] : shown[shown.length + n];
    if (id && !ids.includes(id)) ids.push(id);
  }
  let byName = false;
  if (!ids.length && shown.length && (e.brands.length || e.keywords.length)) {
    const named = shown.filter((id) => {
      const p = catalog.byId.get(id);
      if (!p) return false;
      const title = p.title.toLowerCase();
      return (p.brand_name && e.brands.includes(p.brand_name.toLowerCase())) || e.keywords.some((k) => k.length > 2 && title.includes(k));
    });
    if (named.length && named.length < shown.length) {
      ids.push(...named);
      byName = true;
    }
  }
  if (!ids.length && e.ordinals.pronoun && ctx.focus) ids.push(ctx.focus);
  return { ids, byName };
};

const decideIntent = (a, e, ctx, refs, text) => {
  const intent = a.intent;
  const product = hasProductSignal(e);
  const pending = ctx.pending?.type;
  if (pending === 'gift_recipient' && (e.recipient || e.gender)) return 'gift_suggestion';
  if (pending === 'gift_budget' && (e.budget || NO_LIMIT.test(text))) return 'gift_suggestion';
  if (pending === 'shopping_what' && (product || e.recipient)) return e.recipient && !product ? 'gift_suggestion' : 'product_search';
  if (pending === 'which_product' && refs.ids.length) return 'add_to_cart';
  if (pending === 'bundle_budget' && e.budget) return 'bundle';
  if (pending === 'gift_interest') return 'gift_suggestion';
  // a single product type without bundle words is a search ("laptop for gaming under 5 lakh", "heels for a wedding",
  // "protein for gym"): one category family (men's + women's shoes count as one) or a named product word
  const families = new Set(e.categories.map((c) => c.replace(/^(?:mens|womens)-/, '')));
  if (intent === 'bundle' && (families.size === 1 || (!families.size && e.keywords.length)) && !/\b(?:setup|kit|bundle|set|routine|outfit|pack|combo|everything|starter|makeover|hamper|look|box)\b/.test(text)) return 'product_search';
  const hasShown = ctx.lastProducts.length > 0 || ctx.focus;
  // "explain the specs of the first one" / "in simple words" -> plain-language spec explainer
  if (EXPLAIN_RE.test(text) && (hasShown || refs.ids.length || product)) return 'explain_specs';
  if (ctx.lastIntent === 'gift_suggestion' && GIFT_LIKES_RE.test(text) && !refs.ids.length) return 'gift_suggestion';
  // specific questions about a shown product go to grounded q&a ("does the second one have a good camera?")
  const aboutShown = refs.ids.length || (ctx.focus && e.ordinals.pronoun);
  if (hasShown && aboutShown && qa.looksLikeQuestion(text) && !/\b(?:tell me more|more about|details)\b/.test(text)
    && ['product_info', 'small_talk', 'help', 'product_search', 'recommendation', 'refine_filter', 'return_policy'].includes(intent)) return 'product_question';
  if (['product_info', 'compare', 'add_to_cart'].includes(intent) && !hasShown) return product ? 'product_search' : intent;
  if (['refine_cheaper', 'refine_premium', 'show_more', 'refine_filter'].includes(intent) && !S.hasSearchSlots(ctx.slots)) {
    return product ? 'product_search' : intent;
  }
  if (['small_talk', 'greeting', 'thanks', 'goodbye'].includes(intent) && product && a.confidence < 0.9) return 'product_search';
  if (['product_search', 'recommendation'].includes(intent) && refs.ids.length && e.ordinals.indices.length && !e.categories.length) return 'product_info';
  if (intent === 'refine_filter' && e.categories.length && S.isTopicChange(ctx.slots, e)) return 'product_search';
  if (hasShown && /\b(?:similar|like this|like these|alternatives? to)\b/.test(text) && !e.categories.length) return 'similar';
  if (/\b(?:bought together|goes with|go with|complete the (?:look|set)|accessories for)\b/.test(text) && (hasShown || refs.ids.length)) return 'bought_together';
  if (a.source === 'low_confidence') return 'fallback';
  return intent;
};

// ---------------------------------------------------------------- off-script routing

// safety and noise run before the classifier's intent is trusted
const routeScope = (a, e, ctx, catalog) => {
  const sig = a.signals;
  if (!sig) return null;
  const pending = ctx.pending?.type;
  if (sig.crisis) return { intent: 'feelings', topic: 'crisis' };
  if (sig.profanity) return { intent: 'abuse', topic: 'profanity' };
  if (sig.noise) {
    const { kind } = sig.noise;
    if (kind === 'numbers') {
      // answering "what's your budget?" / any number that is a realistic budget -> normal budget flow
      const n = sig.noise.value;
      const plausible = n && n >= catalog.minPrice && n <= catalog.maxPrice * 1.5 && (sig.noise.digits.length <= 6 || n % 1000 === 0);
      if (pending || plausible) return null;
      return { intent: 'fallback', topic: 'numbers', number: { n, min: catalog.minPrice, max: catalog.maxPrice, digits: Number(sig.noise.digits).toLocaleString('en-US') } };
    }
    return { intent: 'fallback', topic: kind };
  }
  if (pending && SLOT_PENDING.has(pending)) return null;
  if (sig.insult && !sig.strongProduct && !sig.shopping) return { intent: 'abuse', topic: 'insult' };
  return null;
};

const OVERRIDABLE_BY_FAQ = new Set(['order_status', 'cart_help', 'product_search', 'recommendation', 'budget_query', 'help', 'small_talk', 'fallback', 'deals', 'out_of_scope', 'store_info', 'greeting', 'refine_filter', 'about_assistant', 'gift_suggestion']);
const OVERRIDABLE_BY_OOS = new Set(['product_search', 'recommendation', 'budget_query', 'small_talk', 'help', 'fallback', 'out_of_scope', 'refine_filter', 'gift_suggestion', 'deals', 'product_info', 'bundle', 'about_assistant', 'feelings']);
const VAGUE_INTENTS = new Set(['fallback', 'product_search', 'small_talk', 'gift_suggestion', 'help', 'recommendation', 'budget_query', 'out_of_scope', 'feelings']);
const VAGUE_WORDS = /^(?:something|anything|nice|cool|special|interesting|amazing|fun|unique|awesome|beautiful|exciting|surprise|cheer|treat|myself|idea|sure|confused|impress|inspire|today|buy|get|order|know|thing|stuff|kuch)$/;

// after the normal decision: off-topic, store faq, questions about zel, glossary, named-product facts, vague shopping
const refineIntent = (intent, a, e, ctx, refs, extras, catalog) => {
  const sig = a.signals;
  if (!sig) return intent;
  const text = a.normalized;
  const pending = ctx.pending?.type;
  if (pending && SLOT_PENDING.has(pending) && !['out_of_scope', 'about_assistant', 'feelings', 'abuse'].includes(intent)) return intent;
  const strong = sig.strongProduct;
  const search = SEARCH_FAMILY.has(intent);

  if (/\b(?:joke|jokes|chutkula|latifa|funny thing)\b/.test(text) && !strong) return 'small_talk';
  // "i ordered something last week, has it shipped?" -> the order, not a product search
  if (sig.personal && !strong && /\b(?:ordered|order|orders|parcel|package)\b/.test(text)
    && /\b(?:shipped|arrive\w*|deliver\w*|status|check|where|track\w*|happening|late|delayed|received|come|came|dispatch\w*)\b/.test(text)
    && !['order_status', 'return_policy', 'cart_help'].includes(intent) && !sig.faq?.match(/^(?:returns|cancel|payment|cod|coupons)$/)) return 'order_status';

  if (sig.about && !strong && ['help', 'small_talk', 'out_of_scope', 'fallback', 'about_assistant', 'product_search', 'recommendation', 'greeting', 'feelings'].includes(intent)) {
    extras.topic = sig.about;
    return 'about_assistant';
  }
  if (intent === 'about_assistant') {
    extras.topic = sig.about || 'intro';
    return intent;
  }

  const concept = !refs.ids.length ? conceptQuery(text) || conceptQuery(String(a.raw || '').toLowerCase()) : null;
  if (concept && !['add_to_cart', 'order_status', 'cart_help'].includes(intent)) {
    extras.concept = concept;
    return 'concept';
  }

  // "is the iphone 13 waterproof?" -> grounded q&a on that product, no list on screen needed
  if (!refs.ids.length && FACT_Q.test(text) && !['order_status', 'cart_help', 'add_to_cart', 'compare'].includes(intent)
    && !['delivery_time', 'delivery_area', 'payment', 'cod', 'coupons', 'international', 'shipping_fee'].includes(sig.faq)) {
    const named = findNamedProduct(a.tokens, catalog, e.categories);
    if (named) {
      extras.named = named;
      refs.ids.push(named.product.id);
      return 'product_question';
    }
  }

  if (sig.faq) {
    const topic = sig.faq;
    extras.topic = topic;
    if (topic === 'returns' || topic === 'cancel') return ['return_policy', 'order_status', 'add_to_cart'].includes(intent) ? intent : 'return_policy';
    if (intent === 'return_policy' && /\b(?:refund|return|exchange)\b/.test(text)) return intent;
    if (topic === 'warranty' && (refs.ids.length || ctx.focus)) return intent;
    if (topic === 'delivery_time' && sig.personal && intent === 'order_status') return intent;
    if (topic === 'shipping_fee' && /\bcart\b/.test(text)) return 'cart_help';
    // "laptops under 50k with cash on delivery": answer the search, add the faq line
    if (strong && (search || intent === 'gift_suggestion')) {
      extras.faqNote = faq.shortAnswer(topic);
      return intent;
    }
    if (OVERRIDABLE_BY_FAQ.has(intent)) return 'store_info';
  }
  if (intent === 'store_info') {
    extras.topic = sig.faq || (/\b(?:sell|stock|categories|products do you have)\b/.test(text) ? 'catalog' : 'overview');
    return intent;
  }

  if (sig.oos && OVERRIDABLE_BY_OOS.has(intent) && !refs.ids.length) {
    extras.topic = sig.oos;
    return 'out_of_scope';
  }
  if (intent === 'out_of_scope') {
    if (strong && (sig.shopping || a.confidence < 0.75)) return 'product_search';
    extras.topic = sig.oos || sig.oosAny || 'general';
    return intent;
  }

  if (intent === 'abuse') {
    if (strong && sig.shopping) return 'product_search';
    extras.topic = 'insult';
    return intent;
  }

  if (sig.vague && !pending && ctx.lastIntent !== 'gift_suggestion' && !e.recipient && VAGUE_INTENTS.has(intent)
    && !e.keywords.some((k) => !VAGUE_WORDS.test(k))) {
    extras.vague = true;
    return 'recommendation';
  }

  if (intent === 'feelings' || (sig.feeling && ['small_talk', 'fallback', 'help'].includes(intent) && !strong)) {
    if (strong && sig.shopping) return 'product_search';
    extras.topic = sig.feeling || 'general';
    return 'feelings';
  }

  // the model was unsure and nothing rescued it: a confident off-script runner-up beats a generic fallback
  if (intent === 'fallback') {
    const alt = a.alternatives.find((x) => ['out_of_scope', 'about_assistant', 'feelings', 'store_info'].includes(x.intent));
    if (alt && alt.confidence >= 0.2 && alt.confidence >= (a.alternatives[0]?.confidence || 0) * 0.8) {
      extras.topic = { out_of_scope: 'general', store_info: 'overview', feelings: 'general', about_assistant: 'intro' }[alt.intent];
      return alt.intent;
    }
    extras.topic = 'low';
  }
  return intent;
};

// "cheap phone and a cover for it": answer the first need, offer the second as a chip
const detectMulti = (raw, a) => {
  const bundleWords = /\b(?:setup|kit|bundle|set|routine|outfit|pack|combo|everything|starter|makeover|hamper|look|box)\b/i.test(raw);
  const searchy = ['product_search', 'recommendation', 'budget_query'].includes(a.intent) || a.source === 'entities' || (a.intent === 'bundle' && !bundleWords);
  // "show me shoes and the delivery time" can classify as store_info as a whole; the split decides
  if (!searchy && !(['store_info', 'order_status'].includes(a.intent) && a.signals?.faq && a.signals.strongProduct)) return null;
  const m = String(raw).match(MULTI_SPLIT);
  if (!m) return null;
  const leftText = raw.slice(0, m.index).trim();
  const rightText = raw.slice(m.index + m[0].length).trim().replace(/[?.!]+$/, '');
  if (!leftText || !rightText) return null;
  const A = analyze(leftText);
  const B = analyze(rightText);
  const ca = A.entities.categories;
  const cb = B.entities.categories;
  if (!ca.length) return null;
  if (B.signals?.faq && !cb.length) return { kind: 'faq', left: A, topic: B.signals.faq };
  if (/\b(?:or|vs|versus|compare|either)\b/i.test(raw)) return null;
  const merge = () => {
    const le = { ...A.entities };
    for (const k of ['budget', 'recipient', 'gender', 'occasion', 'sort', 'minRating']) if (!le[k] && B.entities[k]) le[k] = B.entities[k];
    return le;
  };
  if (cb.length && cb.some((c) => !ca.includes(c))) return { kind: 'product', left: A, right: B, entities: merge(), rightText };
  if (!cb.length && B.entities.keywords.length && B.tokens.length <= 5 && !B.signals?.oos && !B.signals?.noise) return { kind: 'unknown', left: A, right: B, entities: merge(), rightText };
  return null;
};

const chipFor = (text) => {
  const clean = text.replace(/^(?:also|then|please|me|i need|i want|show me|and)\s+/i, '').replace(/\s+/g, ' ').trim();
  return truncate(`Show ${clean}`, 40);
};

const viewAllQuery = (slots) => {
  const q = {};
  if (slots.categories?.length === 1) q.category = slots.categories[0];
  else if (slots.department) q.department = slots.department;
  if (slots.brands?.length) q.brand = slots.brands.join(',');
  if (slots.budget?.min) q.minPrice = slots.budget.min;
  if (slots.budget?.max) q.maxPrice = slots.budget.max;
  if (slots.minRating) q.minRating = slots.minRating;
  if (slots.gender) q.gender = slots.gender;
  if (slots.keywords?.length) q.q = slots.keywords.join(' ');
  const sorts = { price_asc: 'price_asc', price_desc: 'price_desc', rating: 'rating', popular: 'popular', newest: 'newest', discount: 'discount' };
  if (slots.sort) q.sort = sorts[slots.sort];
  return q;
};

const searchSuggestions = (slots, result, offset) => {
  const chips = [];
  const items = result.items;
  if (items.length >= 2) chips.push('Compare the first two');
  if (items.length && !(slots.budget?.max && items.every((i) => i.product.price <= slots.budget.max * 0.5))) chips.push('Show cheaper options');
  const brands = [...new Set(items.map((i) => i.product.brand_name).filter(Boolean))];
  if (!slots.brands?.length && brands.length > 1) chips.push(`Only ${brands[0]}`);
  if (result.total > offset + items.length) chips.push('Show more');
  if (!slots.sort && items.length > 2) chips.push('Best rated first');
  if (items.length) chips.push('Tell me more about the first one');
  return chips.slice(0, 4);
};

const clarifyShopping = (ctx, budgetText = '') => ({
  content: `Sure! What are you shopping for${budgetText ? ` with ${budgetText}` : ''}? Pick a category or just describe it.`,
  clarify: { question: 'What are you shopping for?', options: ['Phones', 'Laptops', 'Fashion', 'Beauty', 'Home & kitchen', 'Gifts'] },
  suggestions: [],
  pending: { type: 'shopping_what' },
});

// ---------------------------------------------------------------- handlers

const handleSearch = async (t) => {
  const { e, ctx, intent, catalog, profile } = t;
  const prev = ctx.slots;
  const shownPrices = ctx.lastProducts.map((id) => catalog.byId.get(id)?.price).filter(Boolean);
  let slots;
  let offset = 0;
  if (intent === 'refine_cheaper') slots = S.cheaperSlots(S.mergeSlots(prev, e, 'merge'), shownPrices);
  else if (intent === 'refine_premium') slots = S.premiumSlots(S.mergeSlots(prev, e, 'merge'), shownPrices);
  else if (intent === 'show_more') {
    slots = prev;
    offset = (ctx.offset || 0) + ctx.lastProducts.length;
  } else if (intent === 'refine_filter') slots = S.mergeSlots(prev, e, 'filter');
  else {
    const fresh = !S.hasSearchSlots(prev) || S.isTopicChange(prev, e) || !SEARCH_FAMILY.has(ctx.lastIntent);
    slots = S.mergeSlots(prev, e, fresh && hasProductSignal(e) ? 'new' : 'merge');
  }

  if (!S.hasSearchSlots(slots)) {
    if (intent === 'recommendation' || (intent === 'product_search' && t.profile?.hasSignals && /recommend|suggest|something/.test(t.text))) {
      return handlePersonal(t);
    }
    ctx.slots = slots;
    return clarifyShopping(ctx, slots.budget ? nlg.budgetPhrase(slots.budget) : '');
  }

  const result = await retrieve(slots, { profile, limit: CHAT_LIMIT, offset });
  ctx.slots = slots;
  if (intent === 'show_more' && !result.items.length) {
    return { content: `That's everything I have for ${nlg.describe(slots, catalog)}. Want to try a different budget or brand?`, suggestions: ['Show cheaper options', 'Something more premium', 'Start over'] };
  }
  if (result.noMatch) {
    ctx.lastProducts = [];
    return { content: nlg.noMatchReply(slots), suggestions: ['Phones under 50k', 'Perfumes for her', "Today's deals", 'Help'] };
  }
  ctx.prevProducts = ctx.lastProducts;
  ctx.lastProducts = result.items.map((i) => i.product.id);
  ctx.offset = offset;
  ctx.focus = null;
  const content = nlg.searchReply({ slots, result, catalog, seed: t.seed, intent, shownFrom: offset });
  const actions = [];
  if (result.total > offset + result.items.length) actions.push({ type: 'view_all', label: `See all ${result.total} results`, query: viewAllQuery(slots) });
  if (result.items.length >= 2) actions.push({ type: 'compare', label: 'Compare top picks', productIds: ctx.lastProducts.slice(0, 2) });
  return {
    content,
    products: result.items,
    suggestions: searchSuggestions(slots, result, offset),
    actions,
    fallback: result.fallback,
    title: titleFromSlots(slots, catalog),
  };
};

const handlePersonal = async (t) => {
  const { ctx, userId, catalog } = t;
  const rec = await recommendations(userId, CHAT_LIMIT);
  ctx.lastProducts = rec.products.map((i) => i.product.id);
  const top = rec.products[0];
  const content = `${rec.title}${rec.strategy === 'popularity' ? '' : ` — ${nl(rec.subtitle)}`}. ${top ? `Leading the list is **${top.product.title}** at **${money(top.product.price)}** (${nlg.lower(top.reasons[0] || 'a popular choice')}).` : ''}`;
  return {
    content,
    products: rec.products,
    suggestions: ['Show cheaper options', 'Compare the first two', "Today's deals", 'Gift ideas'].slice(0, 4),
    title: 'Picks for you',
    catalogUsed: catalog,
  };
};

const nl = (s) => nlg.lower(s || '');

const GIFT_BUDGETS = ['Under Rs 5,000', 'Under Rs 15,000', 'Under Rs 50,000', 'No limit'];
const GIFT_INTERESTS = {
  women: ['Beauty & makeup', 'Jewellery & bags', 'Fragrance', 'Fashion', 'Tech', 'Surprise me'],
  men: ['Watches', 'Fragrance', 'Tech & gaming', 'Fitness', 'Fashion', 'Surprise me'],
  any: ['Tech', 'Fragrance', 'Home & decor', 'Fitness', 'Cooking', 'Surprise me'],
};
const GIFT_LIKE_CHIPS = {
  women: ['She loves makeup', 'She likes jewellery'],
  men: ['He likes gaming', 'He is into fitness'],
  any: ['They love cooking', 'They like tech'],
};
const SURPRISE_RE = /\b(?:surprise|anything|no idea|not sure|koi bhi|whatever|any)\b/;

// slot filling: recipient -> budget -> (interest, only when nothing has been asked yet) -> curated collection
const handleGift = async (t) => {
  const { e, ctx, text, raw } = t;
  const continuing = ctx.lastIntent === 'gift_suggestion' || ctx.pending?.type?.startsWith('gift');
  const flow = continuing && ctx.gift ? { ...ctx.gift, interests: [...(ctx.gift.interests || [])] } : { asked: 0, interests: [], answeredInterest: false };
  const slots = S.mergeSlots(continuing ? ctx.slots : S.EMPTY_SLOTS(), e, 'merge');
  if (e.recipient && !e.gender && continuing && slots.recipient !== ctx.slots.recipient) slots.gender = L.RECIPIENTS[e.recipient] || null;
  if (ctx.pending?.type === 'gift_interest') {
    flow.answeredInterest = true;
    if (!SURPRISE_RE.test(text)) flow.interests.push(raw.slice(0, 60));
  } else if (continuing && GIFT_LIKES_RE.test(text)) flow.interests.push(raw.slice(0, 60));
  ctx.slots = slots;
  ctx.gift = flow;
  if (!slots.recipient && !slots.gender && !slots.categories.length) {
    flow.asked += 1;
    return {
      content: `I'd love to help you find a gift${slots.occasion ? ` for the ${slots.occasion}` : ''}! Who is it for?`,
      clarify: { question: 'Who is the gift for?', options: ['Mom', 'Dad', 'Wife', 'Husband', 'Sister', 'Friend'] },
      pending: { type: 'gift_recipient' },
      suggestions: [],
    };
  }
  const noLimit = NO_LIMIT.test(text);
  if (!slots.budget && !noLimit && ctx.pending?.type !== 'gift_budget' && !flow.noLimit) {
    flow.asked += 1;
    return {
      content: `Lovely${slots.recipient ? ` — a gift for your ${slots.recipient}` : ''}. What budget do you have in mind?`,
      clarify: { question: "What's your budget?", options: GIFT_BUDGETS },
      pending: { type: 'gift_budget' },
      suggestions: [],
    };
  }
  if (noLimit) flow.noLimit = true;
  const genderKey = slots.gender === 'women' || slots.gender === 'men' ? slots.gender : 'any';
  const hasInterest = flow.interests.length || slots.categories.length || flow.answeredInterest;
  // everything came in one message ("birthday gift for my sister under 5000"): one quick question about interests
  if (!hasInterest && flow.asked === 0) {
    flow.asked += 1;
    const who = slots.recipient ? `your ${slots.recipient}` : slots.gender === 'women' ? 'her' : slots.gender === 'men' ? 'him' : 'them';
    return {
      content: `Great${slots.budget ? `, ${nlg.budgetPhrase(slots.budget)}` : ''}. What is ${who} into? Pick one or tell me in your own words, and I'll curate the gifts around it.`,
      clarify: { question: `What does ${slots.gender === 'women' ? 'she' : slots.gender === 'men' ? 'he' : 'they'} like?`, options: GIFT_INTERESTS[genderKey] },
      pending: { type: 'gift_interest' },
      suggestions: [],
    };
  }
  const recipient = slots.recipient || (slots.gender === 'women' ? 'her' : slots.gender === 'men' ? 'him' : 'friend');
  const g = await buildGift({
    recipient, gender: slots.gender, occasion: slots.occasion, budget: flow.noLimit ? null : slots.budget,
    interests: flow.interests, categories: slots.categories, text: raw, limit: CHAT_LIMIT,
  });
  const giftSlots = { ...slots, categories: g.criteria.categories.length ? g.criteria.categories : slots.categories, category: null };
  ctx.slots = giftSlots;
  ctx.lastProducts = g.items.map((i) => i.product.id);
  ctx.pending = null;
  const top = g.items[0];
  const content = [
    `**${g.title}**: ${g.note}`,
    top ? `My favourite: **${top.product.title}** at **${money(top.product.price)}**${top.reasons[0] ? ` (${nl(top.reasons[0])})` : ''}.` : '',
  ].filter(Boolean).join(' ');
  const likeChips = flow.interests.length || slots.categories.length ? [] : GIFT_LIKE_CHIPS[genderKey];
  return {
    content,
    products: g.items,
    suggestions: [...likeChips, 'Show cheaper options', 'Compare the first two', 'Something more premium'].slice(0, 4),
    actions: g.items.length >= 2 ? [{ type: 'compare', label: 'Compare top picks', productIds: ctx.lastProducts.slice(0, 2) }] : [],
    title: truncate(g.title, 60),
    gift: { title: g.title, note: g.note, criteria: g.criteria },
  };
};

const handleDeals = async (t) => {
  const { e, ctx, catalog } = t;
  const scope = hasProductSignal(e) || e.budget ? S.mergeSlots(S.EMPTY_SLOTS(), e, 'new') : S.EMPTY_SLOTS();
  const filtered = applyFilters(catalog.products, filtersFromSlots(scope)).filter((p) => p.discount_percent > 0);
  const ranked = filtered.sort((a, b) => b.discount_percent - a.discount_percent || b._quality - a._quality);
  const seen = new Map();
  const picks = [];
  for (const p of ranked) {
    const c = seen.get(p.category_slug) || 0;
    if (!hasProductSignal(e) && c >= 1) continue;
    seen.set(p.category_slug, c + 1);
    picks.push(p);
    if (picks.length >= CHAT_LIMIT) break;
  }
  const items = picks.map((p) => simpleItem(p, catalog));
  ctx.slots = scope;
  ctx.lastProducts = picks.map((p) => p.id);
  const coupons = await models.activeCoupons().catch(() => []);
  const top = picks[0];
  const where = hasProductSignal(e) ? ` on ${nlg.describe(scope, catalog)}` : '';
  const content = top
    ? `Today's best deals${where}: the biggest is **${top.title}** at **${money(top.price)}** — **${Math.round(top.discount_percent)}% off**${top.compare_at_price ? `, saving ${money(top.compare_at_price - top.price)}` : ''}.${coupons[0] ? ` Tip: use code **${coupons[0].code}** at checkout — ${nl(coupons[0].description)}.` : ''}`
    : `I couldn't find discounts${where} right now.${coupons[0] ? ` You can still use code **${coupons[0].code}** — ${nl(coupons[0].description)}.` : ''}`;
  return { content, products: items, suggestions: ['Deals on phones', 'Deals on fashion', 'Compare the first two', 'Show cheaper options'], title: "Today's deals" };
};

const handleCompare = async (t) => {
  const { ctx, refs } = t;
  let ids = refs.ids.length >= 2 ? refs.ids : [];
  if (!ids.length && refs.ids.length === 1 && ctx.focus && ctx.focus !== refs.ids[0]) ids = [ctx.focus, refs.ids[0]];
  // a refinement may leave a single item: fall back to the list shown before it
  if (!ids.length) ids = [...new Set([...ctx.lastProducts, ...(ctx.prevProducts || [])])].slice(0, 2);
  ids = ids.slice(0, 4);
  if (ids.length < 2) return { content: 'I need at least two products to compare. Search for something first, then say *compare the first two*.', suggestions: ['Phones under 100k', 'Laptops', 'Perfumes'] };
  // "compare the first two for gaming" / "which is better for my mom"
  const { e } = t;
  const need = e.features.length || e.recipient || e.occasion ? t.raw : null;
  const comparison = await compareProducts(ids, { need });
  if (!comparison) return { content: "I couldn't load those products to compare.", suggestions: ['Show more'] };
  const names = comparison.products.map((p) => `**${p.title}**`);
  const best = comparison.verdict.picks.find((p) => p.label === 'Best value');
  const bestIdx = ids.indexOf(best?.productId);
  const bolded = comparison.products
    .reduce((txt, p) => txt.split(p.title).join(`**${p.title}**`), comparison.verdict.summary)
    .replace(/Rs [\d,]+/g, (m) => `**${m}**`);
  const winnerTitle = comparison.forYou?.matched ? comparison.products.find((p) => p.id === comparison.forYou.productId)?.title : null;
  const forYou = winnerTitle ? ` ${comparison.forYou.reason.split(winnerTitle).join(`**${winnerTitle}**`)}` : '';
  const content = `Comparing ${list(names)}. ${bolded}${forYou}`;
  const suggestions = [
    bestIdx >= 0 ? `Add the ${ORDINAL_NAMES[ctx.lastProducts.indexOf(best.productId)] || 'first'} one to my cart` : 'Add the first one to my cart',
    `Tell me more about the ${ORDINAL_NAMES[ctx.lastProducts.indexOf(ids[0])] || 'first'} one`,
    'Show cheaper options',
  ];
  return {
    content,
    comparison,
    products: ids.map((id) => t.catalog.byId.get(id)).filter(Boolean).map((p) => simpleItem(p, t.catalog)),
    suggestions,
    actions: [{ type: 'compare', label: 'Open full comparison', productIds: ids }],
    title: `Compare ${truncate(comparison.products.map((p) => p.title).join(' vs '), 60)}`,
  };
};


const handleProductInfo = async (t) => {
  const { ctx, refs, catalog } = t;
  const id = refs.ids[0] || ctx.focus || ctx.lastProducts[0];
  const p = catalog.byId.get(id);
  if (!p) return { content: 'Which product do you mean? Try *tell me more about the first one*.', suggestions: ['Show more'] };
  ctx.focus = p.id;
  const summary = await reviewSummary(p.id).catch(() => null);
  const pos = ctx.lastProducts.indexOf(p.id);
  return {
    content: nlg.productInfoReply(p, summary, t.seed),
    products: [simpleItem(p, catalog, summary?.pros?.[0] ? [`Reviewers praise its ${summary.pros[0].aspect.toLowerCase()}`] : [])],
    suggestions: [
      'Add it to my cart',
      'Show similar items',
      ctx.lastProducts.length > 1 ? `Compare it with the ${pos === 0 ? 'second' : 'first'} one` : 'Show cheaper options',
    ],
    actions: p.stock > 0 ? [{ type: 'add_to_cart', label: `Add ${truncate(p.title, 30)} to cart`, productId: p.id, quantity: 1 }] : [],
  };
};

const handleExplain = async (t) => {
  const { ctx, refs, catalog, e, profile } = t;
  let id = refs.ids[0] || null;
  // a named product without a shown list ("explain the specs of iphone 13 pro")
  if (!id && hasProductSignal(e) && !e.ordinals.pronoun) {
    const r = await retrieve(S.mergeSlots(S.EMPTY_SLOTS(), e, 'new'), { profile, limit: 1 });
    id = r.items[0]?.product.id || null;
  }
  id = id || ctx.focus || ctx.lastProducts[0];
  const p = catalog.byId.get(id);
  if (!p) return { content: 'Which product should I explain? Search for something first, then say *explain the specs of the first one*.', suggestions: ['Phones under 50k', 'Laptops'] };
  ctx.focus = p.id;
  const x = explainProduct(p);
  const lines = x.specs.filter((s) => s.level).slice(0, 4).map((s) => `- **${s.title}** (${s.levelLabel.toLowerCase()}): ${s.meaning.split(/(?<=\.)\s/)[0]}`);
  const fallback = x.specs.slice(0, 3).map((s) => `- **${s.title}**: ${s.meaning}`);
  const body = (lines.length ? lines : fallback).join('\n');
  const pos = ctx.lastProducts.indexOf(p.id);
  return {
    content: `Here's **${p.title}** in plain words. ${x.summary}${body ? `\n\n${body}` : ''}`,
    products: [simpleItem(p, catalog)],
    explain: x,
    suggestions: [
      ctx.lastProducts.length > 1 ? `Compare it with the ${pos === 0 ? 'second' : 'first'} one` : 'Show similar items',
      'Add it to my cart',
      'Show cheaper options',
    ],
    actions: p.stock > 0 ? [{ type: 'add_to_cart', label: `Add ${truncate(p.title, 30)} to cart`, productId: p.id, quantity: 1 }] : [],
  };
};

const handleAddToCart = async (t) => {
  const { ctx, refs, catalog, e } = t;
  let ids = refs.ids;
  if (!ids.length && (e.ordinals.pronoun || ctx.pending?.type === 'which_product') && ctx.focus) ids = [ctx.focus];
  if (!ids.length && ctx.focus && !e.ordinals.indices.length) ids = [ctx.focus];
  if (!ids.length && ctx.lastProducts.length === 1) ids = [ctx.lastProducts[0]];
  if (!ids.length) {
    const options = ctx.lastProducts.slice(0, 4).map((pid, i) => `The ${ORDINAL_NAMES[i]} one (${truncate(catalog.byId.get(pid)?.title || '', 24)})`);
    return {
      content: 'Which one should I add to your cart?',
      clarify: { question: 'Which product?', options },
      pending: { type: 'which_product' },
      suggestions: [],
    };
  }
  const products = ids.slice(0, 3).map((id) => catalog.byId.get(id)).filter(Boolean);
  const available = products.filter((p) => p.stock > 0);
  ctx.focus = products[0]?.id || ctx.focus;
  ctx.pending = null;
  if (!available.length) return { content: `Sorry, **${products[0]?.title}** is out of stock right now. Want similar items?`, suggestions: ['Show similar items', 'Show more'] };
  const total = available.reduce((s, p) => s + p.price, 0);
  const content = available.length === 1
    ? `Tap **Add to cart** to add **${available[0].title}** (**${money(available[0].price)}**) to your cart.`
    : `Tap below to add ${list(available.map((p) => `**${p.title}**`))} — **${money(total)}** in total.`;
  return {
    content,
    products: available.map((p) => simpleItem(p, catalog)),
    actions: available.map((p) => ({ type: 'add_to_cart', label: `Add ${truncate(p.title, 30)} to cart`, productId: p.id, quantity: 1 })),
    suggestions: ['Show my cart', 'Frequently bought together', 'Recommend something'],
  };
};

const handleOrderStatus = async (t) => {
  const orderNumber = (t.text.match(/\b[a-z]{2,4}-?\d{4,}\b/i) || [])[0] || null;
  const data = await models.latestOrder(t.userId, orderNumber);
  if (!data) {
    return { content: orderNumber ? `I couldn't find order **${orderNumber}** on your account.` : "You haven't placed any orders yet. Want me to help you find something?", suggestions: ['Trending products', "Today's deals"] };
  }
  const { order, items } = data;
  const count = items.reduce((s, i) => s + i.quantity, 0);
  const when = order.status === 'delivered' && order.delivered_at ? ` on ${nlg.fmtDate(order.delivered_at)}` : '';
  const what = items.length ? ` (${truncate(items[0].title, 32)}${items.length > 1 ? ` + ${items.length - 1} more` : ''})` : '';
  const eta = ['placed', 'confirmed', 'shipped'].includes(order.status) ? ' You can follow every step in **Orders**.' : '';
  return {
    content: `Your latest order **${order.order_number}**${what} — ${plural(count, 'item')}, **${money(order.total)}** — ${nlg.STATUS_TEXT[order.status] || `is **${order.status}**`}${when}.${eta}`,
    actions: [{ type: 'view_order', label: 'View order', orderId: order.id }],
    suggestions: data.totalOrders > 1 ? ['Show my cart', 'Return policy', 'Recommend something'] : ['Return policy', 'Recommend something'],
    personal: true,
  };
};

const handleCart = async (t) => {
  const { items, couponCode } = await models.cartSnapshot(t.userId);
  if (!items.length) return { content: 'Your cart is empty. Want some recommendations to get started?', suggestions: ['Recommend something', "Today's deals", 'Gift ideas'], personal: true };
  const subtotal = items.reduce((s, i) => s + i.price * i.quantity, 0);
  const savings = items.reduce((s, i) => s + Math.max(0, (i.compare_at_price || i.price) - i.price) * i.quantity, 0);
  const count = items.reduce((s, i) => s + i.quantity, 0);
  const gap = FREE_SHIPPING - subtotal;
  const shipping = gap > 0 ? ` Add **${money(gap)}** more to unlock **free shipping**.` : ' You qualify for **free shipping**.';
  const top = items.slice().sort((a, b) => b.price * b.quantity - a.price * a.quantity)[0];
  return {
    content: `You have ${plural(count, 'item')} in your cart totalling **${money(subtotal)}**${savings > 0 ? ` — you're saving **${money(savings)}** on discounts` : ''}.${shipping}${couponCode ? ` Coupon **${couponCode}** is applied.` : ''} The biggest item is **${top.title}**.`,
    actions: [{ type: 'open_cart', label: 'Open cart' }],
    suggestions: ['Frequently bought together', 'Any coupons?', 'Recommend something'],
    personal: true,
  };
};

const handleReturns = async (t) => {
  const p = t.catalog.byId.get(t.refs.ids[0] || t.ctx.focus);
  const specific = p ? ` For **${p.title}**: ${p.return_policy || 'see the product page'}${p.warranty ? `, ${p.warranty.toLowerCase()}` : ''}.` : '';
  return {
    content: `Return windows depend on the product and are shown on every product page (for example "30 days return policy" or "No return policy").${specific} Orders can be **cancelled** while they're still placed or confirmed from **Orders → Cancel**, and the items are restocked.`,
    suggestions: ['Where is my order?', 'Show my cart', 'Recommend something'],
  };
};

const handleRelated = (kind) => async (t) => {
  const { ctx, refs, catalog, userId } = t;
  let baseId = refs.ids[0] || ctx.focus || ctx.lastProducts[0];
  if (!baseId && kind === 'bought_together' && userId) {
    const { items } = await models.cartSnapshot(userId);
    baseId = items.sort((a, b) => b.price - a.price)[0]?.id;
  }
  const base = catalog.byId.get(baseId);
  if (!base) return { content: 'Which product should I base that on? Search for something first.', suggestions: ['Phones', 'Laptops'] };
  // fashion items get a styled outfit (colour harmony, gender, price band) instead of co-purchases; everything else
  // gets complementary items (boughtTogether keeps only co-purchases that genuinely go with it: compatible, right
  // audience, not a substitute, then fills from complementary categories)
  const look = kind === 'bought_together' && FASHION.has(base.category_slug) ? await completeLook(base.id, { limit: CHAT_LIMIT }) : null;
  const items = look ? look.items : (kind === 'similar' ? await similar(base.id, CHAT_LIMIT) : await boughtTogether(base.id, CHAT_LIMIT)) || [];
  ctx.focus = base.id;
  if (!items.length) {
    // nothing in the catalog really fits: say so instead of padding with unrelated products
    return {
      content: kind === 'similar'
        ? `I couldn't find anything close enough to **${base.title}** right now.`
        : `I don't have anything that genuinely goes with **${base.title}** in stock right now.`,
      suggestions: kind === 'similar' ? ['Recommend something'] : ['Show similar items', 'Recommend something'],
    };
  }
  ctx.lastProducts = items.map((i) => i.product.id);
  const top = items[0];
  const lead = kind === 'similar' ? `Here are items similar to **${base.title}**`
    : look ? `To complete the look with **${base.title}**: ${list(look.look.slice(0, 4).map((l) => l.role.toLowerCase()))}${look.palette?.tip ? `. ${look.palette.tip.replace(/\.$/, '')}` : ''}`
      : `These go well with **${base.title}**`;
  return {
    content: `${lead}.${top ? ` Top match: **${top.product.title}** at **${money(top.product.price)}** (${nl(top.reasons[0])}).` : ''}`,
    products: items,
    suggestions: ['Compare the first two', 'Show cheaper options', 'Tell me more about the first one'],
  };
};

const BUNDLE_BUDGETS = ['Rs 50,000', 'Rs 150,000', 'Rs 300,000', 'Rs 500,000'];

const handleBundle = async (t) => {
  const { e, ctx, raw } = t;
  const goal = ctx.pending?.type === 'bundle_budget' && !e.categories.length && !/setup|kit|bundle|set|routine|outfit|pack/.test(t.text) ? ctx.pending.goal : raw;
  const budget = e.budget?.max || e.budget?.target || null;
  if (!budget) {
    return {
      content: 'Happy to build that bundle! What total budget should I work with?',
      clarify: { question: "What's your total budget?", options: BUNDLE_BUDGETS },
      pending: { type: 'bundle_budget', goal: raw },
      suggestions: [],
    };
  }
  const b = await buildBundle({ goal, budget });
  if (b.error) return { content: b.message, suggestions: ['Gaming setup under 400k', 'Gym starter under 30k', 'Skincare routine under 10k'] };
  ctx.lastProducts = b.items.map((it) => it.product.product.id);
  ctx.slots = S.EMPTY_SLOTS();
  const lines = b.items.map((it) => `${it.role}: **${it.product.product.title}** (${money(it.product.product.price)})`);
  const needsMore = b.budgetAdvice.missingRequired.length > 0;
  return {
    content: `Here's your **${b.title}** for **${money(b.total)}** of your ${money(b.budget)} budget (${money(b.remaining)} left): ${lines.join('; ')}. ${needsMore ? b.budgetAdvice.message : b.savingsTips[0] || ''}`.trim(),
    products: b.items.map((it) => it.product),
    bundle: b,
    actions: b.items.length ? [{ type: 'add_bundle_to_cart', label: `Add all ${b.items.length} to cart`, productIds: ctx.lastProducts }] : [],
    suggestions: ['Tell me more about the first one', 'Compare the first two', `Build it for ${shortMoney(needsMore ? b.budgetAdvice.suggestedBudget : Math.round(b.budget * 0.7 / 1000) * 1000)}`],
    title: b.title,
  };
};

const handleProductQuestion = async (t) => {
  const { ctx, refs, catalog, raw } = t;
  const id = refs.ids[0] || ctx.focus;
  const p = catalog.byId.get(id);
  if (!p) return handleProductInfo(t);
  ctx.focus = p.id;
  const named = t.extras?.named;
  let question = raw.replace(/\b(?:the\s+)?(?:first|second|third|fourth|fifth|last|1st|2nd|3rd|4th|5th)\s+(?:one|item|product)?\b/gi, 'it').replace(/\s+/g, ' ');
  // a product named in the question ("can the iphone x fly?") must not match its own title passage
  if (named) {
    const titleWords = new Set([...p.title.toLowerCase().split(/\s+/), ...String(p.brand_name || '').toLowerCase().split(/\s+/), 'iphone', 'galaxy', 'macbook', 'ipad']);
    question = question.split(/\s+/).filter((w) => !titleWords.has(w.toLowerCase().replace(/[^a-z0-9]/g, ''))).join(' ');
    if (!/\b(?:it|its)\b/i.test(question)) question = `${question} it`.trim();
  }
  const r = await qa.ask(p.id, question);
  if (named) ctx.lastProducts = [p.id];
  let content = r.answer;
  let suggestions = r.followUps.slice(0, 3);
  if (r.confidence <= 0.15) {
    // honest "not in the listing" + what we do know, instead of guessing
    const known = Object.entries(p.specs || {}).slice(0, 2).map(([k, v]) => `${k}: ${truncate(String(v), 40)}`);
    content = `I don't have that detail for **${p.title}**: it isn't in the product listing, and I'd rather not guess.${known.length ? ` Here's what I do know: ${known.join(' · ')}.` : ''} I can explain its specs in plain words or show similar items.`;
    suggestions = ['Explain its specs', 'Show similar items', ...r.followUps.slice(0, 1)];
  } else if (named?.partial) {
    content = `We don't carry the plain ${named.asked}, but we do have the **${p.title}** (**${money(p.price)}**). ${r.answer}`;
  } else if (named && !r.answer.includes(p.title)) {
    content = `**${p.title}**: ${r.answer}`;
  }
  return {
    content,
    products: [simpleItem(p, catalog)],
    qa: r,
    suggestions,
    actions: p.stock > 0 ? [{ type: 'add_to_cart', label: `Add ${truncate(p.title, 30)} to cart`, productId: p.id, quantity: 1 }] : [],
  };
};

const STATIC = {
  greeting: (t) => ({
    content: nlg.greeting(t.profile?.firstName, t.seed),
    suggestions: t.profile?.topCategories?.length
      ? [`Show me ${(t.catalog.taxonomy.find((c) => c.slug === t.profile.topCategories[0])?.name || 'trending').toLowerCase()}`, 'Recommend something', "Today's deals", 'Gift for mom']
      : ['Phones under 50k', 'Gift for mom', "Today's deals", 'Where is my order?'],
  }),
  goodbye: () => ({ content: 'Bye for now! Your chat is saved — come back anytime. Happy shopping!', suggestions: [] }),
  thanks: (t) => ({ content: 'You\'re welcome! Anything else I can find for you?', suggestions: t.ctx.lastProducts.length ? ['Show more', 'Compare the first two', "Today's deals"] : ['Recommend something', "Today's deals"] }),
  help: () => ({ content: nlg.HELP, suggestions: ['Gaming laptop under 300k', 'Gift for my sister', 'Compare iPhone and Samsung', 'sasta mobile chahiye'] }),
  small_talk: (t) => (/\b(?:joke|jokes|funny)\b/.test(t.text) || /\bjoke\b/i.test(t.raw)
    ? off.joke(t.seed + t.ctx.turns * 3)
    : { content: nlg.smallTalk(t.text, t.seed), suggestions: ['Recommend something', "Today's deals", 'Help'] }),
  fallback: (t) => off.unclear(t.extras?.topic || 'low', t),
  out_of_scope: (t) => off.outOfScope(t.extras?.topic, t),
  about_assistant: (t) => off.aboutAssistant(t.extras?.topic, t),
  feelings: (t) => off.feelings(t.extras?.topic, t),
  abuse: (t) => off.abuse(t.extras?.topic, t),
  concept: (t) => ({ content: t.extras.concept.text, suggestions: t.extras.concept.chips || [], title: t.extras.concept.title, scope: { kind: 'concept', topic: t.extras.concept.key } }),
};

const handleStoreInfo = async (t) => {
  const topic = t.extras?.topic || 'overview';
  if (topic === 'returns' || topic === 'cancel') return handleReturns(t);
  const out = await faq.answer(topic, { userId: t.userId, signals: t.a.signals, e: t.e, text: t.text, catalog: t.catalog });
  return { ...out, scope: { kind: 'store_info', topic } };
};

const HANDLERS = {
  product_search: handleSearch,
  recommendation: handleSearch,
  budget_query: handleSearch,
  refine_cheaper: handleSearch,
  refine_premium: handleSearch,
  refine_filter: handleSearch,
  show_more: handleSearch,
  gift_suggestion: handleGift,
  deals: handleDeals,
  compare: handleCompare,
  product_info: handleProductInfo,
  add_to_cart: handleAddToCart,
  order_status: handleOrderStatus,
  cart_help: handleCart,
  return_policy: handleReturns,
  similar: handleRelated('similar'),
  bought_together: handleRelated('bought_together'),
  bundle: handleBundle,
  product_question: handleProductQuestion,
  explain_specs: handleExplain,
  store_info: handleStoreInfo,
};

const titleFromSlots = (slots, catalog) => {
  const base = titleCase(nlg.describe(slots, catalog));
  const b = slots.budget;
  const budget = b?.max ? ` under ${shortMoney(b.max)}` : b?.min ? ` above ${shortMoney(b.min)}` : '';
  return truncate(`${base}${budget}`, 60);
};

// main entry: one chat turn
const respond = async ({ text, context, userId = null }) => {
  const started = Date.now();
  const catalog = await getCatalog();
  const ctx = S.loadContext(context);
  const profile = userId ? await getProfile(userId, catalog).catch(() => null) : null;
  const a = analyze(text);
  a.raw = text;
  let e = a.entities;
  e._text = a.normalized;
  if (/\b(?:start over|reset|new search|clear)\b/.test(a.normalized)) {
    Object.assign(ctx, S.initialContext(), { turns: ctx.turns });
  }
  if (!catalog.minPrice) {
    const prices = catalog.products.map((p) => Number(p.price)).filter((v) => v > 0);
    catalog.minPrice = Math.min(...prices);
    catalog.maxPrice = Math.max(...prices);
  }
  const extras = {};
  const routed = routeScope(a, e, ctx, catalog);
  let multi = null;
  if (!routed && !ctx.pending) {
    multi = detectMulti(text, a);
    if (multi?.entities) {
      e = multi.entities;
      e._text = a.normalized;
    } else if (multi?.kind === 'faq') {
      e = { ...multi.left.entities, _text: a.normalized };
      extras.faqNote = faq.shortAnswer(multi.topic);
    }
  }
  const refs = resolveRefs(e, ctx, catalog);
  let intent;
  if (routed) {
    intent = routed.intent;
    extras.topic = routed.topic;
    if (routed.number) extras.number = routed.number;
  } else {
    intent = decideIntent(a, e, ctx, refs, a.normalized);
    if (multi && (multi.kind === 'faq' || ['product_search', 'recommendation', 'budget_query', 'bundle'].includes(intent))) intent = 'product_search';
    else intent = refineIntent(intent, a, e, ctx, refs, extras, catalog);
  }
  const turn = { text: a.normalized, raw: text, e, a, ctx, refs, intent, catalog, profile, userId, extras, number: extras.number, seed: ctx.turns * 7 + text.length };
  // vague shopping ("something nice", "surprise me"): skip the keyword search, show personal/trending picks
  const handler = extras.vague ? handlePersonal : HANDLERS[intent] || STATIC[intent] || STATIC.fallback;
  const out = await handler(turn);
  if (extras.vague && out.products?.length) {
    out.content = `Here's a little inspiration to get you started. ${out.content}`;
    out.suggestions = ['Gift ideas', 'Phones under 50k', "Today's deals", 'Something more premium'];
  }
  if (multi && out.products?.length && multi.kind !== 'faq') {
    const second = await retrieve(S.mergeSlots(S.EMPTY_SLOTS(), multi.right.entities, 'new'), { limit: 1 }).catch(() => null);
    if (second && !second.noMatch && second.items.length) {
      const chip = chipFor(multi.rightText);
      out.suggestions = [chip, ...(out.suggestions || []).filter((c) => c !== chip)];
      out.content = `${out.content} Let's start with that, then tap **${chip}** for the second thing you asked about.`;
    } else {
      out.content = `${out.content} I couldn't find ${truncate(multi.rightText, 40)} in our catalog right now, so I've focused on the first part.`;
    }
  }
  if (extras.faqNote) out.content = `${out.content} ${extras.faqNote}`;

  ctx.pending = out.pending || null;
  ctx.turns += 1;
  ctx.lastIntent = intent;
  const products = recommendedList(out.products || []);

  let content = out.content;
  let source = 'local';
  if (intent === 'out_of_scope' && llm.active()) {
    // optional free llm for general questions only: persona-locked, cached, rate-limited; any failure keeps the offline reply
    const general = await llm.general({ query: text, fallback: content, topic: extras.topic });
    content = general.content;
    source = general.source;
  } else if (!out.personal && LLM_INTENTS.has(intent) && llm.active()) {
    const enhanced = await llm.enhance({ query: text, draft: content, intent, products, facts: (out.comparison?.verdict?.picks || []).map((p) => `${p.label}: product ${p.productId} — ${p.reason}`) });
    content = enhanced.content;
    source = enhanced.source;
  }
  return {
    content,
    title: out.title || null,
    context: ctx,
    meta: {
      intent,
      confidence: +a.confidence.toFixed(3),
      entities: publicEntities(e),
      slots: ctx.slots,
      products,
      suggestions: (out.suggestions || []).slice(0, 4),
      actions: out.actions || [],
      comparison: out.comparison || null,
      bundle: out.bundle ? serializeBundle(out.bundle) : null,
      qa: out.qa ? { confidence: out.qa.confidence, evidence: out.qa.evidence, followUps: out.qa.followUps } : null,
      explain: out.explain || null,
      gift: out.gift || null,
      clarify: out.clarify || null,
      scope: out.scope || null,
      fallback: Boolean(out.fallback),
      nlu: { source: a.source, alternatives: a.alternatives, corrections: a.corrections, normalized: a.normalized },
      source,
      latencyMs: Date.now() - started,
    },
  };
};

module.exports = { respond, resolveRefs, decideIntent, titleFromSlots };
