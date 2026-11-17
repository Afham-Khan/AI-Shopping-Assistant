/* Idempotent seed: upserts by natural keys, never deletes, deterministic RNG -> safe to re-run. */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const db = require('../api/db/connection');
const { DEPARTMENTS, CATEGORIES, kebab, transformProducts } = require('./seed-data/catalog');
const { DEMO_USER, ADMIN_USER, SHOPPER_PASSWORD, PERSONAS, buildShoppers, SEARCH_QUERIES } = require('./seed-data/people');
const { composeReview, reviewRating, titleForRating } = require('./seed-data/reviews');
const { createBasketBuilder, weightedPick } = require('./seed-data/orders');
const { createRng, hashString } = require('./seed-data/random');
const { summarize } = require('../api/modules/cart/services/cart.service');
const { BCRYPT_COST } = require('../helpers/constants');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DAY = 24 * 60 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
const NOW = Date.now();
const SHOPPER_ORDER_COUNT = 150;

const readJson = (file) => (fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null);
const daysAgo = (days, hours = 0) => new Date(NOW - days * DAY - hours * HOUR);
const chunkInsert = async (trx, table, rows, size = 400) => {
  for (let i = 0; i < rows.length; i += size) await trx(table).insert(rows.slice(i, i + size));
};
const json = (v) => JSON.stringify(v);

const CONTENT_COLUMNS = [
  'external_id', 'title', 'slug', 'description', 'category_id', 'brand_id', 'price', 'compare_at_price', 'discount_percent',
  'currency', 'tags', 'highlights', 'specs', 'gender', 'color', 'weight', 'dimensions', 'warranty', 'shipping_info',
  'return_policy', 'search_keywords', 'updated_at',
];

const COUPONS = [
  { code: 'WELCOME10', description: '10% off your order (up to Rs 2,000)', discount_type: 'percent', value: 10, min_order_amount: 0, max_discount: 2000, expires_at: null },
  { code: 'FLAT500', description: 'Rs 500 off on orders above Rs 5,000', discount_type: 'fixed', value: 500, min_order_amount: 5000, max_discount: null, expires_at: new Date('2027-06-30T23:59:59+05:00') },
  { code: 'AI15', description: '15% off orders above Rs 20,000 (up to Rs 5,000) — Cartwise AI picks', discount_type: 'percent', value: 15, min_order_amount: 20000, max_discount: 5000, expires_at: new Date('2027-03-31T23:59:59+05:00') },
  { code: 'SUMMER25', description: 'Summer sale: 25% off (expired)', discount_type: 'percent', value: 25, min_order_amount: 3000, max_discount: 3000, expires_at: new Date('2026-08-31T23:59:59+05:00') },
];

// image comes from a representative product (resolved at seed time so cached local images are reused)
const BANNERS = [
  { title: 'Mega Electronics Week', subtitle: 'Up to 30% off smartphones, laptops & tablets', cta_label: 'Shop now', target: { type: 'department', value: 'electronics' }, theme: 'indigo', imageFrom: 123 },
  { title: 'Not sure what to buy?', subtitle: 'Ask Cartwise AI — describe what you need and get instant picks', cta_label: 'Ask Cartwise AI', target: { type: 'assistant', value: null }, theme: 'violet', imageFrom: 100 },
  { title: 'Glow Up Skin Care', subtitle: 'Serums, cleansers & moisturisers from Rs 999', cta_label: 'Explore', target: { type: 'category', value: 'skin-care' }, theme: 'rose', imageFrom: 'skin-care' },
  { title: 'Fresh Groceries, Delivered', subtitle: 'Fruits, veggies & pantry staples at your door', cta_label: 'Order now', target: { type: 'department', value: 'groceries' }, theme: 'emerald', imageFrom: 'groceries' },
  { title: 'Laptops for work & play', subtitle: 'Power-packed laptops for students and creators', cta_label: 'Browse', target: { type: 'search', value: 'laptop' }, theme: 'amber', imageFrom: 80 },
];

