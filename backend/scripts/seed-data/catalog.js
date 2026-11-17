// DummyJSON -> Cartwise catalog transform (departments, categories, PKR pricing, products)
const USD_TO_PKR = 280;

const DEPARTMENTS = [
  {
    slug: 'electronics', name: 'Electronics', icon: 'devices',
    description: 'Smartphones, laptops, tablets and the accessories that power your day.',
    categories: ['smartphones', 'laptops', 'tablets', 'mobile-accessories'],
  },
  {
    slug: 'fashion', name: 'Fashion', icon: 'checkroom',
    description: 'Clothing, shoes, watches and accessories for men and women.',
    categories: ['mens-shirts', 'mens-shoes', 'mens-watches', 'tops', 'womens-dresses', 'womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses'],
  },
  {
    slug: 'beauty-personal-care', name: 'Beauty & Personal Care', icon: 'spa',
    description: 'Makeup, skin care and fragrances from brands you love.',
    categories: ['beauty', 'skin-care', 'fragrances'],
  },
  {
    slug: 'home-living', name: 'Home & Living', icon: 'chair',
    description: 'Furniture, decor and kitchen essentials to make a house a home.',
    categories: ['furniture', 'home-decoration', 'kitchen-accessories'],
  },
  {
    slug: 'groceries', name: 'Groceries', icon: 'local_grocery_store',
    description: 'Fresh produce, pantry staples and everyday essentials.',
    categories: ['groceries'],
  },
  {
    slug: 'sports-outdoors', name: 'Sports & Outdoors', icon: 'sports_soccer',
    description: 'Cricket, football, tennis and more — gear for every game.',
    categories: ['sports-accessories'],
  },
  {
    slug: 'automotive', name: 'Automotive', icon: 'two_wheeler',
    description: 'Motorcycles, scooters and cars for every road.',
    categories: ['motorcycle', 'vehicle'],
  },
];

const CATEGORIES = {
  smartphones: ['Smartphones', 'Latest Android and iOS phones with great cameras and long battery life.'],
  laptops: ['Laptops', 'Ultrabooks, creator and productivity laptops for work, study and play.'],
  tablets: ['Tablets', 'Tablets for entertainment, note-taking and on-the-go productivity.'],
  'mobile-accessories': ['Mobile Accessories', 'Earbuds, chargers, cases, smart speakers and more.'],
  'mens-shirts': ["Men's Shirts", 'Casual and formal shirts for every occasion.'],
  'mens-shoes': ["Men's Shoes", 'Sneakers, sports and formal shoes for men.'],
  'mens-watches': ["Men's Watches", 'Classic, sporty and luxury watches for men.'],
  tops: ["Women's Tops", 'Everyday tops, blouses and tees for women.'],
  'womens-dresses': ["Women's Dresses", 'Party, casual and formal dresses.'],
  'womens-shoes': ["Women's Shoes", 'Heels, flats and sneakers for women.'],
  'womens-bags': ["Women's Bags", 'Handbags, totes and backpacks.'],
  'womens-jewellery': ["Women's Jewellery", 'Earrings, necklaces and statement pieces.'],
  'womens-watches': ["Women's Watches", 'Elegant and everyday watches for women.'],
  sunglasses: ['Sunglasses', 'UV-protective sunglasses in classic and trendy styles.'],
  beauty: ['Makeup', 'Mascara, lipstick, powder and everyday makeup essentials.'],
  'skin-care': ['Skin Care', 'Cleansers, serums and moisturisers for healthy skin.'],
  fragrances: ['Fragrances', 'Perfumes and colognes for him and her.'],
  furniture: ['Furniture', 'Beds, sofas, chairs and tables for every room.'],
  'home-decoration': ['Home Decor', 'Lamps, plants, frames and accents that add character.'],
  'kitchen-accessories': ['Kitchen Accessories', 'Cookware, utensils and kitchen tools.'],
  groceries: ['Fresh & Pantry', 'Fruits, vegetables, meat, drinks and pantry staples.'],
  'sports-accessories': ['Sports Equipment', 'Balls, bats, rackets and protective gear.'],
  motorcycle: ['Motorcycles', 'Commuter bikes, scooters and superbikes.'],
  vehicle: ['Cars', 'Sedans, SUVs and family vehicles.'],
};

const GENDER_WORDS = { men: 'men mens male gents him', women: 'women womens ladies female her', unisex: 'unisex men women' };

