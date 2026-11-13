import { randomUUID } from 'node:crypto';
import request from 'supertest';
import type { AuthUser, Role } from '../../src/auth/role';
import type { OrderStatus } from '../../src/orders/order-status';
import type { Order } from '../../src/orders/order.types';

export interface Session {
  token: string;
  user: AuthUser;
}

export interface Reply<T> {
  status: number;
  body: T;
}

interface SendOptions {
  as?: Session;
  body?: string | object;
  headers?: Record<string, string>;
}

export const ORDER_BODY = {
  items: [
    { name: 'Chicken shawarma', quantity: 2, unitPrice: 1800 },
    { name: 'Lemonade', quantity: 1, unitPrice: 700 },
  ],
  pickup: { lat: 32.2227, lng: 35.259, label: 'Old Town Grill' },
  dropoff: { lat: 32.2301, lng: 35.2412, label: 'Home' },
};

export class Api {
  constructor(private readonly url: string) {}

  async send<T = unknown>(
    method: 'get' | 'post' | 'put',
    path: string,
    { as, body, headers = {} }: SendOptions = {},
  ): Promise<Reply<T>> {
    const call = request(this.url)
      [method](path)
      .set({ ...headers, ...(as && { Authorization: `Bearer ${as.token}` }) });
    const response = await (body === undefined ? call : call.send(body));
    return { status: response.status, body: response.body as T };
  }

  /** Every call gets a user of its own unless a name is given, so tests cannot see each other's orders. */
  async login(role: Role, name = `${role}-${randomUUID().slice(0, 8)}`): Promise<Session> {
    const reply = await this.send<Session>('post', '/auth/demo-login', { body: { role, name } });
    return expectStatus(reply, 201);
  }

  async placeOrder(customer: Session): Promise<Order> {
    const reply = await this.send<Order>('post', '/orders', {
      as: customer,
      body: ORDER_BODY,
      headers: { 'Idempotency-Key': randomUUID() },
    });
    return expectStatus(reply, 201);
  }

  async move(order: Order, to: OrderStatus, by: Session): Promise<Order> {
    const reply = await this.send<Order>('post', `/orders/${order.id}/transitions`, {
      as: by,
      body: { to, expectedVersion: order.version },
    });
    return expectStatus(reply, 200);
  }

  async makeReady(order: Order, store: Session): Promise<Order> {
    const accepted = await this.move(order, 'accepted', store);
    const preparing = await this.move(accepted, 'preparing', store);
    return this.move(preparing, 'ready', store);
  }

  async getOrder(id: string, as: Session): Promise<Order> {
    return expectStatus(await this.send<Order>('get', `/orders/${id}`, { as }), 200);
  }
}

function expectStatus<T>(reply: Reply<T>, status: number): T {
  if (reply.status !== status) {
    throw new Error(`Expected ${status}, got ${reply.status}: ${JSON.stringify(reply.body)}`);
  }
  return reply.body;
}
