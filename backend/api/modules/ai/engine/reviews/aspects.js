// aspect dictionaries: generic aspects for every product + per-department/category ones
const GENERIC = {
  quality: ['quality', 'build', 'made', 'material', 'materials', 'craftsmanship', 'durable', 'sturdy', 'flimsy', 'cheaply', 'finish'],
  value: ['value', 'price', 'money', 'worth', 'overpriced', 'expensive', 'cheap', 'affordable', 'bargain', 'penny'],
  delivery: ['delivery', 'shipping', 'shipped', 'arrived', 'courier', 'late', 'delayed', 'on time', 'dispatch'],
  packaging: ['packaging', 'package', 'packed', 'box', 'wrapped', 'sealed', 'parcel'],
  appearance: ['look', 'looks', 'design', 'beautiful', 'stylish', 'elegant', 'style', 'gorgeous'],
  accuracy: ['as described', 'not as described', 'description', 'expected', 'expectations', 'pictures', 'as shown', 'pictured'],
};

const BY_CATEGORY = {
  smartphones: { battery: ['battery', 'charge', 'charging', 'mah', 'drains', 'backup'], camera: ['camera', 'photos', 'photo', 'pictures', 'selfie', 'video'], display: ['display', 'screen', 'brightness', 'amoled'], performance: ['performance', 'fast', 'lag', 'laggy', 'slow', 'speed', 'smooth', 'processor', 'gaming'], software: ['software', 'update', 'updates', 'android', 'ios', 'bloatware'] },
  laptops: { battery: ['battery', 'charge', 'charging'], performance: ['performance', 'fast', 'slow', 'lag', 'speed', 'processor', 'ram', 'gaming'], display: ['display', 'screen'], keyboard: ['keyboard', 'keys', 'trackpad', 'touchpad'], portability: ['weight', 'light', 'lightweight', 'heavy', 'portable', 'thin'], thermals: ['heat', 'heats', 'hot', 'fan', 'noise', 'noisy'] },
  tablets: { battery: ['battery', 'charge'], display: ['display', 'screen'], performance: ['performance', 'fast', 'slow', 'lag'] },
  'mobile-accessories': { sound: ['sound', 'audio', 'bass', 'music', 'noise', 'mic', 'calls'], battery: ['battery', 'charge', 'charging', 'charger'], connectivity: ['bluetooth', 'pairing', 'connection', 'connects', 'wireless'], comfort: ['comfort', 'comfortable', 'fit', 'ears'] },
  fashion: { fit: ['fit', 'fits', 'size', 'sizing', 'tight', 'loose', 'small', 'large', 'true to size'], comfort: ['comfort', 'comfortable', 'soft', 'itchy', 'scratchy'], fabric: ['fabric', 'material', 'cotton', 'stitching', 'leather', 'texture'], style: ['style', 'stylish', 'look', 'design', 'elegant'] },
  beauty: { scent: ['scent', 'smell', 'fragrance', 'smells', 'notes'], longevity: ['long-lasting', 'lasting', 'lasts', 'fades', 'wear', 'touch-ups', 'hours'], texture: ['texture', 'greasy', 'sticky', 'cakey', 'smooth', 'thick'], skin: ['skin', 'irritation', 'rash', 'broke', 'gentle', 'sensitive', 'moisturized'], shade: ['shade', 'colour', 'color', 'pigment', 'pigmented'] },
  home: { assembly: ['assembly', 'assemble', 'install', 'setup'], comfort: ['comfort', 'comfortable', 'cozy', 'soft'], size: ['size', 'fits', 'space', 'small', 'large'], usability: ['easy', 'handy', 'use', 'useful', 'practical'] },
  groceries: { taste: ['taste', 'tasty', 'delicious', 'flavour', 'flavor', 'bland'], freshness: ['fresh', 'stale', 'rotten', 'expiry', 'expired', 'ripe'], portion: ['quantity', 'portion', 'size', 'amount'] },
  sports: { grip: ['grip', 'handle', 'hold'], durability: ['durable', 'lasted', 'broke', 'torn', 'ripped'], performance: ['bounce', 'performance', 'control', 'balance'] },
  automotive: { performance: ['engine', 'power', 'speed', 'acceleration', 'performance'], comfort: ['comfort', 'comfortable', 'ride', 'seats'], mileage: ['mileage', 'fuel', 'economy'] },
};

const DEPT_OF = {
  'mens-shirts': 'fashion', 'mens-shoes': 'fashion', 'mens-watches': 'fashion', tops: 'fashion', 'womens-dresses': 'fashion',
  'womens-shoes': 'fashion', 'womens-bags': 'fashion', 'womens-jewellery': 'fashion', 'womens-watches': 'fashion', sunglasses: 'fashion',
  beauty: 'beauty', fragrances: 'beauty', 'skin-care': 'beauty', furniture: 'home', 'home-decoration': 'home',
  'kitchen-accessories': 'home', groceries: 'groceries', 'sports-accessories': 'sports', motorcycle: 'automotive', vehicle: 'automotive',
};

const aspectsFor = (categorySlug) => ({
  ...GENERIC,
  ...(BY_CATEGORY[DEPT_OF[categorySlug]] || {}),
  ...(BY_CATEGORY[categorySlug] || {}),
});

const LABELS = {
  quality: 'Build quality', value: 'Value for money', delivery: 'Delivery', packaging: 'Packaging', appearance: 'Looks & design',
  accuracy: 'Matches description', battery: 'Battery life', camera: 'Camera', display: 'Display', performance: 'Performance',
  software: 'Software', keyboard: 'Keyboard', portability: 'Portability', thermals: 'Heat & noise', sound: 'Sound quality',
  connectivity: 'Connectivity', comfort: 'Comfort', fit: 'Fit & sizing', fabric: 'Fabric', style: 'Style', scent: 'Scent',
  longevity: 'Long-lasting wear', texture: 'Texture', skin: 'Skin feel', shade: 'Shade & colour', assembly: 'Assembly',
  size: 'Size', usability: 'Ease of use', taste: 'Taste', freshness: 'Freshness', portion: 'Portion size', grip: 'Grip',
  durability: 'Durability', mileage: 'Fuel economy',
};

// which aspects a sentence talks about
const detectAspects = (sentence, dict) => {
  const s = ` ${sentence.toLowerCase().replace(/[^a-z0-9\s-]/g, ' ')} `;
  return Object.entries(dict).filter(([, words]) => words.some((w) => s.includes(` ${w} `))).map(([aspect]) => aspect);
};

module.exports = { aspectsFor, detectAspects, LABELS };
