const fs = require('fs');
const path = require('path');
const router = require('express').Router();

// every folder in api/modules with a <name>.routes.js is mounted at /<name>
fs.readdirSync(__dirname, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .forEach(({ name }) => {
    const routesFile = path.join(__dirname, name, `${name}.routes.js`);
    if (fs.existsSync(routesFile)) router.use(`/${name}`, require(routesFile));
  });

module.exports = router;
