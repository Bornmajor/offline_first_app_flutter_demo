import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';

import 'fake_server.dart';

/// Wraps [home] the same way main.dart wraps the real app:
/// providers ABOVE MaterialApp, so every page — including ones pushed with
/// Navigator — can read the repository and the SyncCubit.
///
/// The repository is backed by [db] (an in-memory test database), or by
/// [repository] when a test needs a special one. The SyncCubit talks to a
/// fake server and is NOT started, so no timers run during widget tests.
Widget testApp(
  AppDatabase db, {
  required Widget home,
  SubscriptionRepository? repository,
}) {
  return RepositoryProvider<SubscriptionRepository>.value(
    value: repository ?? db.subscriptionRepository,
    child: BlocProvider(
      create: (_) => SyncCubit(
        SyncService(db.subscriptionsDao, FakeServer()),
        SilentNetworkInfo(),
      ),
      child: MaterialApp(home: home),
    ),
  );
}

/// Network status that never reports anything (tests focus on other things).
class SilentNetworkInfo implements NetworkInfo {
  @override
  Stream<NetworkStatus> watchStatus() => const Stream.empty();
}
