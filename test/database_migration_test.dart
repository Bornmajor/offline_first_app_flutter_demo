import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';

/// Simulates a user who installed the app at schema version 1 (Step 3),
/// added a subscription, and then updated to the current version.
void main() {
  test('v1 → v2: existing rows survive and get is_deleted = false', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        // `setup` runs on the raw SQLite connection BEFORE Drift looks at it,
        // so we can recreate exactly what a version-1 file looked like.
        setup: (raw) {
          raw.execute('''
            CREATE TABLE subscriptions (
              id TEXT NOT NULL,
              name TEXT NOT NULL,
              billing_cycle TEXT NOT NULL,
              due_date INTEGER NOT NULL,
              category TEXT NOT NULL,
              price REAL NOT NULL,
              PRIMARY KEY (id)
            );
          ''');
          raw.execute(
            "INSERT INTO subscriptions VALUES "
            "('old-1', 'Netflix', 'monthly', 1791331200, 'Entertainment', 9.99);",
          );
          // SQLite keeps the schema version in this pragma; Drift reads it
          // to decide between onCreate / onUpgrade.
          raw.userVersion = 1;
        },
      ),
    );
    addTearDown(db.close);

    // First query opens the database → Drift sees version 1 < 2 → onUpgrade.
    final rows = await db.select(db.subscriptions).get();

    final row = rows.single;
    expect(row.id, 'old-1');
    expect(row.name, 'Netflix');
    expect(row.billingCycle, BillingCycles.monthly);
    expect(row.price, 9.99);
    expect(row.isDeleted, isFalse); // new column filled by its default

    // And the upgraded file now reports the new version.
    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, 2);
  });
}
