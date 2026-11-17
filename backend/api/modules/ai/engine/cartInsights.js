// smart cart optimizer: cheaper near-equivalents, complete-the-set items, free-shipping gap fillers
const models = require('../models/ai.models');
const L = require('./nlu/lexicon');
const { getCatalog } = require('./retrieval/catalog');
const { boughtTogether } = require('./ranking/recommender');
const { money, stars, plural } = require('./format');
const { goesWith, compatible, isSubstitute, wrongGender, genderOf, isKidsItem, complementaryFor } = require('./complements');
const { evaluateCoupon } = require('../../cart/services/cart.service');
const { FREE_SHIPPING_THRESHOLD, SHIPPING_FEE } = require('../../../../helpers/constants');

// same rule as the cart: shipping is free when subtotal - coupon discount reaches the threshold
const FREE_SHIPPING = FREE_SHIPPING_THRESHOLD;

const simThreshold = (catalog) => (catalog.neural.size ? 0.6 : 0.35);

// sub-type tags ("wireless earphones", "chargers") must agree so a charger never replaces earbuds
const GENERIC_TAGS = new Set(['electronics', 'fashion', 'beauty', 'groceries', 'furniture', 'watches', 'sports equipment', 'fashion accessories', 'personal care']);
const subtypes = (p) => new Set((p.tags || []).map((t) => t.toLowerCase())
  .filter((t) => t !== p.category_slug && !GENERIC_TAGS.has(t) && t !== (p.brand_name || '').toLowerCase()));
const sameKind = (a, b) => {
  const sa = subtypes(a);
  const sb = subtypes(b);
  if (!sa.size || !sb.size) return true;
  for (const t of sa) if (sb.has(t)) return true;
  return false;
};

const cartInsights = async (userId) => {
  const catalog = await getCatalog();
  const { items, couponCode } = await models.cartSnapshot(userId);
  const inCart = new Set(items.map((i) => i.id));
  if (!items.length) {
    return { savings: [], completeTheSet: [], freeShippingGap: null, summary: 'Your cart is empty — add something and I will look for savings.', subtotal: 0 };
  }
  const subtotal = items.reduce((s, i) => s + i.price * i.quantity, 0);
  const threshold = simThreshold(catalog);

  // 1) cheaper near-equivalents in the same category
  const savings = [];
  for (const item of items) {
    const base = catalog.byId.get(item.id) || item;
    let best = null;
    for (const p of catalog.products) {
      if (p.id === base.id || inCart.has(p.id) || p.stock <= 0 || p.category_slug !== base.category_slug) continue;
      if (p.price > base.price * 0.92) continue;
      if (p.rating < base.rating - 0.3) continue;
      if (!sameKind(base, p)) continue;
      const sim = catalog.similarity(base.id, p.id);
      if (sim < threshold) continue;
      const save = (base.price - p.price) * item.quantity;
      const value = save * (0.5 + sim);
      if (!best || value > best.value) best = { p, sim, save, value };
    }
    if (best) {
      const ratingNote = best.p.rating >= base.rating ? `rated ${stars(best.p.rating)} vs ${stars(base.rating)}` : `nearly the same rating (${stars(best.p.rating)})`;
      savings.push({
        productId: base.id,
        alternative: {
          product: best.p,
          score: +Math.min(1, best.sim).toFixed(3),
          reasons: [`${Math.round(best.sim * 100)}% similar to ${base.title}`, `Save ${money(best.save)}`, `${ratingNote.charAt(0).toUpperCase()}${ratingNote.slice(1)}`],
        },
        save: best.save,
        reason: `${best.p.title} is ${Math.round(best.sim * 100)}% similar to ${base.title}, ${ratingNote} — save ${money(best.save)}.`,
      });
    }
  }
  savings.sort((a, b) => b.save - a.save);

  // 2) complete the set: association rules for the most valuable cart items, kept only when the pick genuinely
  // goes with the item, works with every device in the cart, is not another version of something already in it
  // and matches the cart's gender
  const cartRows = items.map((i) => catalog.byId.get(i.id) || i);
  const cartGender = cartRows.map(genderOf).find((g) => g !== 'unisex') || null;
  const fitsCart = (p) => cartRows.every((c) => compatible(c, p) && !isSubstitute(c, p)) && !wrongGender(p, cartGender);
  const anchors = cartRows.slice().sort((a, b) => b.price * (items.find((i) => i.id === b.id)?.quantity || 1) - a.price * (items.find((i) => i.id === a.id)?.quantity || 1)).slice(0, 2);
  const seen = new Set(inCart);
  const completeTheSet = [];
  for (const a of anchors) {
    const seed = (await boughtTogether(a.id, 12)) || [];
    for (const r of complementaryFor(a, catalog, { limit: 6, seed, exclude: seen, accept: fitsCart })) {
      seen.add(r.product.id);
      completeTheSet.push({ ...r, reasons: [`Pairs with your ${a.title}`, ...r.reasons].slice(0, 4) });
      if (completeTheSet.length >= 4) break;
    }
    if (completeTheSet.length >= 4) break;
  }

  // 3) close the free-shipping gap cheaply, preferring items that go with the cart. The gap is measured on
  // subtotal minus the coupon discount, exactly like the cart's own shipping rule.
  const coupon = couponCode ? await models.couponByCode(couponCode).catch(() => null) : null;
  const discount = coupon ? evaluateCoupon(coupon, subtotal).discount || 0 : 0;
  const payable = subtotal - discount;
  let freeShippingGap = null;
  if (payable < FREE_SHIPPING) {
    const remaining = FREE_SHIPPING - payable;
    const complements = new Set(items.flatMap((i) => L.COMPLEMENTS[i.category_slug] || []));
    const fillers = catalog.products
      .filter((p) => !inCart.has(p.id) && p.stock > 0 && p.price >= remaining && p.price <= remaining + 2500 && fitsCart(p) && !isKidsItem(p))
      .map((p) => ({ p, s: 0.4 * p._quality + 0.25 * (complements.has(p.category_slug) || cartRows.some((c) => goesWith(c, p)) ? 1 : 0) + 0.2 * (1 - (p.price - remaining) / 2500) + 0.15 * p._popularity }))
      .sort((a, b) => b.s - a.s)
      .slice(0, 4)
      .map((x) => x.p);
    freeShippingGap = { remaining, suggestions: fillers };
  }

  const totalSave = savings.reduce((s, x) => s + x.save, 0);
  const parts = [`Your cart has ${plural(items.reduce((s, i) => s + i.quantity, 0), 'item')} worth ${money(subtotal)}.`];
  if (savings.length) parts.push(`Switching ${plural(savings.length, 'item')} to a near-identical alternative could save ${money(totalSave)}.`);
  if (freeShippingGap) parts.push(`Add ${money(freeShippingGap.remaining)} more${discount ? ' (after your coupon)' : ''} to unlock free shipping (saves ${money(SHIPPING_FEE)}).`);
  else parts.push('You already qualify for free shipping.');
  if (completeTheSet.length) parts.push(`Shoppers who bought your items often add ${completeTheSet[0].product.title}.`);
  return { savings, completeTheSet, freeShippingGap, summary: parts.join(' '), subtotal };
};

module.exports = { cartInsights, FREE_SHIPPING };
