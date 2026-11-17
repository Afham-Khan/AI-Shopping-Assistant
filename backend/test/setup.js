const path = require('path');

process.env.NODE_ENV = 'test';
require('dotenv').config({ quiet: true, path: path.join(__dirname, '..', '.env') });

const { cleanupTestData, db } = require('./helpers');

exports.mochaHooks = {
  async afterAll() {
    await cleanupTestData();
    await db.destroy();
  },
};
