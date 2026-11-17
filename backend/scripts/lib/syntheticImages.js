// pure-node synthetic "not a product" images for calibrating visual search (scripts/calibrateVisual.js)
// and for tests: a tiny rgb canvas, a png encoder (zlib, no native deps) and generators for note pages,
// printed text, diagrams, scribbles, solid colours, noise, gradients, shapes and checkerboards.
// these only approximate real off-catalog photos (no camera blur, perspective or real handwriting).
const zlib = require('zlib');

// ---- png encoder ----------------------------------------------------------------------------------

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

const crc32 = (buf) => {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};

// rgb: Uint8Array of width*height*3 (8-bit truecolour, no alpha)
const encodePng = (width, height, rgb) => {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  const stride = width * 3;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0; // filter: none
    Buffer.from(rgb.buffer, rgb.byteOffset + y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 6 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
};

// ---- canvas -----------------------------------------------------------------------------------------

const mulberry32 = (seed) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

class Canvas {
  constructor(width, height, bg = [255, 255, 255]) {
    this.width = width;
    this.height = height;
    this.data = new Uint8Array(width * height * 3);
    this.fill(bg);
  }

  fill(c) {
    for (let i = 0; i < this.data.length; i += 3) {
      this.data[i] = c[0];
      this.data[i + 1] = c[1];
      this.data[i + 2] = c[2];
    }
  }

  blend(x, y, c, a = 1) {
    x = Math.round(x);
    y = Math.round(y);
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    const i = (y * this.width + x) * 3;
    for (let k = 0; k < 3; k += 1) this.data[i + k] = Math.round(this.data[i + k] * (1 - a) + c[k] * a);
  }

  rect(x0, y0, w, h, c, a = 1) {
    const x1 = Math.min(this.width, Math.round(x0 + w));
    const y1 = Math.min(this.height, Math.round(y0 + h));
    for (let y = Math.max(0, Math.round(y0)); y < y1; y += 1) for (let x = Math.max(0, Math.round(x0)); x < x1; x += 1) this.blend(x, y, c, a);
  }

  disc(cx, cy, r, c, a = 1) {
    const rr = r * r;
    for (let y = Math.floor(cy - r); y <= Math.ceil(cy + r); y += 1) {
      for (let x = Math.floor(cx - r); x <= Math.ceil(cx + r); x += 1) {
        const d = (x - cx) ** 2 + (y - cy) ** 2;
        if (d <= rr) this.blend(x, y, c, d > rr * 0.6 ? a * 0.6 : a);
      }
    }
  }

  // thick line by stamping discs
  line(x0, y0, x1, y1, w, c, a = 1) {
    const steps = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0) / Math.max(0.5, w / 3)));
    for (let s = 0; s <= steps; s += 1) {
      const t = s / steps;
      this.disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w / 2, c, a);
    }
  }

  polyline(points, w, c, a = 1) {
    for (let i = 1; i < points.length; i += 1) this.line(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], w, c, a);
  }

  // filled polygon via even-odd scanline
  polygon(points, c, a = 1) {
    const ys = points.map((p) => p[1]);
    for (let y = Math.max(0, Math.floor(Math.min(...ys))); y <= Math.min(this.height - 1, Math.ceil(Math.max(...ys))); y += 1) {
      const xs = [];
      for (let i = 0; i < points.length; i += 1) {
        const [ax, ay] = points[i];
        const [bx, by] = points[(i + 1) % points.length];
        if ((ay <= y && by > y) || (by <= y && ay > y)) xs.push(ax + ((y - ay) / (by - ay)) * (bx - ax));
      }
      xs.sort((p, q) => p - q);
      for (let k = 0; k + 1 < xs.length; k += 2) for (let x = Math.ceil(xs[k]); x <= Math.floor(xs[k + 1]); x += 1) this.blend(x, y, c, a);
    }
  }

  png() {
    return encodePng(this.width, this.height, this.data);
  }
}

// ---- helpers ---------------------------------------------------------------------------------------

const pick = (rng, arr) => arr[Math.floor(rng() * arr.length)];
const range = (rng, a, b) => a + rng() * (b - a);
const randColor = (rng) => [Math.floor(rng() * 256), Math.floor(rng() * 256), Math.floor(rng() * 256)];
const PAPERS = [[255, 255, 255], [250, 248, 240], [246, 242, 228], [252, 250, 245], [238, 238, 236]];
const INKS = [[20, 40, 140], [25, 25, 30], [60, 60, 70], [30, 60, 170], [150, 20, 30]];

