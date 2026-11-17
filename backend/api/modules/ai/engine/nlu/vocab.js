// runtime vocabulary: static lexicon + catalog brands/taxonomy, phrase matcher and spell corrector
const fs = require('fs');
const path = require('path');
const L = require('./lexicon');
const { FuzzyVocabulary } = require('./fuzzy');
const ENGLISH = require('./english');
const { baseClean, tokenize, stem } = require('./normalizer');

const RAW_DATA = path.join(__dirname, '../../../../../data/dummyjson-products.json');
const MAX_PHRASE = 4;

const DEFAULT_DEPT_SLUGS = {
  electronics: 'electronics', fashion: 'fashion', beauty: 'beauty-personal-care', home: 'home-living',
  groceries: 'groceries', sports: 'sports-outdoors', automotive: 'automotive',
};

// product-ish words that should be spell-corrected towards (beyond the lexicon)
const INTENT_WORDS = `recommend recommendation suggest suggestion compare comparison difference cheaper cheapest expensive premium
  discount discounts deals offers order orders delivery shipping return returns refund exchange cart checkout wishlist gift gifts
  birthday anniversary budget similar specifications specs features review reviews rating thanks hello goodbye track status cancel
  available warranty quality affordable alternative alternatives options another better best popular trending latest`.split(/\s+/).filter(Boolean);

// aliases that imply both a brand and a category
const BRAND_ALIASES = {
  iphone: { brand: 'apple', category: 'smartphones' }, ipad: { brand: 'apple', category: 'tablets' },
  macbook: { brand: 'apple', category: 'laptops' }, airpods: { brand: 'apple', category: 'mobile-accessories' },
  homepod: { brand: 'apple', category: 'mobile-accessories' }, galaxy: { brand: 'samsung', category: 'smartphones' },
  zenbook: { brand: 'asus', category: 'laptops' }, matebook: { brand: 'huawei', category: 'laptops' },
  xps: { brand: 'dell', category: 'laptops' }, yoga: { brand: 'lenovo', category: 'laptops' },
  'dolce gabbana': { brand: 'dolce and gabbana' }, 'd and g': { brand: 'dolce and gabbana' }, ck: { brand: 'calvin klein' },
};

const phraseKey = (text) => tokenize(baseClean(text)).map(stem).join(' ');

// offline defaults from the raw catalog file until the db catalog is loaded
const readDefaults = () => {
  try {
    const raw = JSON.parse(fs.readFileSync(RAW_DATA, 'utf8'));
    const products = raw.products || raw;
    const words = new Set();
    for (const p of products) {
      const text = [p.title, p.description, ...(p.tags || [])].join(' ');
      for (const w of tokenize(baseClean(text))) if (/^[a-z]+$/.test(w)) words.add(w);
    }
    return { brands: [...new Set(products.map((p) => p.brand).filter(Boolean))], words: [...words] };
  } catch {
    return { brands: [], words: [] };
  }
};

class Vocabulary {
  constructor() {
    this.brandNames = new Map(); // normalized key -> display name
    this.taxonomy = new Map(); // category slug -> { slug, name, departmentKey, departmentSlug, departmentName }
    this.departmentKeys = new Map(); // db department slug -> internal key
    this.known = new Set([...L.COMMON_WORDS, ...L.STOPWORDS, ...ENGLISH]);
    const defaults = readDefaults();
    this.addKnownWords(defaults.words);
    this.setTaxonomy(null);
    this.setBrands(defaults.brands);
  }

  setTaxonomy(categories) {
    this.taxonomy.clear();
    this.departmentKeys.clear();
    for (const [key, dept] of Object.entries(L.DEPARTMENTS)) {
      for (const slug of dept.categories) {
        this.taxonomy.set(slug, {
          slug, name: L.CATEGORY_NAMES[slug] || slug, departmentKey: key,
          departmentSlug: DEFAULT_DEPT_SLUGS[key], departmentName: dept.name,
        });
      }
      this.departmentKeys.set(DEFAULT_DEPT_SLUGS[key], key);
    }
    // db rows override names/slugs but keep the internal department key
    for (const c of categories || []) {
      const current = this.taxonomy.get(c.slug);
      const departmentKey = current?.departmentKey || c.departmentSlug;
      this.taxonomy.set(c.slug, {
        slug: c.slug, name: c.name, departmentKey, departmentSlug: c.departmentSlug, departmentName: c.departmentName,
      });
      this.departmentKeys.set(c.departmentSlug, departmentKey);
    }
    this.rebuild();
  }

