import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/core/api_failure.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';
import 'package:live_order_tracking/features/orders/logic/place_order_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';

class MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  late MockOrderRepository repository;
  late PlaceOrderCubit cubit;

  /// How the server treats the requests from here on: it creates the order,
  /// or the request ends in [failure].
  void serverAnswers({ApiFailure? failure}) {
    when(() => repository.placeDemoOrder(idempotencyKey: any(named: 'idempotencyKey')))
        .thenAnswer((_) async => failure == null ? anOrder() : throw failure);
  }

  /// The idempotency keys of the requests made so far, oldest first.
  List<String> sentKeys() =>
      verify(() => repository.placeDemoOrder(idempotencyKey: captureAny(named: 'idempotencyKey')))
          .captured
          .cast<String>();

  setUp(() {
    var keys = 0;
    repository = MockOrderRepository();
    cubit = PlaceOrderCubit(repository, newKey: () => 'key-${++keys}');
  });

  tearDown(() => cubit.close());

  test('a retry after a lost answer sends the key of the first attempt', () async {
    serverAnswers(failure: const ApiFailure(ApiErrorCode.network));
    await cubit.placeDemoOrder();
    expect(cubit.state.failure?.code, ApiErrorCode.network);

    serverAnswers();
    await cubit.placeDemoOrder();

    expect(sentKeys(), ['key-1', 'key-1']);
    expect(cubit.state.placed, anOrder());
  });

  test('a server error keeps the key too, because the order may exist', () async {
    serverAnswers(failure: const ApiFailure(ApiErrorCode.unexpected, statusCode: 500));
    await cubit.placeDemoOrder();
    await cubit.placeDemoOrder();

    expect(sentKeys(), ['key-1', 'key-1']);
  });

  test('the next order after a success gets a key of its own', () async {
    serverAnswers();
    await cubit.placeDemoOrder();
    await cubit.placeDemoOrder();

    expect(sentKeys(), ['key-1', 'key-2']);
  });

  test('a request the server turned down is not repeated under the same key', () async {
    serverAnswers(failure: const ApiFailure(ApiErrorCode.validationFailed, statusCode: 400));
    await cubit.placeDemoOrder();
    await cubit.placeDemoOrder();

    expect(sentKeys(), ['key-1', 'key-2']);
  });

  test('a second tap while the first request is in flight sends nothing', () async {
    serverAnswers();
    final first = cubit.placeDemoOrder();
    await cubit.placeDemoOrder();
    await first;

    expect(sentKeys(), ['key-1']);
  });
}
