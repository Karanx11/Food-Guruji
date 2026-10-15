import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_guruji/features/shell/home_shell.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('five round buttons switch tabs and show the selected icon', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(home: const HomeShell()));
    await tester.pumpAndSettle();

    for (final tooltip in [
      'Home',
      'Food log',
      'Snap food',
      'Progress',
      'Profile',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    expect(find.text('Stay On Track Today'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Food log'));
    await tester.pumpAndSettle();
    expect(find.text('Food Log'), findsOneWidget);
    expect(find.byIcon(Icons.room_service_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Goal Progress'), findsWidgets);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your Profile'), findsOneWidget);

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Stay On Track Today'), findsOneWidget);
  });

  testWidgets('Snap opens the photo source sheet', (tester) async {
    await tester.pumpWidget(testApp(home: const HomeShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Snap food'));
    await tester.pumpAndSettle();
    expect(find.text('Add food'), findsOneWidget);
    expect(find.byKey(const Key('snap-source-Camera')), findsOneWidget);
    expect(find.byKey(const Key('snap-source-Gallery')), findsOneWidget);
    expect(find.byKey(const Key('snap-source-Scan barcode')), findsOneWidget);
  });
}
