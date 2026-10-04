import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/subscription_card.dart';

import 'helpers/test_database.dart';

class _SilentNetworkInfo implements NetworkInfo {
  @override
  Stream<NetworkStatus> watchStatus() => const Stream.empty();
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  /// Tall phone-sized screen so the whole form (incl. Save) is built and
  /// tappable; the default 800x600 test screen cuts it off.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('Home → form → Save → new card appears on Home', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          repository: db.subscriptionRepository,
          networkInfo: _SilentNetworkInfo(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No subscriptions yet'), findsOneWidget);

    // Open the form.
    await tester.tap(find.text('Create subscription'));
    await tester.pumpAndSettle();

    // Fill in every field.
    await tester.enterText(find.byType(TextFormField).at(0), 'Netflix');
    await tester.enterText(find.byType(TextFormField).at(1), '9.99');

    await tester.tap(find.text('Select category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music').last);
    await tester.pumpAndSettle();

    // Date picker opens on today; confirm it.
    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Save.
    await tester.tap(find.text('Save subscription'));
    await tester.pumpAndSettle();

    // Back on Home, and the card is there without any refresh call.
    expect(find.text('New subscription'), findsNothing);
    expect(find.byType(SubscriptionCard), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  testWidgets('invalid form does not write to the database', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          repository: db.subscriptionRepository,
          networkInfo: _SilentNetworkInfo(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create subscription'));
    await tester.pumpAndSettle();

    // Save with everything empty.
    await tester.tap(find.text('Save subscription'));
    await tester.pumpAndSettle();

    // Still on the form, errors shown, nothing stored.
    expect(find.text('New subscription'), findsOneWidget);
    expect(find.text('Name is required'), findsOneWidget);
    expect(await db.select(db.subscriptions).get(), isEmpty);
  });

  group('edit', () {
    /// Puts one row in the db, shows Home, taps the card → edit form.
    Future<void> openEditFormFor(
      WidgetTester tester, {
      required DateTime dueDate,
    }) async {
      useTallScreen(tester);
      await tester.runAsync(
        () => insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: dueDate,
          price: 9.99,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            repository: db.subscriptionRepository,
            networkInfo: _SilentNetworkInfo(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
    }

    testWidgets('form opens pre-filled, Save updates the card in place', (
      tester,
    ) async {
      await openEditFormFor(
        tester,
        dueDate: DateTime.now().add(const Duration(days: 10)),
      );

      // Edit mode: different title/button, fields filled from the row.
      expect(find.text('Edit subscription'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Netflix'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '9.99'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Netflix 4K');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      // Back on Home: still ONE card, now with the new name.
      expect(find.byType(SubscriptionCard), findsOneWidget);
      expect(find.text('Netflix 4K'), findsOneWidget);
      expect(find.text('Netflix'), findsNothing);
      expect(await db.select(db.subscriptions).get(), hasLength(1));
    });

    testWidgets('an overdue subscription can still be edited', (tester) async {
      await openEditFormFor(
        tester,
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
      );

      // Only rename; the old past due date is left unchanged.
      await tester.enterText(find.byType(TextFormField).at(0), 'Netflix 4K');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be in the past'), findsNothing);
      expect(find.text('Netflix 4K'), findsOneWidget);
    });
  });
}
