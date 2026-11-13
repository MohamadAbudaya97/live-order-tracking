import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/core/api_failure.dart';
import 'package:live_order_tracking/features/orders/data/models/order_status.dart';
import 'package:live_order_tracking/features/orders/data/order_repository.dart';

import '../support/fixtures.dart';

DioException answered(int statusCode, Object? body) {
  final request = RequestOptions(path: '/orders/$orderId/transitions');
  return DioException.badResponse(
    statusCode: statusCode,
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: statusCode, data: body),
  );
}

void main() {
  test('reads the status, code and message of an error body', () {
    final failure = ApiFailure.fromDio(
      answered(422, {
        'statusCode': 422,
        'code': 'INVALID_TRANSITION',
        'message': 'Cannot go from delivered to cancelled',
        'from': 'delivered',
        'to': 'cancelled',
      }),
    );

    expect(failure.code, ApiErrorCode.invalidTransition);
    expect(failure.statusCode, 422);
    expect(failure.serverMessage, 'Cannot go from delivered to cancelled');
    expect(failure.outcomeUnknown, isFalse);
  });

  test('a version conflict carries the order as it is now', () {
    final failure = ApiFailure.fromDio(
      answered(409, {
        'statusCode': 409,
        'code': 'VERSION_CONFLICT',
        'message': 'Order was changed by someone else',
        'current': orderJson(status: 'accepted', seq: 2),
      }),
    );

    expect(failure.code, ApiErrorCode.versionConflict);
    expect(failure.currentOrder, anOrder(status: OrderStatus.accepted, seq: 2));
  });

  test('other failures carry no order', () {
    final failure = ApiFailure.fromDio(
      answered(404, {'statusCode': 404, 'code': 'ORDER_NOT_FOUND', 'message': 'Order not found'}),
    );

    expect(failure.code, ApiErrorCode.orderNotFound);
    expect(failure.currentOrder, isNull);
  });

  test('no answer at all is a network failure with an unknown outcome', () {
    final failure = ApiFailure.fromDio(
      DioException.connectionError(requestOptions: RequestOptions(), reason: 'refused'),
    );

    expect(failure.code, ApiErrorCode.network);
    expect(failure.outcomeUnknown, isTrue);
  });

  test('an answer outside the contract is unexpected, and unknown when it is a 5xx', () {
    final failure = ApiFailure.fromDio(answered(502, '<html>Bad Gateway</html>'));

    expect(failure.code, ApiErrorCode.unexpected);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.message, isNotEmpty);
  });
}
