import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_list/subscription_list_state.dart';

/// Logic behind the home list.
///
/// A Cubit holds ONE current [state] and replaces it with `emit(newState)`.
/// Widgets listening to it (BlocBuilder) rebuild on every new state.
///
///   Repository.watchAll() ──stream──► Cubit ──emit(state)──► BlocBuilder
///
/// Step 2: READ ✅  ·  Step 3: DELETE ✅
class SubscriptionListCubit extends Cubit<SubscriptionListState> {
  /// Starts in the default state: `loading`, no items.
  SubscriptionListCubit(this._repository)
    : super(const SubscriptionListState());

  final SubscriptionRepository _repository;

  /// Our subscription to the database stream, kept so it can be cancelled.
  StreamSubscription<List<Subscription>>? _subscription;

  // ───────────────────────── READ ─────────────────────────

  /// Starts listening to the live database query.
  ///
  /// The same Drift stream the page used to listen to in a StreamBuilder —
  /// now the Cubit listens, and turns each emission into a state:
  ///   new list  → success state with the items
  ///   error     → failure state with a message
  ///
  /// Because watchAll() re-emits after EVERY write to the table, the state
  /// stays up to date by itself after create / update / delete.
  void watchSubscriptions() {
    // Calling it twice must not create two listeners.
    _subscription?.cancel();

    _subscription = _repository.watchAll().listen(
      (items) => emit(
        state.copyWith(status: SubscriptionListStatus.success, items: items),
      ),
      onError: (Object error) => emit(
        state.copyWith(
          status: SubscriptionListStatus.failure,
          errorMessage: 'Could not load subscriptions: $error',
        ),
      ),
    );
  }

  // ───────────────────────── DELETE ───────────────────────

  /// Soft-deletes a subscription.
  ///
  /// Notice what is NOT here: no `emit` with a shorter list on success.
  /// We only write to the database; `watchAll()` re-emits without the row,
  /// and the listener in [watchSubscriptions] emits the new list. One source
  /// of truth: the database.
  ///
  /// On failure the list stays as it is (status/items unchanged) and an
  /// error is reported as a ONE-OFF event:
  ///   1. emit a state WITH the message  → BlocListener shows a snackbar
  ///   2. emit the same state WITHOUT it → back to normal
  /// Step 2 matters: Cubit skips a state equal to the current one, so if the
  /// error stayed in the state, a second identical failure would be ignored
  /// and no snackbar would show.
  Future<void> delete(String id) async {
    try {
      await _repository.delete(id);
    } catch (error) {
      if (isClosed) return; // page closed while we were waiting
      emit(state.copyWith(errorMessage: 'Could not delete: $error'));
      emit(state.copyWith()); // copyWith drops errorMessage → cleared
    }
  }

  /// Called automatically by BlocProvider when the page goes away.
  /// Stop listening to the database, or the query would keep running (leak).
  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
