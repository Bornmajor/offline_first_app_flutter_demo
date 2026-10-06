import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_state.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/sync_status_line.dart';

/// A SyncCubit whose state the test sets directly (no sync logic).
class _StubSyncCubit extends Cubit<SyncState> implements SyncCubit {
  _StubSyncCubit() : super(const SyncState());

  void show(SyncState state) => emit(state);

  int syncNowCalls = 0;

  @override
  Future<void> syncNow() async => syncNowCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _StubSyncCubit cubit;

  setUp(() => cubit = _StubSyncCubit());
  tearDown(() => cubit.close());

  Future<void> pumpLine(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<SyncCubit>.value(
          value: cubit,
          child: const SyncStatusLine(),
        ),
      ),
    ),
  );

  Future<void> expectText(
    WidgetTester tester,
    SyncState state,
    String text,
  ) async {
    cubit.show(state);
    // First pump delivers the new state, second renders the rebuild.
    await tester.pump();
    await tester.pump();
    expect(find.text(text), findsOneWidget, reason: '$state');
  }

  testWidgets('shows one line per sync status', (tester) async {
    await pumpLine(tester);

    await expectText(tester, const SyncState(), 'Synced');
    await expectText(
      tester,
      const SyncState(pendingCount: 1),
      '1 change waiting',
    );
    await expectText(
      tester,
      const SyncState(status: SyncStatus.syncing, pendingCount: 2),
      'Syncing…',
    );
    await expectText(
      tester,
      const SyncState(status: SyncStatus.offline),
      'Offline',
    );
    // Offline AND what's waiting, in one line (no separate network widget).
    await expectText(
      tester,
      const SyncState(status: SyncStatus.offline, pendingCount: 2),
      'Offline · 2 changes waiting',
    );
    await expectText(
      tester,
      const SyncState(status: SyncStatus.failed),
      'Sync failed · tap to retry',
    );
  });

  testWidgets('tapping the line asks for a sync', (tester) async {
    await pumpLine(tester);

    await tester.tap(find.byType(SyncStatusLine));

    expect(cubit.syncNowCalls, 1);
  });
}
