import 'package:flutter/material.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/core/utils/date_formatter.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/progress_subscription_indicator.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';

/// Subscription card display in home screen
/// [item] - subscription item
/// [onTap] - called when the card is tapped (e.g. open it for editing).
/// [onDelete] - called when Delete is tapped.
/// The card itself doesn't know about the database: the parent decides what
/// "tap" and "delete" mean.
class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
  });

  final Subscription item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16.0);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      // Material + InkWell (instead of a colored Container) so the tap
      // ripple is drawn on top of the card's background color.
      child: Material(
        color: const Color(0xFFF2F2F2),
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16.0,
      children: [
        SubscriptionTopSection(
          title: item.name,
          cycle: item.billingCycle,
          dueDate: item.dueDate,
        ),
        Text(
          item.dueDate.toShortDate(),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
          onPressed: onDelete,
          label: Text(
            'Delete',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class SubscriptionTopSection extends StatelessWidget {
  const SubscriptionTopSection({
    super.key,
    required this.title,
    required this.cycle,
    required this.dueDate,
  });

  final String title;
  final BillingCycles cycle;
  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            Text(
              cycle.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const Spacer(),
        ProgressSubscriptionIndicator(
          // Real period for this subscription instead of fixed dates.
          startDate: cycle.periodStart(dueDate),
          dueDate: dueDate,
          defaultColor: Colors.blue,
        ),
      ],
    );
  }
}
