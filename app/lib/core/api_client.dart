import 'package:dio/dio.dart';

import 'api_failure.dart';

/// JSON over HTTP against the API. Every error leaves as an [ApiFailure].
class ApiClient {
  ApiClient({required String baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  /// Bearer token of the signed-in user. It only ever lives in memory.
  String? token;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String> headers = const {},
  }) => _send('POST', path, body: body, headers: headers);

  Future<void> put(String path, {required Map<String, dynamic> body}) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    final token = this.token;
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {...headers, if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      final data = response.data;
      return data is Map<String, dynamic> ? data : const {};
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }
}
