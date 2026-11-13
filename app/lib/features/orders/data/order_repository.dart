import '../../../core/api_client.dart';
import '../../../core/api_failure.dart';
import 'models/order.dart';
import 'models/order_event.dart';
import 'models/order_status.dart';

const _demoOrder = <String, dynamic>{
  'items': [
    {'name': 'Chicken shawarma', 'quantity': 2, 'unitPrice': 1800},
    {'name': 'Mint lemonade', 'quantity': 1, 'unitPrice': 900},
  ],
  'pickup': {'lat': 32.2227, 'lng': 35.2590, 'label': 'Old Town Grill'},
  'dropoff': {'lat': 32.2301, 'lng': 35.2412, 'label': 'Home'},
};

class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  /// The orders the signed-in user may see, newest first.
  Future<List<Order>> orders() async {
    final json = await _api.get('/orders');
    return [
      for (final order in json['orders'] as List<dynamic>)
        Order.fromJson(order as Map<String, dynamic>),
    ];
  }

  /// Places the one order this demo knows how to place. A second call with
  /// the same [idempotencyKey] returns the order the first one created, so
  /// repeating a request whose answer was lost is safe.
  Future<Order> placeDemoOrder({required String idempotencyKey}) async {
    final json = await _api.post(
      '/orders',
      body: _demoOrder,
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return Order.fromJson(json);
  }

  /// Moves [order] to [to], provided nobody changed it since this copy was
  /// read. Otherwise fails with a version conflict that carries the order as
  /// it is now, see [VersionConflict.currentOrder].
  Future<Order> transition(Order order, OrderStatus to) async {
    final json = await _api.post(
      '/orders/${order.id}/transitions',
      body: {'to': to.wire, 'expectedVersion': order.version},
    );
    return Order.fromJson(json);
  }

  Future<void> sendCourierLocation(
    String orderId, {
    required double lat,
    required double lng,
    required int heading,
  }) => _api.put(
    '/orders/$orderId/courier-location',
    body: {'lat': lat, 'lng': lng, 'heading': heading},
  );

  /// The order's events newer than [seq], oldest first.
  Future<List<OrderEvent>> eventsAfter(String orderId, int seq) async {
    final json = await _api.get('/orders/$orderId/events', query: {'after': seq});
    return [
      for (final event in json['events'] as List<dynamic>)
        OrderEvent.fromJson(event as Map<String, dynamic>),
    ];
  }
}

extension VersionConflict on ApiFailure {
  /// The order as the server has it now. Only a version conflict carries it.
  Order? get currentOrder {
    final current = body['current'];
    return current is Map<String, dynamic> ? Order.fromJson(current) : null;
  }
}
