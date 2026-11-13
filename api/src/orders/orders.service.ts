import { Injectable } from '@nestjs/common';
import type { AuthUser } from '../auth/role';
import {
  forbidden,
  forbiddenTransition,
  invalidTransition,
  orderNotFound,
  versionConflict,
} from '../common/api-error';
import { Prisma } from '../prisma-client/client';
import { PrismaService } from '../prisma/prisma.service';
import { newOrderCode } from './order-code';
import { OrderFeed } from './order-feed';
import { ORDER_INCLUDE, toOrder, toOrderEvent } from './order.mapper';
import type { OrderRow } from './order.mapper';
import { findTransition, mayPerform } from './order-status';
import type { OrderStatus } from './order-status';
import type { CourierLocation, Order, OrderEvent, Place, StatusChanged } from './order.types';
import { visibleTo } from './order-visibility';
import { CourierLocationDto, CreateOrderDto, TransitionDto } from './orders.dto';

// The contract has no paging; the cap keeps a single response bounded.
const LIST_LIMIT = 100;

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly feed: OrderFeed,
  ) {}

  async create(
    user: AuthUser,
    idempotencyKey: string,
    dto: CreateOrderDto,
  ): Promise<{ order: Order; created: boolean }> {
    if (user.role !== 'customer') {
      throw forbidden('Only customers place orders');
    }

    const inserted = await this.insert(user.id, idempotencyKey, dto);
    if (inserted) {
      this.feed.events.next(toOrderEvent(inserted.event));
      return { order: toOrder(inserted.row), created: true };
    }
    const first = await this.prisma.order.findUniqueOrThrow({
      where: { customerId_idempotencyKey: { customerId: user.id, idempotencyKey } },
      include: ORDER_INCLUDE,
    });
    return { order: toOrder(first), created: false };
  }

  async list(user: AuthUser, status?: OrderStatus): Promise<Order[]> {
    const rows = await this.prisma.order.findMany({
      where: { AND: [visibleTo(user), { status }] },
      include: ORDER_INCLUDE,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: LIST_LIMIT,
    });
    return rows.map(toOrder);
  }

  async get(id: string, user: AuthUser): Promise<Order> {
    return toOrder(await this.findVisible(id, user));
  }

  async transition(id: string, user: AuthUser, dto: TransitionDto): Promise<Order> {
    const { to, expectedVersion } = dto;
    const current = await this.findVisible(id, user);

    // A stale version is reported before the rules are consulted: the caller decided on
    // an order that has since changed, so the useful answer is the order as it is now.
    if (current.version !== expectedVersion) {
      throw versionConflict(toOrder(current));
    }
    const transition = findTransition(current.status, to);
    if (!transition) {
      throw invalidTransition(current.status, to);
    }
    if (!mayPerform(transition, current, user)) {
      throw forbiddenTransition(current.status, to);
    }

    const now = new Date();
    const written = await this.prisma.$transaction(async (tx) => {
      // The rules above were checked against `expectedVersion`. Putting the version in
      // the WHERE makes the write land only if that is still the row's version, so a
      // concurrent change cannot slip in between the check and the write.
      const { count } = await tx.order.updateMany({
        where: { id, version: expectedVersion },
        data: {
          status: to,
          version: { increment: 1 },
          lastSeq: { increment: 1 },
          updatedAt: now,
          ...(transition.assignsCourier && { courierId: user.id }),
        },
      });
      if (count === 0) {
        return null;
      }
      // The update holds the row lock until commit, so `lastSeq` is this change's seq and
      // nobody else can take it. The (order_id, seq) primary key would refuse a duplicate.
      const row = await tx.order.findUniqueOrThrow({ where: { id }, include: ORDER_INCLUDE });
      const change: StatusChanged = {
        from: current.status,
        to,
        version: row.version,
        by: { id: user.id, role: user.role, name: user.name },
        courierId: row.courierId,
        courierName: row.courier?.name ?? null,
      };
      const event = await tx.orderEvent.create({
        data: {
          orderId: id,
          seq: row.lastSeq,
          type: 'order.status_changed',
          data: change,
          createdAt: now,
        },
      });
      return { row, event };
    });

    if (!written) {
      throw versionConflict(await this.get(id, user));
    }
    this.feed.events.next(toOrderEvent(written.event));
    return toOrder(written.row);
  }

  async updateCourierLocation(id: string, user: AuthUser, dto: CourierLocationDto): Promise<void> {
    const location: CourierLocation = {
      lat: dto.lat,
      lng: dto.lng,
      heading: dto.heading ?? null,
      at: new Date().toISOString(),
    };
    // One conditional write, because this runs every few seconds per delivery: it only
    // matches while the caller is the courier carrying the order.
    const { count } = await this.prisma.order.updateMany({
      where: { id, courierId: user.id, status: 'picked_up' },
      data: { courierLocation: location },
    });
    if (count === 0) {
      throw (await this.exists(id))
        ? forbidden('Only the courier carrying this order may report its position')
        : orderNotFound();
    }
    this.feed.locations.next({ orderId: id, ...location });
  }

  async events(id: string, user: AuthUser, after: number): Promise<OrderEvent[]> {
    await this.findVisible(id, user);
    const rows = await this.prisma.orderEvent.findMany({
      where: { orderId: id, seq: { gt: after } },
      orderBy: { seq: 'asc' },
    });
    return rows.map(toOrderEvent);
  }

  /** Returns null when this customer has already used the key. */
  private async insert(customerId: string, idempotencyKey: string, dto: CreateOrderDto) {
    const now = new Date();
    try {
      return await this.prisma.$transaction(async (tx) => {
        const row = await tx.order.create({
          data: {
            code: newOrderCode(),
            customerId,
            idempotencyKey,
            items: dto.items.map(({ name, quantity, unitPrice }) => ({
              name,
              quantity,
              unitPrice,
            })),
            total: dto.items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0),
            pickup: toPlace(dto.pickup),
            dropoff: toPlace(dto.dropoff),
            createdAt: now,
            updatedAt: now,
          },
          include: ORDER_INCLUDE,
        });
        const event = await tx.orderEvent.create({
          data: {
            orderId: row.id,
            seq: 1,
            type: 'order.created',
            data: { order: toOrder(row) },
            createdAt: now,
          },
        });
        return { row, event };
      });
    } catch (error) {
      // The unique (customer, key) index is what makes a retry safe, also when the retry
      // and the original are in flight together: the one that loses the insert lands here.
      if (isUniqueViolation(error)) {
        return null;
      }
      throw error;
    }
  }

  private async findVisible(id: string, user: AuthUser): Promise<OrderRow> {
    const row = await this.prisma.order.findFirst({
      where: { id, AND: [visibleTo(user)] },
      include: ORDER_INCLUDE,
    });
    if (row) {
      return row;
    }
    throw (await this.exists(id)) ? forbidden() : orderNotFound();
  }

  private async exists(id: string): Promise<boolean> {
    return (await this.prisma.order.count({ where: { id } })) > 0;
  }
}

function toPlace({ lat, lng, label }: Place): Place {
  return { lat, lng, label };
}

function isUniqueViolation(error: unknown): boolean {
  return error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';
}
