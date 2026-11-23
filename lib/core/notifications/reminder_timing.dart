/// When the user wants to be reminded that a subscription is about to renew.
/// The server reads this per device and sends the reminder at that time.
enum ReminderTiming {
  oneDayBefore('one_day_before', '1 day before'),
  onDueDate('on_due_date', 'On the due date');

  const ReminderTiming(this.apiValue, this.label);

  /// The value the server stores (see the Device model on the server).
  final String apiValue;

  /// What the settings screen shows.
  final String label;

  /// Default for new installs (same default as the server).
  static const defaultValue = ReminderTiming.oneDayBefore;

  static ReminderTiming fromApiValue(String? value) => values.firstWhere(
    (timing) => timing.apiValue == value,
    orElse: () => defaultValue,
  );
}
