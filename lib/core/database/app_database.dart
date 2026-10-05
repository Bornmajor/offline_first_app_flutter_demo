import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
// BillingCycles and Uuid are used by the generated part file (enum column
// and id clientDefault), which only sees this file's imports.
import 'package:offline_first_app_flutter_demo/core/database/tables/sync_metadata_table.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_dao.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_table.dart';
import 'package:uuid/uuid.dart';

// The generated code (`_$AppDatabase`) lives in this file.
// Regenerate after changing tables/DAOs: dart run build_runner build
part 'app_database.g.dart';

/// Single SQLite database for the app — the offline source of truth.
/// Tables and DAOs live in their features and are registered here;
/// app-wide tables (like sync bookkeeping) live in core/database/tables.
@DriftDatabase(tables: [Subscriptions, SyncMetadata], daos: [SubscriptionsDao])
class AppDatabase extends _$AppDatabase {
  /// Real database: a file named `subscriptions_db` in the app's storage.
  AppDatabase() : super(_openConnection());

  /// For tests: pass an in-memory connection instead of a file.
  AppDatabase.forTesting(super.executor);

  /// Version of the table layout, stored inside the SQLite file.
  ///
  /// SQUASHED to 1 during development (Part 4): the app has no released
  /// users, so earlier versions (1: subscriptions, 2: is_deleted) were folded
  /// into one clean starting schema. Dev installs must be uninstalled (or
  /// have their data cleared) once.
  ///
  /// ⚠ From the FIRST RELEASE on, never squash again: bump this number and
  /// add an `onUpgrade` step for every change, so users keep their data —
  /// in an offline-first app their local data may exist nowhere else.
  @override
  int get schemaVersion => 1;

  /// SQLite stores the schema version inside the file. When the app opens
  /// the file, Drift compares it with [schemaVersion]:
  ///
  ///   • no file yet            → onCreate  (fresh install)
  ///   • file version < current → onUpgrade (none yet — see above)
  ///   • equal                  → nothing to do
  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Fresh install: create every table in its current shape.
    onCreate: (m) => m.createAll(),
  );

  /// `drift_flutter` picks the right SQLite setup per platform and stores
  /// the file in the app's documents folder.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'subscriptions_db');
  }
}
