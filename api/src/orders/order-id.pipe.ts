import { Injectable, PipeTransform } from '@nestjs/common';
import { isUUID } from 'class-validator';
import { orderNotFound } from '../common/api-error';

@Injectable()
export class OrderIdPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    // An id that is not a UUID cannot name an order; asking Postgres would be a type error.
    if (!isUUID(value)) {
      throw orderNotFound();
    }
    return value;
  }
}
