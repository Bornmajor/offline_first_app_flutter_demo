import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/remote/subscription_dto.dart';

/// A subscription exactly as the Express server returns it.
Map<String, dynamic> serverJson({Object? deletedAt}) => {
  '_id': '3f2b8c1e-6a4d-4f0e-9b7a-2c5d8e1f0a3b',
  'name': 'Netflix',
  'price': 15, // an int on purpose: JSON has no int/double distinction
  'billingCycle': 'weekly',
  'nextPaymentDate': '2026-10-07T00:00:00.000Z',
  'category': 'entertainment',
  'createdAt': '2026-10-01T08:00:00.000Z',
  'updatedAt': '2026-10-05T09:30:15.123Z',
  'deletedAt': deletedAt,
  'serverUpdatedAt': '2026-10-05T09:30:16.000Z',
  '__v': 0,
};

void main() {
  group('fromJson', () {
    test('reads every field the app needs', () {
      final dto = SubscriptionDto.fromJson(serverJson());

      expect(dto.id, '3f2b8c1e-6a4d-4f0e-9b7a-2c5d8e1f0a3b');
      expect(dto.name, 'Netflix');
      expect(dto.price, 15.0);
      expect(dto.billingCycle, BillingCycles.weekly);
      expect(dto.category, 'entertainment');
      expect(dto.isDeleted, isFalse);
    });

    test('due date is the same calendar day in every time zone', () {
      final dto = SubscriptionDto.fromJson(serverJson());

      // Midnight UTC must NOT become Oct 6 in a UTC-x zone.
      expect(dto.nextPaymentDate, DateTime(2026, 10, 7));
      expect(dto.nextPaymentDate.isUtc, isFalse);
    });

    test('updatedAt keeps the exact moment, with milliseconds', () {
      final dto = SubscriptionDto.fromJson(serverJson());

      expect(
        dto.updatedAt.isAtSameMomentAs(
          DateTime.utc(2026, 10, 5, 9, 30, 15, 123),
        ),
        isTrue,
      );
    });

    test('a tombstone has deletedAt', () {
      final dto = SubscriptionDto.fromJson(
        serverJson(deletedAt: '2026-10-05T10:00:00.000Z'),
      );

      expect(dto.isDeleted, isTrue);
    });

    test('an unknown billing cycle is rejected', () {
      expect(
        () => SubscriptionDto.fromJson(
          serverJson()..['billingCycle'] = 'fortnightly',
        ),
        throwsArgumentError,
      );
    });
  });

  group('toJson', () {
    final dto = SubscriptionDto(
      id: 'abc',
      name: 'Netflix',
      price: 9.99,
      billingCycle: BillingCycles.monthly,
      nextPaymentDate: DateTime(2026, 10, 7),
      category: 'Entertainment',
      updatedAt: DateTime.utc(2026, 10, 5, 9, 30, 15, 123),
    );

    test('sends the writable fields in the server\'s names', () {
      expect(dto.toJson(), {
        'name': 'Netflix',
        'price': 9.99,
        'billingCycle': 'monthly',
        'nextPaymentDate': '2026-10-07', // a plain date: no time zone shift
        'category': 'Entertainment',
        'updatedAt': '2026-10-05T09:30:15.123Z', // UTC, with milliseconds
      });
    });

    test('never sends the id or server-controlled fields in the body', () {
      final json = dto.toJson();
      expect(json.containsKey('_id'), isFalse);
      expect(json.containsKey('deletedAt'), isFalse);
    });
  });
}
