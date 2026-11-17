// coherent basket generator: anchors + affinity companions so co-purchase ("bought together") is meaningful
const BASKETS = {
  phone: { anchor: 'smartphones', companions: [['mobile-accessories', 1, 2]] },
  laptop: { anchor: 'laptops', companions: [['mobile-accessories', 1, 2]] },
  tablet: { anchor: 'tablets', companions: [['mobile-accessories', 1, 1]] },
  audio: { anchor: 'mobile-accessories', companions: [['mobile-accessories', 0, 1]] },
  dress: { anchor: 'womens-dresses', companions: [['womens-bags', 1, 1], ['womens-jewellery', 0, 1], ['womens-shoes', 0, 1]] },
  tops: { anchor: 'tops', companions: [['womens-shoes', 0, 1], ['sunglasses', 0, 1], ['womens-jewellery', 1, 1]] },
  bag: { anchor: 'womens-bags', companions: [['womens-watches', 0, 1], ['womens-jewellery', 0, 1]] },
  skincare: { anchor: 'skin-care', companions: [['beauty', 1, 1], ['skin-care', 0, 1]] },
  makeup: { anchor: 'beauty', companions: [['beauty', 0, 1], ['skin-care', 0, 1]] },
  fragrance: { anchor: 'fragrances', companions: [['beauty', 0, 1]] },
  kitchen: { anchor: 'kitchen-accessories', companions: [['kitchen-accessories', 1, 2]] },
  home: { anchor: 'furniture', companions: [['home-decoration', 1, 2]] },
  groceries: { anchor: 'groceries', companions: [['groceries', 2, 5]], maxQty: 3 },
  sports: { anchor: 'sports-accessories', companions: [['sports-accessories', 1, 2]] },
  shoes: { anchor: 'mens-shoes', companions: [['sports-accessories', 0, 1]] },
  menswear: { anchor: 'mens-shirts', companions: [['mens-shoes', 0, 1], ['mens-watches', 1, 1], ['sunglasses', 0, 1]] },
  watch: { anchor: 'mens-watches', companions: [['sunglasses', 0, 1]] },
  motorcycle: { anchor: 'motorcycle', companions: [['mobile-accessories', 0, 1]] },
};

const FEMALE_SWAP = { 'mens-shoes': 'womens-shoes', 'mens-watches': 'womens-watches', 'mens-shirts': 'tops' };

const firstWord = (title) => title.toLowerCase().split(/\s+/)[0];

// candidates sorted so the same anchor always prefers the same companions (brand / product-line affinity first)
const preferredCompanions = (rng, anchor, candidates) => {
  const tie = new Map(rng.shuffle(candidates).map((c, i) => [c.externalId, i]));
  const score = (c) => (c.brand && c.brand === anchor.brand ? 2 : 0) + (firstWord(c.row.title) === firstWord(anchor.row.title) ? 1 : 0);
  return [...candidates].sort((a, b) => score(b) - score(a) || tie.get(a.externalId) - tie.get(b.externalId));
};

const weightedPick = (rng, items, weight) => {
  const total = items.reduce((s, i) => s + weight(i), 0);
  let r = rng.next() * total;
  for (const item of items) {
    r -= weight(item);
    if (r <= 0) return item;
  }
  return items[items.length - 1];
};

const createBasketBuilder = (products) => {
  const byCategory = {};
  products.filter((p) => p.row.stock > 0).forEach((p) => { (byCategory[p.categorySlug] ||= []).push(p); });

  return (rng, basketKey, gender) => {
    const def = BASKETS[basketKey];
    const swap = (cat) => (gender === 'women' && FEMALE_SWAP[cat]) || cat;
    const anchorPool = byCategory[swap(def.anchor)] || [];
    if (!anchorPool.length) return [];
    const anchor = weightedPick(rng, anchorPool, (p) => p.sourceRating ** 2);
    const chosen = new Map([[anchor.externalId, anchor]]);

    for (const [category, min, max] of def.companions) {
      const pool = (byCategory[swap(category)] || []).filter((p) => !chosen.has(p.externalId));
      if (!pool.length) continue;
      const preferred = preferredCompanions(rng.fork(anchor.externalId), anchor, pool);
      const count = rng.int(min, max);
      for (let i = 0; i < count; i += 1) {
        const remaining = preferred.filter((p) => !chosen.has(p.externalId));
        if (!remaining.length) break;
        const roll = rng.next();
        const pick = roll < 0.6 ? remaining[0] : roll < 0.85 ? rng.pick(remaining.slice(0, 3)) : rng.pick(remaining);
        chosen.set(pick.externalId, pick);
      }
    }
    return [...chosen.values()].map((product) => ({ product, quantity: def.maxQty ? rng.int(1, def.maxQty) : 1 }));
  };
};

module.exports = { BASKETS, createBasketBuilder, weightedPick };
