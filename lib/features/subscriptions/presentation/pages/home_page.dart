import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_list/subscription_list_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_list/subscription_list_state.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/sync/sync_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/subscription_form_page.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/subscription_card.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/sync_status_line.dart';

/// Home screen — PAGE part: wiring only.
///
/// "Page / View" split:
///   • HomePage creates the dependencies the screen needs (the Cubit).
///   • HomeView draws the UI from the Cubit's state.
/// Keeping them apart means the View never cares where the Cubit came from
/// (a test could provide a different one).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // `create` runs once, lazily. The repository comes from the
      // RepositoryProvider in main.dart. `..watchSubscriptions()` (cascade)
      // starts listening to the database right after creating the Cubit.
      //
      // BlocProvider also CLOSES the Cubit when this page is removed,
      // which cancels the database stream (see SubscriptionListCubit.close).
      create: (context) =>
          SubscriptionListCubit(context.read<SubscriptionRepository>())
            ..watchSubscriptions(),
      child: const HomeView(),
    );
  }
}

/// Home screen — VIEW part: draws whatever the Cubit's state says.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  /// DELETE: the dialog is a UI job, so it stays here in the View.
  /// The actual delete is the Cubit's job.
  Future<void> _confirmAndDelete(Subscription item) async {
    // Read the Cubit before any `await`, so we never touch `context` after
    // the page might have closed. `context.read<SubscriptionListCubit>()`
    // finds the Cubit created by BlocProvider in HomePage (an ancestor).
    final cubit = context.read<SubscriptionListCubit>();

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

    // Hand off to the Cubit. No try/catch and no snackbar code here:
    // the Cubit reports failures through its state, and the BlocListener
    // in build() shows them. No list update here either: the database
    // stream removes the card.
    await cubit.delete(item.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Title with the sync status underneath. It also covers being
        // offline ("Offline · 2 changes waiting"), so no separate network
        // indicator is needed.
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('Subscription tracker'), SyncStatusLine()],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Create subscription'),
        icon: const Icon(Icons.add),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            // The form finds the repository in the tree (RepositoryProvider
            // sits above MaterialApp). No "reload" after it closes: the
            // Cubit's database stream picks up the new row by itself.
            builder: (_) => const SubscriptionFormPage(),
          ),
        ),
      ),
      // BlocListener vs BlocBuilder:
      //   • BlocListener → runs `listener` ONCE per new state, for one-off
      //     actions (snackbar, navigation). It draws nothing.
      //   • BlocBuilder  → rebuilds UI from the state.
      body: BlocListener<SubscriptionListCubit, SubscriptionListState>(
        // Only react to ACTION errors (e.g. delete failed) while the list is
        // showing. A load failure has its own full-screen message instead.
        listenWhen: (previous, current) =>
            current.status == SubscriptionListStatus.success &&
            current.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
        },
        child: _buildList(),
      ),
    );
  }

  /// READ: BlocBuilder rebuilds this part every time the Cubit emits a new
  /// state. The View has no logic about WHERE data comes from — it just
  /// draws the state it's given.
  Widget _buildList() {
    return BlocBuilder<SubscriptionListCubit, SubscriptionListState>(
      // Skip rebuilds when only the one-off error message changed — the
      // list itself looks the same.
      buildWhen: (previous, current) =>
          previous.status != current.status || previous.items != current.items,
      builder: (context, state) {
        // A Dart 3 `switch` expression: one case per status, and the
        // compiler checks that every status is handled.
        return switch (state.status) {
          SubscriptionListStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          SubscriptionListStatus.failure => _CenteredMessage(
            icon: Icons.error_outline,
            text: state.errorMessage ?? 'Could not load subscriptions',
          ),
          SubscriptionListStatus.success when state.items.isEmpty =>
            const _CenteredMessage(
              icon: Icons.subscriptions_outlined,
              text:
                  'No subscriptions yet\nTap "Create subscription" to add one',
            ),
          SubscriptionListStatus.success => _SubscriptionList(
            items: state.items,
            onDelete: _confirmAndDelete,
          ),
        };
      },
    );
  }
}

/// The list of cards (success state with items).
class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({required this.items, required this.onDelete});

  final List<Subscription> items;
  final void Function(Subscription item) onDelete;

  @override
  Widget build(BuildContext context) {
    // Pull down to sync now; the spinner stays until the sync finishes.
    return RefreshIndicator(
      onRefresh: () => context.read<SyncCubit>().syncNow(),
      child: _buildCards(),
    );
  }

  Widget _buildCards() {
    return ListView.builder(
      // Extra bottom space so the FAB doesn't cover the last card.
      padding: const EdgeInsets.only(bottom: 88.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        // ValueKey(id) lets Flutter match each card to its row when the
        // list changes (e.g. after a delete).
        return SubscriptionCard(
          key: ValueKey(item.id),
          item: item,
          // UPDATE: open the same form, pre-filled with this item.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubscriptionFormPage(initial: item),
            ),
          ),
          onDelete: () => onDelete(item),
        );
      },
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
