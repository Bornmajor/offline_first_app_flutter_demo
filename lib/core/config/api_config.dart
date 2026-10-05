import 'package:flutter/foundation.dart';

/// Where the sync server is and how to authenticate.
///
/// Values come from the RUN COMMAND, not from source code, so the API key is
/// never committed to Git:
///
///   flutter run --dart-define=API_KEY=YOUR_KEY
///   flutter run --dart-define=API_KEY=YOUR_KEY --dart-define=API_BASE_URL=http://192.168.1.20:5000
///
/// `String.fromEnvironment` reads a `--dart-define` value at COMPILE time
/// (that's why these are `const`). Changing them needs a restart, not a
/// hot reload.
class ApiConfig {
  const ApiConfig({required this.baseUrl, required this.apiKey});

  /// Builds the config from `--dart-define` values (or platform defaults).
  factory ApiConfig.fromEnvironment() {
    const definedUrl = String.fromEnvironment('API_BASE_URL');
    const apiKey = String.fromEnvironment('API_KEY');
    return ApiConfig(
      baseUrl: definedUrl.isNotEmpty ? definedUrl : _defaultBaseUrl(),
      apiKey: apiKey,
    );
  }

  /// e.g. `http://10.0.2.2:5000` (no trailing slash).
  final String baseUrl;

  /// Sent as the `x-api-key` header. Empty = not configured.
  final String apiKey;

  bool get hasApiKey => apiKey.isNotEmpty;

  /// Address of the Express server running on YOUR PC, seen from the app:
  ///   • Android emulator → 10.0.2.2 is the emulator's alias for the PC
  ///     ("localhost" there would mean the emulator itself)
  ///   • Windows/macOS/Linux app, iOS simulator, web → the PC is localhost
  ///   • physical phone → none of these; pass your PC's Wi-Fi IP with
  ///     --dart-define=API_BASE_URL=http://YOUR_PC_IP:5000
  static String _defaultBaseUrl() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }
}
