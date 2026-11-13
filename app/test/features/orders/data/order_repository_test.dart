import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/core/api_client.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;
  late OrderRepository repository;

  setUp(() {
    api = MockApiClient();
    repository = OrderRepository(api);
  });

  test('placing an order sends the key in the Idempotency-Key header', () async {
    when(
      () => api.post(
        '/orders',
        body: any(named: 'body'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => orderJson());

    final order = await repository.placeDemoOrder(idempotencyKey: 'key-1');

    expect(order, anOrder());
    verify(
      () => api.post(
        '/orders',
        body: any(named: 'body'),
        headers: {'Idempotency-Key': 'key-1'},
      ),
    ).called(1);
  });

  test('a transition names the target and the version the change is based on', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => orderJson(status: 'preparing', seq: 3));

    final order = await repository.transition(
      anOrder(status: OrderStatus.accepted, seq: 2),
      OrderStatus.preparing,
    );

    expect(order, anOrder(status: OrderStatus.preparing, seq: 3));
    verify(
      () =>
          api.post('/orders/$orderId/transitions', body: {'to': 'preparing', 'expectedVersion': 2}),
    ).called(1);
  });

  test('catching up asks for the events after a seq and reads them in order', () async {
    when(() => api.get('/orders/$orderId/events', query: {'after': 2})).thenAnswer(
      (_) async => {
        'events': [
          for (final (seq, to) in [(3, 'preparing'), (4, 'ready')])
            {
              'orderId': orderId,
              'seq': seq,
              'type': 'order.status_changed',
              'at': '2026-03-01T12:05:00.000Z',
              'data': {
                'from': 'accepted',
                'to': to,
                'version': seq,
                'by': {'id': 'store-1', 'role': 'store', 'name': 'Old Town Grill'},
                'courierId': null,
                'courierName': null,
              },
            },
        ],
      },
    );

    final events = await repository.eventsAfter(orderId, 2);

    expect(events, [statusChanged(3, OrderStatus.preparing), statusChanged(4, OrderStatus.ready)]);
  });
}
