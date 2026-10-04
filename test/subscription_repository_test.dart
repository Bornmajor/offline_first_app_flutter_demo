import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late SubscriptionRepository repository;

  setUp(() {
    db = createTestDatabase();
    repository = db.subscriptionRepository;
  });

  tearDown(() => db.close());

  group('READ — watchAll', () {
    test('emits an empty list for an empty table', () async {
      expect(await repository.watchAll().first, isEmpty);
    });

    test('maps rows to entities, soonest due date first', () async {
      await insertTestSubscription(
        db,
        name: 'Spotify',
        dueDate: DateTime(2026, 12, 1),
      );
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
        billingCycle: BillingCycles.yearly,
      );

      final items = await repository.watchAll().first;

      expect(items.map((s) => s.name), ['Netflix', 'Spotify']);
      expect(items.first.billingCycle, BillingCycles.yearly);
      expect(items.first.dueDate, DateTime(2026, 10, 7));
      expect(items.first.id, isNotEmpty); // UUID from clientDefault
    });

    test('is live: re-emits when the table changes', () async {
      // Record how many items each emission has.
      final counts = <int>[];
      final subscription = repository.watchAll().listen(
        (items) => counts.add(items.length),
      );

      // First emission: the current (empty) table.
      await pumpEventQueue();
      expect(counts, [0]);

      // Write to the table — nobody calls "refresh"…
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
      );
      await pumpEventQueue();

      // …yet the stream emitted again by itself.
      expect(counts, [0, 1]);

      await subscription.cancel();
    });
  });

  group('CREATE — create', () {
    test('stores all fields and generates an id', () async {
      await repository.create(
        name: 'Netflix',
        billingCycle: BillingCycles.monthly,
        dueDate: DateTime(2026, 10, 7),
        category: 'Entertainment',
        price: 9.99,
      );

      final saved = (await repository.watchAll().first).single;
      expect(saved.id, isNotEmpty);
      expect(saved.name, 'Netflix');
      expect(saved.billingCycle, BillingCycles.monthly);
      expect(saved.dueDate, DateTime(2026, 10, 7));
      expect(saved.category, 'Entertainment');
      expect(saved.price, 9.99);
    });

    test('each create gets its own unique id', () async {
      for (final name in ['Netflix', 'Spotify']) {
        await repository.create(
          name: name,
          billingCycle: BillingCycles.monthly,
          dueDate: DateTime(2026, 10, 7),
          category: 'Entertainment',
          price: 9.99,
        );
      }

      final ids = (await repository.watchAll().first).map((s) => s.id);
      expect(ids.toSet(), hasLength(2));
    });
  });

  group('UPDATE — update', () {
    test('changes the fields of the same row (same id)', () async {
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
      );
      final original = (await repository.watchAll().first).single;

      await repository.update(
        Subscription(
          id: original.id,
          name: 'Netflix Premium',
          billingCycle: BillingCycles.yearly,
          dueDate: DateTime(2027, 1, 1),
          category: 'Entertainment',
          price: 19.99,
        ),
      );

      final updated = (await repository.watchAll().first).single;
      expect(updated.id, original.id); // updated in place, not a new row
      expect(updated.name, 'Netflix Premium');
      expect(updated.billingCycle, BillingCycles.yearly);
      expect(updated.dueDate, DateTime(2027, 1, 1));
      expect(updated.price, 19.99);
    });

    test('throws instead of editing a deleted row', () async {
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
      );
      final original = (await repository.watchAll().first).single;
      await repository.delete(original.id);

      await expectLater(repository.update(original), throwsStateError);

      // Still deleted — the update did not "revive" it.
      final row = (await db.select(db.subscriptions).get()).single;
      expect(row.isDeleted, isTrue);
    });
  });

  group('DELETE — delete (soft)', () {
    test('hides the row from watchAll but keeps it in the table', () async {
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
      );
      await insertTestSubscription(
        db,
        name: 'Spotify',
        dueDate: DateTime(2026, 12, 1),
      );
      final netflix = (await repository.watchAll().first).first;

      await repository.delete(netflix.id);

      // The user no longer sees it…
      final visible = await repository.watchAll().first;
      expect(visible.map((s) => s.name), ['Spotify']);

      // …but the row is still in SQLite, flagged, ready to sync (Part 4).
      final allRows = await db.select(db.subscriptions).get();
      expect(allRows, hasLength(2));
      expect(allRows.firstWhere((r) => r.id == netflix.id).isDeleted, isTrue);
    });

    test('only touches the given id (the WHERE clause works)', () async {
      await insertTestSubscription(db, name: 'A', dueDate: DateTime(2026, 1));
      await insertTestSubscription(db, name: 'B', dueDate: DateTime(2026, 2));

      final changed = await db.subscriptionsDao.softDelete('unknown-id');

      expect(changed, 0);
      expect(await repository.watchAll().first, hasLength(2));
    });
  });
}
