module.exports.suggestions = {
  q: {
    in: ['query'],
    isString: { errorMessage: 'q is required' },
    trim: true,
    isLength: { options: { min: 1, max: 100 }, errorMessage: 'q must be 1-100 characters' },
  },
};

module.exports.addHistory = {
  query: {
    in: ['body'],
    isString: { errorMessage: 'query is required' },
    trim: true,
    isLength: { options: { min: 1, max: 200 }, errorMessage: 'query must be 1-200 characters' },
  },
  resultsCount: {
    in: ['body'],
    optional: { options: { values: 'null' } },
    isInt: { options: { min: 0, max: 1000000 }, errorMessage: 'resultsCount must be a non-negative integer' },
    toInt: true,
  },
};
