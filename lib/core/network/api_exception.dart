import 'package:dio/dio.dart';

/// One error type for every failed server call, so the sync engine doesn't
/// need to know about dio.
///
/// The key question for an offline-first app is: did we reach the server?
///   • [isNetworkError] → no (offline, server down, timeout). Nothing is
///     wrong with the data: just try again later.
///   • otherwise → the server answered with an error ([statusCode], e.g.
///     400 invalid data, 401 wrong API key). Retrying won't help by itself.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// Converts a dio error into an [ApiException].
  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) {
      // No HTTP response at all: connection refused, no internet, timeout.
      return ApiException('Could not reach the server (${error.type.name}).');
    }
    // The server answered; our API puts the reason in `message`.
    final data = response.data;
    final serverMessage = data is Map && data['message'] is String
        ? data['message'] as String
        : null;
    return ApiException(
      serverMessage ?? 'Server error ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  final String message;

  /// HTTP status, or null when no response was received.
  final int? statusCode;

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => statusCode == null
      ? 'ApiException: $message'
      : 'ApiException($statusCode): $message';
}
