import { Prisma } from '../prisma-client/client';
import type { OrderEvent as OrderEventRow } from '../prisma-client/client';
import type { CourierLocation, Order, OrderEvent, OrderItem, Place } from './order.types';

export const ORDER_INCLUDE = {
  customer: { select: { name: true } },
  courier: { select: { name: true } },
} satisfies Prisma.OrderInclude;

export type OrderRow = Prisma.OrderGetPayload<{ include: typeof ORDER_INCLUDE }>;

// The JSON columns are only ever written by this service, from validated input,
// so they are read back as the types they were written from.

export function toOrder(row: OrderRow): Order {
  return {
    id: row.id,
    code: row.code,
    status: row.status,
    version: row.version,
    customerId: row.customerId,
    customerName: row.customer.name,
    courierId: row.courierId,
    courierName: row.courier?.name ?? null,
    items: row.items as OrderItem[],
    total: row.total,
    pickup: row.pickup as Place,
    dropoff: row.dropoff as Place,
    courierLocation: row.courierLocation as CourierLocation | null,
    lastSeq: row.lastSeq,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

export function toOrderEvent(row: OrderEventRow): OrderEvent {
  return {
    orderId: row.orderId,
    seq: row.seq,
    type: row.type,
    at: row.createdAt.toISOString(),
    data: row.data,
  } as OrderEvent;
}
