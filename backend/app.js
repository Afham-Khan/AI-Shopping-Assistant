require('dotenv').config({ quiet: true });

const path = require('path');
const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');
const compression = require('compression');
const modules = require('./api/modules');
const { createCors } = require('./api/middlewares/cors');
const { notFoundHandler, errorHandler } = require('./api/middlewares/errorHandler');

const app = express();

app.disable('x-powered-by');
app.set('trust proxy', 1);
// Flutter web loads images cross-origin, so static files must allow it
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(createCors()); // allowlist from CORS_ORIGINS, see api/middlewares/cors.js
app.use(compression());
app.use(express.json({ limit: '1mb' }));
if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

// only has files after `npm run images:cache` (IMAGE_MODE=local); with IMAGE_MODE=cdn the images are absolute CDN URLs
app.use('/uploads', express.static(path.join(__dirname, 'uploads'), { maxAge: '7d' }));
app.get('/api/v1/health', (req, res) =>
  res.json({ success: true, data: { status: 'ok', time: new Date().toISOString() } }));
app.use('/api/v1', modules);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
