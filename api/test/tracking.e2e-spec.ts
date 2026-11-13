import { randomUUID } from 'node:crypto';
import type { Socket } from 'socket.io-client';
import type { CourierLocationUpdate, Order, OrderEvent } from '../src/orders/order.types';
import { Api } from './support/api';
import type { Session } from './support/api';
import { startApp } from './support/app';
import type { RunningApp } from './support/app';
import { connect, record, settle, subscribe, until } from './support/socket';

describe('tracking socket', () => {
  let app: RunningApp;
  let api: Api;
  let customer: Session;
  let store: Session;
  let courier: Session;
  const sockets: Socket[] = [];

  const open = async (session: Session): Promise<Socket> => {
    const socket = await connect(app.url, session.token);
    sockets.push(socket);
    return socket;
  };

  beforeAll(async () => {
    app = await startApp();
    api = new Api(app.url);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    [customer, store, courier] = await Promise.all([
      api.login('customer'),
      api.login('store'),
      api.login('courier'),
    ]);
  });

  afterEach(() => {
    for (const socket of sockets.splice(0)) {
      socket.close();
    }
  });

  describe('connecting', () => {
    it.each([
      ['no token', undefined],
      ['a token that was not issued here', 'not.a.token'],
    ])('refuses %s with UNAUTHENTICATED', async (_case, token) => {
      await expect(connect(app.url, token)).rejects.toThrow('UNAUTHENTICATED');
    });
  });

  describe('subscribe', () => {
    it('acknowledges with the order as it is now and nothing missed', async () => {
      const order = await api.makeReady(await api.placeOrder(customer), store);
      const socket = await open(customer);

      const ack = await subscribe(socket, { orderId: order.id });

      expect(ack).toEqual({ ok: true, snapshot: order, missed: [] });
    });

    it('lets a client that was offline catch up with afterSeq and carry on live', async () => {
      const order = await api.placeOrder(customer);
      const before = await open(customer);
      await subscribe(before, { orderId: order.id });
      const seenBefore = record<OrderEvent>(before, 'order.event');
      const accepted = await api.move(order, 'accepted', store);
      await until(() => seenBefore.length === 1);
      before.close();

      const preparing = await api.move(accepted, 'preparing', store);
      const ready = await api.move(preparing, 'ready', store);

      const after = await open(customer);
      const seenAfter = record<OrderEvent>(after, 'order.event');
      const ack = await subscribe(after, { orderId: order.id, afterSeq: seenBefore[0].seq });
      const log = await api.send<{ events: OrderEvent[] }>(
        'get',
        `/orders/${order.id}/events?after=2`,
        { as: customer },
      );
      expect(ack).toEqual({ ok: true, snapshot: ready, missed: log.body.events });
      expect(log.body.events.map((event) => event.seq)).toEqual([3, 4]);

      await api.move(ready, 'picked_up', courier);
      await until(() => seenAfter.length === 1);
      expect(seenAfter[0].seq).toBe(5);
    });

    it('replays nothing to a client that is up to date', async () => {
      const order = await api.makeReady(await api.placeOrder(customer), store);
      const socket = await open(customer);

      const ack = await subscribe(socket, { orderId: order.id, afterSeq: order.lastSeq });

      expect(ack).toEqual({ ok: true, snapshot: order, missed: [] });
    });

    it('applies the visibility rules of GET /orders/:id', async () => {
      const order = await api.placeOrder(customer);
      const stranger = await open(await api.login('customer'));
      const waitingCourier = await open(courier);

      expect(await subscribe(stranger, { orderId: order.id })).toEqual({
        ok: false,
        code: 'FORBIDDEN',
      });
      expect(await subscribe(waitingCourier, { orderId: order.id })).toEqual({
        ok: false,
        code: 'FORBIDDEN',
      });

      const strangerEvents = record<OrderEvent>(stranger, 'order.event');
      await api.move(order, 'accepted', store);
      await settle();
      expect(strangerEvents).toEqual([]);
    });

    it('acknowledges an unknown order and a malformed request with their codes', async () => {
      const socket = await open(customer);

      expect(await subscribe(socket, { orderId: randomUUID() })).toEqual({
        ok: false,
        code: 'ORDER_NOT_FOUND',
      });
      for (const payload of [
        {},
        { orderId: 'not-a-uuid' },
        { orderId: randomUUID(), afterSeq: -1 },
      ]) {
        expect(await subscribe(socket, payload)).toEqual({ ok: false, code: 'VALIDATION_FAILED' });
      }
    });
  });

  describe('order.event', () => {
    it('reaches every subscriber of the order, in seq order, as it is stored', async () => {
      const order = await api.placeOrder(customer);
      const customerSocket = await open(customer);
      const storeSocket = await open(store);
      await subscribe(customerSocket, { orderId: order.id });
      await subscribe(storeSocket, { orderId: order.id });
      const seenByCustomer = record<OrderEvent>(customerSocket, 'order.event');
      const seenByStore = record<OrderEvent>(storeSocket, 'order.event');

      const ready = await api.makeReady(order, store);
      await until(() => seenByCustomer.length === 3 && seenByStore.length === 3);

      expect(seenByCustomer.map((event) => event.seq)).toEqual([2, 3, 4]);
      expect(seenByCustomer[2]).toEqual({
        orderId: order.id,
        seq: 4,
        type: 'order.status_changed',
        at: ready.updatedAt,
        data: {
          from: 'preparing',
          to: 'ready',
          version: 4,
          by: store.user,
          courierId: null,
          courierName: null,
        },
      });
      expect(seenByStore).toEqual(seenByCustomer);

      const log = await api.send<{ events: OrderEvent[] }>(
        'get',
        `/orders/${order.id}/events?after=1`,
        { as: customer },
      );
      expect(seenByCustomer).toEqual(log.body.events);
    });

    it('is not sent for a transition that was refused', async () => {
      const order = await api.placeOrder(customer);
      const socket = await open(customer);
      await subscribe(socket, { orderId: order.id });
      const events = record<OrderEvent>(socket, 'order.event');

      await api.send('post', `/orders/${order.id}/transitions`, {
        as: store,
        body: { to: 'ready', expectedVersion: 1 },
      });
      await api.send('post', `/orders/${order.id}/transitions`, {
        as: store,
        body: { to: 'accepted', expectedVersion: 7 },
      });
      await settle();

      expect(events).toEqual([]);
    });

    it('keeps other orders out of a subscription', async () => {
      const watched = await api.placeOrder(customer);
      const other = await api.placeOrder(customer);
      const socket = await open(customer);
      await subscribe(socket, { orderId: watched.id });
      const events = record<OrderEvent>(socket, 'order.event');

      await api.move(other, 'accepted', store);
      await api.move(watched, 'accepted', store);
      await until(() => events.length > 0);
      await settle();

      expect(events.map((event) => event.orderId)).toEqual([watched.id]);
    });

    it('stops after unsubscribe', async () => {
      const order = await api.placeOrder(customer);
      const socket = await open(customer);
      await subscribe(socket, { orderId: order.id });
      const events = record<OrderEvent>(socket, 'order.event');

      const accepted = await api.move(order, 'accepted', store);
      await until(() => events.length === 1);
      const ack: unknown = await socket.emitWithAck('unsubscribe', { orderId: order.id });
      await api.move(accepted, 'preparing', store);
      await settle();

      expect(ack).toEqual({ ok: true });
      expect(events.map((event) => event.seq)).toEqual([2]);
    });

    it('tells a waiting courier that someone else took the order, then stops', async () => {
      const rival = await api.login('courier');
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      const waiting = await open(courier);
      await subscribe(waiting, { orderId: ready.id });
      const events = record<OrderEvent>(waiting, 'order.event');
      const locations = record<CourierLocationUpdate>(waiting, 'courier.location');

      const pickedUp = await api.move(ready, 'picked_up', rival);
      await until(() => events.length === 1);
      await api.send('put', `/orders/${ready.id}/courier-location`, {
        as: rival,
        body: { lat: 32.2, lng: 35.2 },
      });
      await api.move(pickedUp, 'delivered', rival);
      await settle();

      expect(events).toHaveLength(1);
      expect(events[0].data).toMatchObject({ to: 'picked_up', courierId: rival.user.id });
      expect(locations).toEqual([]);
    });
  });

  describe('courier.location', () => {
    const pickedUpOrder = async (): Promise<Order> => {
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      return api.move(ready, 'picked_up', courier);
    };

    const report = (order: Order, lat: number) =>
      api.send('put', `/orders/${order.id}/courier-location`, {
        as: courier,
        body: { lat, lng: 35.25, heading: 90 },
      });

    it('carries the position to the subscribers of the order', async () => {
      const order = await pickedUpOrder();
      const socket = await open(customer);
      await subscribe(socket, { orderId: order.id });
      const locations = record<CourierLocationUpdate>(socket, 'courier.location');

      await report(order, 32.21);
      await until(() => locations.length === 1);

      expect(locations[0]).toEqual({
        orderId: order.id,
        lat: 32.21,
        lng: 35.25,
        heading: 90,
        at: expect.any(String),
      });
      expect((await api.getOrder(order.id, customer)).courierLocation?.at).toBe(locations[0].at);
    });

    it('sends the first of a burst at once and the latest a second later', async () => {
      const order = await pickedUpOrder();
      const socket = await open(customer);
      await subscribe(socket, { orderId: order.id });
      const locations = record<CourierLocationUpdate>(socket, 'courier.location');
      const arrivals: number[] = [];
      socket.on('courier.location', () => arrivals.push(Date.now()));

      for (const lat of [32.21, 32.22, 32.23, 32.24]) {
        await report(order, lat);
      }
      await until(() => locations.length === 2);

      expect(locations.map((location) => location.lat)).toEqual([32.21, 32.24]);
      expect(arrivals[1] - arrivals[0]).toBeGreaterThanOrEqual(900);
      expect((await api.getOrder(order.id, customer)).courierLocation?.lat).toBe(32.24);
    });

    it('does not make one order wait for another', async () => {
      const [first, second] = [await pickedUpOrder(), await pickedUpOrder()];
      const socket = await open(customer);
      await subscribe(socket, { orderId: first.id });
      await subscribe(socket, { orderId: second.id });
      const locations = record<CourierLocationUpdate>(socket, 'courier.location');

      await report(first, 32.21);
      await report(second, 32.31);
      await until(() => locations.length === 2, 500);

      expect(locations.map((location) => location.orderId)).toEqual([first.id, second.id]);
    });
  });
});
