// shopping glossary: plain-language answers to "what is RAM?", "what does IP68 mean?" and
// "difference between iPad and tablet". offline, deterministic, and only general knowledge (no prices or stock).

const CONCEPTS = {
  ram: {
    names: ['ram', 'memory'],
    title: 'RAM',
    text: '**RAM** is a device\'s short-term working memory: it holds the apps you have open right now. More RAM means you can switch between apps (or browser tabs) without them reloading. Rough guide: 4 GB for basics, 6-8 GB for smooth everyday use, 12 GB+ for heavy gaming or multitasking on phones; 8 GB for students and 16 GB+ for programming or editing on laptops.',
    chips: ['Phones with 8 GB RAM', 'Laptops for programming'],
  },
  storage: {
    names: ['storage', 'rom', 'internal storage', 'gb storage'],
    title: 'Storage',
    text: '**Storage** (sometimes called ROM on phones) is where your apps, photos and files live permanently. Unlike RAM it keeps everything when the device is off. 128 GB is comfortable for most phones; laptops are happiest with a 512 GB SSD.',
    chips: ['Phones', 'Laptops'],
  },
  ssd: {
    names: ['ssd', 'hdd', 'hard drive', 'solid state', 'nvme'],
    title: 'SSD vs HDD',
    text: 'An **SSD** (solid-state drive) stores data on chips, so a laptop boots and opens apps in seconds. An **HDD** (hard disk) uses a spinning disk: cheaper per GB but much slower and more fragile. For a laptop, always prefer an SSD.',
    chips: ['Laptops'],
  },
  processor: {
    names: ['processor', 'cpu', 'chipset', 'chip'],
    title: 'Processor',
    text: 'The **processor** (CPU or chipset) is the brain that runs everything. A faster processor makes apps open quicker, games run smoother and the battery last longer for the same work. Core i5 / Ryzen 5 is mainstream for laptops; Core i7 / Ryzen 7 and up is for heavy work.',
    chips: ['Gaming laptops', 'Explain the specs of a phone'],
  },
  gpu: {
    names: ['gpu', 'graphics card', 'graphics'],
    title: 'GPU',
    text: 'The **GPU** (graphics processor) draws everything you see. It matters most for gaming, video editing and 3D work. Gaming laptops have a dedicated GPU (like NVIDIA RTX); everyday laptops use built-in graphics.',
    chips: ['Gaming laptops'],
  },
  network: {
    names: ['5g', '4g', 'lte', '5g phone'],
    title: '5G',
    text: '**5G** is the newest mobile network: faster downloads and less lag than **4G/LTE**, when you are in an area that has 5G coverage. A 5G phone still works on 4G everywhere else, so it is mainly about being ready for the future.',
    chips: ['Phones', 'Phones under 100k'],
  },
  battery: {
    names: ['mah', 'battery capacity', 'battery mah'],
    title: 'mAh',
    text: '**mAh** (milliamp-hours) is battery capacity: a bigger number usually means longer battery life. Around 4,500-5,000 mAh lasts a full day for most phones, but screen size and processor efficiency matter too.',
    chips: ['Phones with long battery life'],
  },
  refresh: {
    names: ['refresh rate', 'hz', '120hz', '90hz', '144hz'],
    title: 'Refresh rate',
    text: 'The **refresh rate** (in Hz) is how many times per second the screen updates. 60 Hz is standard; 90-120 Hz feels noticeably smoother when scrolling and gaming; 144 Hz+ is for competitive gamers.',
    chips: ['Gaming phones', 'Gaming laptops'],
  },
  display: {
    names: ['amoled', 'oled', 'lcd', 'ips', 'retina'],
    title: 'OLED vs LCD',
    text: '**OLED/AMOLED** screens light each pixel on its own, giving deep blacks, vivid colours and better battery life with dark mode. **LCD/IPS** screens use a backlight: cheaper, good colours, but blacks look greyer. Retina is Apple\'s name for its sharp displays.',
    chips: ['Phones', 'Tablets'],
  },
  camera: {
    names: ['megapixel', 'megapixels', 'mp camera'],
    title: 'Megapixels',
    text: '**Megapixels (MP)** measure how much detail a camera captures. Beyond about 12 MP, the sensor size, lens and software matter more than the number, which is why a 12 MP flagship can beat a 64 MP budget phone.',
    chips: ['Phones with a good camera'],
  },
  water: {
    names: ['ip68', 'ip67', 'ip rating', 'water resistance', 'water resistant', 'waterproof'],
    title: 'IP68',
    text: 'An **IP rating** shows dust and water protection. **IP68** means dust-tight and survives being submerged (usually 1.5-6 m for 30 minutes); **IP67** is about 1 m. It is water *resistance*, not a licence to swim with it, and warranties rarely cover water damage.',
    chips: ['Waterproof phones'],
  },
  ipad: {
    names: ['ipad', 'ipads'],
    title: 'iPad',
    text: 'An **iPad** is Apple\'s brand of tablet. It runs iPadOS and works best alongside an iPhone or Mac.',
    chips: ['Show tablets', 'Apple tablets'],
  },
  tablet: {
    names: ['tablet', 'tablets', 'tab'],
    title: 'Tablet',
    text: 'A **tablet** is a large touch-screen device, bigger than a phone, lighter than a laptop, great for videos, reading, drawing and note-taking.',
    chips: ['Show tablets'],
  },
  laptop: {
    names: ['laptop', 'laptops', 'notebook'],
    title: 'Laptop',
    text: 'A **laptop** is a portable computer with a keyboard, built for typing, multitasking and full desktop apps like programming tools.',
    chips: ['Laptops'],
  },
  smartwatch: {
    names: ['smartwatch', 'smart watch', 'smartwatches'],
    title: 'Smartwatch',
    text: 'A **smartwatch** pairs with your phone to show notifications, track steps, heart rate and workouts, and sometimes take calls. A regular watch just tells time, but often looks more classic and never needs charging.',
    chips: ['Show watches'],
  },
  fragrance: {
    names: ['edp', 'edt', 'eau de parfum', 'eau de toilette', 'cologne', 'parfum'],
    title: 'EDP vs EDT',
    text: '**EDP (eau de parfum)** has more fragrance oil (about 15-20%) so it lasts 6-8 hours; **EDT (eau de toilette)** is lighter (5-15%) and lasts 3-5 hours; **cologne** is lighter still. Pick EDP for evenings and long days, EDT for office and summer.',
    chips: ['Perfumes for her', 'Perfumes for him'],
  },
  spf: {
    names: ['spf', 'sunscreen', 'sunblock'],
    title: 'SPF',
    text: '**SPF** (sun protection factor) shows how well a sunscreen blocks UVB rays. SPF 30 blocks about 97%, SPF 50 about 98%. Reapply every 2-3 hours outdoors whatever the number.',
    chips: ['Skin care'],
  },
  charging: {
    names: ['fast charging', 'wireless charging', 'magsafe', 'watts', 'watt charging'],
    title: 'Fast charging',
    text: '**Fast charging** pushes more power (measured in watts) so a phone fills up in well under an hour; higher watts = faster. **Wireless charging** lets you charge by placing the phone on a pad; it is convenient but slower.',
    chips: ['Chargers', 'Phones with fast charging'],
  },
  bluetooth: {
    names: ['bluetooth', 'nfc', 'wifi 6', 'wi fi'],
    title: 'Connectivity',
    text: '**Bluetooth** connects wireless earbuds, speakers and watches; **NFC** enables tap-to-pay and quick pairing; **Wi-Fi 6** is the newer, faster Wi-Fi standard that handles busy home networks better.',
    chips: ['Earbuds', 'Phones'],
  },
};

