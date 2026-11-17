const { types } = require('pg');
const knexConfig = require('../../knexfile');

// NUMERIC and BIGINT come back as strings by default; the API works in numbers
types.setTypeParser(1700, (v) => (v === null ? null : Number.parseFloat(v)));
types.setTypeParser(20, (v) => (v === null ? null : Number.parseInt(v, 10)));

const db = require('knex')(knexConfig);

db.on('error', (err) => console.error('[DB POOL ERROR]', err));

module.exports = db;
