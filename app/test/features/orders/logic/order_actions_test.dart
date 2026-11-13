import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/auth/data/session.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/logic/order_actions.dart';

import '../../../support/fixtures.dart';

void main() {
  const placed = OrderStatus.placed;
  const accepted = OrderStatus.accepted;
  const preparing = OrderStatus.preparing;
  const ready = OrderStatus.ready;
  const pickedUp = OrderStatus.pickedUp;
  const delivered = OrderStatus.delivered;
  const cancelled = OrderStatus.cancelled;

  // The status machine of docs/api.md, read per status: what the customer who
  // placed the order, the store and the courier carrying it may each do.
  const table =
      <
        OrderStatus,
        ({List<OrderStatus> customer, List<OrderStatus> store, List<OrderStatus> courier})
      >{
        placed: (customer: [cancelled], store: [accepted, cancelled], courier: []),
        accepted: (customer: [cancelled], store: [preparing, cancelled], courier: []),
        preparing: (customer: [], store: [ready, cancelled], courier: []),
        ready: (customer: [], store: [], courier: [pickedUp]),
        pickedUp: (customer: [], store: [], courier: [delivered]),
        delivered: (customer: [], store: [], courier: []),
        cancelled: (customer: [], store: [], courier: []),
      };

  for (final MapEntry(key: status, value: allowed) in table.entries) {
    test('a ${status.wire} order offers each role what the contract allows', () {
      final carried = status == pickedUp || status == delivered;
      final order = anOrder(status: status, courierId: carried ? courier.id : null);

      expect(allowedTransitions(order, customer), allowed.customer, reason: 'customer');
      expect(allowedTransitions(order, store), allowed.store, reason: 'store');
      expect(allowedTransitions(order, courier), allowed.courier, reason: 'courier');
    });
  }

  test('a customer cannot cancel an order that belongs to someone else', () {
    const someoneElse = User(id: 'customer-2', role: Role.customer, name: 'Omar');

    expect(allowedTransitions(anOrder(), someoneElse), isEmpty);
  });

  test('a courier cannot deliver an order another courier picked up', () {
    final order = anOrder(status: pickedUp, courierId: 'courier-2');

    expect(allowedTransitions(order, courier), isEmpty);
  });
}
