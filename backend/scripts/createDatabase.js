require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });
const { Client } = require('pg');
const { usesHostedUrl, describeTarget } = require('../helpers/dbConfig');

const name = process.env.DB_NAME || 'cartwise';

const run = async () => {
  // a hosted database (Neon, ...) already exists and the account cannot create others: nothing to do
  if (usesHostedUrl()) {
    console.log(`DATABASE_URL is set: using the hosted database ${describeTarget()}, skipping CREATE DATABASE`);
    return;
  }
  if (!/^[A-Za-z0-9_]+$/.test(name)) throw new Error(`Refusing unsafe database name "${name}"`);
  // CREATE DATABASE can't run inside the target db, so connect to the maintenance db
  const client = new Client({
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT) || 5432,
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
    database: 'postgres',
  });
  await client.connect();
  try {
    const { rowCount } = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [name]);
    if (rowCount) {
      console.log(`Database "${name}" already exists`);
    } else {
      await client.query(`CREATE DATABASE "${name}" ENCODING 'UTF8'`);
      console.log(`Database "${name}" created`);
    }
  } finally {
    await client.end();
  }
};

run().catch((error) => {
  console.error('Could not create database:', error.message);
  process.exit(1);
});