const DEMO_ORDERS = [
  { number: 'CW-DEMO-0001', status: 'delivered', daysAgo: 21, items: [[123, 1], [108, 1], [104, 1]], payment: 'card', last4: '4242', coupon: 'WELCOME10' },
  { number: 'CW-DEMO-0002', status: 'shipped', daysAgo: 2, items: [[173, 1], [119, 1]], payment: 'cod', coupon: null },
  { number: 'CW-DEMO-0003', status: 'placed', daysAgo: 1.1, items: [[80, 1], [107, 1]], payment: 'cod', coupon: 'AI15' },
];
const DEMO_WISHLIST = [160, 101, 174, 78, 7];
const DEMO_CART = [[100, 1], [118, 2]];
const DEMO_SEARCHES = ['iphone 13 pro', 'leather handbag', 'vitamin c serum', 'laptop for students', 'wireless earbuds'];

const HISTORY_FLOW = [
  ['placed', 'Order placed', 0],
  ['confirmed', 'Seller confirmed your order', 2],
  ['shipped', 'Handed over to courier', 26],
  ['out_for_delivery', 'Rider is on the way', 70],
  ['delivered', 'Delivered successfully', 76],
];

const seedCatalog = async (trx, products) => {
  for (const [i, d] of DEPARTMENTS.entries()) {
    await trx('departments').insert({ name: d.name, slug: d.slug, icon: d.icon, description: d.description, sort_order: i })
      .onConflict('slug').merge(['name', 'icon', 'description', 'sort_order']);
  }
  const deptIds = Object.fromEntries((await trx('departments').select('id', 'slug')).map((r) => [r.slug, r.id]));
  for (const d of DEPARTMENTS) {
    for (const [i, slug] of d.categories.entries()) {
      const [name, description] = CATEGORIES[slug];
      await trx('categories').insert({ department_id: deptIds[d.slug], name, slug, description, sort_order: i })
        .onConflict('slug').merge(['department_id', 'name', 'description', 'sort_order']);
    }
  }
  const categoryIds = Object.fromEntries((await trx('categories').select('id', 'slug')).map((r) => [r.slug, r.id]));

  const brandNames = [...new Set(products.map((p) => p.brand).filter(Boolean))];
  const usedSlugs = new Set((await trx('brands').select('slug')).map((r) => r.slug));
  const existingBrands = new Set((await trx('brands').select('name')).map((r) => r.name));
  for (const name of brandNames.filter((n) => !existingBrands.has(n))) {
    let slug = kebab(name) || `brand-${hashString(name)}`;
    if (usedSlugs.has(slug)) slug = `${slug}-${hashString(name) % 1000}`;
    usedSlugs.add(slug);
    await trx('brands').insert({ name, slug }).onConflict('name').ignore();
  }
  const brandIds = Object.fromEntries((await trx('brands').select('id', 'name')).map((r) => [r.name, r.id]));

  const rows = products.map((p) => {
    const created = createRng(`created-${p.externalId}`).int(1, 150);
    return {
      ...p.row,
      category_id: categoryIds[p.categorySlug],
      brand_id: p.brand ? brandIds[p.brand] : null,
      created_at: daysAgo(created),
      updated_at: new Date(NOW),
    };
  });
  for (let i = 0; i < rows.length; i += 50) {
    // stock, counters, rating and (possibly cached) thumbnail are runtime state: only set on first insert
    await trx('products').insert(rows.slice(i, i + 50)).onConflict('sku').merge(CONTENT_COLUMNS);
  }
  const dbProducts = await trx('products').select('id', 'sku', 'external_id', 'thumbnail_url', 'price', 'title', 'category_id');
  const bySku = new Map(dbProducts.map((r) => [r.sku, r]));
  products.forEach((p) => { p.db = bySku.get(p.row.sku); });

  const existingImages = new Set((await trx('product_images').select('product_id', 'sort_order')).map((r) => `${r.product_id}:${r.sort_order}`));
  const imageRows = products.flatMap((p) => p.images.map((url, i) => ({ product_id: p.db.id, url, sort_order: i })))
    .filter((r) => !existingImages.has(`${r.product_id}:${r.sort_order}`));
  await chunkInsert(trx, 'product_images', imageRows);

  // category / department images follow a representative product's current thumbnail
  for (const d of DEPARTMENTS) {
    let deptImage = null;
    for (const slug of d.categories) {
      const rep = products.filter((p) => p.categorySlug === slug).sort((a, b) => b.sourceRating - a.sourceRating)[0];
      if (!rep) continue;
      await trx('categories').where({ slug }).update({ image_url: rep.db.thumbnail_url });
      deptImage ||= rep.db.thumbnail_url;
    }
    await trx('departments').where({ slug: d.slug }).update({ image_url: deptImage });
  }

  // featured: best rating x stock per department, 12 total
  const quota = { electronics: 3, fashion: 2, 'beauty-personal-care': 2, 'home-living': 2, groceries: 1, 'sports-outdoors': 1, automotive: 1 };
  const featured = DEPARTMENTS.flatMap((d) => products
    .filter((p) => d.categories.includes(p.categorySlug) && p.row.stock > 0)
    .sort((a, b) => b.sourceRating * Math.log1p(b.row.stock) - a.sourceRating * Math.log1p(a.row.stock))
    .slice(0, quota[d.slug]).map((p) => p.db.id));
  await trx('products').update({ is_featured: false }).whereNotIn('id', featured);
  await trx('products').update({ is_featured: true }).whereIn('id', featured);

  return { categoryIds, featuredCount: featured.length };
};

