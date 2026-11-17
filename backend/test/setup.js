const path = require('path');

process.env.NODE_ENV = 'test';
// tests stay offline and never spend the free LLM quota (dotenv won't override this)
process.env.LLM_PROVIDER = 'none';
require('dotenv').config({ quiet: true, path: path.join(__dirname, '..', '.env') });

const { cleanupTestData, db } = require('./helpers');

exports.mochaHooks = {
  async afterAll() {
    await cleanupTestData();
    await db.destroy();
  },
};
