import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Date Formatting Utilities
// ---------------------------------------------------------------------------

/// Extension on DateTime for reusable presentable formatting across the app
extension DateTimeFormattingX on DateTime {
  /// Short display date: "Oct 7, 2026"
  String toShortDate() {
    return DateFormat.yMMMd().format(toLocal());
  }

  /// Full display date: "Wednesday, October 7, 2026"
  String toFullDate() {
    return DateFormat.yMMMMEEEEd().format(toLocal());
  }

  /// Compact numerical date: "10/07/2026" or "07/10/2026" based on user locale
  String toNumericDate() {
    return DateFormat.yMd().format(toLocal());
  }

  /// Human-readable status relative to current date (e.g., "Due in 7 days", "Due today")
  String toDueStatusText() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(year, month, day);

    final differenceInDays = target.difference(today).inDays;

    if (differenceInDays < 0) {
      final daysAgo = differenceInDays.abs();
      return daysAgo == 1 ? 'Overdue by 1 day' : 'Overdue by $daysAgo days';
    } else if (differenceInDays == 0) {
      return 'Due today';
    } else if (differenceInDays == 1) {
      return 'Due tomorrow';
    } else {
      return 'Due in $differenceInDays days';
    }
  }
}
