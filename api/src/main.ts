import { existsSync } from 'node:fs';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { AppConfig } from './config/app-config';
import { CorsIoAdapter } from './tracking/cors-io.adapter';

async function bootstrap(): Promise<void> {
  if (existsSync('.env')) {
    process.loadEnvFile('.env');
  }

  const app = await NestFactory.create(AppModule);
  const config = app.get(AppConfig);

  app.enableCors({ origin: config.corsOrigin });
  app.useWebSocketAdapter(new CorsIoAdapter(app, config.corsOrigin));
  app.enableShutdownHooks();

  await app.listen(config.port);
}

void bootstrap();