const seedCouponsAndBanners = async (trx, products) => {
  for (const c of COUPONS) {
    await trx('coupons').insert({ ...c, is_active: true })
      .onConflict('code').merge(['description', 'discount_type', 'value', 'min_order_amount', 'max_discount', 'expires_at', 'is_active']);
  }
  const imageFor = (ref) => {
    const p = typeof ref === 'number'
      ? products.find((x) => x.externalId === ref)
      : products.filter((x) => x.categorySlug === ref).sort((a, b) => b.sourceRating - a.sourceRating)[0];
    return p?.db.thumbnail_url || null;
  };
  for (const [i, { imageFrom, ...b }] of BANNERS.entries()) {
    const row = { ...b, target: json(b.target), image_url: imageFor(imageFrom), sort_order: i, is_active: true };
    const existing = await trx('banners').where({ title: b.title }).first('id');
    if (existing) await trx('banners').where({ id: existing.id }).update(row);
    else await trx('banners').insert(row);
  }
  return Object.fromEntries((await trx('coupons').select('*')).map((c) => [c.code, c]));
};

const seedUsers = async (trx, shoppers) => {
  const demoHash = await bcrypt.hash(DEMO_USER.password, BCRYPT_COST);
  await trx('users').insert({
    name: DEMO_USER.name, email: DEMO_USER.email, password_hash: demoHash, phone: DEMO_USER.phone,
    preferences: json(DEMO_USER.preferences), is_onboarded: true, created_at: daysAgo(90),
  }).onConflict('email').merge(['name', 'password_hash', 'phone', 'preferences', 'is_onboarded']);

  const adminHash = await bcrypt.hash(ADMIN_USER.password, BCRYPT_COST);
  await trx('users').insert({
    name: ADMIN_USER.name, email: ADMIN_USER.email, password_hash: adminHash, phone: ADMIN_USER.phone,
    role: 'admin', preferences: json({}), is_onboarded: true, created_at: daysAgo(120),
  }).onConflict('email').merge(['name', 'password_hash', 'phone', 'role', 'is_onboarded']);

  const existing = new Set((await trx('users').whereIn('email', shoppers.map((s) => s.email)).select('email')).map((r) => r.email));
  const missing = shoppers.filter((s) => !existing.has(s.email));
  if (missing.length) {
    const hash = await bcrypt.hash(SHOPPER_PASSWORD, BCRYPT_COST);
    await trx('users').insert(missing.map((s) => ({
      name: s.name, email: s.email, password_hash: hash, phone: s.phone, preferences: json(s.preferences),
      is_onboarded: true, created_at: daysAgo(s.createdDaysAgo),
    }))).onConflict('email').ignore();
  }
  const ids = Object.fromEntries((await trx('users').whereIn('email', [DEMO_USER.email, ...shoppers.map((s) => s.email)]).select('id', 'email')).map((r) => [r.email, r.id]));

  const withAddress = new Set((await trx('addresses').whereIn('user_id', Object.values(ids)).distinct('user_id')).map((r) => r.user_id));
  const addressRows = [];
  if (!withAddress.has(ids[DEMO_USER.email])) DEMO_USER.addresses.forEach((a) => addressRows.push({ ...a, user_id: ids[DEMO_USER.email] }));
  shoppers.forEach((s) => { if (!withAddress.has(ids[s.email])) addressRows.push({ ...s.address, user_id: ids[s.email] }); });
  if (addressRows.length) await trx('addresses').insert(addressRows);
  return ids;
};

