import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';
import { ApiError } from './api-error';

interface ErrorBody {
  statusCode: number;
  code: string;
  message: string;
  [detail: string]: unknown;
}

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const body = this.toBody(exception);
    host.switchToHttp().getResponse<Response>().status(body.statusCode).json(body);
  }

  private toBody(exception: unknown): ErrorBody {
    if (exception instanceof ApiError) {
      const { statusCode, code, message, details } = exception;
      return { statusCode, code, message, ...details };
    }
    if (exception instanceof HttpException) {
      return frameworkError(exception.getStatus(), exception.message);
    }
    this.logger.error(exception);
    return { statusCode: 500, code: 'INTERNAL_ERROR', message: 'Something went wrong' };
  }
}

/** Errors Nest raises on its own: an unknown route, a body that is not JSON. */
function frameworkError(statusCode: number, message: string): ErrorBody {
  const code = statusCode === 400 ? 'VALIDATION_FAILED' : (HttpStatus[statusCode] ?? 'HTTP_ERROR');
  return { statusCode, code, message };
}
