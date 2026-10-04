import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_form/subscription_form_state.dart';

/// Logic behind the create/edit form: CREATE + UPDATE.
///
///   View (validated values) ──save()──► Cubit ──► Repository ──► SQLite
///   View ◄──────────── state (saving / success / failure) ────── Cubit
///
/// One Cubit per open form: BlocProvider creates it when the page opens and
/// closes it when the page closes.
class SubscriptionFormCubit extends Cubit<SubscriptionFormState> {
  SubscriptionFormCubit(this._repository, {this.initial})
    : super(const SubscriptionFormState());

  final SubscriptionRepository _repository;

  /// The subscription being edited, or null when creating a new one.
  /// The Cubit decides create vs update, so the View doesn't have to.
  final Subscription? initial;

  bool get isEditing => initial != null;

  /// Saves the form's values.
  ///
  /// The View validates first (Flutter's Form), so values arrive non-null
  /// and valid. The Cubit only runs the save and reports how it went:
  ///   saving  → button shows a spinner
  ///   success → View closes the page
  ///   failure → View shows a snackbar; user can tap Save again
  Future<void> save({
    required String name,
    required BillingCycles billingCycle,
    required DateTime dueDate,
    required String category,
    required double price,
  }) async {
    // Double-tap guard: a second tap while saving would insert two rows.
    // (The button is also disabled while saving — this protects the logic
    // itself, whatever the UI does.)
    if (state.isSaving) return;

    emit(state.copyWith(status: SubscriptionFormStatus.saving));

    try {
      if (isEditing) {
        // UPDATE: same id as before → the DAO changes that row.
        await _repository.update(
          Subscription(
            id: initial!.id,
            name: name,
            billingCycle: billingCycle,
            dueDate: dueDate,
            category: category,
            price: price,
          ),
        );
      } else {
        // CREATE: no id → the table generates one.
        await _repository.create(
          name: name,
          billingCycle: billingCycle,
          dueDate: dueDate,
          category: category,
          price: price,
        );
      }

      // The page may have closed while we waited (e.g. back button);
      // emitting on a closed Cubit throws.
      if (isClosed) return;

      // Note: nothing tells the home list to refresh. Its Cubit listens to
      // watchAll(), which already re-emitted after this write.
      emit(state.copyWith(status: SubscriptionFormStatus.success));
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SubscriptionFormStatus.failure,
          errorMessage: 'Could not save: $error',
        ),
      );
      // No "clear the error" emit needed here (unlike the list Cubit):
      // a retry goes failure → saving → failure, and each of those differs
      // from the one before, so every failure is emitted and reported.
    }
  }
}
