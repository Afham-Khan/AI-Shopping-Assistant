const { idParam, pagination } = require('../../../../helpers/validators');

module.exports.list = pagination;
module.exports.id = idParam();
