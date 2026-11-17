// domain knowledge for the nlu: synonyms, roman-urdu, colors, features, occasions, recipients

// roman-urdu / chat-speak -> english (token level)
const ROMAN_URDU = {
  sasta: 'cheap', sasti: 'cheap', saste: 'cheap', sastay: 'cheap', susta: 'cheap',
  acha: 'good', accha: 'good', achha: 'good', achi: 'good', achhi: 'good', acchi: 'good', ache: 'good', achay: 'good',
  behtareen: 'best', behtreen: 'best', bahtareen: 'best', zabardast: 'great', kamaal: 'great', zaberdast: 'great',
  bura: 'bad', buri: 'bad', bekar: 'bad', bakwas: 'bad', ganda: 'bad',
  chahiye: 'want', chahye: 'want', chaiye: 'want', chahiay: 'want', chahie: 'want', chahiyeh: 'want', chiye: 'want', chaheye: 'want',
  dikhao: 'show', dikhaao: 'show', dikha: 'show', dikhayen: 'show', dikhaen: 'show', dikhaiye: 'show', dekhao: 'show', dikhado: 'show',
  batao: 'tell', batayen: 'tell', btao: 'tell', bataen: 'tell', bataiye: 'tell', bata: 'tell',
  lena: 'buy', leni: 'buy', lene: 'buy', khareedna: 'buy', kharidna: 'buy', kharidni: 'buy', khareedni: 'buy',
  mujhe: 'i', mujhay: 'i', mjhe: 'i', hamein: 'we', humein: 'we',
  kya: 'what', kia: 'what', kitna: 'how much', kitne: 'how much', kitni: 'how much',
  kahan: 'where', kidhar: 'where', kab: 'when', kaun: 'which', konsa: 'which', kaunsa: 'which', konsi: 'which', kaunsi: 'which',
  mera: 'my', meri: 'my', mere: 'my', mery: 'my', apna: 'my', apni: 'my',
  liye: 'for', liay: 'for', lye: 'for', leye: 'for', liya: 'for', lie: 'for',
  aur: 'and', ya: 'or', sath: 'with', saath: 'with', bina: 'without', bhi: 'also',
  nahi: 'not', nahin: 'not', nai: 'not', nhi: 'not', mat: 'not', na: 'not',
  koi: 'any', kuch: 'some', kuchh: 'some', sab: 'all', saray: 'all', sare: 'all',
  kam: 'less', zyada: 'more', ziada: 'more', zyda: 'more', thora: 'little',
  hazar: 'thousand', hazaar: 'thousand', hzar: 'thousand', lac: 'lakh', lakhs: 'lakh', lacs: 'lakh',
  mehnga: 'expensive', mehngi: 'expensive', mehngay: 'expensive', mehenga: 'expensive', mehngy: 'expensive',
  naya: 'new', nayi: 'new', naye: 'new', purana: 'old',
  halka: 'lightweight', halki: 'lightweight', mazboot: 'durable', khoobsurat: 'beautiful', khubsurat: 'beautiful', pyara: 'beautiful', pyari: 'beautiful',
  jaldi: 'fast', tez: 'fast', abhi: 'now', dobara: 'again', phir: 'again',
  tohfa: 'gift', tohfay: 'gift', tofa: 'gift', tohfe: 'gift', gifts: 'gift',
  ammi: 'mom', ami: 'mom', amma: 'mom', maa: 'mom', mama: 'mom', mummy: 'mom', mother: 'mom', mum: 'mom',
  abbu: 'dad', abu: 'dad', abba: 'dad', papa: 'dad', father: 'dad', baba: 'dad',
  behan: 'sister', bahan: 'sister', behen: 'sister', sis: 'sister', baji: 'sister', apa: 'sister',
  bhai: 'brother', bro: 'brother', bhaiya: 'brother',
  biwi: 'wife', begum: 'wife', bivi: 'wife', shohar: 'husband', miyan: 'husband', shohor: 'husband',
  dost: 'friend', yaar: 'friend', dosti: 'friend', bff: 'friend',
  bacha: 'kid', bachay: 'kid', bache: 'kid', bachon: 'kid', bachi: 'kid', kids: 'kid', child: 'kid', children: 'kid',
  beta: 'son', beti: 'daughter', shaadi: 'wedding', shadi: 'wedding', mehndi: 'wedding', barat: 'wedding', walima: 'wedding',
  salam: 'hello', salaam: 'hello', assalam: 'hello', assalamualaikum: 'hello', asalam: 'hello', aoa: 'hello', slam: 'hello', hii: 'hi', hiii: 'hi', helo: 'hello', hellow: 'hello',
  shukriya: 'thanks', shukria: 'thanks', shukran: 'thanks', thx: 'thanks', thanku: 'thanks', ty: 'thanks', thnx: 'thanks', thanx: 'thanks', tysm: 'thanks',
  joota: 'shoes', joote: 'shoes', jootay: 'shoes', jutay: 'shoes', jutti: 'shoes', juta: 'shoes', jootey: 'shoes',
  kapray: 'clothes', kapde: 'clothes', kapre: 'clothes', kapdey: 'clothes', kapry: 'clothes',
  ghari: 'watch', ghadi: 'watch', gharri: 'watch', gari: 'car', gaari: 'car', gaadi: 'car',
  khushbu: 'perfume', khushboo: 'perfume', itar: 'perfume', attar: 'perfume', itr: 'perfume',
  rang: 'color', colour: 'color', colours: 'color', colors: 'color',
  kala: 'black', kali: 'black', kaala: 'black', safed: 'white', sufaid: 'white', laal: 'red', lal: 'red',
  neela: 'blue', neeli: 'blue', nila: 'blue', hara: 'green', hari: 'green', peela: 'yellow', peeli: 'yellow', gulabi: 'pink', jamni: 'purple',
  pehla: 'first', pehli: 'first', pehlay: 'first', pehle: 'first', doosra: 'second', dusra: 'second', doosri: 'second', dusri: 'second', doosre: 'second', dusre: 'second',
  teesra: 'third', tesra: 'third', teesri: 'third', tesri: 'third', chotha: 'fourth', chautha: 'fourth', chothi: 'fourth', aakhri: 'last', akhri: 'last', akhari: 'last',
  dono: 'both', donon: 'both',
  dalo: 'add', daalo: 'add', daal: 'add', dal: 'add', daldo: 'add', daaldo: 'add',
  wapis: 'return', wapas: 'return', wapsi: 'return', wapisi: 'return',
  paisay: 'rupees', paise: 'rupees', rupay: 'rupees', rupaye: 'rupees', rupee: 'rupees', rs: 'rupees', pkr: 'rupees',
  aayega: 'arrive', ayega: 'arrive', pohanchega: 'arrive', pohnchega: 'arrive', aaega: 'arrive',
  samjhao: 'explain', samjhaen: 'explain', samjhayen: 'explain', samjhaiye: 'explain', samjha: 'explain', pasand: 'likes',
  sirf: 'only', bana: 'is', bani: 'is', pls: 'please', plz: 'please', plzz: 'please', u: 'you', ur: 'your', r: 'are', wat: 'what', wht: 'what', gud: 'good',
};