const addressSnapshot = (a) => ({
  label: a.label, fullName: a.full_name, phone: a.phone, line1: a.line1, line2: a.line2,
  city: a.city, province: a.province, postalCode: a.postal_code, country: a.country,
});

// deterministic order plan (both new and already-inserted orders), used for reviews/sold counts too
const planShopperOrders = (shoppers, products, coupons) => {
  const rng = createRng('orders-v1');
  const build = createBasketBuilder(products);
  const plan = [];
  const orderCountByUser = new Map();
  for (let i = 0; i < SHOPPER_ORDER_COUNT; i += 1) {
    const shopper = i < shoppers.length ? shoppers[i] : rng.pick(shoppers);
    const persona = rng.pick(shopper.personas);
    const basketKey = rng.pick(PERSONAS[persona].baskets);
    const lines = build(rng, basketKey, shopper.gender);
    if (!lines.length) continue;
    const isFirst = !orderCountByUser.has(shopper.email);
    orderCountByUser.set(shopper.email, (orderCountByUser.get(shopper.email) || 0) + 1);

    const subtotalLines = lines.map((l) => ({ price: l.product.row.price, compareAtPrice: l.product.row.compare_at_price, quantity: l.quantity }));
    const roll = rng.next();
    let coupon = null;
    if (isFirst && roll < 0.25) coupon = coupons.WELCOME10;
    else if (roll < 0.35) coupon = coupons.FLAT500;
    else if (roll < 0.45) coupon = coupons.AI15;
    let summary = summarize(subtotalLines, coupon);
    if (summary.couponError) summary = summarize(subtotalLines, null);

    plan.push({
      number: `CW-SEED-${String(i + 1).padStart(4, '0')}`,
      shopper,
      lines,
      summary,
      status: 'delivered',
      payment: rng.chance(0.6) ? 'cod' : 'card',
      last4: String(rng.int(1000, 9999)),
      placedAt: daysAgo(rng.int(4, 240), rng.int(0, 23)),
    });
  }
  return plan;
};

