// ---------------------------------------------------------------------------
// Reusable Form Validators
// ---------------------------------------------------------------------------

/// Validators shared across forms. Each returns an error message or null.
abstract final class FormValidators {
  /// Value must not be null (and not blank, for strings).
  static String? required<T>(T? value, {String fieldName = 'This field'}) {
    final isEmpty = value == null || (value is String && value.trim().isEmpty);
    return isEmpty ? '$fieldName is required' : null;
  }

  /// Required positive number, e.g. "9.99".
  static String? price(String? value) {
    final requiredError = required(value, fieldName: 'Price');
    if (requiredError != null) return requiredError;

    final price = double.tryParse(value!.trim());
    if (price == null) return 'Price must be a number';
    if (price <= 0) return 'Price must be greater than 0';
    return null;
  }

  /// Required date that is today or later.
  static String? notPastDate(DateTime? value, {String fieldName = 'Date'}) {
    final requiredError = required(value, fieldName: fieldName);
    if (requiredError != null) return requiredError;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value!.year, value.month, value.day);
    if (date.isBefore(today)) return '$fieldName cannot be in the past';
    return null;
  }
}
