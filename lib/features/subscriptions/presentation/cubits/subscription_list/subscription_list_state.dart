import 'package:equatable/equatable.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';

/// Which "screen" the home list should draw.
enum SubscriptionListStatus {
  /// First database emission hasn't arrived yet → spinner.
  loading,

  /// We have a list (possibly empty) → list or empty message.
  success,

  /// Reading from the database failed → error message.
  failure,
}

/// Everything the home page needs to draw itself — nothing more.
///
/// The UI never decides *what* to show on its own; it just reads this object.
/// A state is IMMUTABLE: to change anything, the Cubit builds a new state
/// with [copyWith] and `emit`s it.
class SubscriptionListState extends Equatable {
  const SubscriptionListState({
    this.status = SubscriptionListStatus.loading,
    this.items = const [],
    this.errorMessage,
  });

  final SubscriptionListStatus status;

  /// The subscriptions to show (soonest due date first).
  final List<Subscription> items;

  /// Human-readable error, set together with [SubscriptionListStatus.failure].
  final String? errorMessage;

  /// Returns a NEW state with some fields replaced.
  ///
  /// `status` and `items` keep their old value when not passed.
  /// `errorMessage` does NOT carry over: an error belongs to the state that
  /// reported it, so the next state is error-free unless one is passed again.
  SubscriptionListState copyWith({
    SubscriptionListStatus? status,
    List<Subscription>? items,
    String? errorMessage,
  }) {
    return SubscriptionListState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: errorMessage,
    );
  }

  /// Equatable compares states by these fields (lists element by element).
  ///
  /// Why it matters:
  ///   • Cubit skips `emit` when the new state == current state, so the UI
  ///     doesn't rebuild for nothing.
  ///   • Tests can write `expect: [SubscriptionListState(...)]`.
  @override
  List<Object?> get props => [status, items, errorMessage];
}