// emojis -> words, so "📱 under 50k" is a phone search and "😂" reads as laughter (applied before tokenizing)
const EMOJI_WORDS = [
  [/📱|📲/gu, ' phone '], [/💻|🖥️?/gu, ' laptop '], [/⌚/gu, ' watch '], [/🎁/gu, ' gift '], [/👟|👞|👠|👡|🥿/gu, ' shoes '],
  [/👗/gu, ' dress '], [/👕|👔/gu, ' shirt '], [/👜|👛/gu, ' bag '], [/💄/gu, ' makeup '], [/🕶️?/gu, ' sunglasses '],
  [/💍/gu, ' jewellery '], [/🎧/gu, ' headphones '], [/🏍️?/gu, ' motorcycle '], [/🚗/gu, ' car '], [/🛋️?/gu, ' sofa '],
  [/🛒/gu, ' cart '], [/📦|🚚/gu, ' order '], [/💸|🏷️?/gu, ' deals '], [/🌸|🧴/gu, ' perfume '],
  [/😂|🤣|😆|😹/gu, ' haha '], [/😄|😁|😀|😃|😊|🙂/gu, ' nice '], [/❤️?|💖|💕|😍|🥰|😘/gu, ' love you '],
  [/👍|👌|✅|🆗/gu, ' ok '], [/👋/gu, ' hi '], [/🙏/gu, ' thanks '], [/😢|😭|😞|😔|☹️?|🙁|💔/gu, ' i am sad '],
  [/😡|🤬|😠/gu, ' i am angry '], [/🤔/gu, ' hmm '], [/😴|🥱/gu, ' i am tired '],
];

