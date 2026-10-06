import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/sync/sync_service.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';

import '../helpers/fake_server.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SubscriptionRepository repository;
  late FakeServer server;
  late SyncService syncService;

  setUp(() {
    db = createTestDatabase();
    repository = db.subscriptionRepository;
    server = FakeServer();
    syncService = SyncService(db.subscriptionsDao, server);
  });
  tearDown(() => db.close());

  // ── Small helpers so each test reads like a story ──

  /// The user adds a subscription in the app.
  Future<String> userCreates(String name) async {
    await repository.create(
      name: name,
      billingCycle: BillingCycles.monthly,
      dueDate: DateTime(2026, 10, 7),
      category: 'Entertainment',
      price: 9.99,
    );
    final rows = await db.select(db.subscriptions).get();
    return rows.firstWhere((r) => r.name == name).id;
  }

  /// The user changes the price in the app.
  Future<void> userEditsPrice(String id, double price) async {
    final row = (await db.subscriptionsDao.findById(id))!;
    await repository.update(
      Subscription(
        id: id,
        name: row.name,
        billingCycle: row.billingCycle,
        dueDate: row.dueDate,
        category: row.category,
        price: price,
      ),
    );
  }

  Future<SubscriptionRow?> onPhone(String id) =>
      db.subscriptionsDao.findById(id);

  // ───────────────────── PUSH: phone → server ─────────────────────

  group('push', () {
    test('a subscription created on the phone reaches the server', () async {
      final id = await userCreates('Netflix');

      await syncService.sync();

      expect(server.records[id]!['name'], 'Netflix'); // same id on the server
      expect((await onPhone(id))!.isSynced, isTrue);
    });

    test('an edit on the phone reaches the server', () async {
      final id = await userCreates('Netflix');
      await syncService.sync();

      await userEditsPrice(id, 15.49);
      await syncService.sync();

      expect(server.records[id]!['price'], 15.49);
    });

    test('a delete on the phone reaches the server', () async {
      final id = await userCreates('Netflix');
      await syncService.sync();

      await repository.delete(id);
      await syncService.sync();

      expect(server.records[id]!['deletedAt'], isNotNull);
      expect(await onPhone(id), isNull); // tombstone cleaned up
    });

    test('created and deleted while offline: just cleaned up', () async {
      final id = await userCreates('Netflix');
      await repository.delete(id);

      await syncService.sync();

      expect(server.records, isEmpty);
      expect(await onPhone(id), isNull);
    });

    test('an edit made DURING the upload is not lost', () async {
      final id = await userCreates('Netflix');
      server.whileUploading = () async {
        server.whileUploading = null;
        await userEditsPrice(id, 30); // user saves while uploading
      };

      await syncService.sync();
      expect((await onPhone(id))!.isSynced, isFalse); // still waiting

      await syncService.sync(); // next sync sends it
      expect(server.records[id]!['price'], 30);
    });

    test('a row the server rejects does not block the others', () async {
      final bad = await userCreates('Bad');
      final good = await userCreates('Good');
      server.rejectedIds.add(bad);

      await syncService.sync();

      expect(server.records.containsKey(good), isTrue);
      expect((await onPhone(bad))!.isSynced, isFalse); // tried again later
    });
  });

  // ───────────────────── PULL: server → phone ─────────────────────

  group('pull', () {
    test('first sync downloads what the server already has', () async {
      server.changeOnServer('a1', name: 'Spotify', updatedAt: DateTime.now());

      await syncService.sync();

      final row = (await onPhone('a1'))!;
      expect(row.name, 'Spotify');
      expect(row.dueDate, DateTime(2026, 10, 7));
      expect(row.isSynced, isTrue);
    });

    test('an edit made elsewhere arrives on the phone', () async {
      final id = await userCreates('Netflix');
      await syncService.sync();

      server.changeOnServer(id, name: 'Netflix 4K', updatedAt: DateTime.now());
      await syncService.sync();

      expect((await onPhone(id))!.name, 'Netflix 4K');
    });

    test('a delete made elsewhere removes it from the phone', () async {
      final id = await userCreates('Netflix');
      await syncService.sync();

      server.deleteOnServer(id);
      await syncService.sync();

      expect(await onPhone(id), isNull);
    });

    test('later syncs only ask for changes since the bookmark', () async {
      await syncService.sync();
      await syncService.sync();

      expect(server.downloads.first, isNull); // first: everything
      expect(server.downloads.last, isNotNull); // then: only newer changes
    });
  });

  // ───────────── CONFLICTS: both sides changed the same record ─────────────

  group('conflicts', () {
    test('server change is newer → the server version wins', () async {
      final id = await userCreates('Netflix');
      server.changeOnServer(
        id,
        name: 'Edited elsewhere later',
        updatedAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await syncService.sync();

      expect((await onPhone(id))!.name, 'Edited elsewhere later');
    });

    test('deleted elsewhere beats an edit on the phone', () async {
      final id = await userCreates('Netflix');
      await syncService.sync();
      server.deleteOnServer(id);

      await userEditsPrice(id, 1); // edit after the other deletion
      await syncService.sync();

      expect(await onPhone(id), isNull); // deletes win
    });
  });

  // ───────────────────── OFFLINE ─────────────────────

  test(
    'offline: sync fails, nothing is lost, works when back online',
    () async {
      final id = await userCreates('Netflix');
      server.offline = true;

      await expectLater(syncService.sync(), throwsA(isA<DioException>()));
      expect((await onPhone(id))!.isSynced, isFalse); // still waiting

      server.offline = false;
      await syncService.sync();
      expect((await onPhone(id))!.isSynced, isTrue);
    },
  );
}
