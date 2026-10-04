import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';

/// This subscription entity
/// [id] - unique subscription ID
/// [name] - name of subscription
class Subscription {
  final String id;
  final String name;
  final BillingCycles billingCycle;
  final DateTime dueDate;
  final String category;
  final double price;

  const Subscription({
    required this.id,
    required this.name,
    required this.billingCycle,
    required this.dueDate,
    required this.category,
    required this.price,
  });
}