// multi-word roman-urdu idioms rewritten before tokenizing ($1 = captured amount)
const AMOUNT = '(\\$?\\d+(?:\\.\\d+)?\\s*(?:k|l|lac|lakh|lakhs|thousand|hazar|hazaar|m)?)\\s*(?:rs|rupees|rupay|pkr)?';
const IDIOMS = [
  [new RegExp(`${AMOUNT}\\s+(?:se|say|sy)\\s+(?:kam|kum|neeche|nichay|niche)`, 'g'), 'under $1'],
  [new RegExp(`${AMOUNT}\\s+(?:se|say|sy)\\s+(?:zyada|ziada|zyda|upar|oopar|uper)`, 'g'), 'above $1'],
  [new RegExp(`${AMOUNT}\\s+(?:ke|k|kay)\\s+(?:andar|andr|ander)`, 'g'), 'within $1'],
  [new RegExp(`${AMOUNT}\\s+(?:ke|k|kay)\\s+(?:qareeb|kareeb|qarib|aas paas|aaspaas)`, 'g'), 'around $1'],
  [new RegExp(`${AMOUNT}\\s+(?:tak|takk|tk)\\b`, 'g'), 'upto $1'],
  [new RegExp(`${AMOUNT}\\s+(?:wala|wali|walay|wale|waala|waali)\\b`, 'g'), 'around $1'],
  [/\b(?:sab ?se|sabse|sb se|sbse)\s+(?:sasta|sasti|saste|cheap)\b/g, 'cheapest'],
  [/\b(?:sab ?se|sabse|sb se|sbse)\s+(?:acha|achha|accha|achi|achhi|behtareen|best)\b/g, 'best rated'],
  [/\b(?:sab ?se|sabse|sb se|sbse)\s+(?:mehnga|mehngi|expensive)\b/g, 'most expensive'],
  [/\b(?:khuda|allah) ?hafiz\b/g, 'bye'],
  [/\bkon sa\b|\bkaun sa\b|\bkon si\b|\bkaun si\b/g, 'which'],
  [/\bcart (?:mein|me|main|mai) (?:dal|daal|add|daalo|dalo|daldo|kar)\w*/g, 'add to cart'],
  [/\bcompare (?:karo|kardo|krdo|karein|karen|kr do|kar do)\b/g, 'compare'],
  [/\bkahan hai\b|\bkahan he\b|\bkidhar hai\b/g, 'where is'],
  [/\bkitne ka\b|\bkitne ki\b|\bkitnay ka\b/g, 'how much is'],
];

