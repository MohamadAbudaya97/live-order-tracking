import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const USER = 'postgres';
const PASSWORD = 'postgres';
const PROJECT_ROOT = join(__dirname, '..');

export interface PostgresOptions {
  dataDir: string;
  port: number;
  /** Keep the data directory when the server stops. */
  persistent: boolean;
  onLog?: (line: string) => void;
}

export interface RunningPostgres {
  url: string;
  stop: () => Promise<void>;
}

export async function startPostgres(options: PostgresOptions): Promise<RunningPostgres> {
  // Loaded on demand: a run that brings its own database (CI) never needs the package.
  const { default: EmbeddedPostgres } = await import('embedded-postgres');
  const log = options.onLog ?? (() => undefined);
  const postgres = new EmbeddedPostgres({
    databaseDir: options.dataDir,
    port: options.port,
    user: USER,
    password: PASSWORD,
    persistent: options.persistent,
    onLog: log,
    // Postgres writes its ordinary log to stderr, so this is not only errors.
    onError: (line) => log(String(line)),
  });

  // initdb refuses a directory that already holds a cluster.
  if (!existsSync(join(options.dataDir, 'PG_VERSION'))) {
    await postgres.initialise();
  }
  await postgres.start();

  return {
    url: `postgresql://${USER}:${PASSWORD}@localhost:${options.port}/postgres`,
    stop: () => postgres.stop(),
  };
}

/** Quiet on success; a failure throws with what Prisma printed. */
export function applyMigrations(databaseUrl: string): void {
  execFileSync('npx', ['prisma', 'migrate', 'deploy'], {
    cwd: PROJECT_ROOT,
    env: { ...process.env, DATABASE_URL: databaseUrl },
    stdio: 'pipe',
  });
}
