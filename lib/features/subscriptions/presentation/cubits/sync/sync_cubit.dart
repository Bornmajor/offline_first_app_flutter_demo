import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_state.dart';

/// Decides WHEN to sync, and tells the UI how syncing is going.
///
/// SyncService knows HOW to sync; this Cubit only calls `sync()` at the
/// right moments:
///   1. when the app starts
///   2. after the user changes something (a couple of seconds later, so
///      several quick edits become one sync)
///   3. when the internet comes back
///   4. every few minutes, to pick up changes made on other devices
///   5. when the user asks (pull-to-refresh, or tapping the status)
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(
    this._syncService,
    this._networkInfo, {
    this.debounce = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 5),
  }) : super(const SyncState());

  final SyncService _syncService;
  final NetworkInfo _networkInfo;

  /// Wait this long after a local change before syncing (trigger 2).
  final Duration debounce;

  /// Sync this often while the app is open (trigger 4).
  final Duration interval;

  StreamSubscription<int>? _pendingSubscription;
  StreamSubscription<NetworkStatus>? _networkSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;

  /// Starts all the triggers. Called once, when the app starts.
  void start() {
    // Trigger 2: a local change makes the pending count go UP.
    // (It goes DOWN while a sync uploads; that must not start another sync.)
    _pendingSubscription = _syncService.watchPendingCount().listen((count) {
      final previous = state.pendingCount;
      emit(state.copyWith(pendingCount: count));
      if (count > previous) _syncSoon();
    });

    // Trigger 3: the internet comes back.
    _networkSubscription = _networkInfo.watchStatus().listen((status) {
      if (status == NetworkStatus.online) {
        syncNow();
      } else {
        emit(state.copyWith(status: SyncStatus.offline));
      }
    });

    // Trigger 4: every few minutes.
    _periodicTimer = Timer.periodic(interval, (_) => syncNow());

    // Trigger 1: right now.
    syncNow();
  }

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
    return super.close();
  }
}
