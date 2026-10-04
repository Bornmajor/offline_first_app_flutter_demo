import 'package:flutter/material.dart';

class ProgressSubscriptionIndicator extends StatelessWidget {
  final DateTime startDate;
  final DateTime dueDate;
  final Color? defaultColor;
  final double strokeWidth;

  const ProgressSubscriptionIndicator({
    super.key,
    required this.startDate,
    required this.dueDate,
    this.defaultColor,
    this.strokeWidth = 4.0,
  });

  /// Calculates progress between 0.0 (just started) and 1.0 (due date reached/passed).
  double get _progress {
    final now = DateTime.now();

    // Total cycle duration in milliseconds
    final totalDuration = dueDate.difference(startDate).inMilliseconds;
    if (totalDuration <= 0) return 1.0;

    // Time elapsed so far in milliseconds
    final elapsed = now.difference(startDate).inMilliseconds;

    // Clamp value between 0.0 and 1.0
    return (elapsed / totalDuration).clamp(0.0, 1.0);
  }

  /// Determines indicator color based on remaining days/progress.
  Color _getProgressColor(BuildContext context) {
    final now = DateTime.now();
    final remainingDays = dueDate.difference(now).inDays;

    // Use red if 3 or fewer days remaining OR if progress is >= 90%
    if (remainingDays <= 3 || _progress >= 0.90) {
      return Colors.red;
    }

    // Fallback to custom default color or theme primary color
    return defaultColor ?? Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = _progress;
    final progressColor = _getProgressColor(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: progressValue,
          strokeWidth: strokeWidth,
          color: progressColor,
          backgroundColor: progressColor.withAlpha(50),
        ),
        // Optional percentage text inside the loader
        Text(
          '${(progressValue * 100).toInt()}%',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: progressColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
