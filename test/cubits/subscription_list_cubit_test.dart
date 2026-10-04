import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_list/subscription_list_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_list/subscription_list_state.dart';

import '../helpers/test_database.dart';

/// A repository whose stream fails, to test the failure state.
/// `implements` uses SubscriptionRepository as an interface: we only
/// provide what the Cubit calls.
class _FailingRepository implements SubscriptionRepository {
  @override
  Stream<List<Subscription>> watchAll() => Stream.error('disk on fire');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A repository whose delete always fails (e.g. database locked).
class _DeleteFailsRepository implements SubscriptionRepository {
  @override
  Stream<List<Subscription>> watchAll() => const Stream.empty();

  @override
  Future<void> delete(String id) async => throw 'locked';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Matches a success state whose items have exactly these names, in order.
/// (Ids are random UUIDs, so we compare names instead of whole entities.)
Matcher _successWithNames(List<String> names) => isA<SubscriptionListState>()
    .having((s) => s.status, 'status', SubscriptionListStatus.success)
    .having((s) => s.items.map((i) => i.name).toList(), 'item names', names);

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  test('starts in the loading state with no items', () {
    final cubit = SubscriptionListCubit(db.subscriptionRepository);
    expect(cubit.state, const SubscriptionListState());
    expect(cubit.state.status, SubscriptionListStatus.loading);
    cubit.close();
  });

  // blocTest reads like a story:
  //   build  → create the Cubit
  //   act    → call its methods
  //   expect → the states it must emit, in order (initial state excluded)
  group('READ — watchSubscriptions', () {
    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'emits success with an empty list for an empty table',
      build: () => SubscriptionListCubit(db.subscriptionRepository),
      act: (cubit) => cubit.watchSubscriptions(),
      expect: () => const [
        SubscriptionListState(status: SubscriptionListStatus.success),
      ],
    );

    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'emits the rows, soonest due date first',
      setUp: () async {
        await insertTestSubscription(
          db,
          name: 'Spotify',
          dueDate: DateTime(2026, 12, 1),
        );
        await insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: DateTime(2026, 10, 7),
        );
      },
      build: () => SubscriptionListCubit(db.subscriptionRepository),
      act: (cubit) => cubit.watchSubscriptions(),
      expect: () => [
        _successWithNames(['Netflix', 'Spotify']),
      ],
    );

    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'emits a new state by itself when the table changes',
      build: () => SubscriptionListCubit(db.subscriptionRepository),
      act: (cubit) async {
        cubit.watchSubscriptions();
        await pumpEventQueue(); // first emission: empty table

        // Write straight to the database — nobody tells the Cubit.
        await insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: DateTime(2026, 10, 7),
        );
      },
      expect: () => [
        _successWithNames([]),
        _successWithNames(['Netflix']),
      ],
    );

    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'emits failure with a message when the stream errors',
      build: () => SubscriptionListCubit(_FailingRepository()),
      act: (cubit) => cubit.watchSubscriptions(),
      expect: () => const [
        SubscriptionListState(
          status: SubscriptionListStatus.failure,
          errorMessage: 'Could not load subscriptions: disk on fire',
        ),
      ],
    );
  });

  group('DELETE — delete', () {
    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'removes the item via the database stream (no manual list edit)',
      setUp: () async {
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
      },
      build: () => SubscriptionListCubit(db.subscriptionRepository),
      act: (cubit) async {
        cubit.watchSubscriptions();
        await pumpEventQueue();
        await cubit.delete(cubit.state.items.first.id); // Netflix
      },
      expect: () => [
        _successWithNames(['Netflix', 'Spotify']),
        _successWithNames(['Spotify']), // emitted by watchAll, not delete()
      ],
      verify: (_) async {
        // Soft delete: the row is still in SQLite, flagged.
        final rows = await db.select(db.subscriptions).get();
        expect(rows, hasLength(2));
      },
    );

    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'on failure: keeps the list, reports the error once, then clears it',
      build: () => SubscriptionListCubit(_DeleteFailsRepository()),
      seed: () =>
          const SubscriptionListState(status: SubscriptionListStatus.success),
      act: (cubit) => cubit.delete('any-id'),
      expect: () => const [
        SubscriptionListState(
          status: SubscriptionListStatus.success,
          errorMessage: 'Could not delete: locked',
        ),
        SubscriptionListState(status: SubscriptionListStatus.success),
      ],
    );

    blocTest<SubscriptionListCubit, SubscriptionListState>(
      'two failures in a row are both reported (error is cleared between)',
      build: () => SubscriptionListCubit(_DeleteFailsRepository()),
      seed: () =>
          const SubscriptionListState(status: SubscriptionListStatus.success),
      act: (cubit) async {
        await cubit.delete('a');
        await cubit.delete('b');
      },
      // 4 states = 2 snackbars. Without clearing, the 2nd error state would
      // equal the current state and be skipped.
      expect: () => const [
        SubscriptionListState(
          status: SubscriptionListStatus.success,
          errorMessage: 'Could not delete: locked',
        ),
        SubscriptionListState(status: SubscriptionListStatus.success),
        SubscriptionListState(
          status: SubscriptionListStatus.success,
          errorMessage: 'Could not delete: locked',
        ),
        SubscriptionListState(status: SubscriptionListStatus.success),
      ],
    );
  });

  test('close() stops listening to the database', () async {
    final cubit = SubscriptionListCubit(db.subscriptionRepository)
      ..watchSubscriptions();
    await pumpEventQueue();

    await cubit.close();

    // A write after close must not try to emit on a closed Cubit
    // (that would throw "Cannot emit new states after calling close").
    await insertTestSubscription(
      db,
      name: 'Netflix',
      dueDate: DateTime(2026, 10, 7),
    );
    await pumpEventQueue();
    expect(cubit.isClosed, isTrue);
  });
}
