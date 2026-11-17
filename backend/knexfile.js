require('dotenv').config({ quiet: true });

const { buildConnection, buildPool } = require('./helpers/dbConfig');

// DATABASE_URL (Neon, ...) when set, otherwise the local DB_* values: see helpers/dbConfig.js
module.exports = {
  client: 'pg',
  connection: buildConnection(),
  pool: buildPool(),
  migrations: { directory: './api/db/migrations', tableName: 'knex_migrations' },
  seeds: { directory: './api/db/seeds' },
};
