import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {closeDatabase, db, waitForDatabase} from './client.js';
import {env} from '../env.js';

const currentFile = fileURLToPath(import.meta.url);
const currentDir = path.dirname(currentFile);
const migrationsDir = path.resolve(currentDir, '../../migrations');
const migrationTable = 'parrot_schema_migrations';
const legacyMigrationTable = 'schema_migrations';

type LegacyMigrationRow = {
  name: string;
};

type TableExistsRow = {
  tableExists: number;
};

const encode = (value: string) => encodeURIComponent(value);

const databaseUrl = () => {
  const query = new URLSearchParams({
    multiStatements: 'true',
    'x-migrations-table': migrationTable,
  });

  return `mysql://${encode(env.databaseUser)}:${encode(env.databasePassword)}@tcp(${env.databaseHost}:${env.databasePort})/${encode(env.databaseName)}?${query.toString()}`;
};

const runMigrate = async (args: string[]) => {
  const proc = Bun.spawn(['migrate', '-path', migrationsDir, '-database', databaseUrl(), ...args], {
    stdout: 'inherit',
    stderr: 'inherit',
  });
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    throw new Error(`migrate ${args.join(' ')} failed with exit code ${exitCode}`);
  }
};

const tableExists = async (tableName: string) => {
  const [row] = await db<TableExistsRow[]>`
    SELECT 1 AS tableExists
    FROM information_schema.tables
    WHERE table_schema = ${env.databaseName}
      AND table_name = ${tableName}
    LIMIT 1
  `;

  return Number(row?.tableExists ?? 0) === 1;
};

const latestLegacyVersion = async () => {
  const [row] = await db<LegacyMigrationRow[]>`
    SELECT name
    FROM schema_migrations
    ORDER BY name DESC
    LIMIT 1
  `;

  const match = row?.name.match(/^(\d+)/);
  if (!match) {
    return null;
  }

  return Number(match[1]);
};

const bootstrapLegacyMigrations = async () => {
  const [hasCurrentTable, hasLegacyTable] = await Promise.all([
    tableExists(migrationTable),
    tableExists(legacyMigrationTable),
  ]);

  if (hasCurrentTable || !hasLegacyTable) {
    return;
  }

  const version = await latestLegacyVersion();
  if (!version) {
    return;
  }

  console.log(
    `[migrate] found legacy ${legacyMigrationTable}; forcing ${migrationTable} to ${version}`,
  );
  await runMigrate(['force', String(version)]);
};

const args = Bun.argv.slice(2);
const migrateArgs = args.length > 0 ? args : ['up'];
const shouldBootstrapLegacy = migrateArgs[0] === 'up';

try {
  await waitForDatabase();

  if (shouldBootstrapLegacy) {
    await bootstrapLegacyMigrations();
  }

  await runMigrate(migrateArgs);
} catch (error) {
  console.error('[migrate] failed');
  console.error(error);
  process.exitCode = 1;
} finally {
  await closeDatabase();
}
