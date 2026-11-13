import '../../auth/data/session.dart';
import '../data/models/order.dart';
import '../data/models/order_status.dart';

/// The statuses [user] may move [order] to right now, the forward step first.
///
/// Mirrors the status machine in docs/api.md so the UI only offers what the
/// server will accept. The server still has the last word.
List<OrderStatus> allowedTransitions(Order order, User user) {
  final ownOrder = order.customerId == user.id;
  final assigned = order.courierId == user.id;

  return switch ((order.status, user.role)) {
    (OrderStatus.placed, Role.store) => const [OrderStatus.accepted, OrderStatus.cancelled],
    (OrderStatus.accepted, Role.store) => const [OrderStatus.preparing, OrderStatus.cancelled],
    (OrderStatus.preparing, Role.store) => const [OrderStatus.ready, OrderStatus.cancelled],
    (OrderStatus.placed || OrderStatus.accepted, Role.customer) when ownOrder => const [
      OrderStatus.cancelled,
    ],
    (OrderStatus.ready, Role.courier) => const [OrderStatus.pickedUp],
    (OrderStatus.pickedUp, Role.courier) when assigned => const [OrderStatus.delivered],
    _ => const [],
  };
}
