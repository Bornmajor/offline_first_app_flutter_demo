import 'package:dio/dio.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';

/// A pretend Express server, kept in memory. It follows the same rules as
/// the real one, so sync can be tested quickly without a network:
///   • upload creates under the phone's id, or updates
///   • an older change is not applied (last-write-wins); deletes win
///   • deletions are kept as tombstones and included in downloads
///   • download returns changes since the bookmark, plus a new serverTime
class FakeServer implements SubscriptionApi {
  /// The server's data: id → JSON, exactly like the real API returns it.
  final records = <String, Map<String, dynamic>>{};

  /// Server time of each record's last change (used by download).
  final _changedAt = <String, DateTime>{};

  /// The server's clock: +1 second per change, so tests are predictable.
  DateTime _clock = DateTime.utc(2026, 10, 5, 12);

  /// true = every request fails like a phone with no connection.
  bool offline = false;

  /// Ids the server rejects with 400 (invalid data).
  final rejectedIds = <String>{};

  /// Runs during upload, before the server answers — to simulate the user
  /// editing a row while the upload is in flight.
  Future<void> Function()? whileUploading;

  /// The `since` value of every download, in order.
  final downloads = <String?>[];

  /// Saves a record as if another phone or the dashboard had changed it.
  void changeOnServer(
    String id, {
    required String name,
    double price = 9.99,
    required DateTime updatedAt,
  }) {
    _save(id, {
      '_id': id,
      'name': name,
      'price': price,
      'billingCycle': 'monthly',
      'nextPaymentDate': '2026-10-07T00:00:00.000Z',
      'category': 'Entertainment',
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'deletedAt': null,
    });
  }

  /// Deletes a record as if another phone or the dashboard had deleted it.
  void deleteOnServer(String id) {
    _save(id, {...records[id]!, 'deletedAt': _clock.toIso8601String()});
  }

  @override
  Future<Map<String, dynamic>> upload(SubscriptionRow row) async {
    _failIfNeeded(row.id);
    await whileUploading?.call();

    final existing = records[row.id];
    final sentUpdatedAt = row.updatedAt;
    if (existing != null &&
        (existing['deletedAt'] != null ||
            DateTime.parse(existing['updatedAt']).isAfter(sentUpdatedAt))) {
      return {'applied': false, 'subscription': existing};
    }
    final json = SubscriptionApi.toJson(row);
    _save(row.id, {
      ...json,
      '_id': row.id,
      'nextPaymentDate': '${json['nextPaymentDate']}T00:00:00.000Z',
      'deletedAt': null,
    });
    return {'applied': true, 'subscription': records[row.id]};
  }

  @override
  Future<void> delete(SubscriptionRow row) async {
    _failIfNeeded(row.id);
    final existing = records[row.id];
    if (existing == null || existing['deletedAt'] != null) return;
    _save(row.id, {
      ...existing,
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
      'deletedAt': _clock.toIso8601String(),
    });
  }

  @override
  Future<Map<String, dynamic>> download(String? since) async {
    _failIfNeeded(null);
    downloads.add(since);
    final serverTime = _clock;
    final changes = records.values.where((json) {
      if (since == null) return json['deletedAt'] == null; // first sync
      return _changedAt[json['_id']]!.isAfter(DateTime.parse(since));
    }).toList();
    return {
      'subscriptions': changes,
      'serverTime': serverTime.toIso8601String(),
    };
  }

  void _save(String id, Map<String, dynamic> json) {
    _clock = _clock.add(const Duration(seconds: 1));
    records[id] = json;
    _changedAt[id] = _clock;
  }

  void _failIfNeeded(String? id) {
    final request = RequestOptions();
    if (offline) {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    if (id != null && rejectedIds.contains(id)) {
      throw DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 400),
      );
    }
  }
}
