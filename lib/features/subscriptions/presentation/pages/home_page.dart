import 'package:flutter/material.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/subscription_form_page.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/net_status_topbar.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/subscription_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository, this.networkInfo});

  /// Source of subscription data (Drift behind it).
  final SubscriptionRepository repository;

  /// Injectable for tests; defaults to the real connectivity checks.
  final NetworkInfo? networkInfo;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Created once so rebuilds don't re-subscribe to the network listeners.
  late final Stream<NetworkStatus> _networkStatus =
      (widget.networkInfo ?? NetworkInfo()).watchStatus();

  // READ: the live Drift query, created ONCE.
  // If this were created inside build(), every rebuild would start a brand
  // new database query (and briefly flash the loading state).
  late final Stream<List<Subscription>> _subscriptions = widget.repository
      .watchAll();

  /// DELETE: ask first, then soft delete.
  ///
  /// Notice what is NOT here: no `setState`, no removing the item from a
  /// local list. We only change the database; `watchAll()` re-emits without
  /// the row and the StreamBuilder redraws the list.
  Future<void> _confirmAndDelete(Subscription item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: const Text('It will be removed from your subscriptions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    // null = dismissed by tapping outside, false = Cancel.
    if (confirmed != true) return;

    try {
      await widget.repository.delete(item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription tracker'),
        actions: [
          StreamBuilder<NetworkStatus>(
            stream: _networkStatus,
            builder: (context, snapshot) {
              // Hidden until the first check completes, so it never
              // shows a status we haven't confirmed yet.
              if (!snapshot.hasData) return const SizedBox.shrink();
              return NetStatusTopbar(
                isOffline: snapshot.data == NetworkStatus.offline,
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Create subscription'),
        icon: const Icon(Icons.add),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            // Pass the same repository down (constructor injection).
            builder: (_) => SubscriptionFormPage(repository: widget.repository),
          ),
          // No `await` + "reload" here: the list updates through its stream.
        ),
      ),
      // StreamBuilder listens to the Drift stream and calls `builder` again
      // on every emission: first the initial rows, then after every change
      // to the `subscriptions` table. No manual "refresh" is ever needed.
      body: StreamBuilder<List<Subscription>>(
        stream: _subscriptions,
        builder: (context, snapshot) {
          // 1. ERROR: the query failed (e.g. corrupt file, bad migration).
          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              text: 'Could not load subscriptions\n${snapshot.error}',
            );
          }

          // 2. LOADING: the first emission hasn't arrived yet. On a local
          //    database this usually lasts only a few milliseconds.
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!;

          // 3. EMPTY: query worked, table has no rows.
          if (items.isEmpty) {
            return const _CenteredMessage(
              icon: Icons.subscriptions_outlined,
              text:
                  'No subscriptions yet\nTap "Create subscription" to add one',
            );
          }

          // 4. DATA: one card per row. `builder` only builds visible cards.
          return ListView.builder(
            // Extra bottom space so the FAB doesn't cover the last card.
            padding: const EdgeInsets.only(bottom: 88.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              // ValueKey(id) lets Flutter match each card to its row when the
              // list changes (e.g. after a delete in Step 4).
              return SubscriptionCard(
                key: ValueKey(item.id),
                item: item,
                // UPDATE: open the same form, pre-filled with this item.
                // After saving, watchAll() re-emits and this card redraws
                // with the new values — same mechanism as create/delete.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubscriptionFormPage(
                      repository: widget.repository,
                      initial: item,
                    ),
                  ),
                ),
                onDelete: () => _confirmAndDelete(item),
              );
            },
          );
        },
      ),
    );
  }
}

/// Icon + text centered on screen, for the empty and error states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12.0,
          children: [
            Icon(icon, size: 48.0, color: theme.colorScheme.outline),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
