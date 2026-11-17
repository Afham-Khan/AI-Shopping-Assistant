require('dotenv').config({ quiet: true });

const path = require('path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const compression = require('compression');
const modules = require('./api/modules');
const { notFoundHandler, errorHandler } = require('./api/middlewares/errorHandler');

const app = express();

app.disable('x-powered-by');
app.set('trust proxy', 1);
// Flutter web loads images cross-origin, so static files must allow it
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors());
app.use(compression());
app.use(express.json({ limit: '1mb' }));
if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

app.use('/uploads', express.static(path.join(__dirname, 'uploads'), { maxAge: '7d' }));
app.get('/api/v1/health', (req, res) =>
  res.json({ success: true, data: { status: 'ok', time: new Date().toISOString() } }));
app.use('/api/v1', modules);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