const insertOrder = async (trx, { number, userId, address, lines, summary, status, payment, last4, placedAt }, thumbs) => {
  const steps = HISTORY_FLOW.slice(0, HISTORY_FLOW.findIndex(([s]) => s === status) + 1);
  const at = (h) => new Date(placedAt.getTime() + h * HOUR);
  const delivered = status === 'delivered';
  const [order] = await trx('orders').insert({
    order_number: number,
    user_id: userId,
    status,
    payment_method: payment,
    payment_status: payment === 'card' || delivered ? 'paid' : 'pending',
    card_last4: payment === 'card' ? last4 : null,
    subtotal: summary.subtotal,
    discount: summary.discount,
    shipping_fee: summary.shippingFee,
    total: summary.total,
    coupon_code: summary.coupon?.code || null,
    shipping_address: json(addressSnapshot(address)),
    placed_at: placedAt,
    delivered_at: delivered ? at(steps[steps.length - 1][2]) : null,
    created_at: placedAt,
    updated_at: at(steps[steps.length - 1][2]),
  }).returning(['id', 'order_number']);

  await trx('order_items').insert(lines.map((l) => ({
    order_id: order.id,
    product_id: l.product.db.id,
    title: l.product.row.title,
    thumbnail_url: thumbs.get(l.product.db.id),
    unit_price: l.product.row.price,
    quantity: l.quantity,
    line_total: l.product.row.price * l.quantity,
  })));
  await trx('order_status_history').insert(steps.map(([s, note, h]) => ({ order_id: order.id, status: s, note, created_at: at(h) })));
  await trx('user_interactions').insert(lines.flatMap((l) => [
    { user_id: userId, product_id: l.product.db.id, type: 'view', source: 'browse', created_at: at(-30) },
    { user_id: userId, product_id: l.product.db.id, type: 'cart', source: 'browse', created_at: at(-1) },
    { user_id: userId, product_id: l.product.db.id, type: 'purchase', source: 'checkout', created_at: placedAt },
  ]));
  return { order, steps, at };
};

const seedOrders = async (trx, { products, shoppers, userIds, coupons }) => {
  const existing = new Set((await trx('orders').where('order_number', 'like', 'CW-SEED-%').orWhere('order_number', 'like', 'CW-DEMO-%').select('order_number')).map((r) => r.order_number));
  const addresses = await trx('addresses').whereIn('user_id', Object.values(userIds)).orderBy([{ column: 'is_default', order: 'desc' }, 'id']);
  const addressOf = (userId) => addresses.find((a) => a.user_id === userId);
  const thumbs = new Map(products.map((p) => [p.db.id, p.db.thumbnail_url]));

  const plan = planShopperOrders(shoppers, products, coupons);
  let inserted = 0;
  for (const o of plan) {
    if (existing.has(o.number)) continue;
    const userId = userIds[o.shopper.email];
    await insertOrder(trx, { ...o, userId, address: addressOf(userId) }, thumbs);
    inserted += 1;
  }

  const demoId = userIds[DEMO_USER.email];
  const byExt = new Map(products.map((p) => [p.externalId, p]));
  for (const d of DEMO_ORDERS) {
    if (existing.has(d.number)) continue;
    const lines = d.items.map(([ext, quantity]) => ({ product: byExt.get(ext), quantity })).filter((l) => l.product);
    const sumLines = lines.map((l) => ({ price: l.product.row.price, compareAtPrice: l.product.row.compare_at_price, quantity: l.quantity }));
    let summary = summarize(sumLines, d.coupon ? coupons[d.coupon] : null);
    if (summary.couponError) summary = summarize(sumLines, null);
    const placedAt = new Date(NOW - d.daysAgo * DAY);
    const { order, steps, at } = await insertOrder(trx, {
      number: d.number, userId: demoId, address: addressOf(demoId), lines, summary,
      status: d.status, payment: d.payment, last4: d.last4, placedAt,
    }, thumbs);
    const titles = { placed: 'Order placed', confirmed: 'Order confirmed', shipped: 'Order shipped', out_for_delivery: 'Out for delivery', delivered: 'Order delivered' };
    await trx('notifications').insert(steps.map(([s, note, h]) => ({
      user_id: demoId, type: 'order', title: titles[s], body: `Order ${order.order_number}: ${note.toLowerCase()}.`,
      data: json({ orderId: order.id, orderNumber: order.order_number, status: s }),
      created_at: at(h), read_at: d.status === 'delivered' ? at(h + 1) : null,
    })));
    inserted += 1;
  }
  return { plan, inserted };
};

