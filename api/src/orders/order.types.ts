import type { Role } from '../auth/role';
import type { OrderStatus } from './order-status';

// These are type aliases rather than interfaces because they are also written to JSONB
// columns, and only an alias is assignable to Prisma's JSON input type.

export type OrderItem = { name: string; quantity: number; unitPrice: number };

export type Place = { lat: number; lng: number; label: string };

export type CourierLocation = { lat: number; lng: number; heading: number | null; at: string };

export type Order = {
  id: string;
  code: string;
  status: OrderStatus;
  version: number;
  customerId: string;
  customerName: string;
  courierId: string | null;
  courierName: string | null;
  items: OrderItem[];
  total: number;
  pickup: Place;
  dropoff: Place;
  courierLocation: CourierLocation | null;
  lastSeq: number;
  createdAt: string;
  updatedAt: string;
};

export type OrderCreated = { order: Order };

export type StatusChanged = {
  from: OrderStatus;
  to: OrderStatus;
  version: number;
  by: { id: string; role: Role; name: string };
  courierId: string | null;
  courierName: string | null;
};

type EventEnvelope = { orderId: string; seq: number; at: string };

export type OrderEvent = EventEnvelope &
  (
    | { type: 'order.created'; data: OrderCreated }
    | { type: 'order.status_changed'; data: StatusChanged }
  );

export type CourierLocationUpdate = CourierLocation & { orderId: string };
