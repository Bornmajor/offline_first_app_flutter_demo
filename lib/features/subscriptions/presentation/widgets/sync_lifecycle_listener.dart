import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';

/// Tells SyncCubit when the app goes off screen and comes back, so it can
/// hand sync over to the background task and take it back.
///
/// Uses Flutter's AppLifecycleListener:
///   onPause  → the app is no longer visible (switched away, screen off)
///   onResume → the app is visible and in use again
/// (There is no "killed" event — that's what the heartbeat is for.)
class SyncLifecycleListener extends StatefulWidget {
  const SyncLifecycleListener({super.key, required this.child});

  final Widget child;

  @override
  State<SyncLifecycleListener> createState() => _SyncLifecycleListenerState();
}

class _SyncLifecycleListenerState extends State<SyncLifecycleListener> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    final syncCubit = context.read<SyncCubit>();
    _listener = AppLifecycleListener(
      onPause: syncCubit.appPaused,
      onResume: syncCubit.appResumed,
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