// phrase -> category mapping; `gendered` picks men/women variant
const CATEGORY_SYNONYMS = {
  smartphones: ['smartphone', 'smartphones', 'smart phone', 'phone', 'phones', 'mobile', 'mobiles', 'mobile phone', 'cell phone', 'cellphone', 'cell', 'android', 'iphone', 'iphones', 'handset', 'galaxy'],
  laptops: ['laptop', 'laptops', 'notebook', 'notebooks', 'macbook', 'macbooks', 'ultrabook', 'computer', 'pc', 'zenbook', 'matebook', 'chromebook'],
  tablets: ['tablet', 'tablets', 'ipad', 'ipads', 'tab'],
  'mobile-accessories': ['accessory', 'accessories', 'mobile accessories', 'phone accessories', 'charger', 'chargers', 'earphones', 'earphone', 'earbuds', 'airpods', 'headphones', 'headphone', 'headset', 'cable', 'power bank', 'powerbank', 'phone case', 'case', 'cover', 'speaker', 'speakers', 'smartwatch', 'smart watch', 'selfie stick', 'monopod', 'magsafe', 'homepod', 'echo'],
  'mens-shirts': ['shirt', 'shirts', 'tshirt', 't shirt', 'tshirts', 'tee', 'polo', 'kurta'],
  tops: ['tops', 'blouse', 'blouses', 'kurti', 'crop top'],
  'womens-dresses': ['dress', 'dresses', 'gown', 'gowns', 'frock', 'frocks', 'maxi', 'outfit'],
  'womens-bags': ['bag', 'bags', 'handbag', 'handbags', 'purse', 'purses', 'clutch', 'tote', 'backpack'],
  'womens-jewellery': ['jewellery', 'jewelry', 'jewel', 'necklace', 'earring', 'earrings', 'ring', 'rings', 'bracelet', 'bangles', 'jhumka'],
  sunglasses: ['sunglasses', 'sunglass', 'shades', 'glasses', 'goggles', 'eyewear'],
  shoes: ['shoe', 'shoes', 'sneakers', 'sneaker', 'joggers', 'jogger', 'trainers', 'footwear', 'boots', 'sandals', 'running shoes', 'heels', 'loafers', 'slippers'],
  watches: ['watch', 'watches', 'wristwatch', 'timepiece', 'rolex'],
  beauty: ['makeup', 'make up', 'cosmetics', 'cosmetic', 'mascara', 'lipstick', 'eyeshadow', 'eye shadow', 'nail polish', 'foundation', 'powder', 'beauty products', 'beauty'],
  fragrances: ['perfume', 'perfumes', 'fragrance', 'fragrances', 'scent', 'scents', 'cologne', 'body spray', 'deodorant', 'eau de parfum'],
  'skin-care': ['skincare', 'skin care', 'lotion', 'moisturizer', 'moisturiser', 'cream', 'face wash', 'serum', 'sunscreen', 'body wash', 'soap', 'hand soap'],
  furniture: ['furniture', 'sofa', 'sofas', 'couch', 'bed', 'beds', 'chair', 'chairs', 'table', 'tables', 'desk', 'wardrobe', 'bedside'],
  'home-decoration': ['decor', 'decoration', 'decorations', 'home decor', 'lamp', 'vase', 'wall art', 'showpiece', 'plant pot', 'mirror', 'decorative'],
  'kitchen-accessories': ['kitchen', 'cookware', 'utensils', 'utensil', 'pan', 'pans', 'knife', 'knives', 'spoon', 'spatula', 'blender', 'kitchenware', 'bowl', 'grater', 'lunch box'],
  groceries: ['grocery', 'groceries', 'food', 'fruit', 'fruits', 'vegetable', 'vegetables', 'veggies', 'meat', 'snacks', 'drinks', 'beverages', 'juice', 'milk', 'eggs', 'rice', 'cooking oil', 'honey', 'coffee', 'sabzi', 'phal', 'doodh'],
  'sports-accessories': ['sports', 'sport', 'sports equipment', 'football', 'cricket', 'cricket bat', 'bat', 'ball', 'racket', 'tennis', 'basketball', 'baseball', 'golf', 'volleyball', 'badminton', 'fitness equipment'],
  motorcycle: ['motorcycle', 'motorcycles', 'motorbike', 'motorbikes', 'bike', 'bikes', 'scooter', 'scooty', 'superbike'],
  vehicle: ['car', 'cars', 'vehicle', 'vehicles', 'suv', 'sedan', 'jeep', 'minivan', 'hatchback'],
};

// generic words resolved against gender
const GENDERED = {
  shoes: { men: 'mens-shoes', women: 'womens-shoes', any: ['mens-shoes', 'womens-shoes'] },
  watches: { men: 'mens-watches', women: 'womens-watches', any: ['mens-watches', 'womens-watches'] },
};

