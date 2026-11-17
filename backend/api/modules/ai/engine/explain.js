// ai spec explainer: deterministic rules/knowledge base that turns raw specs into plain language,
// a "what it means for you" line and a 1-5 level, plus a short "who it's for" summary.
const { list, money } = require('./format');

const LEVEL_LABELS = [null, 'Basic', 'Fair', 'Good', 'Great', 'Excellent'];
const clamp = (v) => Math.max(1, Math.min(5, Math.round(v)));
const num = (s) => Number.parseFloat(String(s).replace(/,/g, ''));
const first = (re, s) => {
  const m = String(s).match(re);
  return m ? num(m[1]) : null;
};

const kindOf = (p) => {
  const c = p.category_slug;
  if (c === 'smartphones') return 'phone';
  if (c === 'laptops') return 'laptop';
  if (c === 'tablets') return 'tablet';
  if (c === 'mobile-accessories') return /earbud|airpod|headphone|earphone|beats|buds/i.test(p.title) ? 'audio' : /watch/i.test(p.title) ? 'smartwatch' : 'accessory';
  if (/watches$/.test(c)) return 'watch';
  if (c === 'fragrances') return 'fragrance';
  if (['mens-shirts', 'tops', 'womens-dresses'].includes(c)) return 'apparel';
  if (/shoes$/.test(c)) return 'shoes';
  if (c === 'sunglasses') return 'sunglasses';
  if (c === 'motorcycle') return 'bike';
  if (c === 'vehicle') return 'car';
  if (['beauty', 'skin-care'].includes(c)) return 'beauty';
  if (c === 'groceries') return 'grocery';
  if (['kitchen-accessories', 'furniture', 'home-decoration'].includes(c)) return 'home';
  return 'other';
};

const out = (title, meaning, level = null, scale = null) => ({ title, meaning, level: level === null ? null : clamp(level), scale });

// ---------------------------------------------------------------- rules (value, ctx) -> out | null

const ram = (v, { kind }) => {
  const gb = first(/(\d+(?:\.\d+)?)\s*gb/i, v);
  if (!gb) return null;
  const unified = /unified/i.test(v) ? ' Apple\'s unified memory is shared with the graphics chip and is very efficient.' : '';
  if (kind === 'laptop') {
    const level = gb <= 4 ? 1 : gb < 8 ? 2 : gb < 16 ? 3 : gb < 32 ? 4 : 5;
    const text = [null,
      'Only for browsing and documents; it slows down with many tabs open.',
      'Fine for browsing, documents and video calls, but multitasking will feel tight.',
      'Good for students and office work: browsing, documents, video calls and light photo editing.',
      'Smooth multitasking: plenty for programming, design apps and light gaming.',
      'Workstation-class memory: video editing, virtual machines and heavy creative work.'][level];
    const short = [null, 'basic use only', 'everyday basics', 'everyday multitasking', 'smooth multitasking', 'power-user multitasking'][level];
    return out(`${gb} GB RAM: ${short}`, text + unified, level, 'Multitasking');
  }
  const level = gb <= 2 ? 1 : gb <= 4 ? 2 : gb <= 6 ? 3 : gb <= 8 ? 4 : 5;
  const text = [null,
    'Basic: fine for calls, WhatsApp and browsing, but apps reload when you switch between them.',
    'Enough for everyday apps and social media; heavy games and many open apps may stutter.',
    'Smooth everyday use: social media, YouTube and casual games run comfortably.',
    'Great multitasking: keeps many apps open and handles demanding games well.',
    'Flagship-level memory: effortless multitasking and top-end gaming for years.'][level];
  const short = [null, 'basic use', 'everyday apps', 'smooth everyday use', 'great multitasking', 'flagship multitasking'][level];
  return out(`${gb} GB RAM: ${short}`, text, level, 'Multitasking');
};

const storageCapacity = (v, { kind }) => {
  const m = String(v).match(/(\d+(?:\.\d+)?)\s*(tb|gb)/i);
  if (!m) return null;
  const gb = num(m[1]) * (m[2].toLowerCase() === 'tb' ? 1024 : 1);
  const laptop = kind === 'laptop';
  const level = laptop
    ? (gb <= 128 ? 1 : gb <= 256 ? 2 : gb <= 512 ? 3 : gb <= 1024 ? 4 : 5)
    : (gb <= 32 ? 1 : gb <= 64 ? 2 : gb <= 128 ? 3 : gb <= 256 ? 4 : 5);
  const usable = Math.max(1, gb - (laptop ? 40 : 12));
  const photos = Math.max(1000, Math.round((usable * 1024) / 4 / 1000) * 1000);
  const parts = [`Room for roughly ${photos.toLocaleString('en-US')} photos (about 4 MB each) after the system files.`];
  if (/ssd|nvme/i.test(v)) parts.push(`It's an SSD${/nvme/i.test(v) ? ' (NVMe, the fast kind)' : ''}, so it boots and opens apps in seconds.`);
  if (/microsd|expandable/i.test(v)) parts.push('You can add a memory card later for more space.');
  if (level <= 2 && !laptop) parts.push('Apps and WhatsApp media fill this up fast.');
  return out(`${m[1]} ${m[2].toUpperCase()} storage`, parts.join(' '), level, 'Space');
};

const storageOther = (v) => {
  const s = String(v).toLowerCase();
  if (/freez/.test(s) && /refrigerat/.test(s)) return out('Keep it chilled', `Keep it in the fridge and use it soon, or freeze it to keep it longer (${v}).`);
  if (/frozen|freez/.test(s)) return out('Keep it frozen', `Store in the freezer (${v}).`);
  if (/refrigerat|fridge/.test(s)) return out('Keep it in the fridge', `Store in the fridge (${v}).`);
  if (/cool|dry|room temperature|dark/.test(s)) return out('Pantry storage', `No fridge needed: ${v.charAt(0).toLowerCase()}${v.slice(1)}.`);
  const litres = first(/(\d+(?:\.\d+)?)\s*l\b/i, v);
  if (litres) return out(`${litres} L storage space`, `About the size of a small backpack: handy for a bag of groceries or a rain jacket (${v}).`);
  return null;
};

const storage = (v, ctx) => storageCapacity(v, ctx) || storageOther(v);