const kebab = (s) => s.toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/['’]/g, '')
  .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

// "natural" retail price points: 2,799 / 2,749 under 10k, 45,999 under 100k, 2,099,999 above
const retailPrice = (pkr) => {
  if (pkr < 10000) return Math.max(99, Math.round(pkr / 50) * 50 - 1);
  if (pkr < 100000) return Math.round(pkr / 100) * 100 - 1;
  return Math.round(pkr / 1000) * 1000 - 1;
};

const pricing = (usd, discountPercentage) => {
  const price = retailPrice(usd * USD_TO_PKR);
  if (!(discountPercentage >= 5)) return { price, compareAtPrice: null, discountPercent: 0 };
  let compareAtPrice = retailPrice(price / (1 - discountPercentage / 100));
  if (compareAtPrice <= price) return { price, compareAtPrice: null, discountPercent: 0 };
  const discountPercent = Math.round(((compareAtPrice - price) / compareAtPrice) * 1000) / 10;
  if (discountPercent < 1) compareAtPrice = null;
  return { price, compareAtPrice, discountPercent: compareAtPrice ? discountPercent : 0 };
};

const inferGender = (p) => {
  if (p.category.startsWith('mens-')) return 'men';
  if (p.category.startsWith('womens-') || p.category === 'tops') return 'women';
  if (p.category === 'sunglasses') return 'unisex';
  if (p.category === 'fragrances') return /ck one|calvin klein/i.test(p.title) ? 'unisex' : 'women';
  return null;
};

const departmentOf = (categorySlug) => DEPARTMENTS.find((d) => d.categories.includes(categorySlug));

const fallbackSpecs = (p) => {
  const specs = {};
  if (p.brand) specs.Brand = p.brand;
  if (p.dimensions) specs.Dimensions = `${p.dimensions.width} × ${p.dimensions.height} × ${p.dimensions.depth} cm`;
  if (p.warrantyInformation) specs.Warranty = p.warrantyInformation;
  specs.SKU = p.sku;
  return specs;
};

const fallbackHighlights = (p) =>
  [p.brand && `Genuine ${p.brand} product`, p.warrantyInformation, p.shippingInformation, p.returnPolicy].filter(Boolean);

const transformProducts = (source, enrichment = {}) => {
  const slugs = new Set();
  return source.map((p) => {
    const extra = enrichment[String(p.id)] || {};
    let slug = kebab(p.title);
    if (slugs.has(slug)) slug = `${slug}-${p.id}`;
    slugs.add(slug);

    const dept = departmentOf(p.category);
    const [categoryName] = CATEGORIES[p.category];
    const gender = extra.gender !== undefined ? extra.gender : inferGender(p);
    const keywords = [
      categoryName, p.category.replace(/-/g, ' '), dept.name, p.brand, ...(p.tags || []),
      ...(extra.keywords || []), gender && GENDER_WORDS[gender], extra.color,
    ].filter(Boolean);

    return {
      externalId: p.id,
      categorySlug: p.category,
      brand: p.brand || null,
      reviews: p.reviews || [],
      images: p.images || [],
      sourceRating: p.rating,
      row: {
        external_id: p.id,
        sku: p.sku,
        title: p.title,
        slug,
        description: p.description || '',
        ...(({ price, compareAtPrice, discountPercent }) => ({
          price, compare_at_price: compareAtPrice, discount_percent: discountPercent,
        }))(pricing(p.price, p.discountPercentage)),
        currency: 'PKR',
        stock: p.stock,
        thumbnail_url: p.thumbnail,
        tags: p.tags || [],
        highlights: extra.highlights?.length ? extra.highlights : fallbackHighlights(p),
        specs: JSON.stringify(extra.specs && Object.keys(extra.specs).length ? extra.specs : fallbackSpecs(p)),
        gender,
        color: extra.color || null,
        weight: p.weight ?? null,
        dimensions: p.dimensions ? JSON.stringify(p.dimensions) : null,
        warranty: p.warrantyInformation || null,
        shipping_info: p.shippingInformation || null,
        return_policy: p.returnPolicy || null,
        search_keywords: [...new Set(keywords.map((k) => k.toLowerCase().trim()))].join(' '),
      },
    };
  });
};

module.exports = { DEPARTMENTS, CATEGORIES, kebab, retailPrice, pricing, transformProducts, departmentOf };
