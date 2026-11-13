import { setTimeout as sleep } from 'node:timers/promises';
import { io } from 'socket.io-client';
import type { Socket } from 'socket.io-client';
import type { Order, OrderEvent } from '../../src/orders/order.types';

export type SubscribeAck =
  { ok: true; snapshot: Order; missed: OrderEvent[] } | { ok: false; code: string };

/** Resolves once connected; rejects with the server's `connect_error`. */
export function connect(url: string, token?: string): Promise<Socket> {
  const socket = io(`${url}/tracking`, {
    auth: { token },
    transports: ['websocket'],
    reconnection: false,
    forceNew: true,
  });
  return new Promise((resolve, reject) => {
    socket.once('connect', () => resolve(socket));
    socket.once('connect_error', (error) => {
      socket.close();
      reject(error);
    });
  });
}

export function subscribe(socket: Socket, payload: object): Promise<SubscribeAck> {
  return socket.timeout(5000).emitWithAck('subscribe', payload) as Promise<SubscribeAck>;
}

/** Collects every payload of an event from now on. */
export function record<T>(socket: Socket, event: string): T[] {
  const received: T[] = [];
  socket.on(event, (payload: T) => received.push(payload));
  return received;
}

export async function until(condition: () => boolean, timeoutMs = 3000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!condition()) {
    if (Date.now() > deadline) {
      throw new Error('Timed out waiting for the condition');
    }
    await sleep(10);
  }
}

/** Long enough for anything already on its way to arrive, when the point is that nothing does. */
export const settle = () => sleep(200);
