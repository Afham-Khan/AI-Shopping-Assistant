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
const { money, stars, list, titleCase, truncate, plural, shortMoney } = require('../format');

const CHAT_LIMIT = 5;
const FREE_SHIPPING = 5000;
const NO_LIMIT = /\b(?:no limit|any budget|doesn'?t matter|does not matter|koi bhi|anything|no budget|whatever)\b/;
const SEARCH_FAMILY = new Set(['product_search', 'recommendation', 'budget_query', 'refine_cheaper', 'refine_premium', 'refine_filter', 'show_more', 'gift_suggestion', 'deals']);
const LLM_INTENTS = new Set(['bundle', 'product_question', 'product_search', 'recommendation', 'budget_query', 'refine_cheaper', 'refine_premium', 'refine_filter', 'show_more', 'gift_suggestion', 'deals', 'compare', 'product_info', 'greeting', 'help', 'small_talk']);
const ORDINAL_NAMES = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];

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
  // a single product type without bundle words is a search ("laptop for gaming under 5 lakh")
  if (intent === 'bundle' && e.categories.length === 1 && !/\b(?:setup|kit|bundle|set|routine|outfit|pack|combo|everything|starter|makeover|hamper|look|box)\b/.test(text)) return 'product_search';
  const hasShown = ctx.lastProducts.length > 0 || ctx.focus;
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

