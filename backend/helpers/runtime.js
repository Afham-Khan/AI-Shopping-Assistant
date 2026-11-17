// Where the API is running, shared by server.js (a normal long-running process) and api/index.js (Vercel function).

// Vercel sets VERCEL=1 at build and at run time. SERVERLESS=1 lets you force the serverless behaviour elsewhere
// (the local smoke test uses it): small database pool, no index warm-up timer at boot.
const isServerless = (env = process.env) => Boolean(env.VERCEL || env.SERVERLESS === '1' || env.AWS_LAMBDA_FUNCTION_NAME);

// a public API must not sign tokens with missing or placeholder secrets (the ones from .env.example)
const weakSecrets = (env = process.env) => {
  if (env.NODE_ENV !== 'production') return [];
  return ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET']
    .filter((name) => !env[name] || env[name].length < 24 || /^change-me/i.test(env[name]));
};

const weakSecretsMessage = (names) => `NODE_ENV=production needs real secrets: ${names.join(', ')} missing, shorter than 24 characters or still "change-me".\n`
  + 'Make one with:  node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"';

module.exports = { isServerless, weakSecrets, weakSecretsMessage };
