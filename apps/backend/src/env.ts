// Bun auto-loads .env — no dotenv import needed.

const readString = (key: string, fallback?: string) => {
  const value = process.env[key] ?? fallback;

  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }

  return value;
};

const readOptionalString = (key: string) => {
  const value = process.env[key];
  return value && value.trim() ? value : undefined;
};

const validNodeEnvs = ['development', 'production', 'test'] as const;
type NodeEnv = (typeof validNodeEnvs)[number];

const readNodeEnv = () => {
  const value = readString('NODE_ENV', 'development');

  if (!validNodeEnvs.includes(value as NodeEnv)) {
    throw new Error(`Environment variable NODE_ENV must be one of: ${validNodeEnvs.join(', ')}.`);
  }

  return value as NodeEnv;
};

const readNumber = (key: string, fallback?: number) => {
  const rawValue = process.env[key];

  if (!rawValue) {
    if (fallback === undefined) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
    return fallback;
  }

  const parsedValue = Number(rawValue);

  if (Number.isNaN(parsedValue)) {
    throw new Error(`Environment variable ${key} must be a valid number.`);
  }

  return parsedValue;
};

const validatePort = (key: string, value: number) => {
  if (!Number.isInteger(value) || value < 1 || value > 65_535) {
    throw new Error(`Environment variable ${key} must be an integer between 1 and 65535.`);
  }

  return value;
};

const readPort = (key: string, fallback?: number) => validatePort(key, readNumber(key, fallback));

const readOptionalNumber = (key: string) => {
  const rawValue = readOptionalString(key);

  if (!rawValue) {
    return undefined;
  }

  const parsedValue = Number(rawValue);

  if (Number.isNaN(parsedValue)) {
    throw new Error(`Environment variable ${key} must be a valid number.`);
  }

  return parsedValue;
};

const readOptionalPort = (key: string) => {
  const value = readOptionalNumber(key);
  return value === undefined ? undefined : validatePort(key, value);
};

const databasePassword = readString('MYSQL_PASSWORD', 'parrot_dev_password');
const nodeEnv = readNodeEnv();
const unsafeProductionPasswords = new Set(['parrot_dev_password', 'change-me']);

if (nodeEnv === 'production' && unsafeProductionPasswords.has(databasePassword)) {
  throw new Error(
    'MYSQL_PASSWORD must not use a placeholder or development default in production.',
  );
}

export const env = {
  appName: readString('APP_NAME', 'Parrot'),
  nodeEnv,
  version: readString('VERSION', 'latest'),
  port: readOptionalPort('PORT') ?? readPort('BACKEND_PORT', 26031),
  databaseHost: readString('DATABASE_HOST', '127.0.0.1'),
  databasePort: readPort('DATABASE_PORT', 3306),
  databaseName: readString('MYSQL_DATABASE', 'parrot'),
  databaseUser: readString('MYSQL_USER', 'parrot'),
  databasePassword,
};
