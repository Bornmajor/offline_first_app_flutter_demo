import 'package:equatable/equatable.dart';

enum SyncStatus {
  /// Not syncing right now; the last sync worked (or none has run yet).
  idle,

  /// A sync is running.
  syncing,

  /// The server can't be reached. Changes wait on the phone.
  offline,

  /// The server answered with an error (e.g. wrong API key).
  failed,
}

/// What the app bar's sync line shows.
class SyncState extends Equatable {
  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.lastSyncedAt,
  });

  final SyncStatus status;

  /// Local changes not on the server yet.
  final int pendingCount;

  /// When the last successful sync finished (null = not yet).
  final DateTime? lastSyncedAt;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  List<Object?> get props => [status, pendingCount, lastSyncedAt];
}
