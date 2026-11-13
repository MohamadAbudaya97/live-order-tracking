import { mkdtempSync } from 'node:fs';
import { createServer } from 'node:net';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { applyMigrations, startPostgres } from '../scripts/embedded-postgres';

declare global {
  var stopTestPostgres: (() => Promise<void>) | undefined;
}

/**
 * With DATABASE_URL set (CI has a Postgres service) the tests use that database.
 * Otherwise they get a throwaway Postgres of their own, so `npm run test:e2e` needs no setup.
 */
export default async function globalSetup(): Promise<void> {
  if (!process.env.DATABASE_URL) {
    const postgres = await startPostgres({
      dataDir: mkdtempSync(join(tmpdir(), 'order-tracking-e2e-')),
      port: await freePort(),
      persistent: false,
    });
    globalThis.stopTestPostgres = postgres.stop;
    // Workers are started after this function returns and inherit the environment.
    process.env.DATABASE_URL = postgres.url;
  }
  applyMigrations(process.env.DATABASE_URL);
}

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, () => {
      const { port } = server.address() as AddressInfo;
      server.close(() => resolve(port));
    });
  });
}
