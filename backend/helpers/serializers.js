// DB rows are snake_case; the API speaks camelCase. Product shapes are shared by
// catalog, cart, wishlist, orders and the AI module, so they live here.

const toCard = (row) => ({
  id: row.id,
  title: row.title,
  slug: row.slug,
  brand: row.brand_name || null,
  category: row.category_slug
    ? { id: row.category_id, name: row.category_name, slug: row.category_slug }
    : null,
  price: row.price,
  compareAtPrice: row.compare_at_price,
  discountPercent: row.discount_percent,
  rating: row.rating,
  ratingCount: row.rating_count,
  stock: row.stock,
  inStock: row.stock > 0,
  thumbnail: row.thumbnail_url,
  tags: row.tags || [],
});

const toDetail = (row, { images = [], ratingBreakdown = null } = {}) => ({
  ...toCard(row),
  description: row.description,
  department: row.department_slug
    ? { id: row.department_id, name: row.department_name, slug: row.department_slug }
    : null,
  images: images.length ? images : [row.thumbnail_url].filter(Boolean),
  highlights: row.highlights || [],
  specs: row.specs || {},
  gender: row.gender,
  color: row.color,
  weight: row.weight,
  dimensions: row.dimensions,
  warranty: row.warranty,
  shippingInfo: row.shipping_info,
  returnPolicy: row.return_policy,
  soldCount: row.sold_count,
  ratingBreakdown,
});

const toUser = (row) => ({
  id: row.id,
  name: row.name,
  email: row.email,
  phone: row.phone,
  avatarUrl: row.avatar_url,
  role: row.role,
  preferences: row.preferences || {},
  isOnboarded: row.is_onboarded,
  createdAt: row.created_at,
});

const initials = (name = '') =>
  name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('') || '?';

const toAddress = (row) => ({
  id: row.id,
  label: row.label,
  fullName: row.full_name,
  phone: row.phone,
  line1: row.line1,
  line2: row.line2,
  city: row.city,
  province: row.province,
  postalCode: row.postal_code,
  country: row.country,
  isDefault: row.is_default,
});

const toReview = (row) => ({
  id: row.id,
  rating: row.rating,
  title: row.title,
  comment: row.comment,
  isVerified: row.is_verified,
  helpfulCount: row.helpful_count,
  createdAt: row.created_at,
  user: { name: row.user_name, initials: initials(row.user_name) },
});

const toNotification = (row) => ({
  id: row.id,
  type: row.type,
  title: row.title,
  body: row.body,
  data: row.data || {},
  readAt: row.read_at,
  createdAt: row.created_at,
});

module.exports = { toCard, toDetail, toUser, toAddress, toReview, toNotification, initials };