// department vocabulary keyed by internal key; real db slugs are resolved from the catalog
const DEPARTMENTS = {
  electronics: { name: 'Electronics', words: ['electronics', 'electronic', 'gadget', 'gadgets', 'tech', 'devices', 'device'], categories: ['smartphones', 'laptops', 'tablets', 'mobile-accessories'] },
  fashion: { name: 'Fashion', words: ['fashion', 'clothes', 'clothing', 'apparel', 'wear', 'outfits', 'style'], categories: ['mens-shirts', 'mens-shoes', 'mens-watches', 'tops', 'womens-dresses', 'womens-shoes', 'womens-bags', 'womens-jewellery', 'womens-watches', 'sunglasses'] },
  beauty: { name: 'Beauty & Personal Care', words: ['personal care', 'grooming', 'self care'], categories: ['beauty', 'fragrances', 'skin-care'] },
  home: { name: 'Home & Living', words: ['home', 'house', 'living room', 'bedroom', 'room', 'apartment', 'interior'], categories: ['furniture', 'home-decoration', 'kitchen-accessories'] },
  groceries: { name: 'Groceries', words: ['supermarket', 'pantry', 'kirana'], categories: ['groceries'] },
  sports: { name: 'Sports & Outdoors', words: ['outdoors', 'outdoor', 'athletic', 'workout gear'], categories: ['sports-accessories'] },
  automotive: { name: 'Automotive', words: ['automotive', 'auto', 'automobile', 'ride'], categories: ['motorcycle', 'vehicle'] },
};

const CATEGORY_NAMES = {
  smartphones: 'Smartphones', laptops: 'Laptops', tablets: 'Tablets', 'mobile-accessories': 'Mobile Accessories',
  'mens-shirts': "Men's Shirts", 'mens-shoes': "Men's Shoes", 'mens-watches': "Men's Watches", tops: 'Tops',
  'womens-dresses': "Women's Dresses", 'womens-shoes': "Women's Shoes", 'womens-bags': "Women's Bags",
  'womens-jewellery': "Women's Jewellery", 'womens-watches': "Women's Watches", sunglasses: 'Sunglasses',
  beauty: 'Beauty', fragrances: 'Fragrances', 'skin-care': 'Skin Care', furniture: 'Furniture',
  'home-decoration': 'Home Decoration', 'kitchen-accessories': 'Kitchen Accessories', groceries: 'Groceries',
  'sports-accessories': 'Sports Accessories', motorcycle: 'Motorcycles', vehicle: 'Vehicles',
};

const COLORS = {
  black: ['black', 'jet black', 'matte black'], white: ['white', 'off white'], red: ['red', 'maroon', 'crimson'],
  blue: ['blue', 'navy', 'navy blue', 'sky blue'], green: ['green', 'olive', 'emerald'], yellow: ['yellow', 'mustard'],
  pink: ['pink', 'rose'], purple: ['purple', 'violet', 'plum', 'lavender'], orange: ['orange'], brown: ['brown', 'tan', 'chocolate'],
  grey: ['grey', 'gray', 'space grey', 'space gray', 'graphite'], silver: ['silver'], gold: ['gold', 'golden', 'rose gold'],
  beige: ['beige', 'nude'], multicolor: ['multicolor', 'multicolour', 'colorful', 'colourful'],
};

