import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/background_sync.dart';

import '../helpers/fake_server.dart';
import '../helpers/test_database.dart';

/// runBackgroundSync() opens and closes its OWN database, like the real
/// background isolate. Each test prepares a database first, then hands it
/// over through `openDatabase`, and checks the fake server afterwards.
void main() {
  late FakeServer server;

  setUp(() => server = FakeServer());

  /// A test database with one subscription created offline (not synced).
  Future<AppDatabase> databaseWithOfflineChange() async {
    final db = createTestDatabase();
    await db.subscriptionRepository.create(
      name: 'Netflix',
      billingCycle: BillingCycles.monthly,
      dueDate: DateTime(2026, 10, 7),
      category: 'Entertainment',
      price: 9.99,
    );
    return db;
  }

  test('app closed (no heartbeat): uploads the offline change', () async {
    final db = await databaseWithOfflineChange();

    final ok = await runBackgroundSync(
      openDatabase: () => db,
      createApi: () => server,
    );

    expect(ok, isTrue);
    expect(server.records, hasLength(1)); // reached the server
  });

  test('app in the foreground (fresh heartbeat): skips, no requests', () async {
    final db = await databaseWithOfflineChange();
    await db.subscriptionsDao.setForegroundActiveUntil(
      DateTime.now().add(const Duration(minutes: 2)),
    );

    final ok = await runBackgroundSync(
      openDatabase: () => db,
      createApi: () => server,
    );

    expect(ok, isTrue); // nothing went wrong, just not our turn
    expect(server.records, isEmpty);
    expect(server.downloads, isEmpty);
  });

  test('app killed (heartbeat expired): syncs', () async {
    final db = await databaseWithOfflineChange();
    await db.subscriptionsDao.setForegroundActiveUntil(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );

    await runBackgroundSync(openDatabase: () => db, createApi: () => server);

    expect(server.records, hasLength(1));
  });

  test('offline: returns false so the OS retries later', () async {
    final db = await databaseWithOfflineChange();
    server.offline = true;

    final ok = await runBackgroundSync(
      openDatabase: () => db,
      createApi: () => server,
    );

    expect(ok, isFalse);
  });
}
