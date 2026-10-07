import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/background_sync.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_state.dart';

/// Decides WHEN to sync, and tells the UI how syncing is going.
///
/// SyncService knows HOW to sync; this Cubit only calls `sync()` at the
/// right moments — but ONLY WHILE THE APP IS ON SCREEN:
///   1. when the app starts, and when it comes back (resumed)
///   2. after the user changes something (a couple of seconds later, so
///      several quick edits become one sync)
///   3. when the internet comes back
///   4. every few minutes, to pick up changes made on other devices
///   5. when the user asks (pull-to-refresh, or tapping the status)
///
/// When the app leaves the screen it hands over to background sync
/// (WorkManager), so the two never sync at the same time.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(
    this._syncService,
    this._networkInfo, {
    this.backgroundSync,
    this.debounce = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 5),
    this.heartbeatEvery = const Duration(minutes: 1),
    this.heartbeatValidFor = const Duration(minutes: 2),
  }) : super(const SyncState());

  final SyncService _syncService;
  final NetworkInfo _networkInfo;

  /// null = no background sync (e.g. in tests).
  final BackgroundSyncScheduler? backgroundSync;

  /// Wait this long after a local change before syncing (trigger 2).
  final Duration debounce;

  /// Sync this often while the app is open (trigger 4).
  final Duration interval;

  /// How often to renew the heartbeat, and how long each one stays valid.
  /// Valid > every, so the heartbeat never lapses while the app is open.
  final Duration heartbeatEvery;
  final Duration heartbeatValidFor;

  StreamSubscription<int>? _pendingSubscription;
  StreamSubscription<NetworkStatus>? _networkSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _heartbeatTimer;

  /// Is the app on screen? Triggers only act while it is.
  bool _inForeground = false;

  /// Called once, when the app starts (the app is on screen).
  void start() {
    // Background sync: register the entry point + periodic task with the OS.
    backgroundSync?.initialize();

    // Trigger 2: a local change makes the pending count go UP.
    // (It goes DOWN while a sync uploads; that must not start another sync.)
    _pendingSubscription = _syncService.watchPendingCount().listen((count) {
      final previous = state.pendingCount;
      emit(state.copyWith(pendingCount: count));
      if (_inForeground && count > previous) _syncSoon();
    });

    // Trigger 3: the internet comes back.
    _networkSubscription = _networkInfo.watchStatus().listen((status) {
      if (!_inForeground) return; // background sync's job now
      if (status == NetworkStatus.online) {
        syncNow();
      } else {
        emit(state.copyWith(status: SyncStatus.offline));
      }
    });

    _enterForeground(); // includes trigger 1: sync right now
  }

  // ───────────────────── app lifecycle (handoff) ─────────────────────

  /// The app came back on screen: take over from background sync.
  void appResumed() {
    backgroundSync?.cancelScheduled(); // the app syncs itself now
    _syncService.refreshLocalData(); // show what background sync changed
    _enterForeground(); // heartbeat + timers + sync now
  }

  /// The app left the screen: hand over to background sync.
  Future<void> appPaused() async {
    _inForeground = false;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _heartbeatTimer?.cancel();

    // Expire the heartbeat NOW, so background sync may run right away…
    await _syncService.setForegroundActiveUntil(DateTime.now());
    // …and if changes are still waiting, ask the OS to send them as soon as
    // there's internet — even if the app gets closed.
    if (state.pendingCount > 0) await backgroundSync?.scheduleSoon();
  }

  void _enterForeground() {
    _inForeground = true;

    // Heartbeat: "the app is syncing itself", renewed every minute.
    _beat();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatEvery, (_) => _beat());

    // Trigger 4: every few minutes.
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => syncNow());

    // Trigger 1: right now.
    syncNow();
  }

  void _beat() => _syncService.setForegroundActiveUntil(
    DateTime.now().add(heartbeatValidFor),
  );

  // ───────────────────────────── syncing ─────────────────────────────

  /// Runs one sync and reports how it went. Also trigger 5 (the user).
  Future<void> syncNow() async {
    if (state.status == SyncStatus.syncing) return;
    emit(state.copyWith(status: SyncStatus.syncing));

    try {
      await _syncService.sync();
      if (isClosed) return;
      emit(
        state.copyWith(status: SyncStatus.idle, lastSyncedAt: DateTime.now()),
      );
    } on DioException catch (e) {
      if (isClosed) return;
      // No response = offline / server down. A response = server error.
      final status = e.response == null
          ? SyncStatus.offline
          : SyncStatus.failed;
      emit(state.copyWith(status: status));
    }
  }

  /// Restarts a short countdown; sync when it ends without new changes.
  void _syncSoon() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, syncNow);
  }

  @override
  Future<void> close() async {
    await _pendingSubscription?.cancel();
    await _networkSubscription?.cancel();
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _heartbeatTimer?.cancel();
    return super.close();
  }
}