// soft preferences: `triggers` appear in queries, `terms` are looked for in product text
const FEATURES = {
  gaming: { label: 'gaming', triggers: ['gaming', 'gamer', 'games', 'game', 'pubg', 'fortnite', 'esports'], terms: ['gaming', 'rtx', 'gtx', 'gpu', 'graphics', 'refresh', '16 gb', '16gb', '32gb', 'processor', 'i7', 'i9', 'ryzen', 'dual screen'] },
  camera: { label: 'camera', triggers: ['camera', 'photography', 'photos', 'photo', 'selfie', 'selfies', 'pictures', 'vlogging', 'vlog'], terms: ['camera', 'mp', 'megapixel', 'lens', 'photo', 'selfie'] },
  battery: { label: 'long battery life', triggers: ['battery', 'battery life', 'long battery', 'battery backup', 'backup', 'mah'], terms: ['battery', 'mah', 'all-day', 'long-lasting battery'] },
  lightweight: { label: 'lightweight', triggers: ['lightweight', 'light weight', 'portable', 'slim', 'thin', 'compact', 'travel friendly'], terms: ['lightweight', 'light', 'portable', 'slim', 'thin', 'compact'] },
  waterproof: { label: 'waterproof', triggers: ['waterproof', 'water proof', 'water resistant', 'water resistance'], terms: ['waterproof', 'water resistant', 'water-resistant', 'water resistance'] },
  noise_cancelling: { label: 'noise cancelling', triggers: ['noise cancelling', 'noise canceling', 'noise cancellation', 'anc'], terms: ['noise cancelling', 'noise cancellation', 'anc', 'active noise'] },
  long_lasting: { label: 'long lasting', triggers: ['long lasting', 'longlasting', 'lasting'], terms: ['long-lasting', 'long lasting', 'lasting'] },
  organic: { label: 'organic', triggers: ['organic', 'natural', 'fresh', 'healthy'], terms: ['organic', 'natural', 'fresh', 'healthy'] },
  wireless: { label: 'wireless', triggers: ['wireless', 'bluetooth', 'cordless'], terms: ['wireless', 'bluetooth', 'cordless'] },
  fast_charging: { label: 'fast charging', triggers: ['fast charging', 'fast charge', 'quick charge', 'quick charging'], terms: ['fast charging', 'fast charge', 'quick charge', 'magsafe'] },
  storage: { label: 'big storage', triggers: ['storage', 'memory', 'space', '256gb', '512gb', '1tb'], terms: ['storage', 'gb', 'ssd', 'tb'] },
  performance: { label: 'performance', triggers: ['powerful', 'performance', 'fast processor', 'speed', 'speedy'], terms: ['processor', 'performance', 'powerful', 'chip', 'ram'] },
  display: { label: 'great display', triggers: ['display', 'screen', 'amoled', 'big screen', 'oled', 'retina'], terms: ['display', 'screen', 'amoled', 'oled', 'retina', 'inch'] },
  comfort: { label: 'comfortable', triggers: ['comfortable', 'comfort', 'comfy', 'soft', 'cozy', 'cosy'], terms: ['comfort', 'comfortable', 'soft', 'cushion', 'cozy'] },
  durable: { label: 'durable', triggers: ['durable', 'sturdy', 'strong', 'tough', 'long life'], terms: ['durable', 'sturdy', 'strong', 'leather', 'steel', 'solid'] },
  stylish: { label: 'stylish', triggers: ['stylish', 'elegant', 'classy', 'fancy', 'trendy', 'beautiful', 'chic', 'fashionable'], terms: ['stylish', 'elegant', 'classic', 'chic', 'trendy', 'sleek', 'fashion'] },
  luxury: { label: 'luxury', triggers: ['luxury', 'luxurious', 'designer', 'branded'], terms: ['luxury', 'premium', 'designer', 'gold', 'leather'] },
  work: { label: 'work & study', triggers: ['work', 'office work', 'study', 'studies', 'students', 'student', 'productivity', 'coding', 'programming', 'business'], terms: ['productivity', 'business', 'professional', 'work', 'keyboard', 'processor'] },
  running: { label: 'running', triggers: ['running', 'jogging', 'marathon'], terms: ['running', 'sports', 'athletic', 'trainers', 'sneakers'] },
  hydrating: { label: 'hydrating', triggers: ['dry skin', 'hydrating', 'hydration', 'moisturizing', 'moisture'], terms: ['moisture', 'hydrating', 'shea', 'butter', 'nourish', 'lotion'] },
  oil_control: { label: 'oil control', triggers: ['oily skin', 'oil control', 'acne', 'pimples'], terms: ['oil', 'matte', 'clean', 'gentle'] },
  sensitive: { label: 'gentle on skin', triggers: ['sensitive skin', 'gentle', 'cruelty free', 'vegan'], terms: ['gentle', 'cruelty-free', 'natural', 'sensitive'] },
  smart: { label: 'smart features', triggers: ['smart', 'alexa', 'voice assistant', 'siri'], terms: ['smart', 'alexa', 'siri', 'voice'] },
};

