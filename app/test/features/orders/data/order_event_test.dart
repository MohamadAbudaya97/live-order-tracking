import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/orders/data/models/order_event.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';

import '../../../support/fixtures.dart';

Map<String, dynamic> statusChangedJson({
  required int seq,
  required String from,
  required String to,
  String? courierId,
  String? courierName,
}) => {
  'orderId': orderId,
  'seq': seq,
  'type': 'order.status_changed',
  'at': '2026-03-01T12:05:00.000Z',
  'data': {
    'from': from,
    'to': to,
    'version': seq,
    'by': {'id': 'store-1', 'role': 'store', 'name': 'Old Town Grill'},
    'courierId': courierId,
    'courierName': courierName,
  },
};

void main() {
  group('OrderEvent.fromJson', () {
    test('reads order.created with the order it carries', () {
      final event = OrderEvent.fromJson({
        'orderId': orderId,
        'seq': 1,
        'type': 'order.created',
        'at': '2026-03-01T12:00:00.000Z',
        'data': {'order': orderJson()},
      });

      expect(event, OrderCreated(orderId: orderId, seq: 1, order: anOrder()));
    });

    test('reads order.status_changed before a courier is assigned', () {
      final event = OrderEvent.fromJson(statusChangedJson(seq: 2, from: 'placed', to: 'accepted'));

      expect(event, statusChanged(2, OrderStatus.accepted));
    });

    test('reads order.status_changed with the courier who picked the order up', () {
      final event = OrderEvent.fromJson(
        statusChangedJson(
          seq: 5,
          from: 'ready',
          to: 'picked_up',
          courierId: 'courier-1',
          courierName: 'Sami',
        ),
      );

      expect(
        event,
        statusChanged(5, OrderStatus.pickedUp, courierId: 'courier-1', courierName: 'Sami'),
      );
    });

    test('rejects a type the contract does not have', () {
      final json = statusChangedJson(seq: 2, from: 'placed', to: 'accepted')
        ..['type'] = 'order.refunded';

      expect(() => OrderEvent.fromJson(json), throwsFormatException);
    });
  });

  group('applying an event', () {
    test('a status change moves status, version, courier and seq and nothing else', () {
      final ready = anOrder(status: OrderStatus.ready, seq: 4, courierLocation: courierAt(1));
      final event = statusChanged(
        5,
        OrderStatus.pickedUp,
        courierId: 'courier-1',
        courierName: 'Sami',
      );

      expect(
        event.applyTo(ready),
        anOrder(
          status: OrderStatus.pickedUp,
          seq: 5,
          courierId: 'courier-1',
          courierName: 'Sami',
          courierLocation: courierAt(1),
        ),
      );
    });

    test('a later status change keeps the courier it does not mention again', () {
      final pickedUp = anOrder(
        status: OrderStatus.pickedUp,
        seq: 5,
        courierId: 'courier-1',
        courierName: 'Sami',
      );

      final delivered = statusChanged(
        6,
        OrderStatus.delivered,
        courierId: 'courier-1',
        courierName: 'Sami',
      ).applyTo(pickedUp);

      expect(delivered.status, OrderStatus.delivered);
      expect(delivered.courierName, 'Sami');
      expect(delivered.lastSeq, 6);
    });
  });
}
