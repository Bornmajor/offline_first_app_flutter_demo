import 'package:drift/drift.dart';

/// Small key/value store for sync bookkeeping, e.g.
///   ('subscriptions.lastPulledAt', '2026-10-05T09:00:00.000Z')
///
/// Why a table and not SharedPreferences? The pull cursor must be saved in
/// the SAME database transaction as the rows it describes: either both the
/// pulled rows and the new cursor are stored, or neither is. Two separate
/// storage systems can't give that guarantee.
@DataClassName('SyncMetadataRow')
class SyncMetadata extends Table {
  /// Setting name, namespaced by feature (e.g. `subscriptions.lastPulledAt`).
  TextColumn get key => text()();

  /// Setting value as text (e.g. an ISO-8601 date).
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