const OCCASIONS = {
  birthday: { triggers: ['birthday', 'bday', 'b day', 'saalgirah', 'salgira'], terms: ['gift', 'stylish', 'elegant'] },
  wedding: { triggers: ['wedding', 'marriage', 'nikkah', 'nikah', 'engagement', 'reception'], terms: ['elegant', 'gold', 'luxury', 'formal', 'dress', 'jewellery'] },
  eid: { triggers: ['eid', 'eid ul fitr', 'eid ul adha', 'chand raat'], terms: ['elegant', 'traditional', 'fragrance', 'dress'] },
  gym: { triggers: ['gym', 'workout', 'exercise', 'fitness', 'training', 'bodybuilding'], terms: ['sports', 'fitness', 'protein', 'running', 'athletic'] },
  office: { triggers: ['office', 'formal', 'meeting', 'interview', 'job'], terms: ['formal', 'classic', 'leather', 'shirt', 'professional'] },
  university: { triggers: ['university', 'uni', 'college', 'school', 'campus'], terms: ['casual', 'backpack', 'laptop', 'portable', 'student'] },
  travel: { triggers: ['travel', 'trip', 'vacation', 'holiday', 'journey', 'tour'], terms: ['portable', 'lightweight', 'compact', 'travel', 'sunglasses'] },
  party: { triggers: ['party', 'dinner', 'night out', 'date night', 'valentine', 'valentines'], terms: ['party', 'elegant', 'stylish', 'glam'] },
  anniversary: { triggers: ['anniversary'], terms: ['elegant', 'gold', 'luxury', 'jewellery'] },
  casual: { triggers: ['casual', 'everyday', 'daily use', 'daily wear'], terms: ['casual', 'comfort', 'everyday'] },
};

const RECIPIENTS = {
  mom: 'women', wife: 'women', sister: 'women', daughter: 'women', girlfriend: 'women', aunt: 'women', grandma: 'women', grandmother: 'women', her: 'women', she: 'women', niece: 'women',
  dad: 'men', husband: 'men', brother: 'men', son: 'men', boyfriend: 'men', uncle: 'men', grandpa: 'men', grandfather: 'men', him: 'men', nephew: 'men',
  friend: null, kid: null, colleague: null, boss: null, teacher: null,
};

const GENDER_WORDS = {
  women: ['women', 'woman', 'womens', 'ladies', 'lady', 'female', 'females', 'girl', 'girls', 'feminine', 'aurat', 'khawateen'],
  men: ['men', 'man', 'mens', 'gents', 'gent', 'male', 'males', 'boy', 'boys', 'guy', 'guys', 'masculine', 'mard', 'larka', 'larkay'],
};

// gift ideas per recipient gender (ordered by fit)
const GIFT_CATEGORIES = {
  women: ['womens-jewellery', 'fragrances', 'womens-bags', 'womens-watches', 'beauty', 'skin-care', 'womens-dresses', 'sunglasses'],
  men: ['mens-watches', 'fragrances', 'sunglasses', 'mens-shoes', 'mens-shirts', 'mobile-accessories'],
  kid: ['sports-accessories', 'tablets', 'mobile-accessories'],
  any: ['fragrances', 'mobile-accessories', 'home-decoration', 'sunglasses', 'kitchen-accessories', 'mens-watches', 'womens-watches'],
};

