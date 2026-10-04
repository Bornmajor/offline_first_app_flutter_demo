import 'package:flutter/material.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';

void main() {
  // Required because we do work (create the database) before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // ONE database for the whole app. Opening several AppDatabase instances on
  // the same file causes race conditions (Drift warns about it in debug).
  //
  // Note: this does NOT open the SQLite file yet. Drift opens it lazily,
  // on the first query.
  // Dependency Injection (DI): "pass it in, don't create it inside"
  final db = AppDatabase();

  // The UI never touches `db` directly, only the repository.
  final repository = db.subscriptionRepository;

  runApp(MyApp(repository: repository));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.repository});

  /// Passed down by constructor. In Part 3 (Bloc), RepositoryProvider
  /// replaces this manual passing.
  final SubscriptionRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Offline First App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: HomePage(repository: repository),
    );
  }
}
