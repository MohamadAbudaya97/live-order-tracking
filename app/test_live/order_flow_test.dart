// The app's own data layer and tracking bloc against a running API, no mocks.
// It is not part of `flutter test`; start the API and run:
//
//   flutter test test_live --dart-define=LIVE_API_URL=http://localhost:3000

import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/core/api_client.dart';
import 'package:live_order_tracking/core/api_failure.dart';
import 'package:live_order_tracking/features/auth/data/auth_repository.dart';
import 'package:live_order_tracking/features/auth/data/session.dart';
import 'package:live_order_tracking/features/orders/data/models/order.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';
import 'package:live_order_tracking/features/orders/data/tracking_socket.dart';
import 'package:live_order_tracking/features/orders/logic/order_tracking_bloc.dart';
import 'package:uuid/uuid.dart';

const _url = String.fromEnvironment('LIVE_API_URL');

class _Signed {
  _Signed(this.session, this.orders);

  final Session session;
  final OrderRepository orders;

  static Future<_Signed> as(Role role, String name) async {
    final api = ApiClient(baseUrl: _url);
    final session = await AuthRepository(api).signIn(role, name);
    return _Signed(session, OrderRepository(api));
  }

  OrderTrackingBloc track(Order order) => OrderTrackingBloc(
    order: order,
    repository: orders,
    socket: SocketIoTrackingSocket(baseUrl: _url, token: session.token),
  );
}

Future<OrderTrackingState> _until(
  OrderTrackingBloc bloc,
  bool Function(OrderTrackingState state) reached,
) async {
  if (reached(bloc.state)) return bloc.state;
  return bloc.stream.firstWhere(reached).timeout(const Duration(seconds: 10));
}

void main() {
  test(
    'one order, three roles, placed to delivered',
    () async {
      // Fresh names per run, so earlier runs against the same database do not matter.
      final run = DateTime.now().millisecondsSinceEpoch;
      final customer = await _Signed.as(Role.customer, 'Lina $run');
      final store = await _Signed.as(Role.store, 'Grill $run');
      final courier = await _Signed.as(Role.courier, 'Omar $run');

      final key = const Uuid().v4();
      final placed = await customer.orders.placeDemoOrder(idempotencyKey: key);
      final retried = await customer.orders.placeDemoOrder(idempotencyKey: key);
      expect(retried.id, placed.id);
      expect(placed.status, OrderStatus.placed);
      expect(placed.lastSeq, 1);

      final watching = customer.track(placed);
      addTearDown(watching.close);
      await _until(watching, (state) => state.connection == LiveConnection.connected);

      final accepted = await store.orders.transition(placed, OrderStatus.accepted);
      await _until(watching, (state) => state.order.status == OrderStatus.accepted);

      // The customer still holds the order as it was placed and tries to cancel it.
      await expectLater(
        customer.orders.transition(placed, OrderStatus.cancelled),
        throwsA(
          isA<ApiFailure>()
              .having((failure) => failure.code, 'code', ApiErrorCode.versionConflict)
              .having((failure) => failure.currentOrder?.status, 'current', OrderStatus.accepted),
        ),
      );

      final preparing = await store.orders.transition(accepted, OrderStatus.preparing);
      final ready = await store.orders.transition(preparing, OrderStatus.ready);

      final offered = await courier.orders.orders();
      expect(offered.map((order) => order.id), contains(placed.id));

      final pickedUp = await courier.orders.transition(ready, OrderStatus.pickedUp);
      expect(pickedUp.courierId, courier.session.user.id);

      // Faster than the server passes positions on; the last one must still arrive.
      for (final lng in [35.2570, 35.2550, 35.2530]) {
        await courier.orders.sendCourierLocation(placed.id, lat: 32.2250, lng: lng, heading: 270);
      }
      final moved = await _until(watching, (state) => state.order.courierLocation?.lng == 35.2530);
      expect(moved.order.status, OrderStatus.pickedUp);
      expect(moved.order.courierName, courier.session.user.name);

      await courier.orders.transition(pickedUp, OrderStatus.delivered);
      final done = await _until(watching, (state) => state.order.status == OrderStatus.delivered);
      expect(done.order.lastSeq, 6);
      expect(done.order.version, 6);
      expect(done.syncFailed, isFalse);

      // A screen that was last in step when the order was placed catches up from the log.
      final late = customer.track(placed);
      addTearDown(late.close);
      final caughtUp = await _until(late, (state) => state.order.status == OrderStatus.delivered);
      expect(caughtUp.order.lastSeq, 6);
    },
    skip: _url.isEmpty ? 'needs --dart-define=LIVE_API_URL=<running API>' : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
