import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { ORDER_STATUSES } from './order-status';
import type { OrderStatus } from './order-status';

/** Sequence numbers are stored as a Postgres integer. */
export const MAX_SEQ = 2_147_483_647;

class OrderItemDto {
  @IsString()
  @Length(1, 80)
  name!: string;

  @IsInt()
  @Min(1)
  @Max(50)
  quantity!: number;

  @IsInt()
  @Min(0)
  @Max(1_000_000)
  unitPrice!: number;
}

class CoordinatesDto {
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;
}

class PlaceDto extends CoordinatesDto {
  @IsString()
  @Length(1, 80)
  label!: string;
}

export class CreateOrderDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items!: OrderItemDto[];

  @IsObject()
  @ValidateNested()
  @Type(() => PlaceDto)
  pickup!: PlaceDto;

  @IsObject()
  @ValidateNested()
  @Type(() => PlaceDto)
  dropoff!: PlaceDto;
}

export class TransitionDto {
  @IsIn(ORDER_STATUSES)
  to!: OrderStatus;

  @IsInt()
  @Min(1)
  expectedVersion!: number;
}

export class CourierLocationDto extends CoordinatesDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(359)
  heading?: number | null;
}

export class ListOrdersQuery {
  @IsOptional()
  @IsIn(ORDER_STATUSES)
  status?: OrderStatus;
}

export class EventsQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(MAX_SEQ)
  after = 0;
}
