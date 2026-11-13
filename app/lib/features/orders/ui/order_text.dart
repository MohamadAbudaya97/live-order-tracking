import '../data/models/order.dart';
import '../data/models/order_status.dart';

extension OrderStatusText on OrderStatus {
  String get label => switch (this) {
    OrderStatus.placed => 'Placed',
    OrderStatus.accepted => 'Accepted',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.ready => 'Ready for pickup',
    OrderStatus.pickedUp => 'On the way',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
  };

  /// What the button that moves an order into this status says.
  String get actionLabel => switch (this) {
    OrderStatus.accepted => 'Accept',
    OrderStatus.preparing => 'Start preparing',
    OrderStatus.ready => 'Mark ready',
    OrderStatus.pickedUp => 'Pick up',
    OrderStatus.cancelled => 'Cancel',
    // Delivering is confirmed with the word itself, and nothing moves an
    // order back to placed.
    OrderStatus.delivered || OrderStatus.placed => label,
  };
}

extension OrderText on Order {
  String get itemsSummary => items.map((item) => '${item.quantity} × ${item.name}').join(', ');
}

/// Amounts are integers in minor units and the API has a single currency, so
/// there is no symbol to show.
String formatAmount(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
