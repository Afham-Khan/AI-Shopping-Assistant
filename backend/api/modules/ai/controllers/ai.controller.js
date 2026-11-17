const models = require('../models/ai.models');
const engine = require('../engine');
const { ok } = require('../../../../helpers/response');
const { notFound, badRequest, AppError } = require('../../../../helpers/errors');
const { isMemoryEnabled } = require('../../../../helpers/memory');

const toMessage = (m, { withMeta = true } = {}) => ({
  id: m.id,
  role: m.role,
  content: m.content,
  createdAt: m.created_at,
  ...(withMeta && m.role === 'assistant' ? { meta: m.meta } : {}),
});

const NON_TOPICAL = new Set(['greeting', 'goodbye', 'thanks', 'help', 'small_talk', 'fallback', 'out_of_scope', 'about_assistant', 'feelings', 'abuse', 'store_info', 'concept']);
const fallbackTitle = (text) => {
  const t = text.replace(/\s+/g, ' ').trim();
  return (t.length > 48 ? `${t.slice(0, 47)}…` : t).replace(/^\w/, (c) => c.toUpperCase());
};

module.exports.chat = async (req, res) => {
  const { message, conversationId } = req.body;
  let conversation = conversationId ? await models.findConversation(req.userId, conversationId) : null;
  if (conversationId && !conversation) throw notFound('Conversation not found');
  if (!conversation) conversation = await models.createConversation(req.userId);

  const result = await engine.respond({ text: message, context: conversation.context, userId: req.userId });
  const [userMessage] = await models.insertMessages([{ conversation_id: conversation.id, role: 'user', content: message, meta: {} }]);
  const [assistant] = await models.insertMessages([{ conversation_id: conversation.id, role: 'assistant', content: result.content, meta: result.meta }]);

  const patch = { context: result.context };
  if (conversation.title === 'New chat' && !NON_TOPICAL.has(result.meta.intent)) patch.title = result.title || fallbackTitle(message);
  await models.updateConversation(conversation.id, patch);

  return ok(res, { conversationId: conversation.id, title: patch.title || conversation.title, userMessage: toMessage(userMessage, { withMeta: false }), message: toMessage(assistant) });
};

module.exports.listConversations = async (req, res) => {
  const rows = await models.listConversations(req.userId);
  return ok(res, rows.map((c) => ({ id: c.id, title: c.title, lastMessage: c.last_message, updatedAt: c.updated_at, createdAt: c.created_at })));
};

module.exports.getConversation = async (req, res) => {
  const conversation = await models.findConversation(req.userId, req.params.id);
  if (!conversation) throw notFound('Conversation not found');
  const messages = await models.conversationMessages(conversation.id);
  return ok(res, { id: conversation.id, title: conversation.title, createdAt: conversation.created_at, updatedAt: conversation.updated_at, messages: messages.map((m) => toMessage(m)) });
};

module.exports.deleteConversation = async (req, res) => {
  const deleted = await models.deleteConversation(req.userId, req.params.id);
  if (!deleted) throw notFound('Conversation not found');
  return ok(res, null, { message: 'Conversation deleted' });
};

module.exports.feedback = async (req, res) => {
  const message = await models.findMessageForUser(req.userId, req.params.id);
  if (!message) throw notFound('Message not found');
  if (message.role !== 'assistant') throw badRequest('Feedback is only for assistant messages');
  await models.upsertFeedback(message.id, req.userId, req.body.rating > 0 ? 1 : -1);
  return ok(res, null, { message: 'Thanks for the feedback' });
};

module.exports.recommendations = async (req, res) => ok(res, await engine.recommendations(req.userId, req.query.limit || 10));

module.exports.similar = async (req, res) => {
  const items = await engine.similar(req.params.productId, req.query.limit || 8);
  if (!items) throw notFound('Product not found');
  return ok(res, items);
};

module.exports.boughtTogether = async (req, res) => {
  const items = await engine.boughtTogether(req.params.productId, req.query.limit || 6);
  if (!items) throw notFound('Product not found');
  return ok(res, items);
};