  setBrands(names) {
    this.brandNames.clear();
    for (const name of names) {
      const key = tokenize(baseClean(name)).join(' ');
      if (key) this.brandNames.set(key, name);
    }
    this.rebuild();
  }

  addKnownWords(words) {
    for (const w of words) if (w && w.length > 2) this.known.add(w);
  }

  departmentOf(slug) {
    return this.taxonomy.get(slug) || null;
  }

  departmentByKey(key) {
    const cats = [...this.taxonomy.values()].filter((c) => c.departmentKey === key);
    if (!cats.length) return null;
    return { key, slug: cats[0].departmentSlug, name: cats[0].departmentName, categories: cats.map((c) => c.slug) };
  }

  brandDisplay(key) {
    return this.brandNames.get(key) || key;
  }

  rebuild() {
    if (!this.taxonomy.size) return;
    const phrases = new Map();
    const corrector = new FuzzyVocabulary();
    const add = (text, annotation, priority = 1) => {
      const key = phraseKey(text);
      if (!key) return;
      if (!phrases.has(key)) phrases.set(key, []);
      const list = phrases.get(key);
      if (!list.some((a) => a.type === annotation.type && a.value === annotation.value)) list.push(annotation);
      for (const word of tokenize(baseClean(text))) if (/^[a-z]+$/.test(word) && word.length >= 4) corrector.add(word, priority);
    };

    for (const [slug, words] of Object.entries(L.CATEGORY_SYNONYMS)) {
      const isGeneric = Boolean(L.GENDERED[slug]);
      for (const w of words) add(w, isGeneric ? { type: 'generic', value: slug } : { type: 'category', value: slug }, 2);
    }
    for (const [slug, info] of this.taxonomy) {
      add(info.name, { type: 'category', value: slug }, 2);
      add(slug.replace(/-/g, ' '), { type: 'category', value: slug }, 2);
    }
    for (const [key, dept] of Object.entries(L.DEPARTMENTS)) {
      for (const w of [...dept.words, dept.name]) add(w, { type: 'department', value: key });
    }
    for (const [color, words] of Object.entries(L.COLORS)) for (const w of words) add(w, { type: 'color', value: color });
    for (const [key, f] of Object.entries(L.FEATURES)) for (const w of f.triggers) add(w, { type: 'feature', value: key });
    for (const [key, o] of Object.entries(L.OCCASIONS)) for (const w of o.triggers) add(w, { type: 'occasion', value: key });
    for (const [who, gender] of Object.entries(L.RECIPIENTS)) add(who, { type: 'recipient', value: who, gender });
    for (const [gender, words] of Object.entries(L.GENDER_WORDS)) for (const w of words) add(w, { type: 'gender', value: gender });
    for (const [sort, words] of L.SORTS) for (const w of words) add(w, { type: 'sort', value: sort });
    for (const [key, name] of this.brandNames) add(key, { type: 'brand', value: key, name }, 3);
    for (const [alias, info] of Object.entries(BRAND_ALIASES)) {
      if (this.brandNames.has(info.brand)) add(alias, { type: 'brand', value: info.brand, name: this.brandNames.get(info.brand) }, 3);
      if (info.category) add(alias, { type: 'category', value: info.category }, 3);
    }
    for (const w of INTENT_WORDS) corrector.add(w, 1);

    this.phrases = phrases;
    this.corrector = corrector;
  }

  // longest-match phrase spotting over stemmed tokens
  spot(tokens) {
    const stems = tokens.map(stem);
    const matches = [];
    let i = 0;
    while (i < tokens.length) {
      let found = null;
      for (let len = Math.min(MAX_PHRASE, tokens.length - i); len >= 1; len -= 1) {
        const key = stems.slice(i, i + len).join(' ');
        const annotations = this.phrases.get(key);
        if (annotations) {
          found = { start: i, end: i + len, text: tokens.slice(i, i + len).join(' '), annotations };
          break;
        }
      }
      if (found) {
        matches.push(found);
        i = found.end;
      } else {
        i += 1;
      }
    }
    return matches;
  }
}

let instance = null;
const getVocabulary = () => {
  if (!instance) instance = new Vocabulary();
  return instance;
};

module.exports = { getVocabulary, Vocabulary, phraseKey, BRAND_ALIASES };
