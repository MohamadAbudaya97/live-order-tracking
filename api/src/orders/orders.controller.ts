import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Put,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import type { AuthUser } from '../auth/role';
import { IdempotencyKey } from './idempotency-key.decorator';
import { OrderIdPipe } from './order-id.pipe';
import type { Order, OrderEvent } from './order.types';
import {
  CourierLocationDto,
  CreateOrderDto,
  EventsQuery,
  ListOrdersQuery,
  TransitionDto,
} from './orders.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
@UseGuards(JwtAuthGuard)
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Post()
  async create(
    @CurrentUser() user: AuthUser,
    @IdempotencyKey() idempotencyKey: string,
    @Body() dto: CreateOrderDto,
    @Res({ passthrough: true }) response: Response,
  ): Promise<Order> {
    const { order, created } = await this.orders.create(user, idempotencyKey, dto);
    response.status(created ? HttpStatus.CREATED : HttpStatus.OK);
    return order;
  }

  @Get()
  async list(
    @CurrentUser() user: AuthUser,
    @Query() query: ListOrdersQuery,
  ): Promise<{ orders: Order[] }> {
    return { orders: await this.orders.list(user, query.status) };
  }

  @Get(':id')
  get(@Param('id', OrderIdPipe) id: string, @CurrentUser() user: AuthUser): Promise<Order> {
    return this.orders.get(id, user);
  }

  @Post(':id/transitions')
  @HttpCode(HttpStatus.OK)
  transition(
    @Param('id', OrderIdPipe) id: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: TransitionDto,
  ): Promise<Order> {
    return this.orders.transition(id, user, dto);
  }

  @Put(':id/courier-location')
  @HttpCode(HttpStatus.NO_CONTENT)
  updateCourierLocation(
    @Param('id', OrderIdPipe) id: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: CourierLocationDto,
  ): Promise<void> {
    return this.orders.updateCourierLocation(id, user, dto);
  }

  @Get(':id/events')
  async events(
    @Param('id', OrderIdPipe) id: string,
    @CurrentUser() user: AuthUser,
    @Query() query: EventsQuery,
  ): Promise<{ events: OrderEvent[] }> {
    return { events: await this.orders.events(id, user, query.after) };
  }
}
