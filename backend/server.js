const app = require('./app');
const db = require('./api/db/connection');
const { describeTarget } = require('./helpers/dbConfig');

const PORT = Number(process.env.PORT) || 5000;
const DB_ATTEMPTS = 5;

const sleep = (ms) => new Promise((resolve) => { setTimeout(resolve, ms); });

// a hosted database that scaled to zero (Neon free tier) needs a few seconds to wake up, so retry before giving up
const waitForDatabase = async () => {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await db.raw('select 1');
      return;
    } catch (error) {
      if (attempt >= DB_ATTEMPTS) {
        console.error(`Cannot reach PostgreSQL at ${describeTarget()}. Check DATABASE_URL (or the DB_* values in backend/.env).\n`, error.message);
        process.exit(1);
      }
      console.warn(`Database not ready (${error.message}), retrying in ${attempt * 2}s (${attempt}/${DB_ATTEMPTS - 1})`);
      await sleep(attempt * 2000);
    }
  }
};

// a public API must not sign tokens with the placeholder secrets from .env.example
const refuseWeakSecrets = () => {
  if (process.env.NODE_ENV !== 'production') return;
  const weak = ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET']
    .filter((name) => !process.env[name] || process.env[name].length < 24 || /^change-me/i.test(process.env[name]));
  if (!weak.length) return;
  console.error(`NODE_ENV=production needs real secrets: ${weak.join(', ')} missing, shorter than 24 characters or still "change-me".\n`
    + 'Make one with:  node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
  process.exit(1);
};

const start = async () => {
  refuseWeakSecrets();
  await waitForDatabase();
  // 0.0.0.0 so the Android emulator (10.0.2.2), phones on the same Wi-Fi, containers and tunnels can connect
  const server = app.listen(PORT, '0.0.0.0', () => console.log(`Cartwise API running on http://localhost:${PORT}/api/v1 (database ${describeTarget()})`));

  // hosts stop a container with SIGTERM: finish open requests, then release the database connections
  const shutdown = () => {
    server.close(() => db.destroy().finally(() => process.exit(0)));
    setTimeout(() => process.exit(0), 8000).unref();
  };
  process.on('SIGTERM', shutdown);
};

start();