const seedReviews = async (trx, { products, shoppers, userIds, plan }) => {
  const shopperIds = shoppers.map((s) => userIds[s.email]);
  const purchasers = new Map();
  plan.forEach((o) => o.lines.forEach((l) => {
    const set = purchasers.get(l.product.externalId) || new Set();
    set.add(userIds[o.shopper.email]);
    purchasers.set(l.product.externalId, set);
  }));

  const rows = [];
  for (const p of products) {
    const rng = createRng(`reviews-${p.externalId}`);
    const used = new Set();
    // dummyjson reviewers are mapped onto synthetic shoppers by a stable hash of their email
    for (const r of p.reviews) {
      let userId = shopperIds[hashString(r.reviewerEmail || r.reviewerName) % shopperIds.length];
      for (let k = 1; used.has(userId) && k < shopperIds.length; k += 1) userId = shopperIds[(shopperIds.indexOf(userId) + 1) % shopperIds.length];
      used.add(userId);
      rows.push({
        product_id: p.db.id, user_id: userId, rating: r.rating, title: titleForRating(r.rating), comment: r.comment,
        helpful_count: rng.int(0, 12), created_at: daysAgo(rng.int(10, 200)),
      });
    }
    const buyers = rng.shuffle([...(purchasers.get(p.externalId) || [])].filter((id) => !used.has(id)));
    const others = rng.shuffle(shopperIds.filter((id) => !used.has(id) && !buyers.includes(id)));
    const reviewers = [...buyers, ...others].slice(0, rng.int(2, 6));
    for (const userId of reviewers) {
      used.add(userId);
      const rating = reviewRating(rng, p.sourceRating);
      const { title, comment } = composeReview(rng, p.categorySlug, rating);
      rows.push({
        product_id: p.db.id, user_id: userId, rating, title, comment,
        helpful_count: Math.floor(rng.next() ** 2 * 40), created_at: daysAgo(rng.int(1, 180)),
      });
    }
  }
  for (let i = 0; i < rows.length; i += 400) {
    await trx('reviews').insert(rows.slice(i, i + 400)).onConflict(['product_id', 'user_id']).ignore();
  }
  return rows.length;
};

