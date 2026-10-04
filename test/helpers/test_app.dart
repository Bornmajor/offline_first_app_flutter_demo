import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';

/// Wraps [home] the same way main.dart wraps the real app:
/// RepositoryProvider ABOVE MaterialApp, so every page — including ones
/// pushed with Navigator — can `context.read<SubscriptionRepository>()`.
///
/// The repository is backed by [db] (an in-memory test database).
Widget testApp(AppDatabase db, {required Widget home}) {
  return RepositoryProvider<SubscriptionRepository>.value(
    value: db.subscriptionRepository,
    child: MaterialApp(home: home),
  );
}
