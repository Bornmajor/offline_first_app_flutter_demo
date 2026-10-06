import 'package:drift/drift.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/database/tables/sync_metadata_table.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_table.dart';

part 'subscriptions_dao.g.dart';

/// DAO = Data Access Object: the class where all SQL for one table lives.
/// The generated mixin gives it a `subscriptions` getter for the table.
///
/// Queries are added step by step:
/// READ (Step 2) ✅, CREATE (Step 3) ✅, DELETE (Step 4) ✅, UPDATE (Step 5) ✅.
@DriftAccessor(tables: [Subscriptions, SyncMetadata])
class SubscriptionsDao extends DatabaseAccessor<AppDatabase>
    with _$SubscriptionsDaoMixin {
  SubscriptionsDao(super.attachedDatabase);

  // ───────────────────────── READ ─────────────────────────

  /// LIVE list of all (not deleted) subscriptions, soonest due date first.
  ///
  /// SQL it runs:
  ///   SELECT * FROM subscriptions
  ///   WHERE is_deleted = 0
  ///   ORDER BY due_date ASC;
  ///
  /// How it reads:
  ///   select(subscriptions)   → start a query on the table ("SELECT *")
  ///   ..where(...)            → filter rows (Step 4: hide soft-deleted ones)
  ///   ..orderBy([...])        → add a clause (`..` = cascade: modify the
  ///                             query, then keep using it)
  ///   .watch()                → run it as a Stream instead of once
  ///
  /// `.watch()` vs `.get()`:
  ///   .get()   → Future: runs once, returns the rows, done.
  ///   .watch() → Stream: emits the rows now, then AGAIN every time the
  ///              `subscriptions` table changes (insert/update/delete),
  ///              no matter who made the change.
  Stream<List<SubscriptionRow>> watchAll() {
    return (select(subscriptions)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  // ─────────────────────── LOCAL CHANGES ───────────────────
  //
  // Every write the USER makes (create / update / delete) goes through
  // [_asLocalChange], which stamps two sync columns:
  //   updatedAt = now    → when this device changed it (last-write-wins)
  //   isSynced  = false  → the server doesn't have this version yet
  // Keeping the rule in one place means no write can forget it.
  // (Writes coming FROM the server in Part 4 will set isSynced = true.)

  SubscriptionsCompanion _asLocalChange(SubscriptionsCompanion changes) {
    return changes.copyWith(
      updatedAt: Value(DateTime.now()),
      isSynced: const Value(false),
    );
  }

  // ───────────────────────── CREATE ───────────────────────

  /// Adds one row.
  ///
  /// SQL it runs:  INSERT INTO subscriptions (id, name, …) VALUES (?, ?, …);
  ///
  /// How it reads:
  ///   into(subscriptions)  → "write into this table"
  ///   .insert(entry)       → run an INSERT with the Companion's values
  ///
  /// `entry` is a Companion (a partial row): columns it leaves out get their
  /// defaults — here `id` gets a fresh UUID from `clientDefault`.
  ///
  /// Side effect you get for free: every `.watch()` on this table (e.g.
  /// [watchAll]) re-runs and emits the new list.
  Future<void> insertSubscription(SubscriptionsCompanion entry) {
    return into(subscriptions).insert(_asLocalChange(entry));
  }

  // ───────────────────────── UPDATE ───────────────────────

  /// Changes an existing row.
  ///
  /// SQL it runs:
  ///   UPDATE subscriptions
  ///   SET name = ?, billing_cycle = ?, due_date = ?, category = ?, price = ?
  ///   WHERE id = ? AND is_deleted = 0;
  ///
  /// Same shape as [softDelete] — `update(table)..where(...).write(...)` —
  /// only the Companion is bigger. Columns absent from it stay unchanged.
  ///
  /// `is_deleted = 0` in the WHERE: a row deleted in the meantime (e.g. on
  /// another screen) is not silently edited back.
  ///
  /// Returns how many rows changed: 1 = updated, 0 = not found / deleted.
  ///
  /// Why not `insertOnConflictUpdate` ("upsert")? Upsert INSERTS when the id
  /// doesn't exist. For a user editing a row that should exist, a silent
  /// insert would hide bugs. Upsert is the right tool for SYNC (Part 4),
  /// where server rows may or may not exist locally yet.
  Future<int> updateSubscription(String id, SubscriptionsCompanion changes) {
    return (update(subscriptions)
          ..where((t) => t.id.equals(id) & t.isDeleted.equals(false)))
        .write(_asLocalChange(changes));
  }

  // ───────────────────────── DELETE ───────────────────────

  /// SOFT delete: marks the row as deleted instead of removing it.
  ///
  /// SQL it runs:  UPDATE subscriptions SET is_deleted = 1 WHERE id = ?;
  ///
  /// How it reads:
  ///   update(subscriptions)         → "UPDATE subscriptions"
  ///   ..where((t) => t.id.equals(id)) → only this row ("WHERE id = ?")
  ///   .write(companion)             → "SET …" — ONLY the columns present
  ///                                   in the Companion; all others untouched
  ///
  /// ⚠ Without the `where`, this would update EVERY row in the table.
  ///
  /// Returns how many rows changed (0 = id not found, 1 = done).
  /// [watchAll] re-emits and, thanks to its `is_deleted = 0` filter, the
  /// row disappears from the UI.
  Future<int> softDelete(String id) {
    return (update(subscriptions)..where((t) => t.id.equals(id))).write(
      // A delete is a local change too: the server must hear about it.
      _asLocalChange(const SubscriptionsCompanion(isDeleted: Value(true))),
    );
  }

  // ───────────────────────── SYNC ─────────────────────────
  //
  // Used only by SyncService, never by the UI. These writes come FROM the
  // server, so they skip [_asLocalChange] (they are not user changes).

  /// Rows the server doesn't have yet: new, edited, or deleted locally.
  Future<List<SubscriptionRow>> getUnsynced() {
    return (select(
      subscriptions,
    )..where((t) => t.isSynced.equals(false))).get();
  }

  /// LIVE number of rows waiting to be synced (for the "2 waiting" status).
  ///
  /// SQL: SELECT COUNT(id) FROM subscriptions WHERE is_synced = 0;
  /// `.watchSingle()` re-runs it whenever the table changes.
  Stream<int> watchUnsyncedCount() {
    final count = subscriptions.id.count();
    final query = selectOnly(subscriptions)
      ..addColumns([count])
      ..where(subscriptions.isSynced.equals(false));
    return query.map((row) => row.read(count)!).watchSingle();
  }

  /// One row by id, including deleted ones.
  Future<SubscriptionRow?> findById(String id) {
    return (select(
      subscriptions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// "The server has this version now."
  ///
  /// Only marks the row if it still has the [updatedAt] we uploaded. If the
  /// user edited it during the upload, it stays unsynced and the newer edit
  /// is sent next time.
  Future<void> markSynced(String id, DateTime updatedAt) {
    return (update(subscriptions)
          ..where((t) => t.id.equals(id) & t.updatedAt.equals(updatedAt)))
        .write(const SubscriptionsCompanion(isSynced: Value(true)));
  }

  /// Saves the server's version: inserts it, or replaces the local row.
  Future<void> saveFromServer(SubscriptionsCompanion row) {
    return into(subscriptions).insertOnConflictUpdate(row);
  }

  /// Removes a row for good. Only once the server knows it's deleted.
  Future<void> hardDelete(String id) {
    return (delete(subscriptions)..where((t) => t.id.equals(id))).go();
  }

  // The "bookmark": server time of the last download, so the next download
  // only asks for newer changes. Stored in the sync_metadata table.

  static const _lastPulledAtKey = 'subscriptions.lastPulledAt';

  Future<String?> getLastPulledAt() async {
    final row = await (select(
      syncMetadata,
    )..where((t) => t.key.equals(_lastPulledAtKey))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setLastPulledAt(String serverTime) {
    return into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion.insert(key: _lastPulledAtKey, value: serverTime),
    );
  }
}
