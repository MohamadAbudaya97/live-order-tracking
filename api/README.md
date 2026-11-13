# Live order tracking: API

The backend of a small order-tracking demo. A customer places an order, the store prepares it, a courier delivers it, and everyone watching the order sees each step as it happens.

The contract with the app is [`../docs/api.md`](../docs/api.md). This file is about running and testing the API.

NestJS 11, PostgreSQL through Prisma 7, Socket.IO, Jest.

## Running it

You need Node 22.12 or newer. I use 24.

### Without Docker

```sh
npm install
cp .env.example .env
npm run db:start     # terminal 1: PostgreSQL on port 54329
npm run start:dev    # terminal 2: the API on http://localhost:3000
```

`db:start` runs a real PostgreSQL 16 from the `embedded-postgres` package, applies the migrations and stays up until Ctrl-C. Nothing is installed on the machine. The data lives in `.pgdata/`; delete the folder to start from an empty database.

### With Docker

```sh
docker compose up -d    # PostgreSQL 16, also on port 54329
npm install
cp .env.example .env
npm run db:migrate
npm run start:dev
```

The `Dockerfile` builds the API itself:

```sh
docker build -t order-tracking-api .
docker run --rm -p 3000:3000 \
  -e DATABASE_URL=postgresql://postgres:postgres@host.docker.internal:54329/postgres \
  -e JWT_SECRET=change-me \
  order-tracking-api
```

The image holds only what the server needs at run time, so it does not migrate. Run `npm run db:migrate` against the database first.

### A first request

```sh
curl -s localhost:3000/auth/demo-login \
  -H 'Content-Type: application/json' \
  -d '{"role":"customer","name":"Lina"}'
```

## Environment

| Variable       | Default  |                                    |
| -------------- | -------- | ---------------------------------- |
| `PORT`         | `3000`   |                                    |
| `DATABASE_URL` | required | PostgreSQL connection string       |
| `JWT_SECRET`   | required | signs the demo tokens              |
| `CORS_ORIGIN`  | `*`      | allowed origin, HTTP and Socket.IO |

A `.env` file in this folder is read at start-up. Variables already set in the environment win over it.

## Tests

```sh
npm test            # unit: the status machine and the location throttle
npm run test:e2e    # HTTP and Socket.IO against a real PostgreSQL
npm run lint
npm run typecheck
npm run build
```

The e2e tests need no setup. They start a throwaway PostgreSQL on a free port, migrate it and remove it afterwards. When `DATABASE_URL` is already set, as in CI with a Postgres service, they use that database instead. Every test logs in as users of its own, so the two suites run in parallel and do not mind a database that already has data in it.

## Layout

```
src/
  auth/        demo login, JWT guard, @CurrentUser()
  orders/      the endpoints, the status machine, the event log
  tracking/    the Socket.IO gateway and the location throttle
  common/      the error shape and validation
prisma/        schema and migration
scripts/       embedded PostgreSQL for development and tests
test/          e2e tests and their helpers
```

## Design notes

**Status machine.** `src/orders/order-status.ts` is a table of the transitions and who may make each one. It imports nothing from Nest or Prisma, and it is the only place that knows the rules.

**Concurrent changes.** A transition is an `UPDATE ... WHERE id = $1 AND version = $2`. The rules are checked against the version the caller sent, and the write lands only if the row is still at that version. If it is not, the caller gets `409` with the order as it is now.

**Event log.** The update and the insert of the event are one transaction. The update holds the row lock until commit, so writers of one order go one at a time and each takes the next `seq`. `(order_id, seq)` is the primary key, so a gap or a duplicate cannot be stored.

**Realtime.** An event goes to Socket.IO only after its transaction has committed, so clients never hear about a change that was rolled back. On `subscribe` the socket joins the room first and the snapshot is read second. A change that lands in between arrives both ways, and the client drops the duplicate by `seq`.

**Courier positions.** Only the latest one is kept, on the order row, and it is not part of the log. `LocationThrottle` lets one position per order out per second and always delivers the last one of a burst.

**Idempotent create.** `(customer_id, idempotency_key)` is unique in the database. A retry finds the first order, also when it races the original request.