const seedBehaviour = async (trx, { products, shoppers, userIds }) => {
  const demoId = userIds[DEMO_USER.email];
  const byExt = new Map(products.map((p) => [p.externalId, p]));
  const byCategory = {};
  products.forEach((p) => { (byCategory[p.categorySlug] ||= []).push(p); });
  const browsed = new Set((await trx('user_interactions').where({ source: 'browse', type: 'click' }).distinct('user_id')).map((r) => r.user_id));
  const searched = new Set((await trx('search_history').whereIn('user_id', Object.values(userIds)).distinct('user_id')).map((r) => r.user_id));

  const interactions = [];
  const wishlist = [];
  const searches = [];
  const people = [...shoppers, { email: DEMO_USER.email, preferences: DEMO_USER.preferences, personas: ['techie', 'beauty', 'fashionista'] }];
  for (const person of people) {
    const userId = userIds[person.email];
    const rng = createRng(`behaviour-${person.email}`);
    if (!browsed.has(userId)) {
      for (const slug of person.preferences.interests) {
        const pool = byCategory[slug] || [];
        for (let i = 0; i < Math.min(pool.length, rng.int(3, 6)); i += 1) {
          const p = weightedPick(rng, pool, (x) => x.sourceRating ** 2);
          const when = daysAgo(rng.int(0, 60), rng.int(0, 23));
          interactions.push({ user_id: userId, product_id: p.db.id, type: 'view', source: 'browse', created_at: when });
          if (rng.chance(0.4)) interactions.push({ user_id: userId, product_id: p.db.id, type: 'click', source: 'browse', created_at: when });
          if (rng.chance(0.2)) interactions.push({ user_id: userId, product_id: p.db.id, type: 'cart', source: 'browse', created_at: when });
          if (rng.chance(0.25) && userId !== demoId) {
            interactions.push({ user_id: userId, product_id: p.db.id, type: 'wishlist', source: 'browse', created_at: when });
            wishlist.push({ user_id: userId, product_id: p.db.id, created_at: when });
          }
        }
      }
      // marker row so a re-run knows this user's browsing was already generated
      const marker = byCategory[person.preferences.interests[0]][0];
      interactions.push({ user_id: userId, product_id: marker.db.id, type: 'click', source: 'browse', created_at: daysAgo(61) });
    }
    if (!searched.has(userId)) {
      const queries = userId === demoId ? DEMO_SEARCHES : rng.sample(person.personas.flatMap((p) => SEARCH_QUERIES[p]), rng.int(2, 5));
      queries.forEach((query, i) => searches.push({ user_id: userId, query, results_count: rng.int(3, 40), created_at: daysAgo(rng.int(0, 25), i) }));
    }
  }

  const demoWish = DEMO_WISHLIST.map((ext) => byExt.get(ext)).filter(Boolean);
  demoWish.forEach((p, i) => {
    wishlist.push({ user_id: demoId, product_id: p.db.id, created_at: daysAgo(i + 1) });
  });
  const hadDemoWishlist = await trx('user_interactions').where({ user_id: demoId, type: 'wishlist' }).first('id');
  if (!hadDemoWishlist) demoWish.forEach((p, i) => interactions.push({ user_id: demoId, product_id: p.db.id, type: 'wishlist', source: 'browse', created_at: daysAgo(i + 1) }));

  await chunkInsert(trx, 'user_interactions', interactions);
  for (let i = 0; i < wishlist.length; i += 400) {
    await trx('wishlist_items').insert(wishlist.slice(i, i + 400)).onConflict(['user_id', 'product_id']).ignore();
  }
  await chunkInsert(trx, 'search_history', searches);

  await trx('carts').insert({ user_id: demoId }).onConflict('user_id').ignore();
  for (const [ext, quantity] of DEMO_CART) {
    const p = byExt.get(ext);
    if (p) await trx('cart_items').insert({ user_id: demoId, product_id: p.db.id, quantity }).onConflict(['user_id', 'product_id']).ignore();
  }

  const tab = byExt.get(160);
  const demoNotes = [
    { type: 'system', title: 'Welcome to Cartwise, Ayesha!', body: 'Your AI shopping assistant is ready. Tell it what you need and it will find the best picks.', data: {}, days: 60, read: true },
    { type: 'promo', title: 'Mega Electronics Week is live', body: 'Up to 30% off smartphones and laptops. Use AI15 for an extra 15% off orders above Rs 20,000.', data: { target: { type: 'department', value: 'electronics' } }, days: 3, read: false },
    { type: 'price_drop', title: 'Price drop on your wishlist', body: `${tab?.row.title || 'An item'} in your wishlist is now ${tab ? `Rs ${tab.row.price.toLocaleString('en-US')}` : 'cheaper'}.`, data: { productId: tab?.db.id }, days: 1, read: false },
    { type: 'ai', title: 'Try Cartwise AI', body: 'Ask "best phone under 100k with a great camera" and get instant, personalised picks.', data: { target: { type: 'assistant' } }, days: 0.5, read: false },
  ];
  const existingTitles = new Set((await trx('notifications').where({ user_id: demoId }).select('title')).map((r) => r.title));
  const noteRows = demoNotes.filter((n) => !existingTitles.has(n.title)).map((n) => ({
    user_id: demoId, type: n.type, title: n.title, body: n.body, data: json(n.data),
    created_at: daysAgo(n.days), read_at: n.read ? daysAgo(n.days - 0.1) : null,
  }));
  if (noteRows.length) await trx('notifications').insert(noteRows);

  return { interactions: interactions.length, searches: searches.length };
};

// price history starts with one row per product; a re-seed that changes a price is recorded too
const seedPriceHistory = async (trx) => {
  const { rows } = await trx.raw(`
    INSERT INTO price_history (product_id, price, compare_at_price, stock, source, recorded_at)
    SELECT p.id, p.price, p.compare_at_price, p.stock, 'seed', CASE WHEN last.product_id IS NULL THEN p.created_at ELSE now() END
    FROM products p
    LEFT JOIN LATERAL (
      SELECT h.product_id, h.price FROM price_history h WHERE h.product_id = p.id ORDER BY h.recorded_at DESC, h.id DESC LIMIT 1
    ) last ON true
    WHERE last.product_id IS NULL OR last.price <> p.price
    RETURNING id`);
  return rows.length;
};

