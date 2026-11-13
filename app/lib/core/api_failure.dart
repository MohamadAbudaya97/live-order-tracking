import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

enum ApiErrorCode {
  validationFailed('VALIDATION_FAILED'),
  unauthenticated('UNAUTHENTICATED'),
  forbidden('FORBIDDEN'),
  forbiddenTransition('FORBIDDEN_TRANSITION'),
  orderNotFound('ORDER_NOT_FOUND'),
  versionConflict('VERSION_CONFLICT'),
  invalidTransition('INVALID_TRANSITION'),

  /// No answer arrived at all.
  network,

  /// An answer arrived that the contract does not describe.
  unexpected;

  const ApiErrorCode([this.wire]);

  final String? wire;

  static ApiErrorCode fromWire(Object? wire) =>
      values.firstWhere((code) => wire != null && code.wire == wire, orElse: () => unexpected);
}

class ApiFailure extends Equatable implements Exception {
  const ApiFailure(this.code, {this.statusCode, this.serverMessage, this.body = const {}});

  factory ApiFailure.fromDio(DioException error) {
    final response = error.response;
    if (response == null) return const ApiFailure(ApiErrorCode.network);

    final data = response.data;
    final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final message = body['message'];
    return ApiFailure(
      ApiErrorCode.fromWire(body['code']),
      statusCode: response.statusCode,
      serverMessage: message is String ? message : null,
      body: body,
    );
  }

  final ApiErrorCode code;
  final int? statusCode;
  final String? serverMessage;

  /// The whole error body: some codes carry more than a code and a message.
  final Map<String, dynamic> body;

  /// True when the request may have gone through although no usable answer
  /// came back. Repeating it is only safe if the request is idempotent.
  bool get outcomeUnknown => code == ApiErrorCode.network || (statusCode ?? 0) >= 500;

  String get message => switch (code) {
    ApiErrorCode.validationFailed => serverMessage ?? 'The server did not accept this request.',
    ApiErrorCode.unauthenticated => 'Your session has ended. Sign in again.',
    ApiErrorCode.forbidden => 'You do not have access to this order.',
    ApiErrorCode.forbiddenTransition => 'You are not allowed to make this change.',
    ApiErrorCode.orderNotFound => 'This order no longer exists.',
    ApiErrorCode.versionConflict =>
      'Someone else changed this order first. You are now seeing the latest.',
    ApiErrorCode.invalidTransition => 'The order has moved on, so this step no longer applies.',
    ApiErrorCode.network => 'Cannot reach the server. Check your connection and try again.',
    ApiErrorCode.unexpected => 'Something went wrong. Please try again.',
  };

  @override
  List<Object?> get props => [code, statusCode, serverMessage, body];
}
