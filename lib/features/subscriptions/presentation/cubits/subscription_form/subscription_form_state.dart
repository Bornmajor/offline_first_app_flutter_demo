import 'package:equatable/equatable.dart';

/// Where the form is in its save lifecycle:
///
///   idle ──save()──► saving ──ok──► success   (page closes)
///                       │
///                       └──error──► failure   (snackbar, can retry)
///                                      │
///                                      └──save()──► saving …
enum SubscriptionFormStatus { idle, saving, success, failure }

/// Everything the form screen needs from its Cubit.
///
/// Deliberately small: the FIELD VALUES (name, price, …) are not here. They
/// stay in the widget (TextEditingControllers + Flutter's Form validation),
/// which already handles them well. The Cubit owns only the SAVING part.
class SubscriptionFormState extends Equatable {
  const SubscriptionFormState({
    this.status = SubscriptionFormStatus.idle,
    this.errorMessage,
  });

  final SubscriptionFormStatus status;

  /// Set together with [SubscriptionFormStatus.failure].
  final String? errorMessage;

  bool get isSaving => status == SubscriptionFormStatus.saving;

  SubscriptionFormState copyWith({
    SubscriptionFormStatus? status,
    String? errorMessage,
  }) {
    return SubscriptionFormState(
      status: status ?? this.status,
      // Not carried over: an error belongs to the failure state only.
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, errorMessage];
}