const CHIPS = [
  [/apple m\d\s*(pro|max|ultra)/i, 5, 'Pro-grade Apple silicon'],
  [/apple m\d/i, 4, 'Apple silicon'],
  [/a1[5-9]\b/i, 5, 'Apple flagship chip'],
  [/a1[2-4]\b/i, 4, 'Apple chip from a recent generation'],
  [/a1[01]\b/i, 3, 'Older Apple flagship chip'],
  [/\ba[89]\b/i, 2, 'Older Apple chip'],
  [/\ba7\b/i, 1, 'Very old Apple chip'],
  [/snapdragon 8\+? ?gen/i, 5, 'Flagship Snapdragon'],
  [/snapdragon 8[6-9]\d/i, 5, 'Flagship Snapdragon'],
  [/snapdragon 855/i, 4, 'Former flagship Snapdragon'],
  [/snapdragon 8[0-4]\d/i, 3, 'Older flagship Snapdragon'],
  [/snapdragon 7\d\d/i, 3, 'Upper mid-range Snapdragon'],
  [/snapdragon 6\d\d/i, 2, 'Mid-range Snapdragon'],
  [/snapdragon 4\d\d/i, 1, 'Entry-level Snapdragon'],
  [/exynos 2\d{3}/i, 5, 'Flagship Exynos'],
  [/exynos 98\d\d/i, 4, 'Former flagship Exynos'],
  [/exynos 8\d{3}/i, 3, 'Older flagship Exynos'],
  [/exynos [79]\d{3}/i, 2, 'Mid-range Exynos'],
  [/dimensity 9\d{3}/i, 5, 'Flagship Dimensity'],
  [/dimensity (?:8\d{3}|1\d{3})/i, 4, 'Upper mid-range Dimensity'],
  [/dimensity [6-8]\d\d/i, 3, 'Mid-range Dimensity (5G)'],
  [/helio g9\d/i, 3, 'Gaming-tuned Helio'],
  [/helio g8\d/i, 2, 'Mid-range Helio'],
  [/helio [gpa]\d\d/i, 1, 'Entry-level Helio'],
  [/unisoc|tiger/i, 1, 'Entry-level Unisoc'],
  [/kirin 9\d\d/i, 4, 'Former flagship Kirin'],
  [/kirin [6-8]\d\d/i, 2, 'Mid-range Kirin'],
  [/core i9|ryzen 9/i, 5, 'High-end'],
  [/core i7|ryzen 7/i, 4, 'Performance'],
  [/core i5|ryzen 5/i, 3, 'Mainstream'],
  [/core i3|ryzen 3/i, 2, 'Entry-level'],
  [/celeron|pentium|atom|athlon/i, 1, 'Budget'],
];

const PHONE_CPU = [null,
  'Entry-level chip: fine for calls, social apps and video; games run at low settings.',
  'Mid-range chip: smooth for daily apps, casual games at medium settings.',
  'Capable chip: everyday apps fly and most games run well.',
  'Former flagship power: fast at everything and handles demanding games.',
  'Flagship chip: top-tier speed for gaming, 4K video and years of updates.'];
const LAPTOP_CPU = [null,
  'Basic: browsing and documents only.',
  'Entry-level: office work and online classes.',
  'Solid all-rounder: multitasking, coding and photo editing.',
  'Powerful: programming, design tools and gaming (paired with a good graphics card).',
  'Top-tier: video editing, 3D and heavy compiling without breaking a sweat.'];

