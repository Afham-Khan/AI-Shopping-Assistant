// one envelope for every endpoint: { success, data, meta?, message? }
module.exports.ok = (res, data, extras = {}) => res.status(200).json({ success: true, data, ...extras });

module.exports.created = (res, data, extras = {}) => res.status(201).json({ success: true, data, ...extras });

module.exports.paginated = (res, data, { page, limit, total, ...rest }) =>
  res.status(200).json({
    success: true,
    data,
    meta: { page, limit, total, totalPages: Math.max(1, Math.ceil(total / limit)), ...rest },
  });

module.exports.parsePagination = (query, { defaultLimit = 20, maxLimit = 60 } = {}) => {
  const page = Math.max(1, Number.parseInt(query.page, 10) || 1);
  const limit = Math.min(maxLimit, Math.max(1, Number.parseInt(query.limit, 10) || defaultLimit));
  return { page, limit, offset: (page - 1) * limit };
};
