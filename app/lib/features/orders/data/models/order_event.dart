import 'package:equatable/equatable.dart';

import 'order.dart';
import 'order_status.dart';

/// One entry of an order's log. Sequence numbers start at 1 and have no gaps.
sealed class OrderEvent extends Equatable {
  const OrderEvent({required this.orderId, required this.seq});

  factory OrderEvent.fromJson(Map<String, dynamic> json) {
    final orderId = json['orderId'] as String;
    final seq = json['seq'] as int;
    final data = json['data'] as Map<String, dynamic>;
    return switch (json['type']) {
      'order.created' => OrderCreated(
        orderId: orderId,
        seq: seq,
        order: Order.fromJson(data['order'] as Map<String, dynamic>),
      ),
      'order.status_changed' => OrderStatusChanged(
        orderId: orderId,
        seq: seq,
        to: OrderStatus.fromWire(data['to'] as String),
        version: data['version'] as int,
        courierId: data['courierId'] as String?,
        courierName: data['courierName'] as String?,
      ),
      final type => throw FormatException('Unknown order event type: $type'),
    };
  }

  final String orderId;
  final int seq;

  /// The order as it is once this event has happened to [order].
  Order applyTo(Order order);
}

final class OrderCreated extends OrderEvent {
  const OrderCreated({required super.orderId, required super.seq, required this.order});

  final Order order;

  @override
  Order applyTo(Order order) => this.order;

  @override
  List<Object?> get props => [orderId, seq, order];
}

final class OrderStatusChanged extends OrderEvent {
  const OrderStatusChanged({
    required super.orderId,
    required super.seq,
    required this.to,
    required this.version,
    required this.courierId,
    required this.courierName,
  });

  final OrderStatus to;
  final int version;

  /// Who carries the order after the change: set from pick-up onwards.
  final String? courierId;
  final String? courierName;

  @override
  Order applyTo(Order order) => order.copyWith(
    status: to,
    version: version,
    courierId: courierId,
    courierName: courierName,
    lastSeq: seq,
  );

  @override
  List<Object?> get props => [orderId, seq, to, version, courierId, courierName];
}
