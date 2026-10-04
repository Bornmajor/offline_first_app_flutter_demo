import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_form/subscription_form_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_form/subscription_form_state.dart';

import '../helpers/test_database.dart';

/// Real repository (reads/writes the test db) whose writes always fail.
class _SaveFailsRepository extends SubscriptionRepository {
  _SaveFailsRepository(super.dao);

  @override
  Future<void> create({
    required String name,
    required BillingCycles billingCycle,
    required DateTime dueDate,
    required String category,
    required double price,
  }) async => throw 'disk full';
}

/// Repository whose create() waits until the test says so — lets us tap
/// "Save" twice while the first save is still running.
class _SlowRepository extends SubscriptionRepository {
  _SlowRepository(super.dao);

  final gate = Completer<void>();
  int createCalls = 0;

  @override
  Future<void> create({
    required String name,
    required BillingCycles billingCycle,
    required DateTime dueDate,
    required String category,
    required double price,
  }) async {
    createCalls++;
    await gate.future;
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  /// Calls save() with fixed valid values.
  Future<void> saveNetflix(SubscriptionFormCubit cubit, {double price = 9.99}) {
    return cubit.save(
      name: 'Netflix',
      billingCycle: BillingCycles.monthly,
      dueDate: DateTime(2026, 10, 7),
      category: 'Entertainment',
      price: price,
    );
  }

  const saving = SubscriptionFormState(status: SubscriptionFormStatus.saving);
  const success = SubscriptionFormState(status: SubscriptionFormStatus.success);

  test('starts idle; isEditing depends on `initial`', () {
    final create = SubscriptionFormCubit(db.subscriptionRepository);
    final edit = SubscriptionFormCubit(
      db.subscriptionRepository,
      initial: Subscription(
        id: 'x',
        name: 'Netflix',
        billingCycle: BillingCycles.monthly,
        dueDate: DateTime(2026, 10, 7),
        category: 'Entertainment',
        price: 9.99,
      ),
    );

    expect(create.state, const SubscriptionFormState());
    expect(create.isEditing, isFalse);
    expect(edit.isEditing, isTrue);

    create.close();
    edit.close();
  });

  group('CREATE — save without initial', () {
    blocTest<SubscriptionFormCubit, SubscriptionFormState>(
      'emits saving → success and inserts a row',
      build: () => SubscriptionFormCubit(db.subscriptionRepository),
      act: saveNetflix,
      expect: () => const [saving, success],
      verify: (_) async {
        final rows = await db.select(db.subscriptions).get();
        expect(rows.single.name, 'Netflix');
      },
    );

    blocTest<SubscriptionFormCubit, SubscriptionFormState>(
      'emits saving → failure with a message when the write fails',
      build: () =>
          SubscriptionFormCubit(_SaveFailsRepository(db.subscriptionsDao)),
      act: saveNetflix,
      expect: () => const [
        saving,
        SubscriptionFormState(
          status: SubscriptionFormStatus.failure,
          errorMessage: 'Could not save: disk full',
        ),
      ],
    );

    blocTest<SubscriptionFormCubit, SubscriptionFormState>(
      'a retry after failure reports the failure again',
      build: () =>
          SubscriptionFormCubit(_SaveFailsRepository(db.subscriptionsDao)),
      act: (cubit) async {
        await saveNetflix(cubit);
        await saveNetflix(cubit);
      },
      expect: () => const [
        saving,
        SubscriptionFormState(
          status: SubscriptionFormStatus.failure,
          errorMessage: 'Could not save: disk full',
        ),
        saving,
        SubscriptionFormState(
          status: SubscriptionFormStatus.failure,
          errorMessage: 'Could not save: disk full',
        ),
      ],
    );

    test('a second save while saving is ignored (no double insert)', () async {
      final repository = _SlowRepository(db.subscriptionsDao);
      final cubit = SubscriptionFormCubit(repository);

      final first = saveNetflix(cubit); // still running (gate closed)
      await saveNetflix(cubit); // double tap → ignored immediately

      repository.gate.complete();
      await first;

      expect(repository.createCalls, 1);
      expect(cubit.state, success);
      await cubit.close();
    });
  });

  group('UPDATE — save with initial', () {
    // A plain test (not blocTest) because the Cubit needs the inserted row's
    // generated id, which only exists after the insert.
    test('emits saving → success and updates the same row', () async {
      await insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime(2026, 10, 7),
      );
      final existing =
          (await db.subscriptionRepository.watchAll().first).single;
      final cubit = SubscriptionFormCubit(
        db.subscriptionRepository,
        initial: existing,
      );
      final states = <SubscriptionFormState>[];
      final sub = cubit.stream.listen(states.add);

      await saveNetflix(cubit, price: 15.49);
      await pumpEventQueue();

      expect(states, const [saving, success]);
      final rows = await db.select(db.subscriptions).get();
      expect(rows, hasLength(1)); // updated in place, not inserted
      expect(rows.single.id, existing.id);
      expect(rows.single.price, 15.49);

      await sub.cancel();
      await cubit.close();
    });

    blocTest<SubscriptionFormCubit, SubscriptionFormState>(
      'emits failure when the row was deleted meanwhile',
      build: () => SubscriptionFormCubit(
        db.subscriptionRepository,
        initial: Subscription(
          id: 'does-not-exist',
          name: 'Netflix',
          billingCycle: BillingCycles.monthly,
          dueDate: DateTime(2026, 10, 7),
          category: 'Entertainment',
          price: 9.99,
        ),
      ),
      act: saveNetflix,
      expect: () => [
        saving,
        isA<SubscriptionFormState>()
            .having((s) => s.status, 'status', SubscriptionFormStatus.failure)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('no longer exists'),
            ),
      ],
    );
  });
}
