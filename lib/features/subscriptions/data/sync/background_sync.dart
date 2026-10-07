import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/dio_client.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:workmanager/workmanager.dart';

// ─────────────────────────────────────────────────────────────────────────
// Background sync: runs SyncService.sync() while the app is NOT on screen —
// switched away, or even closed/killed. The OS (Android WorkManager) decides
// exactly when; we only ask: "soon, when there's internet" and "regularly".
// ─────────────────────────────────────────────────────────────────────────

/// Entry point the OS calls in a FRESH Dart isolate — nothing from the app
/// (providers, SyncCubit, the app's database object) exists there.
///
/// Must be a top-level function. `@pragma('vm:entry-point')` stops the
/// compiler from removing it in release builds (nothing in Dart calls it).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) => runBackgroundSync());
}

/// One background sync. Returns true = done, false = "OS, retry later".
///
/// Kept separate from [callbackDispatcher] so tests can call it directly
/// with an in-memory database and a fake server.
Future<bool> runBackgroundSync({
  AppDatabase Function()? openDatabase,
  SubscriptionApi Function()? createApi,
}) async {
  // Build everything this isolate needs, like main() does for the app.
  final db = (openDatabase ?? AppDatabase.new)();
  try {
    // Heartbeat check: the app is visible and syncing itself → skip.
    final activeUntil = await db.subscriptionsDao.getForegroundActiveUntil();
    if (activeUntil != null && activeUntil.isAfter(DateTime.now())) {
      debugPrint('Background sync skipped: the app is in the foreground');
      return true;
    }

    final api = (createApi ?? () => SubscriptionApi(createDioClient()))();
    await SyncService(db.subscriptionsDao, api).sync();
    debugPrint('Background sync done');
    return true;
  } catch (error) {
    // Offline, server down, … — never crash in the background. `false`
    // makes WorkManager retry later, waiting longer each time (backoff).
    debugPrint('Background sync failed, will retry: $error');
    return false;
  } finally {
    await db.close();
  }
}

/// Asks the OS to run background syncs. Used by SyncCubit.
///
/// Two kinds of work:
///   • one-off  "sync when connected" — queued when the app leaves the
///     screen with changes waiting; runs as soon as there's internet, even
///     if the app is closed
///   • periodic "sync every ~30 min" — picks up changes made elsewhere
class BackgroundSyncScheduler {
  static const _taskName = 'subscription-sync';
  static const _oneOffName = 'sync-pending';
  static const _periodicName = 'periodic-sync';

  /// WorkManager exists on Android (and iOS, with extra setup). Elsewhere —
  /// Windows, web, tests — every method does nothing.
  bool get _isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Constraints get _needsInternet =>
      Constraints(networkType: NetworkType.connected);

  /// Once, at app start: register the entry point and the periodic task.
  Future<void> initialize() async {
    if (!_isSupported) return;
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _periodicName,
      _taskName,
      frequency: const Duration(minutes: 30), // Android minimum is 15
      constraints: _needsInternet,
      // Keep the existing schedule; don't restart the clock on every launch.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Queue ONE "sync when connected" task (replacing any queued one, so many
  /// calls still mean one task).
  Future<void> scheduleSoon() async {
    if (!_isSupported) return;
    await Workmanager().registerOneOffTask(
      _oneOffName,
      _taskName,
      constraints: _needsInternet,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential, // retry: 30 s, 1 min, 2 min…
    );
  }

  /// The app is back on screen and syncs itself: drop the queued task.
  Future<void> cancelScheduled() async {
    if (!_isSupported) return;
    await Workmanager().cancelByUniqueName(_oneOffName);
  }
}
