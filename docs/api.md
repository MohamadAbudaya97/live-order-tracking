# API contract

Everything the app and the API agree on lives here. If the two ever disagree, this file is right.

- Base URL in development: `http://localhost:3000`
- JSON in, JSON out. Timestamps are ISO 8601 strings in UTC.
- Money is an integer in minor units (cents). There is one currency, so no currency field.
- Authenticated routes take `Authorization: Bearer <token>`.

## Roles

`customer`, `store`, `courier`. One store exists in this demo, so a store user sees every order.

## Errors

```json
{ "statusCode": 409, "code": "VERSION_CONFLICT", "message": "Order was changed by someone else" }
```

`code` is stable and meant for the client; `message` is for humans.

| Status | code | When |
| --- | --- | --- |
| 400 | `VALIDATION_FAILED` | body or query does not validate |
| 400 | `IDEMPOTENCY_KEY_REQUIRED` | `POST /orders` without the header |
| 401 | `UNAUTHENTICATED` | missing or bad token |
| 403 | `FORBIDDEN` | the caller may not see this order |
| 403 | `FORBIDDEN_TRANSITION` | the transition exists but not for this role / courier |
| 404 | `ORDER_NOT_FOUND` | also when the id is not a UUID |
| 404 | `NOT_FOUND` | unknown route |
| 409 | `VERSION_CONFLICT` | `expectedVersion` is stale; the body also carries `current` (the order as it is now) |
| 422 | `INVALID_TRANSITION` | no such transition from the current status; body also carries `from` and `to` |
| 500 | `INTERNAL_ERROR` | anything unexpected |

## Auth

### `POST /auth/demo-login`

Demo only: there are no passwords. The same `(role, name)` always maps to the same user.

```json
{ "role": "customer", "name": "Lina" }
```

`201`

```json
{ "token": "<jwt>", "user": { "id": "<uuid>", "role": "customer", "name": "Lina" } }
```

`name` is 1–40 characters after trimming.

## Orders

```ts
type OrderStatus =
  | 'placed' | 'accepted' | 'preparing' | 'ready'
  | 'picked_up' | 'delivered' | 'cancelled';

interface Order {
  id: string;            // uuid
  code: string;          // short code people can read out loud, e.g. "K7M2"
  status: OrderStatus;
  version: number;       // starts at 1, +1 on every status change
  customerId: string;
  customerName: string;
  courierId: string | null;
  courierName: string | null;
  items: { name: string; quantity: number; unitPrice: number }[];
  total: number;         // sum of quantity * unitPrice
  pickup: Place;
  dropoff: Place;
  courierLocation: CourierLocation | null;
  lastSeq: number;       // seq of the newest event of this order
  createdAt: string;
  updatedAt: string;
}

interface Place { lat: number; lng: number; label: string }
interface CourierLocation { lat: number; lng: number; heading: number | null; at: string }
```

### Status machine

| From | To | Who |
| --- | --- | --- |
| `placed` | `accepted` | store |
| `placed` | `cancelled` | customer (own order), store |
| `accepted` | `preparing` | store |
| `accepted` | `cancelled` | customer (own order), store |
| `preparing` | `ready` | store |
| `preparing` | `cancelled` | store |
| `ready` | `picked_up` | courier — the order is assigned to the courier who picks it up |
| `picked_up` | `delivered` | the assigned courier |

`delivered` and `cancelled` are final.

### `POST /orders` — customer

Header `Idempotency-Key: <uuid>` is required (`400 VALIDATION_FAILED` if it is not a UUID). Sending the same key again as the same customer returns the order that was created the first time with `200` instead of creating another one; the body of the retry is not compared with the first. A store or a courier gets `403 FORBIDDEN`.

```json
{
  "items": [{ "name": "Chicken shawarma", "quantity": 2, "unitPrice": 1800 }],
  "pickup":  { "lat": 32.2227, "lng": 35.2590, "label": "Old Town Grill" },
  "dropoff": { "lat": 32.2301, "lng": 35.2412, "label": "Home" }
}
```

`201` → `Order` (status `placed`, version `1`, `lastSeq` `1`).

