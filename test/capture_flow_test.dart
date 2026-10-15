import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_guruji/features/capture/data/photo_source.dart';
import 'package:food_guruji/features/capture/domain/detected_food.dart';
import 'package:food_guruji/features/capture/domain/food_analyzer.dart';
import 'package:food_guruji/features/capture/presentation/review_page.dart';
import 'package:food_guruji/features/log/application/log_providers.dart';
import 'package:food_guruji/features/log/domain/food_entry.dart';
import 'package:food_guruji/features/log/domain/nutrition.dart';
import 'package:food_guruji/features/shell/home_shell.dart';

import 'helpers/fake_capture.dart';
import 'helpers/test_app.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps a bounded number of frames. pumpAndSettle can't be used across the
/// analyzing step, whose loader animates forever; a fixed span (~2.4 s)
/// covers every transition, dialog and snackbar in this flow.
Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _snap(WidgetTester tester, PhotoOrigin origin) async {
  await tester.tap(find.byTooltip('Snap food'));
  await _settle(tester);
  expect(find.text('Add food'), findsOneWidget);
  await tester.tap(
    find.byKey(
      Key('snap-source-${origin == PhotoOrigin.camera ? "Camera" : "Gallery"}'),
    ),
  );
  await _settle(tester);
}

/// Today's entries, read from the provider the Home tab already watches, so
/// the test never opens a fresh sembast stream (which the fake clock would
/// never advance).
List<FoodEntry> _todaysEntries(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeShell)),
  );
  return container.read(dayEntriesProvider('2026-09-22')).value ??
      const <FoodEntry>[];
}

