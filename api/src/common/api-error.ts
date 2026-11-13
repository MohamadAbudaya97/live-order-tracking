export type ErrorCode =
  | 'VALIDATION_FAILED'
  | 'IDEMPOTENCY_KEY_REQUIRED'
  | 'UNAUTHENTICATED'
  | 'FORBIDDEN'
  | 'FORBIDDEN_TRANSITION'
  | 'ORDER_NOT_FOUND'
  | 'VERSION_CONFLICT'
  | 'INVALID_TRANSITION';

export class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: ErrorCode,
    message: string,
    /** Extra fields the contract puts next to the code, e.g. `current` on a version conflict. */
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

export const validationFailed = (message: string) =>
  new ApiError(400, 'VALIDATION_FAILED', message);

export const idempotencyKeyRequired = () =>
  new ApiError(400, 'IDEMPOTENCY_KEY_REQUIRED', 'The Idempotency-Key header is required');

export const unauthenticated = () =>
  new ApiError(401, 'UNAUTHENTICATED', 'Missing or invalid token');

export const forbidden = (message = 'You may not see this order') =>
  new ApiError(403, 'FORBIDDEN', message);

export const forbiddenTransition = (from: string, to: string) =>
  new ApiError(403, 'FORBIDDEN_TRANSITION', `You may not move this order from ${from} to ${to}`);

export const orderNotFound = () => new ApiError(404, 'ORDER_NOT_FOUND', 'Order not found');

export const versionConflict = (current: object) =>
  new ApiError(409, 'VERSION_CONFLICT', 'Order was changed by someone else', { current });

export const invalidTransition = (from: string, to: string) =>
  new ApiError(422, 'INVALID_TRANSITION', `An order cannot go from ${from} to ${to}`, { from, to });
