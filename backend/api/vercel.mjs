// The file Vercel builds (see vercel.json). It only re-exports the handler from ./index.js and declares the
// function settings: Vercel reads `export const config` from the entry's source at build time, which a CommonJS
// file cannot provide, hence this tiny ES module.
//
// maxDuration 60 s: a normal request takes well under a second; the slowest one is the first AI request on a cold
// instance against a sleeping Neon database (database wake-up plus building the TF-IDF catalog index, a few
// seconds). 60 s leaves a wide margin and still stops a stuck request long before the Hobby maximum (300 s).
import handler from './index.js';

export const config = { maxDuration: 60 };

export default handler;
