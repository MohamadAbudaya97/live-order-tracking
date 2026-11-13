import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/core/api_failure.dart';
import 'package:live_order_tracking/features/orders/data/models/order.dart';
import 'package:live_order_tracking/features/orders/data/models/order_event.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';
import 'package:live_order_tracking/features/orders/data/tracking_socket.dart';
import 'package:live_order_tracking/features/orders/logic/order_tracking_bloc.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fake_tracking_socket.dart';
import '../../../support/fixtures.dart';

class MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  // The order's life in the order the server would log it.
  final placed = anOrder();
  final accepted = anOrder(status: OrderStatus.accepted, seq: 2);
  final preparing = anOrder(status: OrderStatus.preparing, seq: 3);
  final ready = anOrder(status: OrderStatus.ready, seq: 4);
  final pickedUp = anOrder(
    status: OrderStatus.pickedUp,
    seq: 5,
    courierId: courier.id,
    courierName: courier.name,
  );

  final toAccepted = statusChanged(2, OrderStatus.accepted);
  final toPreparing = statusChanged(3, OrderStatus.preparing);
  final toReady = statusChanged(4, OrderStatus.ready);
  final toPickedUp = statusChanged(
    5,
    OrderStatus.pickedUp,
    courierId: courier.id,
    courierName: courier.name,
  );

  late FakeTrackingSocket socket;
  late MockOrderRepository repository;

  OrderTrackingBloc buildBloc({Order? from}) =>
      OrderTrackingBloc(order: from ?? placed, repository: repository, socket: socket);

  OrderTrackingState live(Order order, {bool syncFailed = false}) => OrderTrackingState(
    order: order,
    connection: LiveConnection.connected,
    syncFailed: syncFailed,
  );

  setUpAll(() {
    registerFallbackValue(placed);
    registerFallbackValue(OrderStatus.placed);
  });

  setUp(() {
    socket = FakeTrackingSocket(snapshot: placed);
    repository = MockOrderRepository();
  });

  group('subscribing', () {
    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'connects, subscribes after the seq it starts from and shows the snapshot',
      build: () {
        socket.onSubscribe = (_) => SubscribeAck(snapshot: preparing);
        return buildBloc();
      },
      act: (_) => socket.goOnline(),
      expect: () => [live(placed), live(preparing)],
      verify: (_) {
        expect(socket.connectCalled, isTrue);
        expect(socket.subscribedAfter, [1]);
      },
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'shows the reconnecting state and subscribes again with the last applied seq',
      build: () {
        socket.onSubscribe = (afterSeq) => afterSeq == 1
            ? SubscribeAck(snapshot: placed)
            : SubscribeAck(snapshot: ready, missed: [toPreparing, toReady]);
        return buildBloc();
      },
      act: (_) => socket
        ..goOnline()
        ..push(toAccepted)
        ..goOffline()
        ..goOnline(),
      expect: () => [
        live(placed),
        live(accepted),
        OrderTrackingState(order: accepted, connection: LiveConnection.reconnecting),
        live(accepted),
        live(ready),
      ],
      verify: (_) => expect(socket.subscribedAfter, [1, 2]),
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'applies the missed events even when the snapshot is older than they are',
      build: () {
        socket.onSubscribe = (_) => SubscribeAck(snapshot: accepted, missed: [toPreparing]);
        return buildBloc(from: accepted);
      },
      act: (_) => socket.goOnline(),
      expect: () => [live(accepted), live(preparing)],
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'does not let a snapshot behind the applied events roll the order back',
      build: () {
        socket.onSubscribe = (_) => SubscribeAck(snapshot: accepted);
        return buildBloc(from: preparing);
      },
      act: (_) => socket.goOnline(),
      expect: () => [live(preparing)],
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'flags a refused subscribe as a failed sync',
      build: () {
        socket.onSubscribe = (_) => throw const ApiFailure(ApiErrorCode.forbidden);
        return buildBloc();
      },
      act: (_) => socket.goOnline(),
      expect: () => [live(placed), live(placed, syncFailed: true)],
    );
  });

  group('live events', () {
    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'are applied one after another without asking the server again',
      build: buildBloc,
      act: (_) => socket
        ..goOnline()
        ..push(toAccepted)
        ..push(toPreparing)
        ..push(toReady)
        ..push(toPickedUp),
      expect: () => [live(placed), live(accepted), live(preparing), live(ready), live(pickedUp)],
      verify: (_) {
        expect(socket.subscribedAfter, [1]);
        verifyZeroInteractions(repository);
      },
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'are ignored when their seq was applied before',
      build: buildBloc,
      act: (_) => socket
        ..goOnline()
        ..push(toAccepted)
        ..push(toAccepted)
        ..push(OrderCreated(orderId: orderId, seq: 1, order: placed)),
      expect: () => [live(placed), live(accepted)],
      verify: (_) => verifyZeroInteractions(repository),
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'for another order are ignored',
      build: buildBloc,
      act: (_) => socket
        ..goOnline()
        ..push(
          const OrderStatusChanged(
            orderId: 'order-2',
            seq: 2,
            to: OrderStatus.cancelled,
            version: 2,
            courierId: null,
            courierName: null,
          ),
        ),
      expect: () => [live(placed)],
    );
  });

  group('a gap in the events', () {
    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'is filled from the event log, after which the late event is a duplicate',
      build: () {
        when(() => repository.eventsAfter(orderId, 1))
            .thenAnswer((_) async => [toAccepted, toPreparing]);
        return buildBloc();
      },
      act: (_) => socket
        ..goOnline()
        ..push(toPreparing)
        ..push(toAccepted),
      expect: () => [live(placed), live(preparing)],
      verify: (_) => verify(() => repository.eventsAfter(orderId, 1)).called(1),
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'holds back the events that arrive while the log is being fetched',
      build: buildBloc,
      act: (_) async {
        final log = Completer<List<OrderEvent>>();
        when(() => repository.eventsAfter(orderId, 1)).thenAnswer((_) => log.future);

        socket
          ..goOnline()
          ..push(toPreparing)
          ..push(toReady);
        await pumpEventQueue();
        log.complete([toAccepted, toPreparing]);
      },
      expect: () => [live(placed), live(preparing), live(ready)],
      verify: (_) => verify(() => repository.eventsAfter(any(), any())).called(1),
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'that cannot be filled leaves a failed sync, and a retry subscribes again',
      build: () {
        when(() => repository.eventsAfter(orderId, 1))
            .thenThrow(const ApiFailure(ApiErrorCode.network));
        return buildBloc();
      },
      act: (bloc) async {
        socket
          ..goOnline()
          ..push(toPreparing);
        await pumpEventQueue();

        socket.onSubscribe = (_) =>
            SubscribeAck(snapshot: preparing, missed: [toAccepted, toPreparing]);
        bloc.add(const TrackingRetryRequested());
      },
      expect: () => [live(placed), live(placed, syncFailed: true), live(preparing)],
      verify: (_) => expect(socket.subscribedAfter, [1, 1]),
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'that could not be filled is tried again by the next event',
      build: () {
        var attempts = 0;
        when(() => repository.eventsAfter(orderId, 1)).thenAnswer((_) async {
          if (++attempts == 1) throw const ApiFailure(ApiErrorCode.network);
          return [toAccepted, toPreparing, toReady];
        });
        return buildBloc();
      },
      act: (_) => socket
        ..goOnline()
        ..push(toPreparing)
        ..push(toReady),
      expect: () => [live(placed), live(placed, syncFailed: true), live(ready)],
    );
  });

  group('the courier position', () {
    /// The order on its way, with the courier last seen at [second].
    Order seenAt(int second) => pickedUp.copyWith(courierLocation: courierAt(second));

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'follows the newest report and drops one older than what is shown',
      build: () {
        socket.onSubscribe = (_) => SubscribeAck(snapshot: pickedUp);
        return buildBloc(from: pickedUp);
      },
      act: (_) => socket
        ..goOnline()
        ..moveCourier(courierAt(10))
        ..moveCourier(courierAt(5))
        ..moveCourier(courierAt(20), of: 'order-2')
        ..moveCourier(courierAt(11)),
      expect: () => [live(pickedUp), live(seenAt(10)), live(seenAt(11))],
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'is taken from a snapshot only when that one is newer than what is shown',
      build: () => buildBloc(from: seenAt(40)),
      act: (_) async {
        socket.onSubscribe = (_) => SubscribeAck(snapshot: seenAt(30));
        socket.goOnline();
        await pumpEventQueue();

        socket.onSubscribe = (_) => SubscribeAck(snapshot: seenAt(50));
        socket
          ..goOffline()
          ..goOnline();
      },
      expect: () => [
        live(seenAt(40)),
        OrderTrackingState(order: seenAt(40), connection: LiveConnection.reconnecting),
        live(seenAt(40)),
        live(seenAt(50)),
      ],
    );
  });

  group('cancelling', () {
    final cancelled = anOrder(status: OrderStatus.cancelled, seq: 2);

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'shows the order the server returns and ignores the event that echoes it',
      build: () {
        when(() => repository.transition(placed, OrderStatus.cancelled))
            .thenAnswer((_) async => cancelled);
        return buildBloc();
      },
      act: (bloc) async {
        socket.goOnline();
        await pumpEventQueue();
        bloc.add(const TrackingCancelRequested());
        await pumpEventQueue();
        socket.push(statusChanged(2, OrderStatus.cancelled));
      },
      expect: () => [live(placed), live(placed).copyWith(cancelling: true), live(cancelled)],
    );

    blocTest<OrderTrackingBloc, OrderTrackingState>(
      'on a version conflict moves to the current order and reports why',
      build: () {
        when(() => repository.transition(any(), any())).thenThrow(
          ApiFailure(
            ApiErrorCode.versionConflict,
            statusCode: 409,
            body: {'current': orderJson(status: 'preparing', seq: 3)},
          ),
        );
        return buildBloc();
      },
      act: (bloc) async {
        socket.goOnline();
        await pumpEventQueue();
        bloc.add(const TrackingCancelRequested());
      },
      expect: () => [
        live(placed),
        live(placed).copyWith(cancelling: true),
        isA<OrderTrackingState>()
            .having((state) => state.order, 'order', preparing)
            .having((state) => state.cancelling, 'cancelling', isFalse)
            .having((state) => state.cancelFailure?.code, 'failure', ApiErrorCode.versionConflict),
      ],
    );
  });

  test('closing the bloc disposes the socket', () async {
    final bloc = buildBloc();

    await bloc.close();

    expect(socket.disposed, isTrue);
  });
}
