const { idParam, phone } = require('../../../../helpers/validators');

const text = (label, max, { required = false, min = 1 } = {}) => ({
  in: ['body'],
  ...(required ? {} : { optional: { options: { values: 'null' } } }),
  isString: { errorMessage: `${label} must be text` },
  trim: true,
  isLength: { options: { min: required ? min : 0, max }, errorMessage: required ? `${label} is required (max ${max} characters)` : `${label} must be at most ${max} characters` },
});

const isDefault = { in: ['body'], optional: true, isBoolean: { options: { strict: true }, errorMessage: 'isDefault must be true or false' } };

const fields = (required) => ({
  label: text('Label', 40),
  fullName: text('Full name', 120, { required, min: 2 }),
  phone: required ? phone() : phone(true),
  line1: text('Address line 1', 255, { required, min: 3 }),
  line2: text('Address line 2', 255),
  city: text('City', 80, { required, min: 2 }),
  province: text('Province', 80),
  postalCode: { ...text('Postal code', 20), matches: { options: /^[A-Za-z0-9 -]*$/, errorMessage: 'Enter a valid postal code' } },
  country: text('Country', 60),
  isDefault,
});

// on patch, required fields may be omitted but never nulled
const optionalize = (schema) =>
  Object.fromEntries(Object.entries(schema).map(([key, rule]) => [key, { optional: true, ...rule }]));

module.exports.create = fields(true);
module.exports.update = { ...idParam(), ...optionalize(fields(true)) };
module.exports.id = idParam();