module.exports.compare = async (req, res) => {
  const ids = [...new Set(req.body.productIds)];
  if (ids.length < 2) throw badRequest('Pick at least two different products');
  const result = await engine.compare(ids, { need: req.body.need || null });
  if (!result) throw notFound('Products not found');
  // rows always carry `differs`; differencesOnly drops the rows where every product is the same
  if (req.body.differencesOnly === true) result.rows = result.rows.filter((r) => r.differs);
  return ok(res, result);
};

module.exports.completeLook = async (req, res) => {
  const result = await engine.completeLook(req.params.productId, req.query.limit || 8);
  if (!result) throw notFound('Product not found');
  return ok(res, result);
};

module.exports.explain = async (req, res) => {
  const result = await engine.explain(req.params.productId);
  if (!result) throw notFound('Product not found');
  return ok(res, result);
};

module.exports.gift = async (req, res) => {
  const { recipient, occasion, budget, interests, age, limit } = req.body;
  const result = await engine.gift({
    recipient, occasion, interests: interests || [], age, limit: limit || 8,
    budget: typeof budget === 'number' ? { min: null, max: budget } : budget ? { min: budget.min ?? null, max: budget.max ?? null } : null,
  });
  return ok(res, result);
};

module.exports.reviewSummary = async (req, res) => {
  const result = await engine.reviewSummary(req.params.productId);
  if (!result) throw notFound('Product not found');
  return ok(res, result);
};

module.exports.search = async (req, res) => {
  const result = await engine.smartSearch(req.query.q, { userId: req.userId, limit: req.query.limit || 20 });
  if (req.userId && (await isMemoryEnabled(req.userId))) await models.recordSearch(req.userId, req.query.q, result.total).catch(() => {});
  return ok(res, result);
};

module.exports.nlu = async (req, res) => ok(res, engine.nluPlayground(req.body.text));

module.exports.finderFlows = async (req, res) => ok(res, await engine.finderFlows());

module.exports.finder = async (req, res) => {
  const result = await engine.finder({ department: req.body.department, answers: req.body.answers || {}, userId: req.userId });
  if (!result) throw badRequest('Unknown department');
  return ok(res, result);
};

module.exports.insights = async (req, res) => ok(res, await engine.insights());


module.exports.bundle = async (req, res) => {
  const result = await engine.bundle({ goal: req.body.goal, budget: req.body.budget });
  if (result.error) throw badRequest(result.message);
  return ok(res, result);
};

module.exports.bundleTemplates = async (req, res) => ok(res, await engine.bundleTemplates());

module.exports.askProduct = async (req, res) => {
  const result = await engine.askProduct(req.params.id, req.body.question);
  if (!result) throw notFound('Product not found');
  return ok(res, result);
};

module.exports.cartInsights = async (req, res) => ok(res, await engine.cartInsights(req.userId));

module.exports.profile = async (req, res) => ok(res, await engine.profile(req.userId));

const unavailable = (error) => {
  const err = new AppError(503, error.message);
  err.code = 'VISUAL_UNAVAILABLE';
  return err;
};

module.exports.visualSearch = async (req, res) => {
  if (!req.file) throw badRequest('Upload an image in the "image" field (jpg, png or webp, up to 5 MB)');
  try {
    return ok(res, await engine.visualSearch(req.file.buffer, req.query.limit || 12));
  } catch (error) {
    if (error instanceof engine.VisualUnavailable) throw unavailable(error);
    if (/unsupported|input buffer|image/i.test(error.message)) throw badRequest('That file could not be read as an image');
    throw error;
  }
};

module.exports.visualTextSearch = async (req, res) => {
  try {
    return ok(res, await engine.visualTextSearch(req.query.q, req.query.limit || 12));
  } catch (error) {
    if (error instanceof engine.VisualUnavailable) throw unavailable(error);
    throw error;
  }
};
