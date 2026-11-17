module.exports = {
  DEMO_EMAIL: 'demo@cartwise.app',
  BCRYPT_COST: 10,
  OTP_TTL_MINUTES: 10,
  OTP_MAX_ATTEMPTS: 5,
  FREE_SHIPPING_THRESHOLD: 5000,
  SHIPPING_FEE: 250,
  // delivery estimate: placed_at + N calendar days (used by orders and by the assistant's store FAQ)
  FAST_DELIVERY_CITIES: ['karachi', 'lahore', 'islamabad', 'rawalpindi'],
  FAST_DELIVERY_DAYS: 2,
  STANDARD_DELIVERY_DAYS: 4,
  PAYMENT_METHODS: ['cod', 'card'],
  MAX_CART_QTY: 10,
  ACTIVE_ORDER_STATUSES: ['placed', 'confirmed', 'shipped', 'out_for_delivery'],
};
