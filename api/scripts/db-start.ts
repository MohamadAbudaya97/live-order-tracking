import { join } from 'node:path';
import { applyMigrations, startPostgres } from './embedded-postgres';

const PORT = 54329;
const DATA_DIR = join(__dirname, '..', '.pgdata');

async function main(): Promise<void> {
  const postgres = await startPostgres({
    dataDir: DATA_DIR,
    port: PORT,
    persistent: true,
    onLog: (line) => process.stdout.write(line.endsWith('\n') ? line : `${line}\n`),
  });
  applyMigrations(postgres.url);

  console.log(`\nPostgres is ready and migrated.\nDATABASE_URL=${postgres.url}\nCtrl-C stops it.`);

  process.once('SIGINT', () => {
    void postgres.stop().then(() => process.exit(0));
  });
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
