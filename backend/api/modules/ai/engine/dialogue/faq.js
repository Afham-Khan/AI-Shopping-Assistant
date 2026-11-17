// store faq: answers about delivery, shipping fees, payment, coupons, returns and contact, built from the
// same constants the order/cart services use, so the assistant can never drift from the real rules.
const models = require('../../models/ai.models');
const {
  FREE_SHIPPING_THRESHOLD, SHIPPING_FEE, FAST_DELIVERY_CITIES, FAST_DELIVERY_DAYS, STANDARD_DELIVERY_DAYS,
} = require('../../../../../helpers/constants');
const { money, list, titleCase, plural, shortMoney } = require('../format');

const FAST_NAMES = list(FAST_DELIVERY_CITIES.map(titleCase));
const CITY_ALIASES = { pindi: 'rawalpindi', isb: 'islamabad', khi: 'karachi', lhr: 'lahore' };
const ACTIVE = ['placed', 'confirmed', 'shipped', 'out_for_delivery'];

const deliveryLine = () => `about **${FAST_DELIVERY_DAYS} days** to ${FAST_NAMES}, and about **${STANDARD_DELIVERY_DAYS} days** to the rest of Pakistan`;
const shippingLine = () => `Shipping is **free on orders of ${money(FREE_SHIPPING_THRESHOLD)} or more**; below that it's a flat **${money(SHIPPING_FEE)}**`;

const fmtDate = (d) => new Date(d).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });

// expected date of the user's active order, same formula as orders.service.estimatedDelivery
const activeOrderEta = async (userId) => {
  if (!userId) return null;
  const data = await models.latestOrder(userId).catch(() => null);
  const order = data?.order;
  if (!order || !ACTIVE.includes(order.status)) return null;
  const city = String(order.shipping_address?.city || '').toLowerCase();
  const days = FAST_DELIVERY_CITIES.includes(city) ? FAST_DELIVERY_DAYS : STANDARD_DELIVERY_DAYS;
  return { order, eta: new Date(new Date(order.placed_at).getTime() + days * 86400000) };
};

const amountIn = (e) => e.budget?.target || e.budget?.max || e.budget?.min || null;

