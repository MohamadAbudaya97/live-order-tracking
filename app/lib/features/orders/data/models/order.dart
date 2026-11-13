import 'package:equatable/equatable.dart';

import 'courier_location.dart';
import 'order_status.dart';
import 'place.dart';

class OrderItem extends Equatable {
  const OrderItem({required this.name, required this.quantity, required this.unitPrice});

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    name: json['name'] as String,
    quantity: json['quantity'] as int,
    unitPrice: json['unitPrice'] as int,
  );

  final String name;
  final int quantity;

  /// In minor units (cents), like every amount in the API.
  final int unitPrice;

  @override
  List<Object?> get props => [name, quantity, unitPrice];
}

class Order extends Equatable {
  const Order({
    required this.id,
    required this.code,
    required this.status,
    required this.version,
    required this.customerId,
    required this.customerName,
    required this.courierId,
    required this.courierName,
    required this.items,
    required this.total,
    required this.pickup,
    required this.dropoff,
    required this.courierLocation,
    required this.lastSeq,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final courierLocation = json['courierLocation'] as Map<String, dynamic>?;
    return Order(
      id: json['id'] as String,
      code: json['code'] as String,
      status: OrderStatus.fromWire(json['status'] as String),
      version: json['version'] as int,
      customerId: json['customerId'] as String,
      customerName: json['customerName'] as String,
      courierId: json['courierId'] as String?,
      courierName: json['courierName'] as String?,
      items: [
        for (final item in json['items'] as List<dynamic>)
          OrderItem.fromJson(item as Map<String, dynamic>),
      ],
      total: json['total'] as int,
      pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
      dropoff: Place.fromJson(json['dropoff'] as Map<String, dynamic>),
      courierLocation: courierLocation == null ? null : CourierLocation.fromJson(courierLocation),
      lastSeq: json['lastSeq'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String code;
  final OrderStatus status;

  /// Goes up by one on every status change; sent back as `expectedVersion`.
  final int version;
  final String customerId;
  final String customerName;
  final String? courierId;
  final String? courierName;
  final List<OrderItem> items;
  final int total;
  final Place pickup;
  final Place dropoff;
  final CourierLocation? courierLocation;

  /// Sequence number of the newest event this copy of the order reflects.
  final int lastSeq;
  final DateTime createdAt;

  /// A courier, once assigned, stays with the order, so there is never a
  /// need to set one of the courier fields back to null.
  Order copyWith({
    OrderStatus? status,
    int? version,
    String? courierId,
    String? courierName,
    CourierLocation? courierLocation,
    int? lastSeq,
  }) => Order(
    id: id,
    code: code,
    status: status ?? this.status,
    version: version ?? this.version,
    customerId: customerId,
    customerName: customerName,
    courierId: courierId ?? this.courierId,
    courierName: courierName ?? this.courierName,
    items: items,
    total: total,
    pickup: pickup,
    dropoff: dropoff,
    courierLocation: courierLocation ?? this.courierLocation,
    lastSeq: lastSeq ?? this.lastSeq,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    code,
    status,
    version,
    customerId,
    customerName,
    courierId,
    courierName,
    items,
    total,
    pickup,
    dropoff,
    courierLocation,
    lastSeq,
    createdAt,
  ];
}
