import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/config/api_config.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/api_client.dart';
import 'package:offline_first_app_flutter_demo/core/network/api_exception.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/dio_subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';

void main() {
  // Required because we do work (create the database) before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // COMPOSITION ROOT: the one place where dependencies are created.
  //
  // ONE database for the whole app. Opening several AppDatabase instances on
  // the same file causes race conditions (Drift warns about it in debug).
  // Note: this does NOT open the SQLite file yet. Drift opens it lazily,
  // on the first query.
  final db = AppDatabase();

  // ONE HTTP client + API for the sync server, configured from
  // --dart-define values (see ApiConfig). Used by the sync engine (A3).
  final apiConfig = ApiConfig.fromEnvironment();
  final subscriptionApi = DioSubscriptionApi(createApiClient(apiConfig));

  // TEMPORARY (A2 only, removed in A3): one authenticated request to check
  // the address and API key, printed to the debug console.
  if (kDebugMode) {
    _checkServerConnection(apiConfig, subscriptionApi);
  }

  runApp(
    // DEPENDENCY INJECTION via the widget tree.
    //
    // RepositoryProvider (from flutter_bloc) makes ONE SubscriptionRepository
    // available to every widget below it. Any widget can get it with:
    //   context.read<SubscriptionRepository>()
    //
    // It sits ABOVE MaterialApp on purpose: pages opened with
    // Navigator.push live inside MaterialApp's Navigator, so they are
    // below this provider too and can find it.
    //
    // `.value` = "I already created the object, just share it". The provider
    // won't dispose it; the database lives as long as the app.
    RepositoryProvider<SubscriptionRepository>.value(
      value: db.subscriptionRepository,
      child: const MyApp(),
    ),
  );
}

/// TEMPORARY (A2): asks for "changes since now" — an empty list — which only
/// succeeds if the server is reachable AND accepts the API key.
Future<void> _checkServerConnection(
  ApiConfig config,
  SubscriptionApi api,
) async {
  if (!config.hasApiKey) {
    debugPrint(
      'Sync server: no API key. Run with --dart-define=API_KEY=YOUR_KEY',
    );
    return;
  }
  try {
    final result = await api.pull(updatedSince: DateTime.now());
    debugPrint(
      'Sync server OK at ${config.baseUrl} '
      '(server time ${result.serverTime.toIso8601String()})',
    );
  } on ApiException catch (e) {
    debugPrint(
      e.isNetworkError
          ? 'Sync server NOT reachable at ${config.baseUrl}: ${e.message}'
          : 'Sync server answered ${e.statusCode}: ${e.message}',
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Offline First App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const HomePage(),
    );
  }
}
