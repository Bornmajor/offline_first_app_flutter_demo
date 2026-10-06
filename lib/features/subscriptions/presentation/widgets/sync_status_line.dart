import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_state.dart';

/// One small line under the app title, e.g. "Synced", "Syncing…",
/// "2 changes waiting", "Offline · 1 change waiting". Tap it to sync now.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, state) {
        final (icon, text) = _describe(state);
        final style = Theme.of(context).textTheme.bodySmall;

        return InkWell(
          onTap: () => context.read<SyncCubit>().syncNow(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4.0,
            children: [
              Icon(icon, size: 14.0, color: style?.color),
              Text(text, style: style),
            ],
          ),
        );
      },
    );
  }

  /// Picks an icon and a short text for the current state.
  static (IconData, String) _describe(SyncState state) {
    final waiting = state.pendingCount == 1
        ? '1 change waiting'
        : '${state.pendingCount} changes waiting';

    return switch (state.status) {
      SyncStatus.syncing => (Icons.sync, 'Syncing…'),
      SyncStatus.offline when state.pendingCount > 0 => (
        Icons.cloud_off,
        'Offline · $waiting',
      ),
      SyncStatus.offline => (Icons.cloud_off, 'Offline'),
      SyncStatus.failed => (Icons.error_outline, 'Sync failed · tap to retry'),
      SyncStatus.idle when state.pendingCount > 0 => (
        Icons.cloud_upload_outlined,
        waiting,
      ),
      SyncStatus.idle => (Icons.cloud_done_outlined, 'Synced'),
    };
  }
}
