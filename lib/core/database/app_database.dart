import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
// BillingCycles and Uuid are used by the generated part file (enum column
// and id clientDefault), which only sees this file's imports.
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_dao.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_table.dart';
import 'package:uuid/uuid.dart';

// The generated code (`_$AppDatabase`) lives in this file.
// Regenerate after changing tables/DAOs: dart run build_runner build
part 'app_database.g.dart';

/// Single SQLite database for the app — the offline source of truth.
/// Tables and DAOs live in their features and are registered here.
@DriftDatabase(tables: [Subscriptions], daos: [SubscriptionsDao])
class AppDatabase extends _$AppDatabase {
  /// Real database: a file named `subscriptions_db` in the app's storage.
  AppDatabase() : super(_openConnection());

  /// For tests: pass an in-memory connection instead of a file.
  AppDatabase.forTesting(super.executor);

  /// Version of the table layout. Bump it when tables change and add an
  /// upgrade step in [migration], so existing users keep their data.
  ///
  /// History:
  ///   1 — subscriptions table (Step 1)
  ///   2 — subscriptions.is_deleted column for soft delete (Step 4)
  @override
  int get schemaVersion => 2;

  /// SQLite stores the schema version inside the file. When the app opens
  /// the file, Drift compares it with [schemaVersion]:
  ///
  ///   • no file yet            → onCreate  (fresh install)
  ///   • file version < current → onUpgrade (app was updated)
  ///   • equal                  → nothing to do
  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Fresh install: create every table in its LATEST shape (already
    // including is_deleted), so no upgrade steps are needed afterwards.
    onCreate: (m) => m.createAll(),

    // Existing install: walk up one version at a time.
    // `from` = version in the file, `to` = schemaVersion.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // ALTER TABLE subscriptions ADD COLUMN is_deleted … DEFAULT 0;
        // Existing rows keep all their data and get is_deleted = false.
        await m.addColumn(subscriptions, subscriptions.isDeleted);
      }
      // Future example: if (from < 3) { … next change … }
    },
  );

  /// `drift_flutter` picks the right SQLite setup per platform and stores
  /// the file in the app's documents folder.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'subscriptions_db');
  }
}
