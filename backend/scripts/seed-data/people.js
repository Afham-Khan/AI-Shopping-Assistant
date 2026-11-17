const { createRng } = require('./random');

const DEMO_USER = {
  name: 'Ayesha Khan',
  email: 'demo@cartwise.app',
  password: 'Demo@1234',
  phone: '+92 300 1234567',
  preferences: {
    interests: ['smartphones', 'laptops', 'womens-bags', 'skin-care'],
    budget: { min: 0, max: 400000 },
    gender: 'women',
  },
  addresses: [
    {
      label: 'Home', full_name: 'Ayesha Khan', phone: '+92 300 1234567', line1: 'House 42, Street 7, Block 5',
      line2: 'Clifton', city: 'Karachi', province: 'Sindh', postal_code: '75600', country: 'Pakistan', is_default: true,
    },
    {
      label: 'Office', full_name: 'Ayesha Khan', phone: '+92 321 7654321', line1: 'Office 1203, Ocean Tower',
      line2: 'Khayaban-e-Iqbal, DHA Phase 6', city: 'Karachi', province: 'Sindh', postal_code: '75500', country: 'Pakistan', is_default: false,
    },
  ],
};

// store admin for PATCH /admin/products/:id (price / stock changes that fire alerts)
const ADMIN_USER = { name: 'Zelora Admin', email: 'admin@zelora.app', password: 'Admin@1234', phone: '+92 300 0000001' };

const SHOPPER_PASSWORD = 'Shopper@1234';

const MEN = ['Ali', 'Ahmed', 'Hamza', 'Bilal', 'Usman', 'Hassan', 'Zain', 'Saad', 'Fahad', 'Omar', 'Faisal', 'Imran',
  'Kamran', 'Danish', 'Waleed', 'Shahzaib', 'Talha', 'Junaid', 'Asad', 'Haris'];
const WOMEN = ['Fatima', 'Ayesha', 'Zainab', 'Maryam', 'Hira', 'Sana', 'Mahnoor', 'Iqra', 'Amna', 'Rabia', 'Sara',
  'Noor', 'Hafsa', 'Khadija', 'Mehwish', 'Anum', 'Laiba', 'Areeba', 'Kiran', 'Saba'];
const SURNAMES = ['Khan', 'Ahmed', 'Malik', 'Hussain', 'Sheikh', 'Butt', 'Chaudhry', 'Qureshi', 'Raza', 'Siddiqui',
  'Abbasi', 'Mirza', 'Javed', 'Iqbal', 'Shah', 'Aslam', 'Riaz', 'Akhtar', 'Baig', 'Zafar'];

const CITIES = [
  { city: 'Karachi', province: 'Sindh', postal: '75', areas: ['Gulshan-e-Iqbal', 'DHA Phase 5', 'North Nazimabad', 'PECHS', 'Bahadurabad'] },
  { city: 'Lahore', province: 'Punjab', postal: '54', areas: ['Johar Town', 'DHA Phase 3', 'Model Town', 'Gulberg III', 'Bahria Town'] },
  { city: 'Islamabad', province: 'Islamabad Capital Territory', postal: '44', areas: ['F-7/2', 'G-11/3', 'E-11', 'I-8/4', 'DHA Phase 2'] },
  { city: 'Rawalpindi', province: 'Punjab', postal: '46', areas: ['Saddar', 'Satellite Town', 'Bahria Town Phase 7'] },
  { city: 'Faisalabad', province: 'Punjab', postal: '38', areas: ['Peoples Colony', 'Madina Town', 'D Ground'] },
  { city: 'Multan', province: 'Punjab', postal: '60', areas: ['Gulgasht Colony', 'Cantt', 'Shah Rukn-e-Alam'] },
  { city: 'Peshawar', province: 'Khyber Pakhtunkhwa', postal: '25', areas: ['Hayatabad Phase 3', 'University Town', 'Saddar'] },
  { city: 'Hyderabad', province: 'Sindh', postal: '71', areas: ['Latifabad Unit 6', 'Qasimabad', 'Citizen Colony'] },
];

