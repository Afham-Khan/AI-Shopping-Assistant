const Orders = require('../models/orders.models');
const OrderService = require('../services/orders.service');
const { ok, created, paginated, parsePagination } = require('../../../../helpers/response');

module.exports.create = async (req, res) => {
  const order = await OrderService.placeOrder(req.userId, req.body);
  return created(res, order, { message: 'Order placed successfully' });
};

module.exports.list = async (req, res) => {
  await OrderService.progressUserOrders(req.userId);
  const { page, limit, offset } = parsePagination(req.query, { defaultLimit: 10, maxLimit: 50 });
  const { rows, total } = await Orders.list(req.userId, { status: req.query.status, limit, offset });
  const items = await Orders.itemsForOrders(rows.map((r) => r.id));
  const data = rows.map((o) => {
    const own = items.filter((i) => i.order_id === o.id);
    return {
      id: o.id,
      orderNumber: o.order_number,
      status: o.status,
      total: o.total,
      itemCount: own.reduce((sum, i) => sum + i.quantity, 0),
      placedAt: o.placed_at,
      previewImages: own.map((i) => i.thumbnail_url).filter(Boolean).slice(0, 3),
    };
  });
  return paginated(res, data, { page, limit, total });
};

module.exports.detail = async (req, res) => ok(res, await OrderService.getDetail(req.userId, req.params.id));

module.exports.cancel = async (req, res) =>
  ok(res, await OrderService.cancel(req.userId, req.params.id), { message: 'Order cancelled' });
