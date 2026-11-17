/* npm run deploy:init
   One-time setup of a HOSTED database (Neon) from your laptop. Safe to run again: every step is idempotent.
     1. migrate    create / update the tables
     2. seed       catalog, demo data and accounts, with IMAGE_MODE=cdn (absolute cdn.dummyjson.com image URLs)
     3. ai:index   product embeddings (MiniLM) and, unless AI_VISUAL=off, the CLIP image index for Snap & Find
   Needs DATABASE_URL in the environment (PowerShell:  $env:DATABASE_URL = "postgresql://...").
   Options:  --skip-visual   skip the CLIP image index (same as AI_VISUAL=off)
             --skip-ai       migrate + seed only                                                              */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const path = require('path');
const { spawnSync } = require('child_process');
const { hostedUrl, describeTarget } = require('../helpers/dbConfig');

const ROOT = path.join(__dirname, '..');
const args = new Set(process.argv.slice(2));
const skipAi = args.has('--skip-ai');
const skipVisual = args.has('--skip-visual') || process.env.AI_VISUAL === 'off';

const fail = (message) => {
  console.error(`\n${message}\n`);
  process.exit(1);
};

if (!hostedUrl(process.env)) {
  fail('DATABASE_URL is not set, so deploy:init has nothing to deploy to.\n'
    + 'Copy the connection string from the Neon dashboard, then in PowerShell run:\n'
    + '  $env:DATABASE_URL = "postgresql://user:password@host/dbname?sslmode=require"\n'
    + '  npm run deploy:init');
}
if (!/^postgres(ql)?:\/\//i.test(hostedUrl(process.env))) fail('DATABASE_URL must start with postgresql://  (copy it again from the Neon dashboard).');

const childEnv = { ...process.env, IMAGE_MODE: 'cdn' };

const run = (label, script, scriptArgs = []) => {
  console.log(`\n=== ${label} ===`);
  const started = Date.now();
  const result = spawnSync(process.execPath, [script, ...scriptArgs], { cwd: ROOT, env: childEnv, stdio: 'inherit' });
  if (result.status !== 0) fail(`Step "${label}" failed (exit code ${result.status}). Fix the error above and run  npm run deploy:init  again, it is safe to repeat.`);
  console.log(`--- ${label} done in ${((Date.now() - started) / 1000).toFixed(1)}s`);
};

const checkConnection = async () => {
  const db = require('../api/db/connection');
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      await db.raw('select 1');
      await db.destroy();
      return;
    } catch (error) {
      if (attempt === 4) {
        await db.destroy().catch(() => {});
        fail(`Could not connect to ${describeTarget()}: ${error.message}\nCheck the connection string (paste it again from the Neon dashboard) and your internet connection.`);
      }
      console.log(`Database is waking up (${error.message}), trying again...`);
      await new Promise((resolve) => { setTimeout(resolve, attempt * 2000); });
    }
  }
};

const main = async () => {
  console.log(`deploy:init -> ${describeTarget()}  (IMAGE_MODE=cdn, ${skipAi ? 'AI index skipped' : skipVisual ? 'CLIP image index skipped' : 'CLIP image index on'})`);
  await checkConnection();
  run('1/3 migrate', require.resolve('knex/bin/cli.js'), ['migrate:latest']);
  run('2/3 seed', path.join(ROOT, 'scripts', 'seed.js'));
  if (skipAi) {
    console.log('\nSkipped the AI index (--skip-ai). Run  npm run ai:index  later: until then search uses the built-in TF-IDF fallback.');
  } else {
    run('3/3 ai:index', path.join(ROOT, 'api', 'modules', 'ai', 'training', 'buildIndex.js'), skipVisual ? ['--skip-visual'] : []);
  }
  console.log('\nDatabase is ready. Next: start the API with this same DATABASE_URL (see docs/DEPLOYMENT.md).');
};

main().catch((error) => fail(error.message));
