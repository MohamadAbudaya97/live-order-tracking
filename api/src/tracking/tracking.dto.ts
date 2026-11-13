import { plainToInstance } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min, validateSync } from 'class-validator';
import { MAX_SEQ } from '../orders/orders.dto';

export class SubscribeDto {
  @IsUUID()
  orderId!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(MAX_SEQ)
  afterSeq?: number | null;
}

export class UnsubscribeDto {
  @IsUUID()
  orderId!: string;
}

/**
 * Socket payloads are validated by hand: a failure has to come back in the
 * acknowledgement, which a pipe that throws cannot do.
 */
export function parsePayload<T extends object>(type: new () => T, payload: unknown): T | null {
  const dto: unknown = plainToInstance(type, payload);
  return dto instanceof type && validateSync(dto).length === 0 ? dto : null;
}
