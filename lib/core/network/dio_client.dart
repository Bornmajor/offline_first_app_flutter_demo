import 'package:dio/dio.dart';

/// The ONE HTTP client for talking to our Express server.
///
/// It only knows HOW to connect (address, API key, timeouts), not what to
/// ask. Feature APIs like SubscriptionApi receive it and make the calls.
/// Created once in main.dart, like the database.
Dio createDioClient() {
  return Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      // The server rejects requests without the right key (401).
      headers: {'x-api-key': apiKey},
      // Fail fast when offline, so a sync attempt ends quickly and the app
      // just tries again later.
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
}

/// Set when running the app (never written in code, so it's not in Git):
///   flutter run --dart-define=API_KEY=YOUR_KEY
const apiKey = String.fromEnvironment('API_KEY');

/// Where the server runs. Default: 10.0.2.2 = "your PC", seen from the
/// Android emulator. Override with --dart-define=API_BASE_URL=…
///   physical phone:              http://YOUR_PC_IP:5000
///   Windows app / iOS simulator: http://localhost:5000
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5000',
);
