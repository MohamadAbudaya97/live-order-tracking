import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';
import 'package:live_order_tracking/features/orders/logic/courier_delivery_cubit.dart';
import 'package:live_order_tracking/features/orders/logic/route.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';

class MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  final pickedUp = anOrder(status: OrderStatus.pickedUp, seq: 5, courierId: courier.id);
  final delivered = anOrder(status: OrderStatus.delivered, seq: 6, courierId: courier.id);

  late MockOrderRepository repository;
  late List<({double lat, double lng, int heading})> sent;

  setUpAll(() {
    registerFallbackValue(pickedUp);
    registerFallbackValue(OrderStatus.placed);
  });

  setUp(() {
    repository = MockOrderRepository();
    sent = [];
    when(
      () => repository.sendCourierLocation(
        orderId,
        lat: any(named: 'lat'),
        lng: any(named: 'lng'),
        heading: any(named: 'heading'),
      ),
    ).thenAnswer((invocation) async {
      final position = invocation.namedArguments;
      sent.add((
        lat: position[#lat] as double,
        lng: position[#lng] as double,
        heading: position[#heading] as int,
      ));
    });
    when(() => repository.transition(any(), OrderStatus.delivered))
        .thenAnswer((_) async => delivered);
  });

  test('the walk sends one position a second and arrives at the drop-off', () {
    fakeAsync((async) {
      final cubit = CourierDeliveryCubit(repository, pickedUp)..simulateRoute();

      async.elapse(const Duration(milliseconds: 2500));
      expect(sent, hasLength(3));
      expect(cubit.state.walking, isTrue);

      async.elapse(const Duration(seconds: 40));
      expect(sent, hasLength(CourierDeliveryCubit.routeSteps));
      expect(sent.map((position) => position.heading).toSet(), {
        bearing(pickedUp.pickup, pickedUp.dropoff),
      });
      expect((sent.last.lat, sent.last.lng), (pickedUp.dropoff.lat, pickedUp.dropoff.lng));
      expect(cubit.state.step, CourierDeliveryCubit.routeSteps);
      expect(cubit.state.walking, isFalse);
    });
  });

  test('delivering ends the walk, so no position follows the delivery', () {
    fakeAsync((async) {
      final cubit = CourierDeliveryCubit(repository, pickedUp)..simulateRoute();
      async.elapse(const Duration(milliseconds: 2500));

      cubit.markDelivered();
      async.elapse(const Duration(seconds: 40));

      expect(sent, hasLength(3));
      expect(cubit.state.order.status, OrderStatus.delivered);
      expect(cubit.state.walking, isFalse);
    });
  });
}
