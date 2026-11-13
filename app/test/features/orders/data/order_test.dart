import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/orders/data/models/order.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';

import '../../../support/fixtures.dart';

void main() {
  group('Order.fromJson', () {
    test('reads a new order, which has no courier and no position yet', () {
      final order = Order.fromJson(orderJson());

      expect(order.id, orderId);
      expect(order.code, 'K7M2');
      expect(order.status, OrderStatus.placed);
      expect(order.version, 1);
      expect(order.customerId, 'customer-1');
      expect(order.customerName, 'Lina');
      expect(order.courierId, isNull);
      expect(order.courierName, isNull);
      expect(order.items, const [
        OrderItem(name: 'Chicken shawarma', quantity: 2, unitPrice: 1800),
      ]);
      expect(order.total, 3600);
      expect(order.pickup.label, 'Old Town Grill');
      expect(order.pickup.lat, 32.2227);
      expect(order.dropoff.lng, 35.2412);
      expect(order.courierLocation, isNull);
      expect(order.lastSeq, 1);
      expect(order.createdAt, DateTime.utc(2026, 3, 1, 12));
    });

    test('reads the courier and the position of an order on its way', () {
      final order = Order.fromJson(
        orderJson(
          status: 'picked_up',
          seq: 5,
          courierId: 'courier-1',
          courierName: 'Sami',
          courierLocation: {
            'lat': 32.225,
            'lng': 35.253,
            'heading': 270,
            'at': '2026-03-01T12:30:10.000Z',
          },
        ),
      );

      expect(order.status, OrderStatus.pickedUp);
      expect(order.courierId, 'courier-1');
      expect(order.courierName, 'Sami');
      expect(order.courierLocation, courierAt(10));
    });

    test('accepts whole-number coordinates and a position without a heading', () {
      final order = Order.fromJson(
        orderJson(
          courierLocation: {'lat': 32, 'lng': 35, 'heading': null, 'at': '2026-03-01T12:30:10Z'},
        ),
      );

      expect(order.courierLocation?.lat, 32.0);
      expect(order.courierLocation?.heading, isNull);
    });

    test('knows every status of the contract', () {
      const wire = [
        'placed',
        'accepted',
        'preparing',
        'ready',
        'picked_up',
        'delivered',
        'cancelled',
      ];

      expect(wire.map(OrderStatus.fromWire), OrderStatus.values);
    });
  });
}
