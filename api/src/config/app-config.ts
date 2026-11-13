export class AppConfig {
  readonly port: number;
  readonly databaseUrl: string;
  readonly jwtSecret: string;
  readonly corsOrigin: string;

  constructor(env: NodeJS.ProcessEnv) {
    this.port = Number(env.PORT ?? 3000);
    this.databaseUrl = required(env, 'DATABASE_URL');
    this.jwtSecret = required(env, 'JWT_SECRET');
    this.corsOrigin = env.CORS_ORIGIN ?? '*';
  }
}

function required(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name];
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}
