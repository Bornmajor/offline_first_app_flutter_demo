import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_dto.dart';

/// Everything the sync engine needs from the server — and nothing about
/// HTTP. The real implementation uses dio ([DioSubscriptionApi]); tests use
/// an in-memory fake that follows the same rules.
///
/// All methods throw `ApiException` on failure
/// (check `isNetworkError` to tell "offline" from "server said no").
abstract class SubscriptionApi {
  /// PUSH a created or edited subscription: `PUT /api/subscriptions/:id`.
  ///
  /// The server creates it under our id if it's new, otherwise updates it —
  /// unless it already has a NEWER change (last-write-wins) or the record was
  /// deleted there; then [PushResult.applied] is false and
  /// [PushResult.subscription] is the server's version to keep instead.
  Future<PushResult> put(SubscriptionDto subscription);

  /// PUSH a deletion: `DELETE /api/subscriptions/:id`.
  ///
  /// Succeeds when the server deleted it OR never had it (404): either way
  /// the server doesn't have a live copy, which is all the app needs.
  Future<void> delete(String id, {required DateTime updatedAt});

  /// PULL changes: `GET /api/subscriptions?updatedSince=<cursor>`.
  ///
  /// [updatedSince] null → first sync: every live subscription.
  /// Otherwise → every change after the cursor, INCLUDING deletions
  /// (`SubscriptionDto.isDeleted`).
  Future<PullResult> pull({DateTime? updatedSince});
}

/// The server's answer to a push.
class PushResult {
  const PushResult({required this.applied, required this.subscription});

  /// true = our change is now on the server.
  /// false = the server kept a newer (or deleted) version: [subscription].
  final bool applied;

  /// What the server now stores for this id.
  final SubscriptionDto subscription;
}

/// The server's answer to a pull.
class PullResult {
  const PullResult({required this.subscriptions, required this.serverTime});

  /// Changed (or, on the first sync, all) subscriptions, incl. tombstones.
  final List<SubscriptionDto> subscriptions;

  /// The server's clock when it answered: store it and send it as
  /// `updatedSince` next time (the "bookmark").
  final DateTime serverTime;
}
