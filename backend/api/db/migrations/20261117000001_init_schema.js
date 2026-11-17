/**
 * Cartwise core schema — single PostgreSQL database for commerce + AI.
 */
exports.up = async (knex) => {
  const ts = (t) => t.timestamps(true, true);

  await knex.schema.createTable('users', (t) => {
    t.increments('id').primary();
    t.string('name', 120).notNullable();
    t.string('email', 190).notNullable().unique();
    t.string('password_hash').notNullable();
    t.string('phone', 30);
    t.string('avatar_url');
    t.string('role', 20).notNullable().defaultTo('customer');
    // interests (category slugs), budget, gender — cold-start signal for the recommender
    t.jsonb('preferences').notNullable().defaultTo('{}');
    t.boolean('is_onboarded').notNullable().defaultTo(false);
    ts(t);
  });

  await knex.schema.createTable('refresh_tokens', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('token_hash', 128).notNullable().unique();
    t.string('user_agent');
    t.timestamp('expires_at').notNullable();
    t.timestamp('revoked_at');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
  });

  await knex.schema.createTable('password_resets', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('otp_hash', 128).notNullable();
    t.integer('attempts').notNullable().defaultTo(0);
    t.timestamp('expires_at').notNullable();
    t.timestamp('used_at');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
  });

  await knex.schema.createTable('addresses', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('label', 40).notNullable().defaultTo('Home');
    t.string('full_name', 120).notNullable();
    t.string('phone', 30).notNullable();
    t.string('line1').notNullable();
    t.string('line2');
    t.string('city', 80).notNullable();
    t.string('province', 80);
    t.string('postal_code', 20);
    t.string('country', 60).notNullable().defaultTo('Pakistan');
    t.boolean('is_default').notNullable().defaultTo(false);
    ts(t);
    t.index(['user_id']);
  });

  await knex.schema.createTable('departments', (t) => {
    t.increments('id').primary();
    t.string('name', 80).notNullable();
    t.string('slug', 80).notNullable().unique();
    t.string('icon', 60);
    t.string('image_url');
    t.text('description');
    t.integer('sort_order').notNullable().defaultTo(0);
  });

  await knex.schema.createTable('categories', (t) => {
    t.increments('id').primary();
    t.integer('department_id').notNullable().references('departments.id').onDelete('CASCADE');
    t.string('name', 80).notNullable();
    t.string('slug', 80).notNullable().unique();
    t.string('image_url');
    t.text('description');
    t.integer('sort_order').notNullable().defaultTo(0);
  });

  await knex.schema.createTable('brands', (t) => {
    t.increments('id').primary();
    t.string('name', 80).notNullable().unique();
    t.string('slug', 80).notNullable().unique();
    t.string('logo_url');
  });

  await knex.schema.createTable('products', (t) => {
    t.increments('id').primary();
    t.integer('external_id');
    t.string('sku', 60).notNullable().unique();
    t.string('title', 200).notNullable();
    t.string('slug', 220).notNullable().unique();
    t.text('description').notNullable().defaultTo('');
    t.integer('category_id').notNullable().references('categories.id');
    t.integer('brand_id').references('brands.id');
    t.decimal('price', 12, 2).notNullable();
    t.decimal('compare_at_price', 12, 2);
    t.decimal('discount_percent', 5, 2).notNullable().defaultTo(0);
    t.string('currency', 3).notNullable().defaultTo('PKR');
    t.decimal('rating', 3, 2).notNullable().defaultTo(0);
    t.integer('rating_count').notNullable().defaultTo(0);
    t.integer('stock').notNullable().defaultTo(0);
    t.string('thumbnail_url');
    t.specificType('tags', 'text[]').notNullable().defaultTo('{}');
    t.specificType('highlights', 'text[]').notNullable().defaultTo('{}');
    t.jsonb('specs').notNullable().defaultTo('{}');
    t.string('gender', 10); // men | women | unisex
    t.string('color', 40);
    t.decimal('weight', 8, 2);
    t.jsonb('dimensions');
    t.string('warranty');
    t.string('shipping_info');
    t.string('return_policy');
    t.text('search_keywords').notNullable().defaultTo('');
    t.boolean('is_featured').notNullable().defaultTo(false);
    t.integer('sold_count').notNullable().defaultTo(0);
    t.integer('view_count').notNullable().defaultTo(0);
    ts(t);
    t.index(['category_id']);
    t.index(['brand_id']);
    t.index(['price']);
  });
  await knex.raw(`
    ALTER TABLE products ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(search_keywords, '')), 'B') ||
      setweight(to_tsvector('english', coalesce(description, '')), 'C')
    ) STORED`);
  await knex.raw('CREATE INDEX products_search_idx ON products USING GIN (search_vector)');

  await knex.schema.createTable('product_images', (t) => {
    t.increments('id').primary();
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.string('url').notNullable();
    t.integer('sort_order').notNullable().defaultTo(0);
    t.index(['product_id']);
  });

  await knex.schema.createTable('reviews', (t) => {
    t.increments('id').primary();
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.smallint('rating').notNullable();
    t.string('title', 150);
    t.text('comment').notNullable();
    t.boolean('is_verified').notNullable().defaultTo(false);
    t.integer('helpful_count').notNullable().defaultTo(0);
    ts(t);
    t.unique(['product_id', 'user_id']);
  });
  await knex.raw('ALTER TABLE reviews ADD CONSTRAINT reviews_rating_check CHECK (rating BETWEEN 1 AND 5)');

  await knex.schema.createTable('wishlist_items', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.unique(['user_id', 'product_id']);
  });

  await knex.schema.createTable('coupons', (t) => {
    t.increments('id').primary();
    t.string('code', 40).notNullable().unique();
    t.string('description').notNullable();
    t.string('discount_type', 10).notNullable(); // percent | fixed
    t.decimal('value', 12, 2).notNullable();
    t.decimal('min_order_amount', 12, 2).notNullable().defaultTo(0);
    t.decimal('max_discount', 12, 2);
    t.timestamp('starts_at');
    t.timestamp('expires_at');
    t.integer('usage_limit');
    t.integer('used_count').notNullable().defaultTo(0);
    t.boolean('is_active').notNullable().defaultTo(true);
  });

  await knex.schema.createTable('carts', (t) => {
    t.integer('user_id').primary().references('users.id').onDelete('CASCADE');
    t.string('coupon_code', 40);
    t.timestamp('updated_at').notNullable().defaultTo(knex.fn.now());
  });

  await knex.schema.createTable('cart_items', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.integer('quantity').notNullable().defaultTo(1);
    ts(t);
    t.unique(['user_id', 'product_id']);
  });

  await knex.schema.createTable('orders', (t) => {
    t.increments('id').primary();
    t.string('order_number', 30).notNullable().unique();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    // placed | confirmed | shipped | out_for_delivery | delivered | cancelled
    t.string('status', 30).notNullable().defaultTo('placed');
    t.string('payment_method', 20).notNullable(); // cod | card
    t.string('payment_status', 20).notNullable().defaultTo('pending'); // pending | paid | refunded
    t.string('card_last4', 4);
    t.decimal('subtotal', 12, 2).notNullable();
    t.decimal('discount', 12, 2).notNullable().defaultTo(0);
    t.decimal('shipping_fee', 12, 2).notNullable().defaultTo(0);
    t.decimal('total', 12, 2).notNullable();
    t.string('coupon_code', 40);
    t.jsonb('shipping_address').notNullable();
    t.text('notes');
    t.timestamp('placed_at').notNullable().defaultTo(knex.fn.now());
    t.timestamp('delivered_at');
    t.timestamp('cancelled_at');
    ts(t);
    t.index(['user_id', 'placed_at']);
  });

  await knex.schema.createTable('order_items', (t) => {
    t.increments('id').primary();
    t.integer('order_id').notNullable().references('orders.id').onDelete('CASCADE');
    t.integer('product_id').references('products.id').onDelete('SET NULL');
    t.string('title', 200).notNullable();
    t.string('thumbnail_url');
    t.decimal('unit_price', 12, 2).notNullable();
    t.integer('quantity').notNullable();
    t.decimal('line_total', 12, 2).notNullable();
    t.index(['order_id']);
    t.index(['product_id']);
  });

  await knex.schema.createTable('order_status_history', (t) => {
    t.increments('id').primary();
    t.integer('order_id').notNullable().references('orders.id').onDelete('CASCADE');
    t.string('status', 30).notNullable();
    t.string('note');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.index(['order_id']);
  });

  await knex.schema.createTable('notifications', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('type', 30).notNullable(); // order | promo | price_drop | system | ai
    t.string('title', 150).notNullable();
    t.text('body').notNullable();
    t.jsonb('data').notNullable().defaultTo('{}');
    t.timestamp('read_at');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.index(['user_id', 'created_at']);
  });

  await knex.schema.createTable('banners', (t) => {
    t.increments('id').primary();
    t.string('title', 120).notNullable();
    t.string('subtitle');
    t.string('image_url');
    t.string('cta_label', 40);
    t.jsonb('target').notNullable().defaultTo('{}'); // { type: 'category'|'department'|'search'|'assistant', value }
    t.string('theme', 20).notNullable().defaultTo('indigo');
    t.integer('sort_order').notNullable().defaultTo(0);
    t.boolean('is_active').notNullable().defaultTo(true);
  });

  // implicit feedback that powers personalization and collaborative filtering
  await knex.schema.createTable('user_interactions', (t) => {
    t.bigIncrements('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.integer('product_id').notNullable().references('products.id').onDelete('CASCADE');
    t.string('type', 30).notNullable(); // view | click | wishlist | cart | purchase | ai_click
    t.string('source', 30);
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.index(['user_id', 'created_at']);
    t.index(['product_id']);
  });

  await knex.schema.createTable('search_history', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('query', 200).notNullable();
    t.integer('results_count').notNullable().defaultTo(0);
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.index(['user_id', 'created_at']);
  });

  await knex.schema.createTable('ai_conversations', (t) => {
    t.increments('id').primary();
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.string('title', 150).notNullable().defaultTo('New chat');
    // dialog state: slots carried across turns (category, budget, brands, features...)
    t.jsonb('context').notNullable().defaultTo('{}');
    ts(t);
    t.index(['user_id', 'updated_at']);
  });

  await knex.schema.createTable('ai_messages', (t) => {
    t.increments('id').primary();
    t.integer('conversation_id').notNullable().references('ai_conversations.id').onDelete('CASCADE');
    t.string('role', 12).notNullable(); // user | assistant
    t.text('content').notNullable();
    t.jsonb('meta').notNullable().defaultTo('{}');
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.index(['conversation_id', 'created_at']);
  });

  await knex.schema.createTable('ai_feedback', (t) => {
    t.increments('id').primary();
    t.integer('message_id').notNullable().references('ai_messages.id').onDelete('CASCADE');
    t.integer('user_id').notNullable().references('users.id').onDelete('CASCADE');
    t.smallint('rating').notNullable(); // 1 | -1
    t.timestamp('created_at').notNullable().defaultTo(knex.fn.now());
    t.unique(['message_id', 'user_id']);
  });

  await knex.schema.createTable('product_embeddings', (t) => {
    t.integer('product_id').primary().references('products.id').onDelete('CASCADE');
    t.string('model', 80).notNullable();
    t.integer('dims').notNullable();
    t.specificType('vector', 'real[]').notNullable();
    t.timestamp('updated_at').notNullable().defaultTo(knex.fn.now());
  });
};

exports.down = async (knex) => {
  const tables = [
    'product_embeddings', 'ai_feedback', 'ai_messages', 'ai_conversations', 'search_history',
    'user_interactions', 'banners', 'notifications', 'order_status_history', 'order_items', 'orders',
    'cart_items', 'carts', 'coupons', 'wishlist_items', 'reviews', 'product_images', 'products',
    'brands', 'categories', 'departments', 'addresses', 'password_resets', 'refresh_tokens', 'users',
  ];
  for (const table of tables) await knex.schema.dropTableIfExists(table);
};