// "difference between X and Y" answers for pairs that are not just two definitions side by side
const PAIRS = {
  'ipad|tablet': {
    text: '**iPad** is Apple\'s brand of tablet, so every iPad is a tablet, but not every tablet is an iPad. iPads run iPadOS, get long software support and pair best with an iPhone or Mac; Android tablets like the Samsung Galaxy Tab run Android, often cost less and work well with Google apps.',
    chips: ['Show tablets', 'Tablets under 150k'],
  },
  'laptop|tablet': {
    text: 'A **laptop** has a keyboard and full desktop apps: best for typing, programming and multitasking. A **tablet** is lighter, all touch-screen and lasts longer on battery: best for videos, reading, drawing and notes. Students who write a lot usually prefer a laptop.',
    chips: ['Laptops for students', 'Show tablets'],
  },
  'ram|storage': {
    text: '**RAM** is short-term working memory (how many apps can stay open at once); **storage** is long-term space (how many apps, photos and files you can keep). A phone with 8 GB RAM / 128 GB storage can keep many apps open and store roughly 25,000 photos.',
    chips: ['Phones with 8 GB RAM', 'Laptops'],
  },
  'network|network': {
    text: '**5G** is faster with lower lag than **4G/LTE**, but only where 5G coverage exists; a 5G phone falls back to 4G elsewhere, so it is mostly about being future-ready.',
    chips: ['Phones'],
  },
  'smartwatch|watch': {
    text: 'A **smartwatch** tracks fitness and shows phone notifications but needs charging every day or two; a classic **watch** is about style and craftsmanship and just keeps going.',
    chips: ['Show watches'],
  },
};

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const NAME_INDEX = Object.entries(CONCEPTS)
  .flatMap(([key, c]) => c.names.map((n) => ({ key, name: n, re: new RegExp(`(?:^|\\s)${escape(n)}(?:\\s|$)`) })))
  .sort((a, b) => b.name.length - a.name.length);

