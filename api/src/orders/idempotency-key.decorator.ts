import { ExecutionContext, createParamDecorator } from '@nestjs/common';
import { isUUID } from 'class-validator';
import type { Request } from 'express';
import { idempotencyKeyRequired, validationFailed } from '../common/api-error';

export const IdempotencyKey = createParamDecorator(
  (_data: unknown, context: ExecutionContext): string => {
    const key = context.switchToHttp().getRequest<Request>().header('idempotency-key');
    if (!key) {
      throw idempotencyKeyRequired();
    }
    if (!isUUID(key)) {
      throw validationFailed('Idempotency-Key must be a UUID');
    }
    return key;
  },
);
