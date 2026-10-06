import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_state.dart';

import '../helpers/fake_server.dart';
import '../helpers/test_database.dart';

/// Network status the test can switch: `network.add(NetworkStatus.online)`.
class _ControllableNetwork implements NetworkInfo {
  final controller = StreamController<NetworkStatus>.broadcast();

  @override
  Stream<NetworkStatus> watchStatus() => controller.stream;
}

void main() {
  late AppDatabase db;
  late FakeServer server;
  late _ControllableNetwork network;
  late SyncCubit cubit;

  setUp(() {
    db = createTestDatabase();
    server = FakeServer();
    network = _ControllableNetwork();
    cubit = SyncCubit(
      SyncService(db.subscriptionsDao, server),
      network,
      // Tiny timers so tests run in real time, fast.
      debounce: const Duration(milliseconds: 20),
      interval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await cubit.close();
    await network.controller.close();
    await db.close();
  });

  Future<void> userCreates(String name) => db.subscriptionRepository.create(
    name: name,
    billingCycle: BillingCycles.monthly,
    dueDate: DateTime(2026, 10, 7),
    category: 'Entertainment',
    price: 9.99,
  );

  /// Lets timers, streams and fake requests finish.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  group('syncNow', () {
    test('success: syncing → idle, with the time it finished', () async {
      final states = <SyncState>[];
      final sub = cubit.stream.listen(states.add);

      await cubit.syncNow();
      await settle(); // let the stream deliver the last state

      expect(states.map((s) => s.status), [
        SyncStatus.syncing,
        SyncStatus.idle,
      ]);
      expect(cubit.state.lastSyncedAt, isNotNull);
      await sub.cancel();
    });

    test('server unreachable: syncing → offline', () async {
      server.offline = true;

      await cubit.syncNow();

      expect(cubit.state.status, SyncStatus.offline);
    });
  });

  group('automatic triggers (after start)', () {
    test('app start: syncs once right away', () async {
      server.changeOnServer('a1', name: 'Spotify', updatedAt: DateTime.now());

      cubit.start();
      await settle();

      expect(server.downloads, hasLength(1));
      expect(cubit.state.status, SyncStatus.idle);
    });

    test(
      'a local change: counted as waiting, then synced shortly after',
      () async {
        cubit.start();
        await settle();

        await userCreates('Netflix');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cubit.state.pendingCount, 1); // "1 change waiting"

        await settle(); // debounce passes → sync runs
        expect(server.records, hasLength(1));
        expect(cubit.state.pendingCount, 0); // "Synced"
      },
    );

    test('offline: changes wait; back online: they are sent', () async {
      server.offline = true;
      cubit.start();
      await userCreates('Netflix');
      await settle();
      expect(cubit.state.status, SyncStatus.offline);
      expect(cubit.state.pendingCount, 1);

      server.offline = false;
      network.controller.add(NetworkStatus.online); // internet is back
      await settle();

      expect(server.records, hasLength(1));
      expect(cubit.state.status, SyncStatus.idle);
      expect(cubit.state.pendingCount, 0);
    });

    test('network reports offline → status shows offline', () async {
      cubit.start();
      await settle();

      network.controller.add(NetworkStatus.offline);
      await settle();

      expect(cubit.state.status, SyncStatus.offline);
    });
  });
}
