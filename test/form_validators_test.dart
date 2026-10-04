import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/utils/form_validators.dart';

void main() {
  group('required', () {
    test('rejects null and blank values', () {
      expect(
        FormValidators.required(null, fieldName: 'Name'),
        'Name is required',
      );
      expect(
        FormValidators.required('   ', fieldName: 'Name'),
        'Name is required',
      );
    });

    test('accepts a value', () {
      expect(FormValidators.required('Netflix'), isNull);
    });
  });

  group('price', () {
    test('rejects empty, non-numeric and non-positive values', () {
      expect(FormValidators.price(''), 'Price is required');
      expect(FormValidators.price('.'), 'Price must be a number');
      expect(FormValidators.price('0'), 'Price must be greater than 0');
    });

    test('accepts positive numbers', () {
      expect(FormValidators.price('10'), isNull);
      expect(FormValidators.price('9.99'), isNull);
    });
  });

  group('notPastDate', () {
    final now = DateTime.now();

    test('rejects null and past dates', () {
      expect(
        FormValidators.notPastDate(null, fieldName: 'Due date'),
        'Due date is required',
      );
      expect(
        FormValidators.notPastDate(
          now.subtract(const Duration(days: 1)),
          fieldName: 'Due date',
        ),
        'Due date cannot be in the past',
      );
    });

    test('accepts today (any time) and future dates', () {
      expect(
        FormValidators.notPastDate(DateTime(now.year, now.month, now.day)),
        isNull,
      );
      expect(
        FormValidators.notPastDate(now.add(const Duration(days: 30))),
        isNull,
      );
    });
  });
}