const processor = (v, { kind }) => {
  const hit = CHIPS.find(([re]) => re.test(v));
  if (!hit) return null;
  let [, level, family] = hit;
  const gen = first(/(\d+)(?:th|st|nd|rd) gen/i, v);
  const intel = /core i\d-(\d{4,5})([a-z]*\d?[a-z]*)/i.exec(v);
  const notes = [];
  if (intel) {
    // i7-8550U -> 8th gen, i7-1165G7 -> 11th, i7-10750H -> 10th (an explicit "(11th Gen)" wins)
    const digits = intel[1];
    const genNo = gen || (digits.length === 5 || (digits[0] === '1' && /^g/i.test(intel[2])) ? Number(digits.slice(0, 2)) : Number(digits[0]));
    const suffix = intel[2].toUpperCase();
    if (genNo <= 8) {
      level -= 1;
      notes.push('It is an older generation: still capable, but less efficient than current chips.');
    }
    if (/H/.test(suffix)) notes.push('The "H" means a high-performance chip built for gaming and creator laptops (more power, more heat).');
    else if (/U|G\d/.test(suffix)) notes.push('It is a low-power chip, so the laptop runs cooler and the battery lasts longer.');
  } else if (gen && gen <= 8) notes.push('It is an older generation, so it is less efficient than current chips.');
  const cores = first(/(\d+)-core/i, v);
  if (cores) notes.push(`${cores} CPU cores share the work when you multitask.`);
  if (/\b5g\b/i.test(v)) notes.push('Includes a 5G modem.');
  const base = kind === 'laptop' ? LAPTOP_CPU : PHONE_CPU;
  const name = String(v).split(/[(,]/)[0].replace(/\s+(?:octa|hexa|quad)-core$/i, '').trim();
  return out(`${name}: ${family}`, [base[clamp(level)], ...notes].join(' '), level, 'Speed');
};

const display = (v, { kind }) => {
  const s = String(v);
  const inch = first(/(\d+(?:\.\d+)?)\s*(?:-|\s)?(?:inch|")/i, s);
  const res = s.match(/(\d{3,4})\s*x\s*(\d{3,4})/i);
  const hz = first(/(\d{2,3})\s*hz/i, s);
  const oled = /oled|amoled|xdr/i.test(s);
  const tft = /tft/i.test(s);
  if (!inch && !res && !oled && !/lcd|ips|retina/i.test(s)) return null;
  let level = oled ? 4 : tft ? 2 : 3;
  const parts = [];
  if (inch) {
    if (['phone'].includes(kind)) parts.push(inch < 5.5 ? 'Compact screen, easy to use with one hand.' : inch <= 6.3 ? 'Comfortable size for one-handed use.' : 'Big screen: lots of room for videos and games.');
    else if (kind === 'laptop') parts.push(inch <= 13.5 ? 'Very portable size.' : inch < 15.5 ? 'A balanced size: portable but roomy enough to work on.' : 'Roomy for spreadsheets and movies, but less portable.');
    else if (kind === 'tablet') parts.push(inch >= 12 ? 'Large canvas for drawing, notes and split-screen.' : 'Handy size for reading, streaming and classes.');
  }
  if (oled) parts.push('OLED panel: true blacks and vivid colours, and dark mode saves battery.');
  else if (tft) parts.push('Budget TFT LCD panel: fine indoors, weaker viewing angles.');
  else if (/ips|lcd|retina/i.test(s)) parts.push('IPS LCD panel: accurate colours and good viewing angles, though blacks look a bit grey.');
  if (res) {
    const short = Math.min(Number(res[1]), Number(res[2]));
    if (short >= 1440) {
      level += 1;
      parts.push('Very sharp resolution: text and photos look crisp.');
    } else if (short >= 1080) parts.push('Full HD sharpness: text and video look crisp.');
    else if (short < 800) {
      level -= 1;
      parts.push('HD+ resolution: fine for casual use, but text is less crisp.');
    }
  }
  if (hz >= 120) {
    level += 1;
    parts.push(`${hz} Hz refresh rate makes scrolling and games look silky-smooth.`);
  } else if (hz >= 90) parts.push(`${hz} Hz refresh rate feels smoother than a standard 60 Hz screen.`);
  if (/touch/i.test(s)) parts.push('Touchscreen.');
  const panel = oled ? 'OLED' : tft ? 'LCD' : 'LCD';
  const title = `${inch ? `${inch}" ` : ''}${panel} display${hz >= 90 ? `, ${hz} Hz` : ''}`;
  return out(title, parts.join(' '), level, 'Viewing quality');
};

const refreshRate = (v) => {
  const hz = first(/(\d{2,3})\s*hz/i, v);
  if (!hz) return null;
  const level = hz >= 144 ? 5 : hz >= 120 ? 4 : hz >= 90 ? 3 : 2;
  return out(`${hz} Hz refresh rate`, hz >= 90 ? 'The screen redraws more often than a standard 60 Hz one, so scrolling and games look smoother.' : 'Standard smoothness.', level, 'Smoothness');
};

const battery = (v, { kind, p }) => {
  const s = String(v);
  const mah = first(/(\d{3,5})\s*mah/i, s);
  const hours = first(/(\d+(?:\.\d+)?)\s*hours?/i, s);
  if (mah && ['phone', 'tablet', 'other', 'accessory'].includes(kind)) {
    let level;
    if (kind === 'tablet') level = mah >= 10000 ? 5 : mah >= 7000 ? 4 : mah >= 5000 ? 3 : 2;
    else level = mah < 3000 ? 1 : mah < 3700 ? 2 : mah < 4300 ? 3 : mah < 4900 ? 4 : 5;
    const notes = [];
    const apple = /apple|iphone/i.test(`${p.brand_name} ${p.title}`);
    if (apple && kind === 'phone') {
      level += 1;
      notes.push('iPhones get more hours out of each mAh than most Android phones.');
    }
    const day = [null, 'Will likely need a top-up by evening.', 'Gets through a light day.', 'A full day of normal use.', 'A full day of heavy use.', 'About a day and a half to two days of normal use.'][clamp(level)];
    return out(`${mah.toLocaleString('en-US')} mAh battery`, [day, ...notes].join(' '), level, 'Battery life');
  }
  if (hours) {
    let level;
    let meaning;
    if (kind === 'laptop' || /video|playback/i.test(s) && kind !== 'audio') {
      level = hours < 5 ? 1 : hours < 8 ? 2 : hours < 11 ? 3 : hours < 15 ? 4 : 5;
      meaning = [null, 'Stay near a charger.', 'A few hours unplugged, e.g. a couple of lectures.', 'Most of a working day unplugged.', 'A full work or university day unplugged.', 'All-day unplugged, with battery to spare.'][level];
    } else {
      level = hours < 3 ? 1 : hours < 5 ? 2 : hours < 8 ? 3 : hours < 15 ? 4 : 5;
      meaning = `Around ${hours} hours of use per charge${/case/i.test(s) ? '; the charging case tops it up on the go' : ''}.`;
      const total = first(/(\d+)\s*hours? with (?:the )?charging case/i, s);
      if (total) meaning = `About ${hours} hours per charge and ${total} hours in total with the charging case: a week of commutes.`;
    }
    const wh = first(/(\d+(?:\.\d+)?)\s*wh\b/i, s);
    return out(`${wh ? `${wh} Wh, up` : 'Up'} to ${hours} hours battery`, meaning, level, 'Battery life');
  }
  return null;
};

const charging = (v) => {
  const s = String(v);
  const watts = [...s.matchAll(/(\d+(?:\.\d+)?)\s*w\b/gi)].map((m) => num(m[1]));
  const wired = watts.length ? Math.max(...watts) : null;
  const wireless = /wireless|qi|magsafe/i.test(s);
  const notes = [];
  let level = null;
  if (wired) {
    level = wired < 10 ? 1 : wired < 18 ? 2 : wired < 30 ? 3 : wired < 50 ? 4 : 5;
    notes.push([null, 'Slow: a full charge takes 2 to 3 hours.', 'Moderate: about 2 hours to full.', 'Standard fast charging: roughly half a battery in 30 to 40 minutes.', 'Very fast: about half a battery in around 20 minutes.', 'Blazing fast: a full charge in under an hour.'][level]);
  } else if (/fast/i.test(s)) {
    level = 3;
    notes.push('Supports fast charging, so short top-ups go a long way.');
  }
  if (wireless) notes.push('Also charges wirelessly: just drop it on a pad.');
  if (/usb-?c/i.test(s)) notes.push('USB-C is the universal port used by most new phones and laptops.');
  if (/lightning/i.test(s)) notes.push('Uses Apple\'s Lightning cable.');
  if (/micro-?usb/i.test(s)) notes.push('Micro-USB is the older, slower connector.');
  if (!notes.length) return null;
  return out(wired ? `${wired}W charging` : 'Charging', notes.join(' '), level, level ? 'Charging speed' : null);
};

const camera = (front) => (v) => {
  const s = String(v);
  const mps = [...s.matchAll(/(\d+(?:\.\d+)?)\s*mp/gi)].map((m) => num(m[1]));
  if (!mps.length) return null;
  const main = Math.max(...mps);
  if (front) {
    let level = main <= 2 ? 1 : main <= 8 ? 2 : main <= 12 ? 3 : main < 25 ? 3 : 4;
    const notes = [main <= 2 ? 'Basic quality: OK for video calls only.' : main <= 8 ? 'Fine for video calls and casual selfies.' : 'Detailed selfies and clear video calls.'];
    if (/face id|truedepth/i.test(s)) {
      level += 1;
      notes.push('Includes Face ID: secure face unlock that works in the dark.');
    }
    if (/ultra-?wide|center stage/i.test(s)) notes.push('Ultra-wide lens fits the whole group in selfies and keeps you centred on calls.');
    if (/pop-?up/i.test(s)) notes.push('Pop-up mechanism: no notch, but a moving part.');
    return out(`${main} MP front camera`, notes.join(' '), level, 'Selfie quality');
  }
  const count = /quad/i.test(s) ? 4 : /triple/i.test(s) ? 3 : /dual/i.test(s) ? 2 : mps.length;
  const ultra = /ultra-?wide/i.test(s);
  const tele = /tele/i.test(s);
  const ois = /ois/i.test(s);
  const aperture = first(/f\/(\d(?:\.\d)?)/i, s);
  let level = main >= 48 ? 3 : main >= 12 ? 2.5 : main >= 8 ? 1.5 : 1;
  if (ultra) level += 0.5;
  if (tele) level += 1;
  if (ois) level += 0.5;
  if (/dual pixel|smart hdr/i.test(s)) level += 0.5;
  const notes = [`${count > 1 ? `${count} rear cameras led by a` : 'A'} ${main} MP main sensor.`];
  if (ultra) notes.push('Ultra-wide lens fits more into group shots and landscapes.');
  if (tele) notes.push('Telephoto lens gives real optical zoom for portraits and far-away subjects.');
  if (ois) notes.push('Optical stabilisation (OIS) means sharper night shots and steadier video.');
  if (aperture && aperture <= 1.8) notes.push(`A wide f/${aperture} aperture lets in more light for low-light photos.`);
  if (/2 mp (?:depth|macro|b&w|mono)/i.test(s)) notes.push('The extra 2 MP depth/macro lenses add little real quality.');
  return out(`${main} MP${count > 1 ? ` ${['', '', 'dual', 'triple', 'quad'][count]}` : ''} camera`, notes.join(' '), level, 'Photo quality');
};

const network = (v) => {
  const s = String(v);
  const dual = /dual sim/i.test(s) ? ' Dual SIM lets you use two numbers, e.g. personal and work.' : '';
  if (/5g/i.test(s)) return out('5G ready', `Fastest mobile data where 5G is available, and future-proof as networks roll out.${dual}`, 5, 'Future-proofing');
  if (/4g|lte/i.test(s)) return out('4G LTE', `Fast browsing, streaming and video calls on all major networks.${dual}`, 3, 'Future-proofing');
  return null;
};

const waterResistance = (v) => {
  const s = String(v);
  const ip = s.match(/ip([0-9x])([0-9])/i);
  if (ip) {
    const water = Number(ip[2]);
    const depth = first(/(\d+(?:\.\d+)?)\s*m\b/i, s);
    if (water >= 8) return out(`IP${ip[1]}${ip[2]}: water and dust proof`, `Survives being submerged${depth ? ` (up to ${depth} m for 30 minutes)` : ' (typically 1.5 m for 30 minutes)'}: rain, spills and an accidental drop in water are fine. Avoid sea water and swimming with it.`, 5, 'Protection');
    if (water === 7) return out(`IP${ip[1]}7: water resistant`, 'Survives a dunk up to 1 m for 30 minutes: rain and spills are fine.', 4, 'Protection');
    if (water >= 4) return out(`IP${ip[1]}${water}: splash resistant`, 'Handles splashes and light rain, but keep it out of water.', 2, 'Protection');
  }
  const metres = first(/(\d+)\s*m\b/i, s);
  const atm = first(/(\d+)\s*(?:atm|bar)/i, s);
  const depth = metres || (atm ? atm * 10 : null);
  if (depth) {
    if (depth >= 200) return out(`${depth} m water resistance`, 'A true diver\'s watch: fine for swimming, snorkelling and scuba diving.', 5, 'Water safety');
    if (depth >= 100) return out(`${depth} m water resistance`, 'Fine for swimming and snorkelling (not scuba diving).', 4, 'Water safety');
    if (depth >= 50) return out(`${depth} m water resistance`, 'OK for showers and pool swimming; no diving or high-pressure water.', 3, 'Water safety');
    return out(`${depth} m water resistance`, 'Splash-proof only: rain and hand washing are fine, swimming is not.', 2, 'Water safety');
  }
  return null;
};

const weight = (v, { kind }) => {
  const s = String(v);
  const kg = first(/(\d+(?:\.\d+)?)\s*kg/i, s);
  const g = first(/(\d+(?:\.\d+)?)\s*g\b/i, s);
  const grams = kg ? kg * 1000 : g;
  if (!grams) return null;
  if (kind === 'phone') {
    const level = grams < 170 ? 5 : grams < 190 ? 4 : grams < 210 ? 3 : grams < 230 ? 2 : 1;
    return out(`${Math.round(grams)} g`, [null, 'Heavy: you will notice it in your pocket and during long calls.', 'On the heavy side.', 'Average weight for a modern phone.', 'Light and comfortable to hold.', 'Very light: barely noticeable in a pocket.'][level], level, 'Portability');
  }
  if (kind === 'laptop') {
    const level = grams < 1200 ? 5 : grams < 1500 ? 4 : grams < 1900 ? 3 : grams < 2400 ? 2 : 1;
    return out(`${(grams / 1000).toFixed(2).replace(/0$/, '')} kg`, [null, 'Heavy: better as a desk machine.', 'Portable, but you will feel it in a backpack all day.', 'Fine to carry to class or the office.', 'Light: easy to carry all day.', 'Ultra-portable: like carrying a notebook.'][level], level, 'Portability');
  }
  if (kind === 'audio' && grams < 10) return out(`${grams} g per earbud`, 'Feather-light, so they stay comfortable for hours.', 5, 'Comfort');
  return null;
};

const os = (v) => {
  const s = String(v);
  const upgrade = s.match(/upgradable to (?:ios |android )?(\d+(?:\.\d+)?)/i);
  if (/windows 10/i.test(s)) {
    return out(s, `${/pro/i.test(s) ? 'Pro adds business tools like BitLocker encryption. ' : ''}Microsoft ended Windows 10 support in October 2025, so plan a free upgrade to Windows 11 if the hardware supports it.`, 2, 'Software freshness');
  }
  if (/windows 11/i.test(s)) return out(s, 'Current Windows: runs all mainstream apps and gets regular updates.', 4, 'Software freshness');
  if (/macos/i.test(s)) return out(s, 'Smooth and secure, great for creative apps, and works hand-in-hand with an iPhone (AirDrop, Handoff).', 4, 'Software freshness');
  if (/ipados|watchos/i.test(s)) return out(s, 'Apple software: simple, secure and works seamlessly with an iPhone.', 4, 'Software freshness');
  const ios = s.match(/\bios (\d+)/i);
  if (ios) {
    const latest = upgrade ? num(upgrade[1]) : num(ios[1]);
    const level = latest >= 15 ? 4 : latest >= 13 ? 3 : latest >= 12 ? 2 : 1;
    return out(s, level >= 4 ? 'iOS: simple, secure and works seamlessly with other Apple devices.' : `Supports iOS ${latest} at most, so many new apps may no longer install or update.`, level, 'Software freshness');
  }
  const android = s.match(/android (\d+(?:\.\d+)?)/i);
  if (android) {
    const latest = upgrade ? num(upgrade[1]) : num(android[1]);
    const level = latest >= 13 ? 4 : latest >= 11 ? 3 : latest >= 9 ? 2 : 1;
    const skin = s.match(/^(one ui|coloros|funtouch os|realme ui|miui|oxygenos)/i) || s.match(/\((one ui[^)]*)\)/i);
    const notes = [level <= 2 ? `Android ${latest} is old: some new apps and security fixes will not reach it.` : `Android ${latest}: runs all popular apps.`];
    if (skin) notes.push(`${skin[1]} is the maker's own look and features on top of Android.`);
    return out(s, notes.join(' '), level, 'Software freshness');
  }
  return null;
};

const graphics = (v) => {
  const s = String(v);
  const rtx = s.match(/rtx\s*(\d{4})/i);
  if (rtx) {
    const series = Number(rtx[1].slice(0, 2));
    const level = series >= 30 ? 5 : 4;
    return out(`NVIDIA RTX ${rtx[1]} graphics`, level === 5 ? 'Dedicated gaming GPU: modern games at high settings and fast video editing.' : 'Dedicated gaming GPU: modern games at 1080p on medium-high settings, plus GPU-accelerated editing.', level, 'Gaming & graphics');
  }
  if (/gtx/i.test(s)) return out(s, 'Dedicated graphics: plays popular games at 1080p on medium settings.', 3, 'Gaming & graphics');
  const cores = first(/(\d+)-core apple gpu/i, s);
  if (cores) return out(`${cores}-core Apple GPU`, 'Strong for photo and video editing; gaming is limited mainly by the Mac game library.', cores >= 14 ? 4 : 3, 'Gaming & graphics');
  if (/iris xe/i.test(s)) return out('Intel Iris Xe (integrated)', 'Integrated graphics: smooth 4K video and light or older games at low settings.', 3, 'Gaming & graphics');
  if (/iris/i.test(s)) return out(s, 'Integrated graphics: video, office work and very light games.', 2, 'Gaming & graphics');
  if (/uhd|hd graphics/i.test(s)) return out(s, 'Basic integrated graphics: video and office work, not for gaming.', 1, 'Gaming & graphics');
  if (/radeon/i.test(s)) return out(s, 'AMD graphics: casual and esports games at modest settings.', 3, 'Gaming & graphics');
  return null;
};

const noiseCancellation = (v) => {
  const s = String(v);
  if (/active|anc/i.test(s)) return out('Active noise cancellation', `Electronically cancels engine hum and crowd noise: great for travel and busy offices.${/transparency/i.test(s) ? ' Transparency mode lets voices in when you need them.' : ''}`, 5, 'Noise blocking');
  if (/passive/i.test(s)) return out('Passive noise isolation', 'Blocks some outside noise through the fit alone.', 2, 'Noise blocking');
  if (/none|no\b/i.test(s)) return out('No noise cancellation', 'You will hear your surroundings, which is safer outdoors but worse on a noisy commute.', 1, 'Noise blocking');
  return null;
};

const connectivity = (v) => {
  const s = String(v);
  const bt = first(/bluetooth\s*(\d(?:\.\d)?)/i, s);
  const notes = [];
  let level = null;
  if (bt) {
    level = bt >= 5.2 ? 5 : bt >= 5 ? 4 : 3;
    notes.push(`Bluetooth ${bt}: ${bt >= 5 ? 'stable connection, low power use and about 10 m of range' : 'older Bluetooth, can drop more often'}.`);
  }
  if (/wi-?fi 6|ax\b/i.test(s)) notes.push('Wi-Fi 6 for faster, more reliable home internet.');
  if (/ultra wideband|u1/i.test(s)) notes.push('Ultra Wideband helps find it precisely with an iPhone.');
  if (/qi/i.test(s)) notes.push('Charges on any Qi wireless pad.');
  return notes.length ? out('Connectivity', notes.join(' '), level, level ? 'Connection quality' : null) : null;
};

const FABRICS = [
  [/linen/i, 5, 'Airy and the coolest choice for peak summer (it wrinkles easily).'],
  [/jersey/i, 5, 'Soft, stretchy T-shirt knit that breathes well.'],
  [/lightweight cotton|100% cotton|^cotton$/i, 5, 'Soft, breathable and absorbs sweat: ideal for hot, humid summers.'],
  [/poplin/i, 4, 'Crisp, smooth cotton weave that looks sharp at the office and stays breathable.'],
  [/flannel/i, 2, 'Brushed and warm: made for winter.'],
  [/cotton[- ]poly|poly[- ]cotton/i, 3, 'Fewer wrinkles than pure cotton and quick to dry, but a little less breathable.'],
  [/cotton[- ]blend|cotton blend/i, 3, 'Mostly cotton for comfort, blended for shape and fewer wrinkles.'],
  [/wool/i, 2, 'Warm with a smart drape: best for winter and formal wear.'],
  [/viscose|rayon/i, 3, 'Drapes nicely and feels soft; less breathable than cotton in peak heat.'],
  [/satin/i, 2, 'Shiny and smooth for evening events, but it traps heat; dry clean recommended.'],
  [/crepe/i, 3, 'Flowy, elegant drape that resists wrinkles.'],
  [/silk/i, 3, 'Luxurious and light; needs gentle care.'],
  [/polyester/i, 2, 'Durable and wrinkle-resistant, but not very breathable in heat.'],
  [/leather|pu\b/i, 1, 'Leather look that wipes clean easily; not breathable.'],
  [/cotton/i, 4, 'Cotton-based: comfortable and breathable.'],
];

const fabric = (v) => {
  const hit = FABRICS.find(([re]) => re.test(String(v).trim()));
  return hit ? out(String(v), hit[2], hit[1], 'Breathability') : null;
};

const concentration = (v) => {
  const s = String(v);
  if (/extrait|parfum\b(?!.*eau)|\(p\)|pure perfume/i.test(s) && !/eau de/i.test(s)) return out('Parfum (extrait)', 'The strongest form: about 20 to 30% perfume oil, often lasting 8+ hours. A dab is enough.', 5, 'Strength & longevity');
  if (/edp|eau de parfum/i.test(s)) return out('Eau de Parfum (EDP)', 'About 15 to 20% perfume oil: a rich scent that typically lasts 6 to 8 hours on skin.', 4, 'Strength & longevity');
  if (/edt|eau de toilette/i.test(s)) return out('Eau de Toilette (EDT)', 'About 5 to 15% perfume oil: lighter and fresher, usually 3 to 5 hours. Great for daytime and office.', 3, 'Strength & longevity');
  if (/edc|eau de cologne|cologne/i.test(s)) return out('Eau de Cologne', 'About 2 to 5% oil: a light splash that fades in about 2 hours.', 2, 'Strength & longevity');
  if (/mist|body spray/i.test(s)) return out('Body mist', 'Very light scent that lasts 1 to 2 hours.', 1, 'Strength & longevity');
  return null;
};

const hoursLevel = (h) => (h < 3 ? 1 : h < 5 ? 2 : h < 7 ? 3 : h < 9 ? 4 : 5);

const longevity = (v) => {
  const nums = [...String(v).matchAll(/(\d+(?:\.\d+)?)/g)].map((m) => num(m[1]));
  if (!nums.length) return null;
  const avg = nums.reduce((a, b) => a + b, 0) / nums.length;
  return out(`Lasts ${v}`, avg >= 7 ? 'Lasts from morning to evening with one application.' : avg >= 5 ? 'Lasts most of a work day; a touch-up helps for evening plans.' : 'Fades within a few hours, so carry it for touch-ups.', hoursLevel(avg), 'Longevity');
};

const FAMILIES = [
  [/citrus/i, 'fresh and zesty, great for daytime, office and summer'],
  [/aromatic/i, 'herbal and clean'],
  [/floral/i, 'flowery and romantic, easy to wear anywhere'],
  [/fruity/i, 'sweet and juicy, playful and daytime-friendly'],
  [/oriental|amber|spicy/i, 'warm, spicy-sweet, made for evenings and winter'],
  [/woody/i, 'earthy and sophisticated, works all year'],
  [/fresh|aquatic|marine/i, 'clean and airy'],
  [/gourmand|vanilla/i, 'sweet and cosy, like dessert'],
];

const fragranceFamily = (v) => {
  const hits = FAMILIES.filter(([re]) => re.test(v)).map(([, t]) => t);
  return hits.length ? out(`${v} scent`, `${hits[0].charAt(0).toUpperCase()}${hits[0].slice(1)}${hits[1] ? `, and ${hits[1]}` : ''}.`) : null;
};

const notes = (stage) => (v) => out(`${stage} notes: ${v}`, {
  Top: 'What you smell first, for roughly the first 15 to 30 minutes.',
  Heart: 'The main character of the scent, showing after about 30 minutes.',
  Base: 'What lingers on skin and clothes for hours.',
}[stage]);

const movement = (v) => {
  const s = String(v);
  if (/automatic|mechanical|self-winding/i.test(s)) return out('Automatic (mechanical) movement', 'Powered by the motion of your wrist, no battery ever. A piece of fine engineering; it needs a service every few years and may stop if left unworn for a couple of days.', 5, 'Craftsmanship');
  if (/quartz/i.test(s)) return out('Quartz movement', 'Battery-powered and very accurate, with almost no maintenance: just a battery change every 2 to 3 years.', 3, 'Craftsmanship');
  if (/smart|digital/i.test(s)) return out(s, 'Electronic movement with smart features; needs regular charging.', 3, 'Craftsmanship');
  return null;
};

const crystal = (v) => {
  const s = String(v);
  if (/sapphire/i.test(s)) return out('Sapphire crystal', `Almost scratch-proof: only diamond is harder.${/cyclops/i.test(s) ? ' The Cyclops lens magnifies the date.' : ''}${/anti-reflective/i.test(s) ? ' Anti-reflective coating keeps it readable in sunlight.' : ''}`, 5, 'Scratch resistance');
  if (/mineral/i.test(s)) return out('Mineral glass', 'Resists everyday scratches but can scuff over the years.', 3, 'Scratch resistance');
  if (/acrylic|plexi|plastic/i.test(s)) return out(s, 'Light and shatter-resistant, but scratches easily.', 2, 'Scratch resistance');
  return null;
};

const caseSize = (v) => {
  const mm = first(/(\d+(?:\.\d+)?)\s*mm/i, v);
  if (!mm) return null;
  const text = mm < 34 ? 'Petite and dainty, suits slim wrists.' : mm < 38 ? 'Classic small-to-medium size, elegant on most wrists.' : mm <= 42 ? 'The most versatile size: suits most wrists.' : mm <= 45 ? 'Bold and sporty, best on medium to large wrists.' : 'A large statement watch.';
  return out(`${mm} mm case`, text);
};

const powerReserve = (v) => {
  const h = first(/(\d+)\s*hours?/i, v);
  if (!h) return null;
  return out(`${h}-hour power reserve`, `Keeps running about ${h >= 48 ? `${Math.round((h / 24) * 10) / 10} days` : `${h} hours`} after you take it off.`, h < 40 ? 2 : h < 60 ? 3 : h < 80 ? 4 : 5, 'Power reserve');
};

const strap = (v) => {
  const s = String(v);
  if (/leather|alligator/i.test(s)) return out(s, 'Comfortable and dressy; keep it away from water and sweat.');
  if (/steel|bracelet|jubilee|oyster|metal/i.test(s)) return out(s, 'Durable, water-friendly metal that goes with anything.');
  if (/silicone|rubber|sport/i.test(s)) return out(s, 'Sporty and sweat-proof.');
  return null;
};

const engine = (v, { kind }) => {
  const s = String(v);
  const cc = first(/(\d+)\s*cc/i, s);
  const litres = first(/(\d(?:\.\d)?)\s*l\b/i, s);
  if (cc && kind !== 'car') {
    const level = cc <= 110 ? 1 : cc <= 160 ? 2 : cc <= 400 ? 3 : cc <= 800 ? 4 : 5;
    const text = [null, 'Commuter engine: very economical for city rides.', 'Everyday city bike: a good balance of power and fuel economy.', 'Sporty: comfortable on highways too.', 'Big bike: strong highway power; insurance and upkeep cost more.', 'Superbike power: for experienced riders only.'][level];
    return out(`${cc} cc engine`, `${text}${/liquid-cooled/i.test(s) ? ' Liquid cooling keeps it cool in traffic.' : ''}`, level, 'Power');
  }
  if (litres) {
    const level = litres <= 1 ? 1 : litres <= 1.5 ? 2 : litres <= 2 ? 3 : litres <= 3 ? 4 : 5;
    const turbo = /turbo/i.test(s) ? ' The turbo adds punch without a bigger engine.' : '';
    return out(`${litres} L engine`, `${[null, 'Small and economical, made for city driving.', 'Balanced power and fuel economy.', 'Strong, confident on highways.', 'Powerful; uses more fuel.', 'Big, powerful engine (V6/V8 class): effortless, but thirsty.'][level]}${turbo}`, level, 'Power');
  }
  return null;
};

const mileage = (v) => {
  const kmpl = first(/(\d+(?:\.\d+)?)\s*km\/l/i, v);
  if (!kmpl) return null;
  return out(`About ${kmpl} km per litre`, kmpl >= 40 ? 'Very economical on petrol.' : kmpl >= 20 ? 'Reasonable fuel economy.' : 'Thirsty on petrol.', kmpl >= 45 ? 5 : kmpl >= 35 ? 4 : kmpl >= 20 ? 3 : kmpl >= 12 ? 2 : 1, 'Fuel economy');
};

const transmission = (v) => {
  const s = String(v);
  if (/cvt|automatic/i.test(s)) return out(s, 'No gear shifting: smooth and relaxed in city traffic.');
  if (/sequential|quickshifter/i.test(s)) return out(s, 'Race-style gearbox: lightning-quick gear changes.');
  if (/manual/i.test(s)) return out(s, 'You shift the gears: more control and usually better fuel economy.');
  return null;
};

const brakes = (v) => {
  const s = String(v);
  if (/abs/i.test(s)) return out(s, 'ABS stops the wheels locking under hard braking: much safer in rain.', 5, 'Safety');
  if (/disc/i.test(s) && /drum/i.test(s)) return out(s, 'The front disc bites strongly; the rear drum is basic.', 3, 'Safety');
  if (/disc/i.test(s)) return out(s, 'Disc brakes stop strongly and handle heat well.', 4, 'Safety');
  return null;
};

const uv = (v) => (/uv\s*400|100%/i.test(v)
  ? out('UV400 protection', 'Blocks virtually all UVA and UVB rays: real eye protection, not just a dark tint.', 5, 'Eye protection')
  : null);

const lensMaterial = (v) => {
  if (/polycarbonate/i.test(v)) return out('Polycarbonate lenses', 'Lightweight and shatter-resistant: safe for sports and kids.', 4, 'Durability');
  if (/acrylic/i.test(v)) return out('Acrylic lenses', 'Budget lenses that scratch more easily.', 2, 'Durability');
  if (/glass/i.test(v)) return out('Glass lenses', 'Very clear and scratch-resistant, but heavier.', 4, 'Durability');
  return null;
};

const frameMaterial = (v) => {
  if (/acetate/i.test(v)) return out(String(v), 'Premium plant-based plastic with rich colours; comfortable and adjustable.');
  if (/metal|titanium|steel/i.test(v)) return out(String(v), 'Slim and strong metal frame.');
  if (/plastic/i.test(v)) return out(String(v), 'Light and affordable.');
  return null;
};

const heelHeight = (v) => {
  const cm = first(/(\d+(?:\.\d+)?)\s*cm/i, v);
  if (!cm) return /flat/i.test(v) ? out('Flat', 'All-day comfort.', 5, 'Comfort') : null;
  const level = cm <= 3 ? 5 : cm <= 5 ? 4 : cm <= 7 ? 3 : cm <= 9 ? 2 : 1;
  return out(`${cm} cm heel`, cm <= 3 ? 'Barely-there lift: comfortable all day.' : cm <= 6 ? `A moderate heel, manageable for long events${/block/i.test(v) ? ' (the block heel adds stability)' : ''}.` : 'A high heel: dressy, but less comfortable for long walks.', level, 'Comfort');
};

const yesNoSafe = (what) => (v) => {
  const s = String(v);
  if (/^yes/i.test(s)) return out(`${what} safe`, `Saves time: it can go in the ${what.toLowerCase()}${/top rack/i.test(s) ? ' (top rack)' : ''}.`);
  if (/^no/i.test(s)) return out(`Not ${what.toLowerCase()} safe`, 'Hand wash to keep it in good shape.');
  return null;
};

const volume = (v, { kind }) => {
  const ml = first(/(\d+(?:\.\d+)?)\s*ml/i, v);
  if (!ml || kind !== 'fragrance') return null;
  const sprays = Math.round(ml * 10);
  const months = Math.max(1, Math.round(sprays / 3 / 30));
  return out(`${ml} ml bottle`, `About ${sprays.toLocaleString('en-US')} sprays: roughly ${months} month${months === 1 ? '' : 's'} at 3 sprays a day.`);
};

const MATERIALS = [
  [/stainless steel/i, 'Rust-resistant, hygienic and easy to clean.'],
  [/genuine leather|leather/i, 'Durable and ages nicely with use.'],
  [/silicone/i, 'Heat-resistant and gentle on non-stick surfaces.'],
  [/bamboo|wood/i, 'Natural material: hand wash and dry it quickly.'],
  [/cast iron/i, 'Holds heat very well; season it and keep it dry.'],
  [/glass/i, 'Non-porous and does not hold smells.'],
  [/ceramic/i, 'Non-stick and easy to clean; avoid metal scrubbers.'],
  [/plastic/i, 'Light and affordable.'],
];

const material = (v) => {
  const hit = MATERIALS.find(([re]) => re.test(v));
  return hit ? out(String(v), hit[1]) : null;
};

const warranty = (v) => {
  const s = String(v).toLowerCase();
  if (/no warranty|none/.test(s)) return out('No warranty', 'Repairs will be at your own cost.', 1, 'Peace of mind');
  if (/lifetime/.test(s)) return out(v, 'Covered for life against manufacturing defects.', 5, 'Peace of mind');
  const years = first(/(\d+)\s*years?/i, s);
  const months = years ? years * 12 : first(/(\d+)\s*months?/i, s);
  const weeks = first(/(\d+)\s*weeks?/i, s);
  const m = months || (weeks ? weeks / 4 : null);
  if (!m) return null;
  const level = m < 3 ? 1 : m < 6 ? 2 : m < 12 ? 3 : m < 24 ? 4 : 5;
  return out(v, `Defects in the first ${m >= 12 ? `${m / 12} year${m === 12 ? '' : 's'}` : `${Math.round(m)} month${m === 1 ? '' : 's'}`} are fixed or replaced for free.`, level, 'Peace of mind');
};

const fingerprint = (v) => out(`${v} fingerprint sensor`, /in-display/i.test(v) ? `Unlock by touching the screen${/ultrasonic/i.test(v) ? '; ultrasonic sensors work even with wet fingers' : ''}.` : 'Quick unlock from the side button, where your thumb naturally rests.');

const stylus = (v) => out(String(v), /included/i.test(v) ? 'A pen comes in the box: great for notes and drawing.' : 'Works with a stylus (sold separately) for notes and drawing.');

// key pattern -> rule. first match wins, so specific keys come first
const RULES = [
  [/^ram$|^memory$/i, ram],
  [/^storage$|^capacity$/i, storage],
  [/^processor$|^chipset$|^cpu$/i, processor],
  [/^display$|^screen$/i, display],
  [/refresh/i, refreshRate],
  [/^battery( life)?$/i, battery],
  [/^charging$|^fast charging$/i, charging],
  [/^rear camera$|^camera$|^main camera$/i, camera(false)],
  [/^front camera$|^selfie camera$/i, camera(true)],
  [/^network$/i, network],
  [/water resistance|waterproof/i, waterResistance],
  [/^weight$/i, weight],
  [/^os$|operating system/i, os],
  [/^graphics$|^gpu$/i, graphics],
  [/noise cancell?ation/i, noiseCancellation],
  [/^connectivity$/i, connectivity],
  [/^fabric$/i, fabric],
  [/^concentration$/i, concentration],
  [/^longevity$/i, longevity],
  [/^fragrance family$/i, fragranceFamily],
  [/^top notes$/i, notes('Top')],
  [/^heart notes$|^middle notes$/i, notes('Heart')],
  [/^base notes$/i, notes('Base')],
  [/^movement$/i, movement],
  [/^crystal$/i, crystal],
  [/^case size$/i, caseSize],
  [/^power reserve$/i, powerReserve],
  [/^strap$/i, strap],
  [/^engine$/i, engine],
  [/^mileage$/i, mileage],
  [/^transmission$/i, transmission],
  [/^brakes$/i, brakes],
  [/^uv protection$/i, uv],
  [/^lens material$/i, lensMaterial],
  [/^frame material$/i, frameMaterial],
  [/^heel height$|^heel$/i, heelHeight],
  [/^dishwasher safe$/i, yesNoSafe('Dishwasher')],
  [/^microwave safe$/i, yesNoSafe('Microwave')],
  [/^freezer safe$/i, yesNoSafe('Freezer')],
  [/^volume$/i, volume],
  [/^material$|^case material$/i, material],
  [/^fingerprint$/i, fingerprint],
  [/^stylus$/i, stylus],
];

// importance order per product kind (keys not listed keep their original order after these)
const PRIORITY = {
  phone: ['Processor', 'RAM', 'Storage', 'Display', 'Rear Camera', 'Front Camera', 'Battery', 'Charging', 'Network', 'Water Resistance', 'OS', 'Weight'],
  laptop: ['Processor', 'RAM', 'Storage', 'Graphics', 'Display', 'Battery Life', 'Weight', 'OS'],
  tablet: ['Processor', 'RAM', 'Storage', 'Display', 'Battery', 'Stylus'],
  fragrance: ['Concentration', 'Longevity', 'Fragrance Family', 'Top Notes', 'Heart Notes', 'Base Notes', 'Volume'],
  watch: ['Movement', 'Water Resistance', 'Crystal', 'Case Size', 'Power Reserve', 'Strap', 'Case Material'],
};

const explainSpec = (key, value, ctx) => {
  const rule = RULES.find(([re]) => re.test(String(key).trim()));
  if (!rule) return null;
  try {
    return rule[1](String(value), ctx);
  } catch {
    return null;
  }
};

const shape = (key, value, e) => ({
  key,
  value: String(value),
  title: e.title,
  meaning: e.meaning,
  level: e.level,
  levelLabel: e.level ? LEVEL_LABELS[e.level] : null,
  scale: e.scale,
});

// who-it's-for personas from levels (by explained key)
const personasFor = (kind, lv, p) => {
  const L = (k) => lv[k] || 0;
  const out2 = [];
  if (kind === 'phone' || kind === 'tablet') {
    if (L('Rear Camera') >= 4) out2.push('photography lovers');
    if (L('Processor') >= 4 && L('RAM') >= 3) out2.push('mobile gamers');
    if (L('Battery') >= 4) out2.push('heavy users who are away from a charger all day');
    if (L('Display') >= 4) out2.push('binge-watchers');
    if (L('Processor') && L('Processor') <= 2 && L('RAM') <= 2) out2.push('first-time smartphone users or anyone needing a simple backup phone');
    if (L('Weight') >= 5) out2.push('anyone who wants a light, pocketable phone');
  } else if (kind === 'laptop') {
    if (L('Graphics') >= 4 && /rtx|gtx|radeon rx/i.test(String(p.specs?.Graphics || ''))) out2.push('gamers');
    if (L('RAM') >= 4 && L('Processor') >= 4) out2.push('programmers, designers and other power users');
    if (L('Weight') >= 4 && L('Battery Life') >= 4) out2.push('students and travellers who work on the go');
    if (L('Processor') && L('Processor') <= 2) out2.push('browsing, online classes and documents');
    if (!out2.length && L('RAM') >= 3) out2.push('students and office work');
  } else if (kind === 'watch') {
    if (L('Movement') >= 5) out2.push('watch enthusiasts and formal occasions');
    if (L('Water Resistance') >= 4) out2.push('active people who swim');
    if (L('Movement') === 3) out2.push('everyday wear with zero fuss');
  } else if (kind === 'fragrance') {
    const fam = String(p.specs?.['Fragrance Family'] || '').toLowerCase();
    if (/oriental|amber|woody|spicy/.test(fam)) out2.push('evenings, events and cooler weather');
    if (/citrus|fresh|aquatic|fruity|aromatic/.test(fam)) out2.push('daytime, the office and warm weather');
    if (/floral/.test(fam)) out2.push('anyone who loves a romantic floral scent');
    if (L('Concentration') >= 4) out2.push('people who want their scent to last all day');
  } else if (kind === 'apparel') {
    if (L('Fabric') >= 4) out2.push('hot summer days');
    if (L('Fabric') && L('Fabric') <= 2) out2.push('cooler weather and evening events');
  } else if (kind === 'audio') {
    if (L('Noise Cancellation') >= 5) out2.push('commuters and frequent flyers');
    if (L('Battery') >= 4) out2.push('long listening sessions');
  } else if (kind === 'bike') {
    if (L('Engine') <= 2) out2.push('daily city commuting on a budget');
    if (L('Engine') >= 4) out2.push('experienced riders who want highway power');
  }
  const stated = p.specs?.['Ideal For'] || p.specs?.['Best For'] || p.specs?.Occasion || p.specs?.Use;
  if (!out2.length && stated) out2.push(String(stated).toLowerCase());
  return out2.slice(0, 3);
};

const keyName = (k) => (/^[A-Z]{2,}$/.test(k) ? k : k.toLowerCase());

const KIND_NOUN = { phone: 'phone', laptop: 'laptop', tablet: 'tablet', watch: 'watch', fragrance: 'fragrance', apparel: 'piece', audio: 'pair', bike: 'bike', car: 'car' };

// main entry: catalog product row -> explanation
const explainProduct = (p) => {
  const kind = kindOf(p);
  const ctx = { kind, p };
  const entries = Object.entries(p.specs || {});
  if (p.warranty && !entries.some(([k]) => /warranty/i.test(k))) entries.push(['Warranty', p.warranty]);
  const prio = PRIORITY[kind] || [];
  entries.sort((a, b) => {
    const ia = prio.indexOf(a[0]);
    const ib = prio.indexOf(b[0]);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
  });
  const specs = [];
  const others = [];
  for (const [key, value] of entries) {
    const e = /warranty/i.test(key) ? warranty(String(value)) : explainSpec(key, value, ctx);
    if (e) specs.push(shape(key, value, e));
    else others.push({ key, value: String(value) });
  }
  const levels = {};
  for (const s of specs) if (s.level) levels[s.key] = s.level;
  const rated = specs.filter((s) => s.level && !/warranty/i.test(s.key));
  const overall = rated.length >= 3 ? Math.round((rated.reduce((a, s) => a + s.level, 0) / rated.length) * 10) / 10 : null;

  const whoFor = personasFor(kind, levels, p);
  const strengths = rated.filter((s) => s.level >= 4).sort((a, b) => b.level - a.level).slice(0, 2);
  const weak = rated.filter((s) => s.level <= 2).sort((a, b) => a.level - b.level)[0];
  const noun = KIND_NOUN[kind] || 'product';
  const sentences = [];
  sentences.push(whoFor.length ? `This ${noun} suits ${list(whoFor)}.` : `A ${p.price ? `${money(p.price)} ` : ''}${p.category_name ? p.category_name.toLowerCase().replace(/s$/, '') : noun} for everyday use.`);
  if (strengths.length) sentences.push(`Its strongest point${strengths.length > 1 ? 's are' : ' is'} the ${list(strengths.map((s) => keyName(s.key)))} (${list(strengths.map((s) => s.title))}).`);
  if (weak) sentences.push(`Keep in mind: the ${keyName(weak.key)} is ${LEVEL_LABELS[weak.level].toLowerCase()} (${weak.value}). ${weak.meaning.split(/(?<=\.)\s/)[0]}`);
  else if (rated.length >= 3) sentences.push('No spec stands out as a weak spot.');

  return {
    product: { id: p.id, title: p.title, category: p.category_slug ? { slug: p.category_slug, name: p.category_name } : null, kind },
    overall: overall ? { level: overall, label: LEVEL_LABELS[clamp(overall)] } : null,
    whoFor,
    summary: sentences.slice(0, 3).join(' '),
    specs,
    others,
  };
};

module.exports = { explainProduct, explainSpec, kindOf, LEVEL_LABELS };
