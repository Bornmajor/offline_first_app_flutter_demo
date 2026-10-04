// ---------------------------------------------------------------------------
// 1. Enum Definition & UI Utilities
// ---------------------------------------------------------------------------

enum BillingCycles { daily, weekly, monthly, yearly }

/// Extension on BillingCycles for UI presentation
extension BillingCyclesUIX on BillingCycles {
  /// Simple label (e.g., "Monthly")
  String get label {
    switch (this) {
      case BillingCycles.daily:
        return 'Daily';
      case BillingCycles.weekly:
        return 'Weekly';
      case BillingCycles.monthly:
        return 'Monthly';
      case BillingCycles.yearly:
        return 'Yearly';
    }
  }

  /// Billing period suffix for prices (e.g., "/ mo" or "per month")
  String get priceSuffix {
    switch (this) {
      case BillingCycles.daily:
        return '/ day';
      case BillingCycles.weekly:
        return '/ wk';
      case BillingCycles.monthly:
        return '/ mo';
      case BillingCycles.yearly:
        return '/ yr';
    }
  }

  /// Start of the billing period that ends on [dueDate]
  /// (e.g. monthly, due Oct 7 → Sep 7).
  /// DateTime normalizes overflow, so Mar 31 - 1 month → "Feb 31" → Mar 3.
  DateTime periodStart(DateTime dueDate) {
    switch (this) {
      case BillingCycles.daily:
        return DateTime(dueDate.year, dueDate.month, dueDate.day - 1);
      case BillingCycles.weekly:
        return DateTime(dueDate.year, dueDate.month, dueDate.day - 7);
      case BillingCycles.monthly:
        return DateTime(dueDate.year, dueDate.month - 1, dueDate.day);
      case BillingCycles.yearly:
        return DateTime(dueDate.year - 1, dueDate.month, dueDate.day);
    }
  }

  /// Descriptive frequency text (e.g., "Billed every month")
  String get description {
    switch (this) {
      case BillingCycles.daily:
        return 'Billed every day';
      case BillingCycles.weekly:
        return 'Billed every week';
      case BillingCycles.monthly:
        return 'Billed every month';
      case BillingCycles.yearly:
        return 'Billed every year';
    }
  }
}