const findConcept = (phrase) => {
  const p = ` ${phrase.trim()} `;
  return NAME_INDEX.find((n) => n.re.test(p))?.key || null;
};

const DEFINE_RE = /^(?:so |and |hey |zel )?(?:what(?: is| are|s| does| do)?|whats|meaning of|define|explain(?: what)?|what is meant by)\s+(?:a |an |the )?(.{2,30}?)(?:\s+(?:mean|means|stand for|stands for|in (?:a |my )?(?:phone|phones|laptop|laptops|mobile|perfume)))?\s*\??$/;
const PAIR_RE = /\b(?:difference|differences|diff)\s+(?:between\s+)?(?:an? |the )?(.{2,25}?)\s+(?:and|vs|versus|or)\s+(?:an? |the )?(.{2,25}?)\s*\??$|^(?:an? )?([a-z0-9 ]{2,20}?)\s+(?:vs|versus)\s+(?:an? )?([a-z0-9 ]{2,20}?)\s*\??$/;

// text is the normalized (lower-case) message. returns { key, text, chips, title } or null
const conceptQuery = (text) => {
  const t = String(text || '').trim().replace(/[?!.]+$/, '');
  const pair = t.match(PAIR_RE);
  if (pair) {
    const a = findConcept(pair[1] || pair[3] || '');
    const b = findConcept(pair[2] || pair[4] || '');
    if (a && b) {
      const key = [a, b].sort().join('|');
      const hit = PAIRS[key] || PAIRS[`${b}|${a}`];
      if (hit) return { key, ...hit, title: `${CONCEPTS[a].title} vs ${CONCEPTS[b].title}` };
      if (a !== b) {
        return {
          key, title: `${CONCEPTS[a].title} vs ${CONCEPTS[b].title}`,
          text: `${CONCEPTS[a].text}\n\n${CONCEPTS[b].text}`,
          chips: [...new Set([...CONCEPTS[a].chips, ...CONCEPTS[b].chips])].slice(0, 3),
        };
      }
      return { key: a, ...CONCEPTS[a] };
    }
    return null;
  }
  const def = t.match(DEFINE_RE);
  if (!def) return null;
  // "what is the price of iphone x" is a product question, not a definition
  if (/\b(?:price|cost|warranty|rating|of the|of this|of it|best|cheapest|my|your)\b/.test(def[1])) return null;
  const key = findConcept(def[1]);
  if (!key) return null;
  // the phrase must be about the term itself ("what is a 5g phone"), not a sentence that contains it
  // ("kia ap ke pas laptops hain" -> "what ap ke pas laptops hain" is a product question)
  const name = NAME_INDEX.find((n) => n.key === key && n.re.test(` ${def[1]} `)).name;
  const rest = ` ${def[1]} `.replace(` ${name} `, ' ').trim().split(/\s+/).filter(Boolean);
  if (rest.some((w) => !/^(?:a|an|the|phone|phones|mobile|laptop|laptops|in|on|exactly|actually|really|basically|for|good|card|rating|screen|display|camera|battery|charging)$/.test(w))) return null;
  return { key, ...CONCEPTS[key] };
};

module.exports = { conceptQuery, CONCEPTS, PAIRS, findConcept };
