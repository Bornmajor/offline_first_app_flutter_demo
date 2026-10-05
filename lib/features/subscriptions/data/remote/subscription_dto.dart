import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';

/// DTO = Data Transfer Object: a subscription exactly as the SERVER sends
/// and receives it (JSON). The third shape of the same data:
///
///   SubscriptionDto  ⇄  SubscriptionRow (Drift)  ⇄  Subscription (entity)
///   server's shape       database's shape            app's shape
///
/// Keeping them apart means a server rename (e.g. `nextPaymentDate`) only
/// touches this file, never the database or the UI.
class SubscriptionDto {
  const SubscriptionDto({
    required this.id,
    required this.name,
    required this.price,
    required this.billingCycle,
    required this.nextPaymentDate,
    required this.category,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Parses one subscription from the server's JSON.
  ///
  /// Example input:
  ///   { "_id": "3f2b…", "name": "Netflix", "price": 15.49,
  ///     "billingCycle": "monthly", "nextPaymentDate": "2026-10-07T00:00:00.000Z",
  ///     "category": "entertainment", "updatedAt": "2026-10-05T09:30:00.000Z",
  ///     "deletedAt": null, … }
  /// Fields the app doesn't need (createdAt, serverUpdatedAt, __v) are ignored.
  factory SubscriptionDto.fromJson(Map<String, dynamic> json) {
    final deletedAt = json['deletedAt'] as String?;
    return SubscriptionDto(
      id: json['_id'] as String,
      name: json['name'] as String,
      // JSON numbers may arrive as int (15) or double (15.49).
      price: (json['price'] as num).toDouble(),
      // Throws if the server sends a cycle this app version doesn't know.
      billingCycle: BillingCycles.values.byName(json['billingCycle'] as String),
      nextPaymentDate: _parseCalendarDate(json['nextPaymentDate'] as String),
      category: json['category'] as String,
      // Moments in time: parsed (UTC) then shown in the device's time zone.
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      deletedAt: deletedAt == null ? null : DateTime.parse(deletedAt).toLocal(),
    );
  }

  /// The UUID shared by app and server (`_id` on the server).
  final String id;
  final String name;
  final double price;
  final BillingCycles billingCycle;

  /// A CALENDAR date (no time of day), in the device's local calendar.
  final DateTime nextPaymentDate;
  final String category;

  /// When the latest change was made, for last-write-wins.
  final DateTime updatedAt;

  /// Non-null = deleted on the server (a tombstone).
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Body for `PUT /api/subscriptions/:id`. The id travels in the URL, and
  /// server-controlled fields (deletedAt, serverUpdatedAt) are never sent.
  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'billingCycle': billingCycle.name,
    'nextPaymentDate': formatCalendarDate(nextPaymentDate),
    'category': category,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Calendar date → "2026-10-07".
  ///
  /// Why not `toIso8601String()`? That sends a MOMENT in time. A due date of
  /// "Oct 7" picked at midnight in Nairobi (UTC+3) is "Oct 6, 21:00" in UTC,
  /// and would come back as Oct 6. A plain date string has no time zone to
  /// shift.
  static String formatCalendarDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
  }

  /// The server stores "2026-10-07" as midnight UTC: "2026-10-07T00:00:00.000Z".
  /// Read the year/month/day of THAT UTC value, then build a local calendar
  /// date from them — so it's Oct 7 in every time zone.
  static DateTime _parseCalendarDate(String value) {
    final utc = DateTime.parse(value).toUtc();
    return DateTime(utc.year, utc.month, utc.day);
  }
}
