const app = require('./app');
const db = require('./api/db/connection');

const PORT = Number(process.env.PORT) || 5000;

const start = async () => {
  try {
    await db.raw('select 1');
  } catch (error) {
    console.error('Cannot reach PostgreSQL. Check the DB_* values in backend/.env\n', error.message);
    process.exit(1);
  }
  // 0.0.0.0 so the Android emulator (10.0.2.2) and phones on the same Wi-Fi can connect
  app.listen(PORT, '0.0.0.0', () => console.log(`Cartwise API running on http://localhost:${PORT}/api/v1`));
};

start();
