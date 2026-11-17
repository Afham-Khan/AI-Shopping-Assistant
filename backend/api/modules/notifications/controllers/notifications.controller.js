const Notifications = require('../models/notifications.models');
const { ok, paginated, parsePagination } = require('../../../../helpers/response');
const { toNotification } = require('../../../../helpers/serializers');
const { notFound } = require('../../../../helpers/errors');

module.exports.list = async (req, res) => {
  const { page, limit, offset } = parsePagination(req.query);
  const { rows, total, unread } = await Notifications.listByUser(req.userId, { limit, offset });
  return paginated(res, rows.map(toNotification), { page, limit, total, unreadCount: unread });
};

module.exports.unreadCount = async (req, res) => ok(res, { count: await Notifications.unreadCount(req.userId) });

module.exports.markRead = async (req, res) => {
  const notification = await Notifications.findOwned(req.params.id, req.userId);
  if (!notification) throw notFound('Notification not found');
  await Notifications.markRead(notification.id);
  return ok(res, null);
};

module.exports.markAllRead = async (req, res) => {
  await Notifications.markAllRead(req.userId);
  return ok(res, null);
};
