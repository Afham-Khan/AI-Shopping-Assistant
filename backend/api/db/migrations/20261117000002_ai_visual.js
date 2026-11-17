/**
 * AI visual search: CLIP image embeddings per product (computed by `npm run ai:index`).
 */
exports.up = async (knex) => {
  await knex.schema.createTable('product_image_embeddings', (t) => {
    t.integer('product_id').primary().references('products.id').onDelete('CASCADE');
    t.string('model', 80).notNullable();
    t.integer('dims').notNullable();
    t.specificType('vector', 'real[]').notNullable();
    t.timestamp('updated_at').notNullable().defaultTo(knex.fn.now());
  });
};

exports.down = async (knex) => {
  await knex.schema.dropTableIfExists('product_image_embeddings');
};