Rules: 1–20 items, `quantity` 1–50, `unitPrice` 0–1 000 000, names 1–80 characters, labels 1–80 characters, latitude −90…90, longitude −180…180.

### `GET /orders`

- customer: own orders
- store: every order
- courier: orders that are `ready` and unassigned, plus every order assigned to this courier

Optional `?status=<OrderStatus>`. Newest first, at most 100 — there is no paging. `200` → `{ "orders": Order[] }`.

### `GET /orders/:id`

`200` → `Order`. A customer may read own orders, a store any order, a courier the orders `GET /orders` would list for them.

### `POST /orders/:id/transitions`

```json
{ "to": "accepted", "expectedVersion": 1 }
```

`200` → the updated `Order`. The write only goes through when the stored version still equals `expectedVersion`.

Checks run in this order: may the caller see the order (`404`, `403 FORBIDDEN`), is `expectedVersion` current (`409`), does the move exist (`422`), may this caller make it (`403 FORBIDDEN_TRANSITION`).

A courier cannot see an order someone else is carrying, so trying to take or deliver it is `403 FORBIDDEN`. The courier who loses the race for a pick-up gets the same answer rather than a `409`, because `current` would show them an order that is no longer theirs to see.

### `PUT /orders/:id/courier-location` — the assigned courier, while `picked_up`

```json
{ "lat": 32.2250, "lng": 35.2530, "heading": 270 }
```

`204`. The server keeps only the latest position. `heading` is optional (0–359). Anyone else, or any other status, gets `403 FORBIDDEN`.

### `GET /orders/:id/events?after=<seq>`

`200` → `{ "events": OrderEvent[] }`, ascending by `seq`, only events with `seq > after` (`after` defaults to 0). This is how a client catches up after it was offline.

```ts
interface OrderEvent {
  orderId: string;
  seq: number;   // per order, starts at 1, no gaps
  type: 'order.created' | 'order.status_changed';
  at: string;
  data:
    | { order: Order }                                                    // order.created
    | { from: OrderStatus; to: OrderStatus; version: number;
        by: { id: string; role: string; name: string };
        courierId: string | null; courierName: string | null };            // order.status_changed
}
```

Status changes are a log: every one gets the next `seq` and is stored. Courier positions are not part of the log — only the last one matters, so they are never replayed.

## Realtime (Socket.IO)

Namespace `/tracking`. The handshake carries the token: `io(url + '/tracking', { auth: { token } })`. A bad token disconnects the socket with a `connect_error` whose message is `UNAUTHENTICATED`.

### client → server

`subscribe` with an acknowledgement:

```json
{ "orderId": "<uuid>", "afterSeq": 3 }
```

ack on success:

```json
{ "ok": true, "snapshot": { "...": "Order" }, "missed": [ { "...": "OrderEvent with seq > afterSeq" } ] }
```

ack on failure: `{ "ok": false, "code": "ORDER_NOT_FOUND" | "FORBIDDEN" | "VALIDATION_FAILED" }`.

`afterSeq` is optional (default: no replay, `missed` is empty). The same visibility rules as `GET /orders/:id` apply.

`unsubscribe`: `{ "orderId": "<uuid>" }`, ack `{ "ok": true }`.

Every courier may watch a `ready` order. When one of them picks it up, the others still receive that event — it is how they learn to drop the order — and are then removed from the room.

### server → client (to everyone subscribed to that order)

- `order.event` — an `OrderEvent`, sent after the change is committed.
- `courier.location` — `{ "orderId": "<uuid>", "lat": 32.2250, "lng": 35.2530, "heading": 270, "at": "<iso>" }`. At most one per second per order; the newest position inside a busy second is the one that goes out, so the last position is never lost.

### What a client has to do

1. On connect (and on every reconnect) send `subscribe` with the highest `seq` it has applied.
2. Apply `missed`, then live `order.event`s, strictly in `seq` order. Ignore a `seq` it already has.
3. If a live event arrives with a gap (`seq > last + 1`), fetch `GET /orders/:id/events?after=<last>` and apply what comes back.
4. Treat `courier.location` as last-value-wins; drop one whose `at` is older than the one on screen.

## Health

`GET /health` → `200 { "status": "ok" }` (no auth).