const ANSWERS = {
  delivery_time: async ({ userId }) => {
    const active = await activeOrderEta(userId);
    return {
      content: `Delivery takes ${deliveryLine()}. ${shippingLine()}.${active ? ` Your latest order **${active.order.order_number}** is expected by **${fmtDate(active.eta)}**.` : ' After you order, you can follow every step in **My orders**.'}`,
      suggestions: active ? ['Where is my order?', 'Payment methods', 'Return policy'] : ['Do you deliver to Quetta?', 'Payment methods', 'Is shipping free?', "Today's deals"],
      actions: active ? [{ type: 'view_order', label: 'View order', orderId: active.order.id }] : [],
    };
  },
  delivery_area: async ({ signals }) => {
    const city = signals.city;
    const key = CITY_ALIASES[city?.name] || city?.name;
    if (key && FAST_DELIVERY_CITIES.includes(key)) {
      return {
        content: `Yes! We deliver to **${titleCase(key)}** in about **${FAST_DELIVERY_DAYS} days**. ${shippingLine()}, and you can pay by Cash on Delivery or card.`,
        suggestions: ['Payment methods', 'Is shipping free?', "Today's deals"],
      };
    }
    if (city && !city.unknown) {
      return {
        content: `Yes, we deliver to **${titleCase(key)}**: it usually takes about **${STANDARD_DELIVERY_DAYS} days** (${FAST_NAMES} get it in about ${FAST_DELIVERY_DAYS}). ${shippingLine()}.`,
        suggestions: ['Is cash on delivery available?', 'Is shipping free?', "Today's deals"],
      };
    }
    return {
      content: `We deliver all across **Pakistan**: ${deliveryLine()}${city ? `, so ${titleCase(city.name)} should take about ${STANDARD_DELIVERY_DAYS} days if it's in Pakistan` : ''}. ${shippingLine()}.`,
      suggestions: ['Payment methods', 'Is shipping free?', "Today's deals"],
    };
  },
  delivery_days: async () => ({
    content: `Our delivery estimates count every day of the week: ${deliveryLine()}. Once you order, the exact progress (confirmed, shipped, out for delivery) shows in **My orders**, and you get a notification at each step.`,
    suggestions: ['How long is delivery?', 'Payment methods', "Today's deals"],
  }),
  international: async () => ({
    content: `For now Zelora delivers only within **Pakistan**: ${deliveryLine()}. If you're ordering for family here, just use their Pakistani address at checkout.`,
    suggestions: ['How long is delivery?', 'Payment methods', 'Gift ideas'],
  }),
  shipping_fee: async ({ e }) => {
    const amount = amountIn(e);
    if (amount) {
      const gap = FREE_SHIPPING_THRESHOLD - amount;
      return {
        content: gap > 0
          ? `For a **${money(amount)}** order, shipping is **${money(SHIPPING_FEE)}**. Add **${money(gap)}** more to make it **free** (free from ${money(FREE_SHIPPING_THRESHOLD)}).`
          : `A **${money(amount)}** order ships **free**: everything from ${money(FREE_SHIPPING_THRESHOLD)} up has free shipping.`,
        suggestions: ['Show my cart', `Things under ${shortMoney(Math.max(1000, gap > 0 ? Math.ceil(gap / 1000) * 1000 : 5000))}`, 'Any coupons?'],
      };
    }
    return {
      content: `${shippingLine()} (after discounts). Delivery takes ${deliveryLine()}.`,
      suggestions: ['Show my cart', 'Any coupons?', 'Payment methods'],
    };
  },
  payment: async ({ text }) => {
    const wallet = /\b(?:easypaisa|easy paisa|jazzcash|jazz cash|bank transfer|installments?|qist)\b/.test(text);
    return {
      content: `You can pay by **Cash on Delivery (COD)** or by **card** at checkout.${wallet ? ' Mobile wallets, bank transfer and instalments aren\'t supported yet.' : ''} Card orders are marked paid straight away; with COD you simply pay the rider when your parcel arrives.`,
      suggestions: ['Is it safe to pay by card?', 'How long is delivery?', 'Is shipping free?'],
    };
  },
  cod: async () => ({
    content: `Yes, **Cash on Delivery** is available on every order across Pakistan. Choose COD at checkout and pay the rider when your parcel arrives. Prefer paying upfront? Card works too.`,
    suggestions: ['How long is delivery?', 'Is shipping free?', "Today's deals"],
  }),
  card_safety: async () => ({
    content: 'Card payment happens at checkout, and Zelora keeps only the **last 4 digits** of your card on the order, never the full number. If you\'d rather not pay online at all, choose **Cash on Delivery** and pay when the parcel arrives.',
    suggestions: ['Payment methods', 'How long is delivery?', 'Return policy'],
  }),
  hours: async () => ({
    content: `Zelora is an online store, so you can shop **24/7**, and I'm always here too. Orders are delivered in ${deliveryLine()}.`,
    suggestions: ['How long is delivery?', "Today's deals", 'Recommend something'],
  }),
  physical_store: async () => ({
    content: `Zelora is **online-only**: there's no physical shop to visit. Everything is delivered to your door across Pakistan (${FAST_DELIVERY_DAYS}-${STANDARD_DELIVERY_DAYS} days), and you can pay by Cash on Delivery.`,
    suggestions: ['How long is delivery?', 'Payment methods', "Today's deals"],
  }),
  contact: async () => ({
    content: 'I can sort out most things right here: order status, returns, cancellations, delivery and payment questions. For an order issue, open **Account → My orders**: you can track, cancel or buy again from there. App info lives under **Account → Help & about**.',
    suggestions: ['Where is my order?', 'Return policy', 'How do I cancel my order?'],
  }),
  coupons: async () => {
    const coupons = await models.activeCoupons().catch(() => []);
    if (!coupons.length) return { content: 'There are no coupon codes running right now, but there are plenty of discounted products.', suggestions: ["Today's deals", 'Recommend something'] };
    const lines = coupons.map((c) => `**${c.code}**: ${c.description}`);
    return {
      content: `Active coupon ${coupons.length === 1 ? 'code' : 'codes'}: ${lines.join('; ')}. Apply one in your cart at checkout (one code per order).`,
      suggestions: ["Today's deals", 'Show my cart', 'Is shipping free?'],
    };
  },
  warranty: async ({ catalog }) => {
    const covered = catalog.products.filter((p) => p.warranty && !/^no warranty/i.test(p.warranty)).length;
    return {
      content: `Warranty depends on the product: ${covered} of our ${catalog.products.length} products come with one, from about a week up to lifetime, and it's listed on every product page. Ask me about a specific product (for example *what is the warranty on iPhone X?*) and I'll tell you exactly.`,
      suggestions: ['Return policy', 'Phones', 'Laptops'],
    };
  },
  catalog: async ({ catalog }) => {
    const depts = [...new Map(catalog.taxonomy.map((c) => [c.departmentName, c])).keys()];
    const cats = catalog.taxonomy.map((c) => c.name);
    return {
      content: `Zelora stocks **${catalog.products.length} products** across **${cats.length} categories** in ${list(depts.map((d) => `**${d}**`))}: everything from smartphones, laptops and tablets to fashion, beauty, fragrances, home decor, groceries and even motorcycles and cars. What are you in the mood for?`,
      clarify: { question: 'What are you shopping for?', options: ['Phones', 'Laptops', 'Fashion', 'Beauty', 'Home & kitchen', 'Gifts'] },
      pending: { type: 'shopping_what' },
      suggestions: [],
    };
  },
  overview: async () => ({
    content: `Quick facts about shopping on Zelora: delivery takes ${deliveryLine()}; ${shippingLine().charAt(0).toLowerCase()}${shippingLine().slice(1)}; you can pay by **Cash on Delivery** or **card**; and return windows are listed on each product page.`,
    suggestions: ['Do you deliver to my city?', 'Any coupons?', 'Return policy', "Today's deals"],
  }),
};

const answer = async (topic, ctx) => (ANSWERS[topic] || ANSWERS.overview)(ctx);

// one-line versions for a second question in the same message ("show me shoes and the delivery time")
const SHORT = {
  delivery_time: () => `Delivery: ${deliveryLine()}.`,
  delivery_area: () => `Delivery: ${deliveryLine()}.`,
  delivery_days: () => `Delivery: ${deliveryLine()}.`,
  shipping_fee: () => `${shippingLine()}.`,
  payment: () => 'You can pay by **Cash on Delivery** or **card**.',
  cod: () => '**Cash on Delivery** is available on every order.',
  international: () => 'We deliver within **Pakistan** only.',
};
const shortAnswer = (topic) => (SHORT[topic] ? SHORT[topic]() : null);

module.exports = { answer, shortAnswer, ANSWERS, deliveryLine, shippingLine, plural };