void main() {
  testWidgets('snap → review → log adds the detected foods to a meal', (
    tester,
  ) async {
    _tallView(tester);
    final source = FakePhotoSource(
      photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
    );
    final analyzer = FakeFoodAnalyzer();
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: source,
        foodAnalyzer: analyzer,
      ),
    );
    await _settle(tester);

    await _snap(tester, PhotoOrigin.camera);
    expect(source.lastOrigin, PhotoOrigin.camera);
    expect(analyzer.calls, 1);

    // Review screen: both detected foods, at 1 pm the meal defaults to Lunch.
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.text('Dal tadka'), findsOneWidget);
    expect(find.text('Steamed rice'), findsOneWidget);
    // 180 (dal x1) + 390 (rice x2) = 570 kcal.
    expect(find.text('2 items · 570 kcal'), findsOneWidget);
    expect(find.text('Add 2 to Lunch'), findsOneWidget);
    // Not a demo analyzer, so no demo banner.
    expect(find.textContaining('Demo results'), findsNothing);

    await tester.tap(find.text('Add 2 to Lunch'));
    await _settle(tester);

    expect(find.byType(ReviewPage), findsNothing);
    final entries = _todaysEntries(tester);
    expect(
      entries.map((e) => e.name),
      containsAll(['Dal tadka', 'Steamed rice']),
    );
    expect(entries.every((e) => e.source == FoodSource.photo), isTrue);
    expect(entries.firstWhere((e) => e.name == 'Steamed rice').servings, 2);
  });

  testWidgets('portions can be adjusted and items removed before logging', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: FakeFoodAnalyzer(),
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.gallery);

    // Drop the rice.
    await tester.tap(find.byKey(const Key('review-remove-Steamed rice')));
    await _settle(tester);
    expect(find.text('Steamed rice'), findsNothing);
    expect(find.text('1 item · 180 kcal'), findsOneWidget);

    // Add half a serving of dal: 1.25 x 180 = 225 kcal.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('review-Dal tadka')),
        matching: find.byTooltip('More'),
      ),
    );
    await _settle(tester);
    expect(find.text('1.25 × 1 katori   ·   187.5 g'), findsOneWidget);
    expect(find.text('1 item · 225 kcal'), findsOneWidget);

    await tester.tap(find.text('Add 1 to Lunch'));
    await _settle(tester);
    final entries = _todaysEntries(tester);
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Dal tadka');
    expect(entries.single.servings, 1.25);
  });

  testWidgets('a failed analysis can be retried, then succeeds', (
    tester,
  ) async {
    _tallView(tester);
    final analyzer = FakeFoodAnalyzer(
      error: const AnalyzerException("Couldn't reach the server."),
    );
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: analyzer,
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.camera);

    expect(find.text("Couldn't reach the server."), findsOneWidget);
    expect(find.byType(ReviewPage), findsNothing);

    analyzer.error = null; // server recovers
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(analyzer.calls, 2);
    expect(find.byType(ReviewPage), findsOneWidget);
  });

  testWidgets('cancelling the source sheet does nothing', (tester) async {
    final analyzer = FakeFoodAnalyzer();
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(),
        foodAnalyzer: analyzer,
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('Snap food'));
    await _settle(tester);
    // Dismiss the sheet without choosing a source.
    await tester.tapAt(const Offset(200, 60));
    await _settle(tester);
    expect(find.text('Add food'), findsNothing);
    expect(analyzer.calls, 0);
  });

  testWidgets('an empty result is reported, not opened as a blank review', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: FakeFoodAnalyzer(result: const []),
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.camera);

    expect(find.byType(ReviewPage), findsNothing);
    expect(find.textContaining('No food found'), findsOneWidget);
  });

  testWidgets('the review card shows macros, micros and notes', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: FakeFoodAnalyzer(
          result: const [
            DetectedFood(
              name: 'Kulhad Masala Chai',
              servingLabel: '1 kulhad',
              gramsPerServing: 150,
              servings: 1,
              perServing: Nutrition(
                calories: 210,
                proteinG: 4,
                carbsG: 30,
                fatG: 6,
                sugarG: 28,
                fiberG: 0,
                sodiumMg: 90,
              ),
              notes: 'Provides calcium from milk.',
            ),
          ],
        ),
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.camera);

    // Macro pills (grams) and the micronutrient line are shown.
    expect(find.text('4 g'), findsOneWidget); // protein
    expect(find.text('30 g'), findsOneWidget); // carbs
    expect(find.text('6 g'), findsOneWidget); // fat
    expect(find.text('Protein'), findsOneWidget);
    expect(
      find.text('Sugar 28 g   ·   Fiber 0 g   ·   Sodium 90 mg'),
      findsOneWidget,
    );
    expect(find.text('Provides calcium from milk.'), findsOneWidget);
    // Totals under the summary.
    expect(find.text('Protein 4 g · Carbs 30 g · Fat 6 g'), findsOneWidget);
  });

  testWidgets('editing a food corrects its macros before logging', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: FakeFoodAnalyzer(
          result: const [
            DetectedFood(
              name: 'Chicken Biryani',
              servingLabel: '1 plate',
              gramsPerServing: 250,
              servings: 1,
              // The model over-counted protein at 70 g per plate.
              perServing: Nutrition(
                calories: 450,
                proteinG: 70,
                carbsG: 52,
                fatG: 16,
              ),
            ),
          ],
        ),
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.camera);
    expect(find.text('70 g'), findsOneWidget); // the wrong protein

    // Open the editor and correct protein to a realistic 25 g.
    await tester.tap(find.byKey(const Key('review-edit-Chicken Biryani')));
    await _settle(tester);
    expect(find.text('Edit food'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Protein'), '25');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    // Card and totals reflect the correction.
    expect(find.text('70 g'), findsNothing);
    expect(find.text('25 g'), findsOneWidget);
    expect(find.text('Protein 25 g · Carbs 52 g · Fat 16 g'), findsOneWidget);

    await tester.tap(find.text('Add 1 to Lunch'));
    await _settle(tester);
    final entries = _todaysEntries(tester);
    expect(entries.single.perServing.proteinG, 25);
  });

  testWidgets('the demo analyzer shows a demo banner in review', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      testApp(
        home: const HomeShell(),
        photoSource: FakePhotoSource(
          photo: CapturedPhoto(bytes: kTinyPng, mimeType: 'image/png'),
        ),
        foodAnalyzer: FakeFoodAnalyzer(isDemo: true),
      ),
    );
    await _settle(tester);
    await _snap(tester, PhotoOrigin.camera);
    expect(find.textContaining('Demo results'), findsOneWidget);
  });
}
