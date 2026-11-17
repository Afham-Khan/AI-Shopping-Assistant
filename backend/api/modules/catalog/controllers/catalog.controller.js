const Catalog = require('../models/catalog.models');
const Products = require('../../products/models/products.models');
const { ok } = require('../../../../helpers/response');
const { toCard } = require('../../../../helpers/serializers');
const { notFound } = require('../../../../helpers/errors');

const PKT_OFFSET_MS = 5 * 60 * 60 * 1000;

// flash deals roll over at midnight Pakistan time
const nextMidnightPkt = () => {
  const local = new Date(Date.now() + PKT_OFFSET_MS);
  local.setUTCHours(24, 0, 0, 0);
  return new Date(local.getTime() - PKT_OFFSET_MS).toISOString();
};

const loadDepartments = async ({ withCategories }) => {
  const [departments, categories] = await Promise.all([Catalog.departments(), Catalog.categoriesWithCounts()]);
  return departments.map((d) => {
    const own = categories.filter((c) => c.department_id === d.id);
    return {
      id: d.id,
      name: d.name,
      slug: d.slug,
      icon: d.icon,
      imageUrl: d.image_url,
      description: d.description,
      productCount: own.reduce((sum, c) => sum + c.product_count, 0),
      ...(withCategories && {
        categories: own.map((c) => ({ id: c.id, name: c.name, slug: c.slug, imageUrl: c.image_url, productCount: c.product_count })),
      }),
    };
  });
};

module.exports.departments = async (req, res) => ok(res, await loadDepartments({ withCategories: true }));

module.exports.category = async (req, res) => {
  const category = await Catalog.categoryBySlug(req.params.slug.toLowerCase());
  if (!category) throw notFound('Category not found');
  const [brands, price] = await Promise.all([Catalog.categoryBrands(category.id), Catalog.categoryPriceRange(category.id)]);
  return ok(res, {
    id: category.id,
    name: category.name,
    slug: category.slug,
    description: category.description,
    imageUrl: category.image_url,
    department: { id: category.department_id, name: category.department_name, slug: category.department_slug },
    brands,
    priceRange: { min: price.min ?? 0, max: price.max ?? 0 },
  });
};

module.exports.home = async (req, res) => {
  const interests = await Products.userInterests(req.userId);
  const [banners, departments, flashDeals, trending, topRated, newArrivals] = await Promise.all([
    Catalog.banners(),
    loadDepartments({ withCategories: false }),
    Catalog.flashDeals(),
    Catalog.trending(interests),
    Catalog.topRated(),
    Catalog.newArrivals(),
  ]);
  return ok(res, {
    banners: banners.map((b) => ({
      id: b.id,
      title: b.title,
      subtitle: b.subtitle,
      imageUrl: b.image_url,
      ctaLabel: b.cta_label,
      target: b.target,
      theme: b.theme,
    })),
    departments,
    flashDeals: flashDeals.map(toCard),
    trending: trending.map(toCard),
    topRated: topRated.map(toCard),
    newArrivals: newArrivals.map(toCard),
    dealEndsAt: nextMidnightPkt(),
  });
};
