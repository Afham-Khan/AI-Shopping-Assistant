class AppError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

module.exports = {
  AppError,
  badRequest: (message, errors) => new AppError(400, message, errors),
  unauthorized: (message = 'Authentication required') => new AppError(401, message),
  forbidden: (message = 'You do not have access to this resource') => new AppError(403, message),
  notFound: (message = 'Resource not found') => new AppError(404, message),
  conflict: (message) => new AppError(409, message),
};
