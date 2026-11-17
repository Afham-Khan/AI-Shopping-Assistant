/**
 * Price watches (target price / restock alerts) and a real price history that accumulates from now on.
 * Existing products get one initial history row so every product has a starting point.
 */
exports.up = async (knex) => {
  await knex.schema.createTable('price_watches', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.decimal('target_price', 12, 2); // null = alert on any drop
    t.boolean('notify_restock').notNullable().defaultTo(true);
    t.decimal('initial_price', 12, 2); // price when the watch was created, for "dropped Rs X since"
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.timestamp('last_notified_at');
    t.unique(['user_id', 'product_id']);
    t.index(['product_id']);
  });

  await knex.schema.createTable('price_history', (t) => {
    t.bigIncrements('id').primary();
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.decimal('price', 12, 2).notNullable();
    t.decimal('compare_at_price', 12, 2);
    t.integer('stock');
    t.string('source', 30).notNullable().defaultTo('system'); // seed | admin | demo | system
    t.timestamp('recorded_at').notNullable().defaultTo(knex.fn.now());
    t.index(['product_id', 'recorded_at']);
  });

  await knex.raw(`
    INSERT INTO price_history (product_id, price, compare_at_price, stock, source, recorded_at)
    SELECT p.id, p.price, p.compare_at_price, p.stock, 'seed', p.created_at FROM products p`);

  // swipe feedback (discover deck) is read back per user and type
  await knex.schema.alterTable('user_interactions', (t) => {
    t.index(['user_id', 'type']);
  });
};

exports.down = async (knex) => {
  await knex.schema.alterTable('user_interactions', (t) => {
    t.dropIndex(['user_id', 'type']);
  });
  await knex.schema.dropTableIfExists('price_history');
  await knex.schema.dropTableIfExists('price_watches');
};