const handleGift = async (t) => {
  const { e, ctx, catalog, profile, text } = t;
  const continuing = ctx.lastIntent === 'gift_suggestion' || ctx.pending?.type?.startsWith('gift');
  let slots = S.mergeSlots(continuing ? ctx.slots : S.EMPTY_SLOTS(), e, 'merge');
  if (e.recipient && !e.gender && continuing && slots.recipient !== ctx.slots.recipient) slots.gender = L.RECIPIENTS[e.recipient] || null;
  ctx.slots = slots;
  if (!slots.recipient && !slots.gender && !slots.categories.length) {
    return {
      content: `I'd love to help you find a gift${slots.occasion ? ` for the ${slots.occasion}` : ''}! Who is it for?`,
      clarify: { question: 'Who is the gift for?', options: ['Mom', 'Dad', 'Wife', 'Husband', 'Sister', 'Friend'] },
      pending: { type: 'gift_recipient' },
      suggestions: [],
    };
  }
  const noLimit = NO_LIMIT.test(text);
  if (!slots.budget && !noLimit && ctx.pending?.type !== 'gift_budget') {
    return {
      content: `Lovely${slots.recipient ? ` — a gift for your ${slots.recipient}` : ''}. What budget do you have in mind?`,
      clarify: { question: "What's your budget?", options: GIFT_BUDGETS },
      pending: { type: 'gift_budget' },
      suggestions: [],
    };
  }
  const key = slots.recipient === 'kid' ? 'kid' : slots.gender || 'any';
  const giftSlots = { ...slots, categories: slots.categories.length ? slots.categories : L.GIFT_CATEGORIES[key], category: null };
  const result = await retrieve(giftSlots, { profile, limit: CHAT_LIMIT, perCategoryCap: 2 });
  ctx.slots = giftSlots;
  ctx.lastProducts = result.items.map((i) => i.product.id);
  ctx.pending = null;
  const forWho = slots.recipient ? `your ${slots.recipient}` : slots.gender === 'women' ? 'her' : slots.gender === 'men' ? 'him' : 'them';
  const cats = [...new Set(result.items.map((i) => i.product.category_name))].slice(0, 3);
  const top = result.items[0];
  const content = [
    result.relaxed.map((r) => r.message).join(' '),
    `Here are gift ideas for ${forWho}${slots.occasion ? ` for the ${slots.occasion}` : ''}${slots.budget ? ` ${nlg.budgetPhrase(slots.budget)}` : ''} — a mix of ${list(cats.map((c) => c.toLowerCase()))}.`,
    top ? `My favourite: **${top.product.title}** at **${money(top.product.price)}**${top.reasons[0] ? ` (${nl(top.reasons[0])})` : ''}.` : '',
  ].filter(Boolean).join(' ');
  return {
    content,
    products: result.items,
    suggestions: ['Show cheaper options', 'Something more premium', 'Compare the first two', 'Show more'],
    actions: result.items.length >= 2 ? [{ type: 'compare', label: 'Compare top picks', productIds: ctx.lastProducts.slice(0, 2) }] : [],
    title: `Gift for ${slots.recipient || (slots.gender === 'women' ? 'her' : slots.gender === 'men' ? 'him' : 'someone')}`,
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
  const comparison = await compareProducts(ids);
  if (!comparison) return { content: "I couldn't load those products to compare.", suggestions: ['Show more'] };
  const names = comparison.products.map((p) => `**${p.title}**`);
  const best = comparison.verdict.picks.find((p) => p.label === 'Best value');
  const bestIdx = ids.indexOf(best?.productId);
  const bolded = comparison.products
    .reduce((txt, p) => txt.split(p.title).join(`**${p.title}**`), comparison.verdict.summary)
    .replace(/Rs [\d,]+/g, (m) => `**${m}**`);
  const content = `Comparing ${list(names)}. ${bolded}`;
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
  const items = (kind === 'similar' ? await similar(base.id, CHAT_LIMIT) : await boughtTogether(base.id, CHAT_LIMIT)) || [];
  ctx.lastProducts = items.map((i) => i.product.id);
  ctx.focus = base.id;
  const top = items[0];
  const lead = kind === 'similar' ? `Here are items similar to **${base.title}**` : `Shoppers who buy **${base.title}** often add these`;
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
  return {
    content: `Here's your **${b.title}** for **${money(b.total)}** of your ${money(b.budget)} budget (${money(b.remaining)} left): ${lines.join('; ')}. ${b.savingsTips[0] || ''}`.trim(),
    products: b.items.map((it) => it.product),
    bundle: b,
    actions: b.items.length ? [{ type: 'add_bundle_to_cart', label: `Add all ${b.items.length} to cart`, productIds: ctx.lastProducts }] : [],
    suggestions: ['Tell me more about the first one', 'Compare the first two', `Build it for ${shortMoney(Math.round(b.budget * 0.7 / 1000) * 1000)}`],
    title: b.title,
  };
};

const handleProductQuestion = async (t) => {
  const { ctx, refs, catalog, raw } = t;
  const id = refs.ids[0] || ctx.focus;
  const p = catalog.byId.get(id);
  if (!p) return handleProductInfo(t);
  ctx.focus = p.id;
  const question = raw.replace(/\b(?:thes+)?(?:first|second|third|fourth|fifth|last|1st|2nd|3rd|4th|5th)s+(?:one|item|product)?\b/gi, 'it').replace(/s+/g, ' ');
  const r = await qa.ask(p.id, question);
  return {
    content: r.answer,
    products: [simpleItem(p, catalog)],
    qa: r,
    suggestions: r.followUps.slice(0, 3),
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
  small_talk: (t) => ({ content: nlg.smallTalk(t.text), suggestions: ['Recommend something', "Today's deals", 'Help'] }),
  fallback: () => ({ content: nlg.fallback(), suggestions: ['Phones under 50k', 'Gift ideas', 'Help'] }),
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
  const e = a.entities;
  e._text = a.normalized;
  if (/\b(?:start over|reset|new search|clear)\b/.test(a.normalized)) {
    Object.assign(ctx, S.initialContext(), { turns: ctx.turns });
  }
  const refs = resolveRefs(e, ctx, catalog);
  const intent = decideIntent(a, e, ctx, refs, a.normalized);
  const turn = { text: a.normalized, raw: text, e, a, ctx, refs, intent, catalog, profile, userId, seed: ctx.turns * 7 + text.length };
  const handler = HANDLERS[intent] || STATIC[intent] || STATIC.fallback;
  const out = await handler(turn);

  ctx.pending = out.pending || null;
  ctx.turns += 1;
  ctx.lastIntent = intent;
  const products = recommendedList(out.products || []);

  let content = out.content;
  let source = 'local';
  if (!out.personal && LLM_INTENTS.has(intent) && llm.active()) {
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
      clarify: out.clarify || null,
      fallback: Boolean(out.fallback),
      nlu: { source: a.source, alternatives: a.alternatives, corrections: a.corrections, normalized: a.normalized },
      source,
      latencyMs: Date.now() - started,
    },
  };
};

module.exports = { respond, resolveRefs, decideIntent, titleFromSlots };
