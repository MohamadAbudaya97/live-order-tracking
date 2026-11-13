import { randomUUID } from 'node:crypto';
import type { Order, OrderEvent } from '../src/orders/order.types';
import { Api, ORDER_BODY } from './support/api';
import type { Session } from './support/api';
import { startApp } from './support/app';
import type { RunningApp } from './support/app';

interface ErrorBody {
  statusCode: number;
  code: string;
  message: string;
  current?: Order;
  from?: string;
  to?: string;
}

describe('orders', () => {
  let app: RunningApp;
  let api: Api;
  let customer: Session;
  let store: Session;
  let courier: Session;

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

  const transition = (order: Order, body: object, as: Session) =>
    api.send<ErrorBody>('post', `/orders/${order.id}/transitions`, { as, body });

  describe('the happy path', () => {
    it('takes an order from placed to delivered across the three roles', async () => {
      const placed = await api.placeOrder(customer);
      expect(placed).toMatchObject({
        status: 'placed',
        version: 1,
        lastSeq: 1,
        customerId: customer.user.id,
        customerName: customer.user.name,
        courierId: null,
        courierName: null,
        courierLocation: null,
        total: 2 * 1800 + 700,
        ...ORDER_BODY,
      });
      expect(placed.code).toMatch(/^[2-9A-Z]{4}$/);

      const ready = await api.makeReady(placed, store);
      expect(ready).toMatchObject({ status: 'ready', version: 4, lastSeq: 4, courierId: null });

      const pickedUp = await api.move(ready, 'picked_up', courier);
      expect(pickedUp).toMatchObject({
        status: 'picked_up',
        version: 5,
        courierId: courier.user.id,
        courierName: courier.user.name,
      });

      const position = { lat: 32.225, lng: 35.253, heading: 270 };
      const moved = await api.send('put', `/orders/${placed.id}/courier-location`, {
        as: courier,
        body: position,
      });
      expect(moved.status).toBe(204);
      const onTheWay = await api.getOrder(placed.id, customer);
      expect(onTheWay.courierLocation).toEqual({ ...position, at: expect.any(String) });
      expect(onTheWay.version).toBe(5);

      const delivered = await api.move(pickedUp, 'delivered', courier);
      expect(delivered).toMatchObject({ status: 'delivered', version: 6, lastSeq: 6 });

      const log = await api.send<{ events: OrderEvent[] }>('get', `/orders/${placed.id}/events`, {
        as: customer,
      });
      expect(log.body.events.map((event) => event.seq)).toEqual([1, 2, 3, 4, 5, 6]);
      expect(log.body.events[0]).toEqual({
        orderId: placed.id,
        seq: 1,
        type: 'order.created',
        at: placed.createdAt,
        data: { order: placed },
      });
      expect(log.body.events[4]).toEqual({
        orderId: placed.id,
        seq: 5,
        type: 'order.status_changed',
        at: pickedUp.updatedAt,
        data: {
          from: 'ready',
          to: 'picked_up',
          version: 5,
          by: courier.user,
          courierId: courier.user.id,
          courierName: courier.user.name,
        },
      });

      const tail = await api.send<{ events: OrderEvent[] }>(
        'get',
        `/orders/${placed.id}/events?after=4`,
        { as: store },
      );
      expect(tail.body.events.map((event) => event.seq)).toEqual([5, 6]);
    });
  });

  describe('placing an order', () => {
    const place = (as: Session, key?: string, body: object = ORDER_BODY) =>
      api.send<Order & ErrorBody>('post', '/orders', {
        as,
        body,
        headers: key ? { 'Idempotency-Key': key } : {},
      });

    it('returns the first order when the same key is sent again', async () => {
      const key = randomUUID();

      const first = await place(customer, key);
      const again = await place(customer, key);

      expect(first.status).toBe(201);
      expect(again.status).toBe(200);
      expect(again.body).toEqual(first.body);
    });

    it('creates one order when retries with the same key race each other', async () => {
      const key = randomUUID();

      const replies = await Promise.all(Array.from({ length: 5 }, () => place(customer, key)));

      expect(replies.map((reply) => reply.status).sort()).toEqual([200, 200, 200, 200, 201]);
      expect(new Set(replies.map((reply) => reply.body.id)).size).toBe(1);
      const mine = await api.send<{ orders: Order[] }>('get', '/orders', { as: customer });
      expect(mine.body.orders).toHaveLength(1);
    });

    it('keeps keys apart per customer', async () => {
      const key = randomUUID();
      const someoneElse = await api.login('customer');

      const first = await place(customer, key);
      const second = await place(someoneElse, key);

      expect(second.status).toBe(201);
      expect(second.body.id).not.toBe(first.body.id);
    });

    it('requires the Idempotency-Key header', async () => {
      const reply = await place(customer);

      expect(reply.status).toBe(400);
      expect(reply.body).toMatchObject({ statusCode: 400, code: 'IDEMPOTENCY_KEY_REQUIRED' });
    });

    it.each([
      ['no items', { ...ORDER_BODY, items: [] }],
      [
        'a quantity over 50',
        { ...ORDER_BODY, items: [{ name: 'Tea', quantity: 51, unitPrice: 1 }] },
      ],
      ['a negative price', { ...ORDER_BODY, items: [{ name: 'Tea', quantity: 1, unitPrice: -1 }] }],
      ['a latitude off the map', { ...ORDER_BODY, pickup: { lat: 91, lng: 0, label: 'North' } }],
      ['no drop-off', { items: ORDER_BODY.items, pickup: ORDER_BODY.pickup }],
    ])('rejects %s', async (_case, body) => {
      const reply = await place(customer, randomUUID(), body);

      expect(reply.status).toBe(400);
      expect(reply.body).toEqual({
        statusCode: 400,
        code: 'VALIDATION_FAILED',
        message: expect.any(String),
      });
    });

    it('is for customers only', async () => {
      const reply = await place(store, randomUUID());

      expect(reply.status).toBe(403);
      expect(reply.body.code).toBe('FORBIDDEN');
    });
  });

  describe('transitions', () => {
    it('answers a stale expectedVersion with 409 and the order as it is now', async () => {
      const placed = await api.placeOrder(customer);
      const accepted = await api.move(placed, 'accepted', store);

      const reply = await transition(placed, { to: 'cancelled', expectedVersion: 1 }, customer);

      expect(reply.status).toBe(409);
      expect(reply.body).toEqual({
        statusCode: 409,
        code: 'VERSION_CONFLICT',
        message: expect.any(String),
        current: accepted,
      });
    });

    it('lets exactly one of several concurrent transitions through', async () => {
      const placed = await api.placeOrder(customer);

      const replies = await Promise.all(
        Array.from({ length: 8 }, (_, attempt) =>
          api.send<Order & ErrorBody>('post', `/orders/${placed.id}/transitions`, {
            as: store,
            body: { to: attempt % 2 === 0 ? 'accepted' : 'cancelled', expectedVersion: 1 },
          }),
        ),
      );

      const winners = replies.filter((reply) => reply.status === 200);
      const losers = replies.filter((reply) => reply.status === 409);
      expect(winners).toHaveLength(1);
      expect(losers).toHaveLength(7);

      const stored = await api.getOrder(placed.id, store);
      expect(stored).toEqual(winners[0].body);
      expect(stored.version).toBe(2);
      for (const loser of losers) {
        expect(loser.body).toMatchObject({ code: 'VERSION_CONFLICT', current: stored });
      }

      const log = await api.send<{ events: OrderEvent[] }>('get', `/orders/${placed.id}/events`, {
        as: store,
      });
      expect(log.body.events.map((event) => event.seq)).toEqual([1, 2]);
    });

    it('answers a move the machine does not have with 422, from and to', async () => {
      const placed = await api.placeOrder(customer);

      const reply = await transition(placed, { to: 'ready', expectedVersion: 1 }, store);

      expect(reply.status).toBe(422);
      expect(reply.body).toEqual({
        statusCode: 422,
        code: 'INVALID_TRANSITION',
        message: expect.any(String),
        from: 'placed',
        to: 'ready',
      });
    });

    it('lets nothing move a cancelled order', async () => {
      const placed = await api.placeOrder(customer);
      const cancelled = await api.move(placed, 'cancelled', customer);

      const reply = await transition(cancelled, { to: 'accepted', expectedVersion: 2 }, store);

      expect(reply.status).toBe(422);
      expect(reply.body).toMatchObject({ code: 'INVALID_TRANSITION', from: 'cancelled' });
    });

    it('answers a move that belongs to another role with 403', async () => {
      const placed = await api.placeOrder(customer);
      const asCustomer = await transition(placed, { to: 'accepted', expectedVersion: 1 }, customer);
      expect(asCustomer.status).toBe(403);
      expect(asCustomer.body.code).toBe('FORBIDDEN_TRANSITION');

      const ready = await api.makeReady(placed, store);
      const asStore = await transition(ready, { to: 'picked_up', expectedVersion: 4 }, store);
      expect(asStore.status).toBe(403);
      expect(asStore.body.code).toBe('FORBIDDEN_TRANSITION');

      expect((await api.getOrder(placed.id, store)).version).toBe(4);
    });

    it('stops a customer from cancelling once the kitchen has started', async () => {
      const placed = await api.placeOrder(customer);
      const accepted = await api.move(placed, 'accepted', store);
      const preparing = await api.move(accepted, 'preparing', store);

      const reply = await transition(preparing, { to: 'cancelled', expectedVersion: 3 }, customer);

      expect(reply.status).toBe(403);
      expect(reply.body.code).toBe('FORBIDDEN_TRANSITION');
    });

    it.each([
      ['an unknown status', { to: 'eaten', expectedVersion: 1 }],
      ['no expectedVersion', { to: 'accepted' }],
      ['a fractional expectedVersion', { to: 'accepted', expectedVersion: 1.5 }],
    ])('rejects %s', async (_case, body) => {
      const placed = await api.placeOrder(customer);

      const reply = await transition(placed, body, store);

      expect(reply.status).toBe(400);
      expect(reply.body.code).toBe('VALIDATION_FAILED');
    });
  });

  describe('visibility', () => {
    it('shows a customer only their own orders', async () => {
      const mine = await api.placeOrder(customer);
      const stranger = await api.login('customer');

      const list = await api.send<{ orders: Order[] }>('get', '/orders', { as: stranger });
      expect(list.body.orders).toEqual([]);

      for (const path of [`/orders/${mine.id}`, `/orders/${mine.id}/events`]) {
        const reply = await api.send<ErrorBody>('get', path, { as: stranger });
        expect(reply.status).toBe(403);
        expect(reply.body).toEqual({
          statusCode: 403,
          code: 'FORBIDDEN',
          message: expect.any(String),
        });
      }

      const cancel = await transition(mine, { to: 'cancelled', expectedVersion: 1 }, stranger);
      expect(cancel.status).toBe(403);
      expect(cancel.body.code).toBe('FORBIDDEN');
    });

    it('shows the store every order, newest first, and filters by status', async () => {
      const older = await api.placeOrder(customer);
      const newer = await api.placeOrder(await api.login('customer'));
      await api.move(older, 'accepted', store);

      const all = await api.send<{ orders: Order[] }>('get', '/orders', { as: store });
      const ids = all.body.orders.map((order) => order.id);
      expect(ids).toEqual(expect.arrayContaining([older.id, newer.id]));
      expect(ids.indexOf(newer.id)).toBeLessThan(ids.indexOf(older.id));

      const accepted = await api.send<{ orders: Order[] }>('get', '/orders?status=accepted', {
        as: store,
      });
      const acceptedIds = accepted.body.orders.map((order) => order.id);
      expect(acceptedIds).toContain(older.id);
      expect(acceptedIds).not.toContain(newer.id);
      expect(accepted.body.orders.every((order) => order.status === 'accepted')).toBe(true);
    });

    it('shows a courier the ready orders nobody has taken, plus their own', async () => {
      const rival = await api.login('courier');
      const stillCooking = await api.placeOrder(customer);
      const waiting = await api.makeReady(await api.placeOrder(customer), store);
      const mine = await api.move(
        await api.makeReady(await api.placeOrder(customer), store),
        'picked_up',
        courier,
      );
      const theirs = await api.move(
        await api.makeReady(await api.placeOrder(customer), store),
        'picked_up',
        rival,
      );

      const list = await api.send<{ orders: Order[] }>('get', '/orders', { as: courier });
      const ids = list.body.orders.map((order) => order.id);
      expect(ids).toEqual(expect.arrayContaining([waiting.id, mine.id]));
      expect(ids).not.toContain(stillCooking.id);
      expect(ids).not.toContain(theirs.id);
      for (const order of list.body.orders) {
        expect(order.courierId === courier.user.id || order.status === 'ready').toBe(true);
      }

      expect((await api.send('get', `/orders/${waiting.id}`, { as: courier })).status).toBe(200);
      expect((await api.send('get', `/orders/${mine.id}`, { as: courier })).status).toBe(200);
      for (const hidden of [stillCooking, theirs]) {
        const reply = await api.send<ErrorBody>('get', `/orders/${hidden.id}`, { as: courier });
        expect(reply.status).toBe(403);
        expect(reply.body.code).toBe('FORBIDDEN');
      }
    });

    it('gives a ready order to one of two couriers who grab it at the same moment', async () => {
      const rival = await api.login('courier');
      const ready = await api.makeReady(await api.placeOrder(customer), store);

      const grabs = await Promise.all(
        [courier, rival].map((by) =>
          transition(ready, { to: 'picked_up', expectedVersion: 4 }, by),
        ),
      );

      expect(grabs.map((grab) => grab.status).sort()).toEqual([200, 403]);
      // Not a 409: its `current` would show the loser an order that is no longer theirs to see.
      expect(grabs.find((grab) => grab.status === 403)?.body).toEqual({
        statusCode: 403,
        code: 'FORBIDDEN',
        message: expect.any(String),
      });
      const stored = await api.getOrder(ready.id, store);
      expect(stored.version).toBe(5);
      expect([courier.user.id, rival.user.id]).toContain(stored.courierId);
    });

    it('does not let another courier deliver an order that is being carried', async () => {
      const rival = await api.login('courier');
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      const pickedUp = await api.move(ready, 'picked_up', courier);

      const reply = await transition(pickedUp, { to: 'delivered', expectedVersion: 5 }, rival);

      expect(reply.status).toBe(403);
      expect((await api.getOrder(ready.id, store)).status).toBe('picked_up');
    });

    it('answers 404 for an order that does not exist', async () => {
      for (const id of [randomUUID(), 'not-a-uuid']) {
        const reply = await api.send<ErrorBody>('get', `/orders/${id}`, { as: store });
        expect(reply.status).toBe(404);
        expect(reply.body).toEqual({
          statusCode: 404,
          code: 'ORDER_NOT_FOUND',
          message: expect.any(String),
        });
      }
    });

    it.each([
      ['no token', {}],
      ['a token that was not issued here', { Authorization: 'Bearer not.a.token' }],
      ['another scheme', { Authorization: 'Basic abc' }],
    ])('answers 401 with %s', async (_case, headers) => {
      const reply = await api.send<ErrorBody>('get', '/orders', { headers });

      expect(reply.status).toBe(401);
      expect(reply.body).toEqual({
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: expect.any(String),
      });
    });
  });

  describe('courier location', () => {
    const report = (order: Order, as: Session, body: object = { lat: 32.2, lng: 35.2 }) =>
      api.send<ErrorBody>('put', `/orders/${order.id}/courier-location`, { as, body });

    it('is accepted only from the courier carrying the order, while it is picked up', async () => {
      const rival = await api.login('courier');
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      expect((await report(ready, courier)).status).toBe(403);

      const pickedUp = await api.move(ready, 'picked_up', courier);
      expect((await report(pickedUp, courier)).status).toBe(204);
      for (const other of [rival, store, customer]) {
        const reply = await report(pickedUp, other);
        expect(reply.status).toBe(403);
        expect(reply.body.code).toBe('FORBIDDEN');
      }

      const delivered = await api.move(pickedUp, 'delivered', courier);
      expect((await report(delivered, courier)).status).toBe(403);
    });

    it('keeps only the latest position and treats heading as optional', async () => {
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      const pickedUp = await api.move(ready, 'picked_up', courier);

      await report(pickedUp, courier, { lat: 32.21, lng: 35.21, heading: 90 });
      await report(pickedUp, courier, { lat: 32.22, lng: 35.22 });

      const order = await api.getOrder(pickedUp.id, customer);
      expect(order.courierLocation).toEqual({
        lat: 32.22,
        lng: 35.22,
        heading: null,
        at: expect.any(String),
      });
    });

    it('rejects a heading outside 0–359', async () => {
      const ready = await api.makeReady(await api.placeOrder(customer), store);
      const pickedUp = await api.move(ready, 'picked_up', courier);

      const reply = await report(pickedUp, courier, { lat: 32.2, lng: 35.2, heading: 360 });

      expect(reply.status).toBe(400);
      expect(reply.body.code).toBe('VALIDATION_FAILED');
    });
  });

  describe('the edges of the HTTP surface', () => {
    it('validates the query of the list and of the event log', async () => {
      const placed = await api.placeOrder(customer);

      for (const path of ['/orders?status=eaten', `/orders/${placed.id}/events?after=-1`]) {
        const reply = await api.send<ErrorBody>('get', path, { as: customer });
        expect(reply.status).toBe(400);
        expect(reply.body.code).toBe('VALIDATION_FAILED');
      }
    });

    it('uses the same error shape for a body that is not JSON and for an unknown route', async () => {
      const broken = await api.send<ErrorBody>('post', '/auth/demo-login', {
        body: '{"role": ',
        headers: { 'Content-Type': 'application/json' },
      });
      expect(broken.status).toBe(400);
      expect(broken.body).toEqual({
        statusCode: 400,
        code: 'VALIDATION_FAILED',
        message: expect.any(String),
      });

      const missing = await api.send<ErrorBody>('get', '/nowhere');
      expect(missing.status).toBe(404);
      expect(missing.body).toEqual({
        statusCode: 404,
        code: 'NOT_FOUND',
        message: expect.any(String),
      });
    });

    it('maps the same role and name to the same user, and trims the name', async () => {
      const first = await api.login('customer', 'Lina');
      const again = await api.send<Session>('post', '/auth/demo-login', {
        body: { role: 'customer', name: '  Lina ' },
      });
      const asCourier = await api.login('courier', 'Lina');

      expect(again.status).toBe(201);
      expect(again.body.user).toEqual(first.user);
      expect(asCourier.user.id).not.toBe(first.user.id);

      const blank = await api.send<ErrorBody>('post', '/auth/demo-login', {
        body: { role: 'customer', name: '   ' },
      });
      expect(blank.status).toBe(400);
      expect(blank.body.code).toBe('VALIDATION_FAILED');
    });

    it('reports health without a token', async () => {
      const reply = await api.send('get', '/health');

      expect(reply.status).toBe(200);
      expect(reply.body).toEqual({ status: 'ok' });
    });
  });
});
