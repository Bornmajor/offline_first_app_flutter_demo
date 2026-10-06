import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';

/// Talks to the Express server. Sync only needs THREE calls:
///
///   upload()   → PUT    /api/subscriptions/:id   (send a new/edited row)
///   delete()   → DELETE /api/subscriptions/:id   (send a deletion)
///   download() → GET    /api/subscriptions?updatedSince=…  (fetch changes)
///
/// This is also the only file that knows the server's JSON format.
///
/// The [Dio] client (address, API key, timeouts) is created in
/// core/network/dio_client.dart and passed in.
class SubscriptionApi {
  SubscriptionApi(this._dio);

  final Dio _dio;

  /// Sends a created or edited subscription.
  ///
  /// The server answers:
  ///   { "applied": true,  "subscription": {...} }  → saved
  ///   { "applied": false, "subscription": {...} }  → the server kept ITS
  ///      version (newer, or deleted); we must take that version instead
  Future<Map<String, dynamic>> upload(SubscriptionRow row) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/subscriptions/${row.id}',
      data: toJson(row),
    );
    return response.data!;
  }

  /// Sends a deletion. A 404 means the server never had it (created and
  /// deleted while offline): nothing to delete, so that's fine too.
  Future<void> delete(SubscriptionRow row) async {
    try {
      await _dio.delete<void>(
        '/api/subscriptions/${row.id}',
        data: {'updatedAt': row.updatedAt.toUtc().toIso8601String()},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
  }

  /// Fetches changes made on the server since [since] (null = everything).
  ///
  /// The server answers:
  ///   { "subscriptions": [ {...}, ... ],   ← changes, including deleted ones
  ///     "serverTime": "2026-10-05T09:00:00.000Z" }  ← remember for next time
  Future<Map<String, dynamic>> download(String? since) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/subscriptions',
      // `?since` = include this entry only when since is not null.
      queryParameters: {'updatedSince': ?since},
    );
    return response.data!;
  }

  // ───────────── JSON ⇄ database row (the server's format) ─────────────

  /// Database row → JSON body the server expects.
  static Map<String, dynamic> toJson(SubscriptionRow row) => {
    'name': row.name,
    'price': row.price,
    'billingCycle': row.billingCycle.name, // "monthly"
    // Send the due date as a plain date ("2026-10-07"), not a moment in time,
    // so time zones can't shift it to the day before.
    'nextPaymentDate': _dateOnly(row.dueDate),
    'category': row.category,
    // When the user made this change: the server uses it for last-write-wins.
    'updatedAt': row.updatedAt.toUtc().toIso8601String(),
  };

  /// Server JSON → database row. `isSynced: true` because this IS the
  /// server's version: there's nothing to send back.
  static SubscriptionsCompanion fromJson(Map<String, dynamic> json) {
    // The server stores "2026-10-07" as "2026-10-07T00:00:00.000Z":
    // keep its year/month/day so it's Oct 7 in every time zone.
    final due = DateTime.parse(json['nextPaymentDate'] as String).toUtc();
    return SubscriptionsCompanion(
      id: Value(json['_id'] as String),
      name: Value(json['name'] as String),
      price: Value((json['price'] as num).toDouble()),
      billingCycle: Value(
        BillingCycles.values.byName(json['billingCycle'] as String),
      ),
      dueDate: Value(DateTime(due.year, due.month, due.day)),
      category: Value(json['category'] as String),
      updatedAt: Value(DateTime.parse(json['updatedAt'] as String).toLocal()),
      isDeleted: Value(json['deletedAt'] != null),
      isSynced: const Value(true),
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
