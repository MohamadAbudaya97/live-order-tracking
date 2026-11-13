import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { Test } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { AppConfig } from '../../src/config/app-config';

export interface RunningApp {
  url: string;
  close(): Promise<void>;
}

/** The real application on a real port, because Socket.IO clients need one to connect to. */
export async function startApp(): Promise<RunningApp> {
  const config = new AppConfig({
    DATABASE_URL: process.env.DATABASE_URL,
    JWT_SECRET: 'e2e-secret',
  });
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(AppConfig)
    .useValue(config)
    .compile();

  const app = moduleRef.createNestApplication();
  await app.listen(0, '127.0.0.1');
  const { port } = (app.getHttpServer() as Server).address() as AddressInfo;

  return { url: `http://127.0.0.1:${port}`, close: () => app.close() };
}
