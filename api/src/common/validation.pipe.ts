import { ValidationError, ValidationPipe } from '@nestjs/common';
import { validationFailed } from './api-error';

export function createValidationPipe(): ValidationPipe {
  return new ValidationPipe({
    whitelist: true,
    transform: true,
    exceptionFactory: (errors) => validationFailed(describe(errors).join('; ')),
  });
}

/** Flattens nested errors into messages that carry their path, e.g. "items.0.quantity must not be greater than 50". */
function describe(errors: ValidationError[], parent = ''): string[] {
  return errors.flatMap((error) => [
    ...Object.values(error.constraints ?? {}).map((message) => parent + message),
    ...describe(error.children ?? [], `${parent}${error.property}.`),
  ]);
}
