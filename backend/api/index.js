// Vercel function handler: the whole Express API runs as ONE function. vercel.json builds only api/vercel.mjs (which
// re-exports this file and adds the function settings) and routes every path to it, so the other files under api/
// (modules, db, middlewares) stay plain modules and never become functions of their own.
// Local development does not use this file: `npm run dev` / `npm start` run server.js, which calls app.listen.
//
// Everything at module scope (the Express app, the knex pool, the AI catalog index once built) lives as long as the
// warm instance, so later requests reuse it. There is no app.listen here: Vercel passes (req, res) to the app.
const { weakSecrets, weakSecretsMessage } = require('../helpers/runtime');

const weak = weakSecrets();

if (weak.length) {
  // server.js exits in this case; a function cannot, so it answers every request with a clear 503 instead
  console.error(weakSecretsMessage(weak));
  module.exports = (req, res) => {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ success: false, message: 'Server misconfigured: JWT secrets are missing or too weak.' }));
  };
} else {
  module.exports = require('../app');
}
