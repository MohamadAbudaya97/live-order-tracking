import 'package:live_order_tracking/features/auth/data/session.dart';
import 'package:live_order_tracking/features/orders/data/models/courier_location.dart';
import 'package:live_order_tracking/features/orders/data/models/order.dart';
import 'package:live_order_tracking/features/orders/data/models/order_event.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/models/place.dart';

const orderId = 'order-1';

const customer = User(id: 'customer-1', role: Role.customer, name: 'Lina');
const store = User(id: 'store-1', role: Role.store, name: 'Old Town Grill');
const courier = User(id: 'courier-1', role: Role.courier, name: 'Sami');

/// An order of [customer]. A new order is at version 1 and seq 1 and every
/// status change adds one to both, so [seq] sets the two together.
Order anOrder({
  OrderStatus status = OrderStatus.placed,
  int seq = 1,
  String? courierId,
  String? courierName,
  CourierLocation? courierLocation,
}) => Order(
  id: orderId,
  code: 'K7M2',
  status: status,
  version: seq,
  customerId: customer.id,
  customerName: customer.name,
  courierId: courierId,
  courierName: courierName,
  items: const [OrderItem(name: 'Chicken shawarma', quantity: 2, unitPrice: 1800)],
  total: 3600,
  pickup: const Place(lat: 32.2227, lng: 35.2590, label: 'Old Town Grill'),
  dropoff: const Place(lat: 32.2301, lng: 35.2412, label: 'Home'),
  courierLocation: courierLocation,
  lastSeq: seq,
  createdAt: DateTime.utc(2026, 3, 1, 12),
);

/// The status change that takes [anOrder] to [to] as event number [seq].
OrderStatusChanged statusChanged(
  int seq,
  OrderStatus to, {
  String? courierId,
  String? courierName,
}) => OrderStatusChanged(
  orderId: orderId,
  seq: seq,
  to: to,
  version: seq,
  courierId: courierId,
  courierName: courierName,
);

CourierLocation courierAt(int second, {double lat = 32.225, double lng = 35.253}) =>
    CourierLocation(lat: lat, lng: lng, heading: 270, at: DateTime.utc(2026, 3, 1, 12, 30, second));

/// [anOrder] the way the API sends it, as in docs/api.md.
Map<String, dynamic> orderJson({
  String status = 'placed',
  int seq = 1,
  String? courierId,
  String? courierName,
  Map<String, dynamic>? courierLocation,
}) => {
  'id': orderId,
  'code': 'K7M2',
  'status': status,
  'version': seq,
  'customerId': 'customer-1',
  'customerName': 'Lina',
  'courierId': courierId,
  'courierName': courierName,
  'items': [
    {'name': 'Chicken shawarma', 'quantity': 2, 'unitPrice': 1800},
  ],
  'total': 3600,
  'pickup': {'lat': 32.2227, 'lng': 35.2590, 'label': 'Old Town Grill'},
  'dropoff': {'lat': 32.2301, 'lng': 35.2412, 'label': 'Home'},
  'courierLocation': courierLocation,
  'lastSeq': seq,
  'createdAt': '2026-03-01T12:00:00.000Z',
  'updatedAt': '2026-03-01T12:00:00.000Z',
};
