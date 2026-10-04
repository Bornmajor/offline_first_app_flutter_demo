import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';

/// A real Drift database that lives in memory: fast, isolated per test,
/// and gone when closed. Remember to `close()` it in tearDown.
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(
    DatabaseConnection(
      NativeDatabase.memory(),
      // Lets stream queries shut down immediately when the db is closed,
      // so widget tests don't complain about pending timers.
      closeStreamsSynchronously: true,
    ),
  );
}

/// Test-only shortcut to put a row in the table directly with Drift
/// (the app's own CREATE arrives in Step 3).
Future<void> insertTestSubscription(
  AppDatabase db, {
  required String name,
  required DateTime dueDate,
  BillingCycles billingCycle = BillingCycles.monthly,
  String category = 'Entertainment',
  double price = 9.99,
}) {
  return db
      .into(db.subscriptions)
      .insert(
        SubscriptionsCompanion.insert(
          name: name,
          billingCycle: billingCycle,
          dueDate: dueDate,
          category: category,
          price: price,
        ),
      );
}
