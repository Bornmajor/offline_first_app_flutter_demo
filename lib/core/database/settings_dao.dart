import 'package:drift/drift.dart';
import 'package:offline_first_subscription_app/core/database/app_database.dart';
import 'package:offline_first_subscription_app/core/database/tables/sync_metadata_table.dart';

part 'settings_dao.g.dart';

/// Small app settings stored in the local database's key/value table, e.g.
///   ('push.token', 'cA1b2…')   ('settings.reminderTiming', 'one_day_before')
///
/// Stored locally (not only on the server), so settings work offline and
/// survive restarts.
@DriftAccessor(tables: [SyncMetadata])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Future<String?> read(String key) async {
    final row = await (select(
      syncMetadata,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) {
    return into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion.insert(key: key, value: value),
    );
  }
}