// personas drive interests, budgets, order baskets and search queries so behaviour is coherent
const PERSONAS = {
  techie: { interests: ['smartphones', 'laptops', 'mobile-accessories', 'tablets'], budget: 400000, baskets: ['phone', 'laptop', 'tablet', 'audio'] },
  fashionista: { interests: ['womens-dresses', 'womens-bags', 'womens-jewellery', 'womens-shoes', 'tops'], budget: 60000, gender: 'women', baskets: ['dress', 'tops', 'bag'] },
  beauty: { interests: ['beauty', 'skin-care', 'fragrances'], budget: 30000, baskets: ['skincare', 'makeup', 'fragrance'] },
  homemaker: { interests: ['furniture', 'home-decoration', 'kitchen-accessories', 'groceries'], budget: 150000, baskets: ['kitchen', 'home', 'groceries'] },
  grocer: { interests: ['groceries', 'kitchen-accessories'], budget: 20000, baskets: ['groceries', 'groceries', 'kitchen'] },
  sporty: { interests: ['sports-accessories', 'mens-shoes', 'sunglasses'], budget: 40000, baskets: ['sports', 'sports', 'shoes'] },
  gent: { interests: ['mens-shirts', 'mens-shoes', 'mens-watches', 'sunglasses', 'fragrances'], budget: 80000, gender: 'men', baskets: ['menswear', 'watch', 'fragrance'] },
  rider: { interests: ['motorcycle', 'mobile-accessories', 'sports-accessories'], budget: 3000000, baskets: ['motorcycle', 'audio', 'sports'] },
};

const MALE_PERSONAS = ['techie', 'techie', 'gent', 'gent', 'sporty', 'sporty', 'rider', 'homemaker', 'grocer', 'beauty'];
const FEMALE_PERSONAS = ['fashionista', 'fashionista', 'beauty', 'beauty', 'homemaker', 'grocer', 'techie', 'techie', 'sporty'];

const buildShoppers = (count = 40) => {
  const rng = createRng('shoppers-v1');
  const used = new Set();
  const shoppers = [];
  for (let i = 0; i < count; i += 1) {
    const isMan = i % 2 === 0;
    let first;
    let last;
    do {
      first = rng.pick(isMan ? MEN : WOMEN);
      last = rng.pick(SURNAMES);
    } while (used.has(`${first}.${last}`));
    used.add(`${first}.${last}`);

    const primary = rng.pick(isMan ? MALE_PERSONAS : FEMALE_PERSONAS);
    let secondary = rng.pick(isMan ? MALE_PERSONAS : FEMALE_PERSONAS);
    if (secondary === primary) secondary = null;
    const personas = [primary, secondary].filter(Boolean);
    const interests = [...new Set(personas.flatMap((p) => rng.sample(PERSONAS[p].interests, rng.int(2, 3))))];
    const where = rng.pick(CITIES);
    const phone = `+92 3${rng.int(0, 4)}${rng.int(0, 9)} ${rng.int(1000000, 9999999)}`;

    shoppers.push({
      name: `${first} ${last}`,
      email: `${first}.${last}@example.com`.toLowerCase(),
      phone,
      personas,
      gender: isMan ? 'men' : 'women',
      preferences: {
        interests,
        budget: { min: 0, max: PERSONAS[primary].budget },
        gender: isMan ? 'men' : 'women',
      },
      createdDaysAgo: rng.int(200, 420),
      address: {
        label: 'Home',
        full_name: `${first} ${last}`,
        phone,
        line1: `House ${rng.int(1, 450)}, Street ${rng.int(1, 40)}`,
        line2: rng.pick(where.areas),
        city: where.city,
        province: where.province,
        postal_code: `${where.postal}${rng.int(100, 999)}`,
        country: 'Pakistan',
        is_default: true,
      },
    });
  }
  return shoppers;
};

const SEARCH_QUERIES = {
  techie: ['iphone', 'iphone 13 pro', 'gaming laptop', 'samsung phone', 'wireless earbuds', 'macbook', 'tablet under 150k', 'fast charger'],
  fashionista: ['party dress', 'leather handbag', 'earrings', 'heels', 'summer tops', 'women watch'],
  beauty: ['mascara', 'perfume for women', 'skin care', 'face serum', 'lipstick', 'chanel perfume'],
  homemaker: ['sofa', 'bed', 'table lamp', 'kitchen knife set', 'non stick pan', 'wall decor'],
  grocer: ['apple', 'chicken', 'cooking oil', 'eggs', 'juice', 'rice'],
  sporty: ['cricket bat', 'football', 'tennis racket', 'running shoes', 'sunglasses'],
  gent: ['formal shirt', 'men watch', 'sneakers', 'cologne', 'sunglasses for men'],
  rider: ['motorcycle', 'kawasaki', 'helmet', 'scooter'],
};

module.exports = { DEMO_USER, ADMIN_USER, SHOPPER_PASSWORD, PERSONAS, buildShoppers, SEARCH_QUERIES };
