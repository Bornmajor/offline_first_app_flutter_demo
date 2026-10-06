import 'package:dio/dio.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/local/subscriptions_dao.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';

/// Keeps the local database and the server in step.
///
/// One sync = two steps:
///   1. PUSH: send my changes to the server
///   2. PULL: fetch changes made elsewhere (another phone, the dashboard)
///
/// It only reads and writes the database. The screens are never told
/// anything: when a row changes, watchAll() re-emits and the list updates,
/// exactly like after a local edit.
class SyncService {
  SyncService(this._dao, this._api);

  final SubscriptionsDao _dao;
  final SubscriptionApi _api;

  bool _isSyncing = false;

  /// Runs one full sync. Throws [DioException] if the server can't be reached;
  /// nothing is lost then: unsynced rows simply wait for the next sync.
  Future<void> sync() async {
    if (_isSyncing) return; // one sync at a time
    _isSyncing = true;
    try {
      await _push(); // first: our changes reach the server…
      await _pull(); // …then: download, so it can't overwrite our changes
    } finally {
      _isSyncing = false;
    }
  }

  // ─────────────────── 1. PUSH: my changes → server ───────────────────

  Future<void> _push() async {
    final unsynced = await _dao.getUnsynced();

    for (final row in unsynced) {
      try {
        if (row.isDeleted) {
          // Deleted on this phone → tell the server, then the local
          // "tombstone" row has done its job and can go.
          await _api.delete(row);
          await _dao.hardDelete(row.id);
        } else {
          // Created or edited on this phone → upload it.
          final response = await _api.upload(row);

          if (response['applied'] == true) {
            await _dao.markSynced(row.id, row.updatedAt); // server has it ✓
          } else {
            // The server kept its own version (newer, or deleted there).
            // The server wins: take its version.
            await _saveServerVersion(response['subscription']);
          }
        }
      } on DioException catch (e) {
        // No response at all = offline / server down → stop syncing.
        if (e.response == null) rethrow;
        // The server rejected just THIS row (e.g. invalid data): leave it
        // unsynced and carry on with the others.
      }
    }
  }

  // ─────────────── 2. PULL: changes from elsewhere → me ───────────────

  Future<void> _pull() async {
    // The bookmark: "I already have everything up to this server time."
    // null on the very first sync → the server sends everything.
    final since = await _dao.getLastPulledAt();

    final response = await _api.download(since);

    // Save the changes AND the new bookmark together: if the app is killed
    // halfway, neither is saved, and the next sync simply downloads again.
    await _dao.transaction(() async {
      for (final json in response['subscriptions'] as List) {
        await _saveServerVersion(json);
      }
      await _dao.setLastPulledAt(response['serverTime'] as String);
    });
  }

  // ───────── The one rule: "the server says this is the record now" ─────────

  Future<void> _saveServerVersion(Map<String, dynamic> json) async {
    final id = json['_id'] as String;

    // Deleted on the server → delete here too ("deletes win").
    if (json['deletedAt'] != null) {
      await _dao.hardDelete(id);
      return;
    }

    // Last-write-wins: if this phone has a NEWER change that isn't uploaded
    // yet, keep it. The next push sends it to the server.
    final local = await _dao.findById(id);
    final serverUpdatedAt = DateTime.parse(json['updatedAt'] as String);
    if (local != null &&
        !local.isSynced &&
        local.updatedAt.isAfter(serverUpdatedAt)) {
      return;
    }

    // Otherwise the server's version is the latest: save it.
    await _dao.saveFromServer(SubscriptionApi.fromJson(json));
  }
}
