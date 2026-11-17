/* Live demo: change a product's price (and optionally stock) and fire price-drop / restock alerts.
   usage: npm run demo:price-drop -- <productId> <newPrice> [--stock <n>]
   e.g.   npm run demo:price-drop -- 160 1999            (wishlisters + watchers get a notification)
          npm run demo:price-drop -- 42 899 --stock 25   (restock + drop) */
require('dotenv').config({ quiet: true, path: require('path').join(__dirname, '..', '.env') });

const db = require('../api/db/connection');
const { applyProductUpdate } = require('../api/modules/alerts/services/priceAlerts.service');

const usage = () => {
  console.log('usage: npm run demo:price-drop -- <productId> <newPrice> [--stock <n>]');
  process.exit(1);
};

const main = async () => {
  const args = process.argv.slice(2);
  const stockFlag = args.indexOf('--stock');
  const stock = stockFlag >= 0 ? Number(args[stockFlag + 1]) : undefined;
  const [idArg, priceArg] = args.filter((a, i) => !(stockFlag >= 0 && (i === stockFlag || i === stockFlag + 1)));
  const productId = Number(idArg);
  const price = priceArg === undefined || priceArg === '-' ? undefined : Number(priceArg);
  if (!Number.isInteger(productId) || productId < 1) usage();
  if (price !== undefined && !(price > 0)) usage();
  if (stock !== undefined && !(Number.isInteger(stock) && stock >= 0)) usage();
  if (price === undefined && stock === undefined) usage();

  const changes = {};
  if (price !== undefined) changes.price = price;
  if (stock !== undefined) changes.stock = stock;
  const result = await applyProductUpdate(productId, changes, { source: 'demo' });
  if (!result) {
    console.error(`Product ${productId} not found`);
    process.exitCode = 1;
    return;
  }
  const { product, changes: diff, alerts } = result;
  console.log(`\n${product.title} (#${product.id})`);
  if (diff.price) console.log(`  price: Rs ${diff.price.from.toLocaleString('en-US')} -> Rs ${diff.price.to.toLocaleString('en-US')}`);
  if (diff.stock) console.log(`  stock: ${diff.stock.from} -> ${diff.stock.to}`);
  if (!diff.price && !diff.stock) console.log('  nothing changed');
  console.log(`  price history recorded: ${result.priceHistoryRecorded ? 'yes' : 'no'}`);
  console.log(`  notifications: ${alerts.notifiedUsers} (price_drop ${alerts.priceDrop}, restock ${alerts.restock})`);
  if (!alerts.notifiedUsers) console.log('  tip: wishlist or watch the product first (POST /alerts/price-watch), then drop the price.');
  console.log('  the app shows the alert on the next notifications refresh.\n');
};

main()
  .then(() => db.destroy())
  .catch(async (error) => {
    console.error('Demo failed:', error.message);
    await db.destroy();
    process.exit(1);
  });