// complementary categories used when there is no co-purchase data yet
const COMPLEMENTS = {
  smartphones: ['mobile-accessories'],
  tablets: ['mobile-accessories'],
  laptops: ['mobile-accessories', 'tablets'],
  'mobile-accessories': ['smartphones', 'mobile-accessories'],
  'mens-shirts': ['mens-shoes', 'mens-watches', 'sunglasses'],
  'mens-shoes': ['mens-shirts', 'mens-watches'],
  'mens-watches': ['mens-shirts', 'sunglasses', 'fragrances'],
  tops: ['womens-bags', 'womens-jewellery', 'womens-shoes'],
  'womens-dresses': ['womens-shoes', 'womens-bags', 'womens-jewellery'],
  'womens-shoes': ['womens-dresses', 'womens-bags'],
  'womens-bags': ['womens-jewellery', 'womens-watches', 'sunglasses'],
  'womens-jewellery': ['womens-dresses', 'womens-bags', 'fragrances'],
  'womens-watches': ['womens-jewellery', 'womens-bags'],
  sunglasses: ['mens-watches', 'womens-bags'],
  beauty: ['skin-care', 'fragrances'],
  fragrances: ['beauty', 'skin-care'],
  'skin-care': ['beauty', 'fragrances'],
  furniture: ['home-decoration', 'kitchen-accessories'],
  'home-decoration': ['furniture'],
  'kitchen-accessories': ['groceries', 'home-decoration'],
  groceries: ['kitchen-accessories', 'groceries'],
  'sports-accessories': ['sports-accessories', 'groceries'],
  motorcycle: ['sports-accessories', 'sunglasses'],
  vehicle: ['mobile-accessories', 'sunglasses'],
};

// sort phrases checked longest first
const SORTS = [
  ['price_asc', ['cheapest', 'cheap', 'affordable', 'budget friendly', 'low budget', 'lowest price', 'least expensive', 'most affordable', 'lowest cost', 'low to high', 'cheap first']],
  ['price_desc', ['most expensive', 'highest price', 'costliest', 'high to low', 'expensive first']],
  ['rating', ['best rated', 'top rated', 'highest rated', 'best reviewed', 'best reviews', 'highly rated', 'best rating', 'top rating']],
  ['popular', ['most popular', 'best selling', 'bestselling', 'best seller', 'bestseller', 'bestsellers', 'trending', 'popular', 'most sold', 'hot selling']],
  ['newest', ['latest', 'newest', 'new arrivals', 'new arrival', 'just launched', 'recent']],
  ['discount', ['biggest discount', 'most discount', 'highest discount', 'on sale', 'best discount', 'max discount']],
];

const STOPWORDS = new Set(`a an the and or of to in on for with at by from is are was were be been am i me my we our you your it its this that these those
  please can could would will shall should do does did have has had want need looking look find show get give buy purchase some any something
  anything one ones thing things item items product products also just really very so too what which who whom how there here hi hey
  like love about into over upto up as than then but if not no yes ok okay kindly plz pls tell let us
  hai hain he ho ka ki ke ko se mein main mai ne kar karo krna karna wala wali walay wale ek do bhi to tu hum ap aap kese kaise kesi kaisi kesay kaisay haal hal theek thik shukriya salam assalam walaikum
  rupees rs pkr price budget under below within less more around between sa si sy`.split(/\s+/).filter(Boolean));

// words the spell-corrector must never touch (frequent chat words)
const COMMON_WORDS = `show shoe shoes what want with which while white where when there their then than this that those these them they
  have help hello here hers some same sale save cart card care case cheap cheaper cheapest check order orders return refund track
  more most much many good great best better nice cool okay thanks thank please about after again also another any back bye
  compare compared tell more first second third fourth fifth last both other others only just like love need want find look
  looking give get got buy buying bought wish list wishlist delivery deliver shipping ship status where items item thing things
  today tomorrow price prices cost costs rupees budget under over below above upto within around between less least cheap
  something anything everything nothing someone gift gifts gifting present recommend recommendation suggest suggestion options
  option choice choices deal deals discount discounts offer offers coupon coupons sale sales premium luxury expensive better
  higher lower rated rating ratings review reviews stars star model models brand brands color colour size sizes type types new
  latest newest popular trending selling seller sold stock available availability night light right fight might tight
  shirt shirts short shorts sport sports game games time times line lines fine mine nine wine dine store stores
  how who why the you your yours mine ours his her him she he me my it its and or but not no yes yeah yep nope`.split(/\s+/).filter(Boolean);

module.exports = {
  ROMAN_URDU, IDIOMS, CATEGORY_SYNONYMS, GENDERED, DEPARTMENTS, CATEGORY_NAMES, COLORS, FEATURES, OCCASIONS,
  RECIPIENTS, GENDER_WORDS, GIFT_CATEGORIES, COMPLEMENTS, SORTS, STOPWORDS, COMMON_WORDS, EMOJI_WORDS,
};
