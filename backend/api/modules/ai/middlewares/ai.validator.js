// request validation for the ai endpoints (express-validator schemas)
const multer = require('multer');
const { validate } = require('../../../middlewares/validate');
const { badRequest } = require('../../../../helpers/errors');

const idParam = (name, label = 'id') => ({ [name]: { in: ['params'], isInt: { options: { min: 1 }, errorMessage: `Invalid ${label}` }, toInt: true } });
const limitQuery = (max) => ({ limit: { in: ['query'], optional: true, isInt: { options: { min: 1, max }, errorMessage: `limit must be 1-${max}` }, toInt: true } });

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => (IMAGE_TYPES.has(file.mimetype) ? cb(null, true) : cb(badRequest('Only jpg, png or webp images are allowed'))),
}).single('image');

// multer errors (size, field name) become 400s
const imageUpload = (req, res, next) => upload(req, res, (err) => {
  if (!err) return next();
  if (err.status) return next(err);
  return next(badRequest(err.code === 'LIMIT_FILE_SIZE' ? 'Image must be 5 MB or smaller' : 'Upload a single image in the "image" field'));
});

module.exports = {
  imageUpload,
  chat: validate({
    message: { in: ['body'], isString: { errorMessage: 'message is required' }, trim: true, isLength: { options: { min: 1, max: 500 }, errorMessage: 'message must be 1-500 characters' } },
    conversationId: { in: ['body'], optional: { options: { values: 'null' } }, isInt: { options: { min: 1 }, errorMessage: 'Invalid conversationId' }, toInt: true },
  }),
  conversationId: validate(idParam('id', 'conversation id')),
  feedback: validate({
    ...idParam('id', 'message id'),
    rating: { in: ['body'], isIn: { options: [[1, -1, '1', '-1']], errorMessage: 'rating must be 1 or -1' }, toInt: true },
  }),
  recommendations: validate(limitQuery(30)),
  similar: validate({ ...idParam('productId', 'product id'), ...limitQuery(24) }),
  boughtTogether: validate({ ...idParam('productId', 'product id'), ...limitQuery(24) }),
  reviewSummary: validate(idParam('productId', 'product id')),
  compare: validate({
    productIds: { in: ['body'], isArray: { options: { min: 2, max: 4 }, errorMessage: 'productIds must contain 2-4 ids' } },
    'productIds.*': { in: ['body'], isInt: { options: { min: 1 }, errorMessage: 'productIds must be integers' }, toInt: true },
    need: { in: ['body'], optional: { options: { values: 'null' } }, isString: { errorMessage: 'need must be text' }, trim: true, isLength: { options: { min: 2, max: 200 }, errorMessage: 'need must be 2-200 characters' } },
    differencesOnly: { in: ['body'], optional: true, isBoolean: { options: { strict: true }, errorMessage: 'differencesOnly must be true or false' } },
  }),
  completeLook: validate({ ...idParam('productId', 'product id'), ...limitQuery(12) }),
  explain: validate(idParam('productId', 'product id')),
  gift: validate({
    recipient: { in: ['body'], isString: { errorMessage: 'recipient is required' }, trim: true, isLength: { options: { min: 2, max: 40 }, errorMessage: 'recipient must be 2-40 characters' } },
    occasion: { in: ['body'], optional: { options: { values: 'null' } }, isString: { errorMessage: 'occasion must be text' }, trim: true, isLength: { options: { max: 40 }, errorMessage: 'occasion must be at most 40 characters' } },
    budget: {
      in: ['body'],
      optional: { options: { values: 'null' } },
      custom: {
        options: (b) => (typeof b === 'number' && b >= 100 && b <= 100000000)
          || (b && typeof b === 'object' && !Array.isArray(b) && (b.max === undefined || b.max === null || (Number(b.max) >= 100 && Number(b.max) <= 100000000))
            && (b.min === undefined || b.min === null || Number(b.min) >= 0) && !(b.min && b.max && Number(b.min) > Number(b.max))),
        errorMessage: 'budget must be a number (≥ 100) or { min, max } with min ≤ max',
      },
    },
    interests: { in: ['body'], optional: true, isArray: { options: { max: 8 }, errorMessage: 'interests must be a list of up to 8 items' } },
    'interests.*': { in: ['body'], isString: { errorMessage: 'each interest must be text' }, trim: true, isLength: { options: { min: 2, max: 40 }, errorMessage: 'each interest must be 2-40 characters' } },
    age: { in: ['body'], optional: { options: { values: 'null' } }, isInt: { options: { min: 1, max: 110 }, errorMessage: 'age must be 1-110' }, toInt: true },
    limit: { in: ['body'], optional: true, isInt: { options: { min: 1, max: 20 }, errorMessage: 'limit must be 1-20' }, toInt: true },
  }),
  search: validate({
    q: { in: ['query'], isString: { errorMessage: 'q is required' }, trim: true, isLength: { options: { min: 1, max: 200 }, errorMessage: 'q must be 1-200 characters' } },
    ...limitQuery(60),
  }),
  nlu: validate({
    text: { in: ['body'], isString: { errorMessage: 'text is required' }, trim: true, isLength: { options: { min: 1, max: 500 }, errorMessage: 'text must be 1-500 characters' } },
  }),
  finder: validate({
    department: { in: ['body'], isString: { errorMessage: 'department is required' }, trim: true, notEmpty: { errorMessage: 'department is required' } },
    answers: { in: ['body'], optional: true, isObject: { errorMessage: 'answers must be an object' } },
  }),
  bundle: validate({
    goal: { in: ['body'], isString: { errorMessage: 'goal is required' }, trim: true, isLength: { options: { min: 2, max: 200 }, errorMessage: 'goal must be 2-200 characters' } },
    budget: { in: ['body'], isInt: { options: { min: 500, max: 100000000 }, errorMessage: 'budget must be a number of at least 500' }, toInt: true },
  }),
  ask: validate({
    ...idParam('id', 'product id'),
    question: { in: ['body'], isString: { errorMessage: 'question is required' }, trim: true, isLength: { options: { min: 2, max: 300 }, errorMessage: 'question must be 2-300 characters' } },
  }),
  visual: validate(limitQuery(30)),
  visualText: validate({
    q: { in: ['query'], isString: { errorMessage: 'q is required' }, trim: true, isLength: { options: { min: 2, max: 200 }, errorMessage: 'q must be 2-200 characters' } },
    ...limitQuery(30),
  }),
};
