import 'package:dio/dio.dart';
import 'package:offline_first_app_flutter_demo/core/config/api_config.dart';

/// Creates the ONE configured HTTP client the app uses for the sync server.
///
/// Created in main.dart (the composition root), like the database.
Dio createApiClient(ApiConfig config) {
  return Dio(
    BaseOptions(
      // Every request path is relative to this, e.g. '/api/subscriptions'.
      baseUrl: config.baseUrl,
      // Sent with every request: the Express server's API-key middleware
      // rejects requests without it (401).
      headers: {'x-api-key': config.apiKey},
      contentType: Headers.jsonContentType,
      // Fail fast when the server isn't reachable, so an offline sync attempt
      // ends quickly instead of hanging; sync simply retries later.
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
}
