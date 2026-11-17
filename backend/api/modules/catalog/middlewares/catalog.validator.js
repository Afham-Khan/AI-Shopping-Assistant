module.exports.category = {
  slug: { in: ['params'], matches: { options: /^[A-Za-z0-9-]{1,80}$/, errorMessage: 'Invalid category slug' } },
};
