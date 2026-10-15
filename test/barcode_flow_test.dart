import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_guruji/features/barcode/domain/barcode_lookup.dart';
import 'package:food_guruji/features/capture/domain/detected_food.dart';
import 'package:food_guruji/features/capture/presentation/review_page.dart';
import 'package:food_guruji/features/log/application/log_providers.dart';
import 'package:food_guruji/features/log/domain/food_entry.dart';
import 'package:food_guruji/features/log/domain/nutrition.dart';
import 'package:food_guruji/features/shell/home_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

const _cola = DetectedFood(
  name: 'Coca-Cola',
  brand: 'Coca-Cola',
  barcode: '5449000000996',
  servingLabel: '330 ml',
  gramsPerServing: 330,
  perServing: Nutrition(calories: 139, carbsG: 35, sugarG: 35),
);

List<FoodEntry> _todaysEntries(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeShell)),
  );
  return container.read(dayEntriesProvider('2026-09-22')).value ??
      const <FoodEntry>[];
}

void main() {
  testWidgets('scan a barcode, look it up, review and log the product', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        barcodeLookup: InMemoryBarcodeLookup({'5449000000996': _cola}),
      ),
    );
    await _settle(tester);

    // Open the Snap sheet and choose "Scan barcode".
    await tester.tap(find.byTooltip('Snap food'));
    await _settle(tester);
    expect(find.text('Add food'), findsOneWidget);
    await tester.tap(find.byKey(const Key('snap-source-Scan barcode')));
    await _settle(tester);

    // Camera is off in tests, so type the barcode and look it up.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '5449000000996');
    await tester.tap(find.widgetWithText(FilledButton, 'Look up product'));
    await _settle(tester);

    // The review screen shows the scanned product with its brand and badge.
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.text('Coca-Cola'), findsOneWidget);
    expect(find.text('Scanned product'), findsOneWidget);
    expect(find.text('COCA-COLA'), findsOneWidget); // brand eyebrow
    expect(find.text('Scanned'), findsOneWidget); // from-barcode badge

    // Log it to the meal.
    await tester.tap(find.textContaining('Add 1 to'));
    await _settle(tester);

    final entries = _todaysEntries(tester);
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Coca-Cola');
    expect(entries.single.perServing.calories, 139);
  });

  testWidgets('an unknown barcode is reported, not opened as a review', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        barcodeLookup: InMemoryBarcodeLookup(const {}),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('Snap food'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('snap-source-Scan barcode')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '0000000000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Look up product'));
    await _settle(tester);

    expect(find.byType(ReviewPage), findsNothing);
    expect(find.textContaining('No product found'), findsOneWidget);
  });
}
