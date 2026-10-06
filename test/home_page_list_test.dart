import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/subscription_card.dart';

import 'helpers/test_app.dart';
import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(testApp(db, home: const HomePage()));
    // Let the first Drift emission arrive and render.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the empty state when the table is empty', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('No subscriptions yet'), findsOneWidget);
    expect(find.byType(SubscriptionCard), findsNothing);
  });

  testWidgets('shows rows from the database and updates live', (tester) async {
    await pumpHome(tester);
    expect(find.byType(SubscriptionCard), findsNothing);

    // Write straight to the database — no "refresh" call on the page.
    await tester.runAsync(
      () => insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime.now().add(const Duration(days: 10)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SubscriptionCard), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  group('delete from the card', () {
    Future<void> pumpHomeWithNetflix(WidgetTester tester) async {
      await tester.runAsync(
        () => insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: DateTime.now().add(const Duration(days: 10)),
        ),
      );
      await pumpHome(tester);
      expect(find.byType(SubscriptionCard), findsOneWidget);

      // Tap the card's Delete button → confirmation dialog.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Netflix?'), findsOneWidget);
    }

    testWidgets('Cancel keeps the subscription', (tester) async {
      await pumpHomeWithNetflix(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionCard), findsOneWidget);
      final row = (await db.select(db.subscriptions).get()).single;
      expect(row.isDeleted, isFalse);
    });

    testWidgets('confirming removes the card and soft-deletes the row', (
      tester,
    ) async {
      await pumpHomeWithNetflix(tester);

      // Two "Delete" texts now: the card's button and the dialog's. The
      // dialog is on top, so it's the last one.
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionCard), findsNothing);
      expect(find.textContaining('No subscriptions yet'), findsOneWidget);

      final row = (await db.select(db.subscriptions).get()).single;
      expect(row.isDeleted, isTrue);
    });

    testWidgets('a failed delete keeps the card and shows a snackbar', (
      tester,
    ) async {
      await tester.runAsync(
        () => insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: DateTime.now().add(const Duration(days: 10)),
        ),
      );
      // Real reads from the test db, but delete always fails.
      await tester.pumpWidget(
        testApp(
          db,
          repository: _DeleteFailsRepository(db.subscriptionsDao),
          home: const HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last); // confirm in dialog
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Could not delete: locked'), findsOneWidget);
      expect(find.byType(SubscriptionCard), findsOneWidget);
    });
  });
}

/// Reads like the real repository (extends it), but delete always fails.
class _DeleteFailsRepository extends SubscriptionRepository {
  _DeleteFailsRepository(super.dao);

  @override
  Future<void> delete(String id) async => throw 'locked';
}