// one ready-made price watch so the demo account's "Price alerts" screen is not empty
const seedDemoWatch = async (trx, userIds, products) => {
  const demoId = userIds[DEMO_USER.email];
  const target = products.find((p) => p.externalId === 101);
  if (!demoId || !target?.db) return;
  const row = await trx('products').where({ id: target.db.id }).first('price');
  await trx('price_watches').insert({
    user_id: demoId, product_id: target.db.id, target_price: Math.round(row.price * 0.9), notify_restock: true, initial_price: row.price,
  }).onConflict(['user_id', 'product_id']).ignore();
};

const recompute = async (trx) => {
  await trx.raw(`
    UPDATE reviews r SET is_verified = EXISTS (
      SELECT 1 FROM order_items oi JOIN orders o ON o.id = oi.order_id
      WHERE o.user_id = r.user_id AND oi.product_id = r.product_id AND o.status = 'delivered')`);
  await trx.raw(`
    UPDATE products p SET
      rating = COALESCE((SELECT ROUND(AVG(r.rating)::numeric, 2) FROM reviews r WHERE r.product_id = p.id), 0),
      rating_count = (SELECT COUNT(*) FROM reviews r WHERE r.product_id = p.id),
      sold_count = COALESCE((SELECT SUM(oi.quantity) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                             WHERE oi.product_id = p.id AND o.status <> 'cancelled'), 0)`);
  await trx.raw(`
    UPDATE coupons c SET used_count = (SELECT COUNT(*) FROM orders o WHERE o.coupon_code = c.code AND o.status <> 'cancelled')`);
};

const main = async () => {
  const started = Date.now();
  const sourceFile = readJson(path.join(DATA_DIR, 'dummyjson-products.json'));
  if (!sourceFile) throw new Error('backend/data/dummyjson-products.json is missing');
  const source = Array.isArray(sourceFile) ? sourceFile : sourceFile.products;
  const enrichment = readJson(path.join(DATA_DIR, 'product-enrichment.json')) || {};
  const products = transformProducts(source, enrichment);
  const shoppers = buildShoppers(40);

  const stats = await db.transaction(async (trx) => {
    const { featuredCount } = await seedCatalog(trx, products);
    const coupons = await seedCouponsAndBanners(trx, products);
    const userIds = await seedUsers(trx, shoppers);
    const { plan, inserted } = await seedOrders(trx, { products, shoppers, userIds, coupons });
    await seedReviews(trx, { products, shoppers, userIds, plan });
    const behaviour = await seedBehaviour(trx, { products, shoppers, userIds });
    await recompute(trx);
    const priceHistory = await seedPriceHistory(trx);
    await seedDemoWatch(trx, userIds, products);
    return { featuredCount, ordersInserted: inserted, priceHistory, ...behaviour };
  });

  const count = async (table) => (await db(table).count('* as n').first()).n;
  const totals = {};
  for (const t of ['departments', 'categories', 'brands', 'products', 'product_images', 'users', 'addresses', 'reviews', 'orders', 'order_items', 'user_interactions', 'wishlist_items', 'coupons', 'banners', 'notifications', 'search_history', 'price_history', 'price_watches']) {
    totals[t] = await count(t);
  }
  console.log(`Seed complete in ${((Date.now() - started) / 1000).toFixed(1)}s (enrichment: ${Object.keys(enrichment).length ? 'yes' : 'no'})`);
  console.log(`This run: ${stats.ordersInserted} orders, ${stats.interactions} interactions, ${stats.searches} searches inserted; ${stats.featuredCount} featured`);
  console.table(totals);
  console.log(`Price history rows added this run: ${stats.priceHistory}`);
  console.log(`Demo login: ${DEMO_USER.email} / ${DEMO_USER.password}`);
  console.log(`Admin login: ${ADMIN_USER.email} / ${ADMIN_USER.password}`);
};

main()
  .then(() => db.destroy())
  .catch(async (error) => {
    console.error('Seed failed:', error);
    await db.destroy();
    process.exit(1);
  });
