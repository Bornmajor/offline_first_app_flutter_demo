import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_api.dart';

/// The JSON format is where small mistakes hide (dates, number types), so
/// the two conversion functions get their own tests.
void main() {
  test('toJson: plain due date, UTC change time with milliseconds', () {
    final row = SubscriptionRow(
      id: 'abc',
      name: 'Netflix',
      billingCycle: BillingCycles.monthly,
      dueDate: DateTime(2026, 10, 7),
      category: 'Entertainment',
      price: 9.99,
      isDeleted: false,
      updatedAt: DateTime.utc(2026, 10, 5, 9, 30, 15, 123),
      isSynced: false,
    );

    expect(SubscriptionApi.toJson(row), {
      'name': 'Netflix',
      'price': 9.99,
      'billingCycle': 'monthly',
      'nextPaymentDate': '2026-10-07',
      'category': 'Entertainment',
      'updatedAt': '2026-10-05T09:30:15.123Z',
    });
  });

  test('fromJson: reads the server format into a synced row', () {
    final row = SubscriptionApi.fromJson({
      '_id': 'abc',
      'name': 'Netflix',
      'price': 15, // JSON may send whole numbers as int
      'billingCycle': 'weekly',
      'nextPaymentDate': '2026-10-07T00:00:00.000Z',
      'category': 'Entertainment',
      'updatedAt': '2026-10-05T09:30:15.123Z',
      'deletedAt': null,
    });

    expect(row.id.value, 'abc');
    expect(row.price.value, 15.0);
    expect(row.billingCycle.value, BillingCycles.weekly);
    // Same calendar day in every time zone (not shifted to Oct 6).
    expect(row.dueDate.value, DateTime(2026, 10, 7));
    expect(
      row.updatedAt.value.isAtSameMomentAs(
        DateTime.utc(2026, 10, 5, 9, 30, 15, 123),
      ),
      isTrue,
    );
    expect(row.isDeleted.value, isFalse);
    expect(row.isSynced.value, isTrue); // it IS the server's version
  });

  test('fromJson: deletedAt marks the row as deleted', () {
    final row = SubscriptionApi.fromJson({
      '_id': 'abc',
      'name': 'Netflix',
      'price': 9.99,
      'billingCycle': 'monthly',
      'nextPaymentDate': '2026-10-07T00:00:00.000Z',
      'category': 'Entertainment',
      'updatedAt': '2026-10-05T09:30:15.123Z',
      'deletedAt': '2026-10-05T10:00:00.000Z',
    });

    expect(row.isDeleted.value, isTrue);
  });
}