// photo-ish finish: uneven lighting, a little sensor noise
const photoFinish = (cv, rng, strength = 1) => {
  const gx = range(rng, -0.12, 0.12) * strength;
  const gy = range(rng, -0.12, 0.12) * strength;
  const noise = range(rng, 0, 7) * strength;
  for (let y = 0; y < cv.height; y += 1) {
    for (let x = 0; x < cv.width; x += 1) {
      const shade = 1 + gx * (x / cv.width - 0.5) * 2 + gy * (y / cv.height - 0.5) * 2;
      const i = (y * cv.width + x) * 3;
      const n = (rng() - 0.5) * noise;
      for (let k = 0; k < 3; k += 1) cv.data[i + k] = Math.max(0, Math.min(255, Math.round(cv.data[i + k] * shade + n)));
    }
  }
};

// catmull-rom through control points -> smooth cursive-like curve
const smooth = (pts, per = 6) => {
  if (pts.length < 3) return pts;
  const out = [];
  for (let i = 0; i < pts.length - 1; i += 1) {
    const p0 = pts[Math.max(0, i - 1)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(pts.length - 1, i + 2)];
    for (let k = 0; k < per; k += 1) {
      const t = k / per;
      const t2 = t * t;
      const t3 = t2 * t;
      out.push([0, 1].map((d) => 0.5 * (2 * p1[d] + (-p0[d] + p2[d]) * t + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t2 + (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * t3)));
    }
  }
  out.push(pts[pts.length - 1]);
  return out;
};

// one handwritten-looking word: a connected cursive stroke of loops, ascenders and descenders
const scrawlWord = (cv, rng, x, baseline, xHeight, width, ink, w) => {
  const pts = [];
  let cx = x;
  const slant = range(rng, 0, 0.35) * xHeight;
  while (cx < x + width) {
    const tall = rng() < 0.22 ? range(rng, 1.7, 2.3) : range(rng, 0.85, 1.1);
    const down = rng() < 0.12 ? range(rng, 0.6, 1.0) : 0;
    const step = range(rng, 0.6, 1.0) * xHeight;
    pts.push([cx, baseline + down * xHeight]);
    pts.push([cx + step * 0.25 + slant, baseline - xHeight * tall]);
    pts.push([cx + step * 0.55, baseline - xHeight * range(rng, 0.1, 0.4)]);
    cx += step;
  }
  pts.push([cx, baseline]);
  cv.polyline(smooth(pts), w, ink, 0.9);
};

const paperLines = (cv, rng, kind, spacing, top) => {
  if (kind === 'ruled') {
    for (let y = top; y < cv.height; y += spacing) cv.rect(0, y, cv.width, 1, [150, 180, 220], 0.8);
    if (rng() < 0.7) cv.rect(Math.round(cv.width * 0.12), 0, 1.5, cv.height, [220, 90, 90], 0.8);
  } else if (kind === 'grid') {
    const g = Math.round(spacing / 2);
    for (let y = 0; y < cv.height; y += g) cv.rect(0, y, cv.width, 1, [170, 200, 225], 0.6);
    for (let x = 0; x < cv.width; x += g) cv.rect(x, 0, 1, cv.height, [170, 200, 225], 0.6);
  }
};

// ---- generators ------------------------------------------------------------------------------------

const handwrittenNotes = (rng) => {
  const cv = new Canvas(512, 384, pick(rng, PAPERS));
  const paper = pick(rng, ['ruled', 'ruled', 'grid', 'plain']);
  const spacing = Math.round(range(rng, 18, 30));
  const top = Math.round(range(rng, 20, 50));
  paperLines(cv, rng, paper, spacing, top);
  const ink = pick(rng, INKS);
  const w = range(rng, 1.2, 2.6);
  const left = paper === 'ruled' ? cv.width * 0.14 : range(rng, 12, 40);
  for (let y = top + spacing; y < cv.height - 6; y += spacing) {
    if (rng() < 0.12) continue; // blank line
    let x = left + (rng() < 0.2 ? range(rng, 10, 40) : 0);
    const end = cv.width - range(rng, 10, 120);
    while (x < end) {
      const wordW = range(rng, 14, 70);
      scrawlWord(cv, rng, x, y - 3, spacing * range(rng, 0.25, 0.4), Math.min(wordW, end - x), ink, w);
      x += wordW + range(rng, 6, 14);
    }
    if (rng() < 0.08) cv.line(left, y + 2, left + range(rng, 40, 200), y + 2, w, ink, 0.9); // underline
  }
  photoFinish(cv, rng, rng() < 0.6 ? 1 : 0.3);
  return cv;
};

const printedText = (rng) => {
  const cv = new Canvas(512, 384, pick(rng, PAPERS));
  const ink = rng() < 0.8 ? [25, 25, 25] : pick(rng, INKS);
  const lineH = Math.round(range(rng, 9, 16));
  const glyphH = Math.round(lineH * 0.55);
  const cols = rng() < 0.3 ? 2 : 1;
  const margin = range(rng, 24, 48);
  const colW = (cv.width - margin * 2 - (cols - 1) * 20) / cols;
  let y = margin;
  if (rng() < 0.6) {
    cv.rect(margin, y, range(rng, 120, 300), glyphH * 2, ink, 0.9); // heading
    y += glyphH * 2 + lineH;
  }
  for (; y < cv.height - margin; y += lineH) {
    if (rng() < 0.08) continue; // paragraph break
    for (let c = 0; c < cols; c += 1) {
      let x = margin + c * (colW + 20);
      const end = x + colW * (rng() < 0.1 ? range(rng, 0.3, 0.8) : 1);
      while (x < end) {
        const word = range(rng, 8, 40);
        for (let gx = x; gx < Math.min(end, x + word); gx += glyphH * 0.6) cv.rect(gx, y + (rng() < 0.2 ? -2 : 0), glyphH * 0.45, glyphH + (rng() < 0.2 ? 2 : 0), ink, 0.85);
        x += word + glyphH * 0.6;
      }
    }
  }
  photoFinish(cv, rng, rng() < 0.5 ? 1 : 0.2);
  return cv;
};

// boxes, arrows and labels on paper or a whiteboard (class-notes diagrams)
const diagram = (rng) => {
  const board = rng() < 0.4;
  const cv = new Canvas(512, 384, board ? [235, 237, 238] : pick(rng, PAPERS));
  if (!board) paperLines(cv, rng, pick(rng, ['ruled', 'grid', 'plain']), 24, 30);
  const ink = board ? pick(rng, [[30, 60, 160], [20, 20, 20], [180, 30, 30], [20, 120, 60]]) : pick(rng, INKS);
  const nodes = [];
  for (let i = 0; i < 3 + Math.floor(rng() * 4); i += 1) {
    const x = range(rng, 30, 400);
    const y = range(rng, 30, 300);
    const w = range(rng, 60, 110);
    const h = range(rng, 30, 60);
    nodes.push([x + w / 2, y + h / 2]);
    if (rng() < 0.5) cv.polyline([[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]], 2, ink, 0.9);
    else cv.polyline(Array.from({ length: 49 }, (_, a) => [x + w / 2 + (Math.cos((a / 48) * Math.PI * 2) * w) / 2, y + h / 2 + (Math.sin((a / 48) * Math.PI * 2) * h) / 2]), 2, ink, 0.9);
    scrawlWord(cv, rng, x + 8, y + h / 2 + 4, 7, w - 16, ink, 1.4);
  }
  for (let i = 1; i < nodes.length; i += 1) cv.line(nodes[i - 1][0], nodes[i - 1][1], nodes[i][0], nodes[i][1], 1.8, ink, 0.8);
  photoFinish(cv, rng, 0.8);
  return cv;
};

const scribbles = (rng) => {
  const cv = new Canvas(384, 384, rng() < 0.7 ? pick(rng, PAPERS) : randColor(rng));
  for (let s = 0; s < 2 + Math.floor(rng() * 6); s += 1) {
    const c = rng() < 0.5 ? pick(rng, INKS) : randColor(rng);
    let x = range(rng, 0, 384);
    let y = range(rng, 0, 384);
    let dx = range(rng, -8, 8);
    let dy = range(rng, -8, 8);
    const pts = [[x, y]];
    for (let k = 0; k < 60 + rng() * 140; k += 1) {
      dx = Math.max(-12, Math.min(12, dx + range(rng, -4, 4)));
      dy = Math.max(-12, Math.min(12, dy + range(rng, -4, 4)));
      x = Math.max(0, Math.min(383, x + dx));
      y = Math.max(0, Math.min(383, y + dy));
      pts.push([x, y]);
    }
    cv.polyline(pts, range(rng, 1.5, 6), c, 0.9);
  }
  return cv;
};

const solid = (rng) => {
  const cv = new Canvas(256, 256, rng() < 0.3 ? pick(rng, PAPERS) : randColor(rng));
  photoFinish(cv, rng, rng() < 0.5 ? 0.6 : 0);
  return cv;
};

const noise = (rng) => {
  const cv = new Canvas(256, 256);
  const gray = rng() < 0.4;
  const base = randColor(rng);
  const amp = range(rng, 40, 255);
  for (let i = 0; i < cv.data.length; i += 3) {
    const g = (rng() - 0.5) * amp;
    for (let k = 0; k < 3; k += 1) cv.data[i + k] = Math.max(0, Math.min(255, Math.round((gray ? 128 : base[k]) + (gray ? g : (rng() - 0.5) * amp))));
  }
  return cv;
};

const gradient = (rng) => {
  const cv = new Canvas(256, 256);
  const a = randColor(rng);
  const b = randColor(rng);
  const radial = rng() < 0.4;
  const ang = rng() * Math.PI * 2;
  for (let y = 0; y < 256; y += 1) {
    for (let x = 0; x < 256; x += 1) {
      const t = radial
        ? Math.min(1, Math.hypot(x - 128, y - 128) / 181)
        : Math.max(0, Math.min(1, 0.5 + ((x - 128) * Math.cos(ang) + (y - 128) * Math.sin(ang)) / 256));
      const i = (y * 256 + x) * 3;
      for (let k = 0; k < 3; k += 1) cv.data[i + k] = Math.round(a[k] * (1 - t) + b[k] * t);
    }
  }
  return cv;
};

const shapes = (rng) => {
  const cv = new Canvas(320, 320, rng() < 0.5 ? [255, 255, 255] : randColor(rng));
  for (let s = 0; s < 1 + Math.floor(rng() * 7); s += 1) {
    const c = randColor(rng);
    const x = range(rng, 20, 300);
    const y = range(rng, 20, 300);
    const r = range(rng, 12, 90);
    const kind = Math.floor(rng() * 3);
    if (kind === 0) cv.disc(x, y, r, c);
    else if (kind === 1) cv.rect(x - r, y - r * range(rng, 0.4, 1), r * 2, r * 2 * range(rng, 0.4, 1), c);
    else cv.polygon([[x, y - r], [x + r, y + r], [x - r, y + r]], c);
  }
  return cv;
};

const checkerboard = (rng) => {
  const cv = new Canvas(256, 256);
  const a = rng() < 0.5 ? [0, 0, 0] : randColor(rng);
  const b = rng() < 0.5 ? [255, 255, 255] : randColor(rng);
  const size = Math.round(range(rng, 8, 64));
  for (let y = 0; y < 256; y += 1) {
    for (let x = 0; x < 256; x += 1) {
      const c = (Math.floor(x / size) + Math.floor(y / size)) % 2 ? a : b;
      const i = (y * 256 + x) * 3;
      cv.data[i] = c[0];
      cv.data[i + 1] = c[1];
      cv.data[i + 2] = c[2];
    }
  }
  return cv;
};

const GENERATORS = { handwrittenNotes, printedText, diagram, scribbles, solid, noise, gradient, shapes, checkerboard };

// default mix: weighted towards the reported failure (pages of notes / text)
const DEFAULT_COUNTS = { handwrittenNotes: 60, printedText: 30, diagram: 20, scribbles: 25, solid: 20, noise: 15, gradient: 20, shapes: 25, checkerboard: 15 };

// [{ kind, seed, png: Buffer }]
const generateNegatives = ({ counts = DEFAULT_COUNTS, seed = 1234 } = {}) => {
  const out = [];
  let n = 0;
  for (const [kind, count] of Object.entries(counts)) {
    for (let i = 0; i < count; i += 1) {
      n += 1;
      const s = seed * 1000 + n;
      out.push({ kind, seed: s, png: GENERATORS[kind](mulberry32(s)).png() });
    }
  }
  return out;
};

module.exports = { encodePng, crc32, Canvas, mulberry32, GENERATORS, DEFAULT_COUNTS, generateNegatives };
