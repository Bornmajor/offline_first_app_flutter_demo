import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/dio_client.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';
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

  // ONE HTTP client for the server (address, API key, timeouts).
  final dio = createDioClient();

  // ONE sync engine: keeps the database and the server in step.
  final syncService = SyncService(db.subscriptionsDao, SubscriptionApi(dio));

  runApp(
    // DEPENDENCY INJECTION via the widget tree.
    //
    // MultiRepositoryProvider = several RepositoryProviders in one widget.
    // Each object is available to every widget below it with
    //   context.read<SubscriptionRepository>()
    //   context.read<SyncService>()
    //
    // It sits ABOVE MaterialApp on purpose: pages opened with
    // Navigator.push live inside MaterialApp's Navigator, so they are
    // below these providers too and can find them.
    //
    // `.value` = "I already created the object, just share it". The provider
    // won't dispose it; these live as long as the app.
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SubscriptionRepository>.value(
          value: db.subscriptionRepository,
        ),
        RepositoryProvider<SyncService>.value(value: syncService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ONE SyncCubit for the whole app (above MaterialApp, so every page can
    // read it). `lazy: false` creates it right away, and `..start()` turns
    // on the automatic sync triggers as soon as the app opens.
    return BlocProvider(
      lazy: false,
      create: (context) =>
          SyncCubit(context.read<SyncService>(), NetworkInfo())..start(),
      child: MaterialApp(
        title: 'Flutter Offline First App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
        home: const HomePage(),
      ),
    );
  }
}
