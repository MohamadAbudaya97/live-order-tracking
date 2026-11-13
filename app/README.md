# App

The Flutter client: one app, three roles (customer, store, courier). It is written against [`docs/api.md`](../docs/api.md) and needs the API from [`api/`](../api) to be running.

## Run

```bash
flutter pub get

# iOS simulator: the API on this machine is at localhost
flutter run

# Android emulator: the host machine is 10.0.2.2
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

`API_URL` defaults to `http://localhost:3000`. Plain HTTP is only allowed for local development: the Android debug manifest permits cleartext traffic and `Info.plist` sets `NSAllowsLocalNetworking`. Release builds keep the platform defaults.

Sign in with any name. The same role and name always open the same account. The token is kept in memory only, so restarting the app signs you out.

To watch an order travel, use two devices or sign out and back in:

1. Customer: "Place a demo order". The tracking screen opens.
2. Store: Accept, Start preparing, Mark ready.
3. Courier: Pick up, Open delivery, Simulate route, Delivered.

"Simulate route" walks a straight line from pickup to drop-off and sends one position a second, so there is no location permission to grant.

## Tests

```bash
flutter analyze
flutter test
```

The tests do not need the API. The repository is mocked and the socket is replaced by a fake that the test drives by hand (`test/support/fake_tracking_socket.dart`).

One more test does need it. `test_live/` runs the real repositories, the real socket and the tracking bloc against a running API, from placing an order to delivering it:

```bash
flutter test test_live --dart-define=LIVE_API_URL=http://localhost:3000
```

## Layout

```
lib/
  core/          HTTP client, ApiFailure, Socket.IO client, config
  features/
    auth/        demo sign-in
    orders/
      data/      models, OrderRepository, TrackingSocket
      logic/     blocs and cubits, the transition table, the simulated route
      ui/        screens and widgets
```

Dependencies go in through constructors and are provided with `RepositoryProvider` and `BlocProvider`. JSON is parsed by hand; there is no code generation.

## How tracking stays in order

The tracking screen starts from the order the list already has, and `OrderTrackingBloc` keeps it current. Everything that can change the order (the connection coming up, a live event, a courier position, the customer's cancel) goes through one queue and is handled to the end before the next thing is looked at, so a slow request can never be overtaken by what arrives while it is in flight.

On every connect and reconnect the bloc subscribes with the `seq` of the newest event it has applied. It applies the `missed` events from the answer in order, then takes the snapshot unless the snapshot is behind what it already has. A live event is applied only when its `seq` is exactly the next one. A lower `seq` is a duplicate and is dropped. A higher one means something was lost, so the bloc fetches `GET /orders/:id/events?after=<seq>` and applies that instead. The early event is not kept, because the log returns it again. If the fetch fails, the state says so and the screen offers a retry; the next event or reconnect repairs it as well.

Courier positions are not part of the log. The newest `at` wins and an older one is dropped.

Two smaller pieces follow the same contract: `PlaceOrderCubit` keeps one `Idempotency-Key` per intended order until the server has answered, so a retry cannot create a second order, and `allowedTransitions` is the status machine as a pure function, used only to decide which buttons to show.

## Notes

- Map tiles come from the public OpenStreetMap server, which is fine for a demo and not for production traffic.
- The formatter runs at 100 columns (`analysis_options.yaml`).
