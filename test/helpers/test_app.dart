import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_guruji/app/app.dart';
import 'package:food_guruji/app/theme.dart';
import 'package:food_guruji/app/theme_mode.dart';
import 'package:food_guruji/core/db/app_database.dart';
import 'package:food_guruji/features/auth/application/auth_providers.dart';
import 'package:food_guruji/features/auth/data/auth_repository.dart';
import 'package:food_guruji/features/auth/domain/account.dart';
import 'package:food_guruji/features/barcode/application/barcode_providers.dart';
import 'package:food_guruji/features/barcode/domain/barcode_lookup.dart';
import 'package:food_guruji/features/capture/application/capture_providers.dart';
import 'package:food_guruji/features/capture/data/photo_source.dart';
import 'package:food_guruji/features/capture/domain/food_analyzer.dart';
import 'package:food_guruji/features/food_search/application/catalog_providers.dart';
import 'package:food_guruji/features/food_search/data/food_catalog_repository.dart';
import 'package:food_guruji/features/food_search/domain/food_item.dart';
import 'package:food_guruji/features/log/application/log_providers.dart';
import 'package:food_guruji/features/log/domain/nutrition.dart';
import 'package:food_guruji/features/profile/application/profile_providers.dart';
import 'package:food_guruji/features/profile/data/profile_repository.dart';
import 'package:sembast/sembast_memory.dart';

/// Fixed "now" for tests: a Tuesday at 1 pm, so the default meal is lunch.
final testNow = DateTime(2026, 9, 22, 13);

/// A signed-in account for tests. Hashes are placeholders; tests that log in
/// build their own account.
const testAccount = Account(
  email: 'karan@foodbaba.test',
  passwordHash: 'x',
  securityQuestion: 'What is your favourite food?',
  securityAnswerHash: 'x',
);

/// A fresh in-memory database config, isolated per call.
DatabaseConfig memoryDatabase() => DatabaseConfig(
  factory: newDatabaseFactoryMemory(),
  path: () async => 'test.db',
);

/// Small catalog for widget tests, so they never load the bundled asset.
const testCatalog = <FoodItem>[
  FoodItem(
    id: 'white-rice',
    name: 'White rice (cooked)',
    aliases: ['chawal'],
    category: 'Rice & grains',
    per100g: Nutrition(calories: 130, proteinG: 2.7, carbsG: 28.2, fatG: 0.3),
    servings: [
      ServingOption(label: '1 katori', grams: 150),
      ServingOption(label: '1 cup', grams: 158),
      ServingOption.hundredGrams,
    ],
  ),
  FoodItem(
    id: 'roti',
    name: 'Roti / chapati',
    aliases: ['chapati', 'phulka'],
    category: 'Breads',
    per100g: Nutrition(calories: 300, proteinG: 9, carbsG: 47, fatG: 8),
    servings: [
      ServingOption(label: '1 roti', grams: 40),
      ServingOption.hundredGrams,
    ],
  ),
  FoodItem(
    id: 'banana',
    name: 'Banana',
    aliases: ['kela'],
    category: 'Fruits',
    per100g: Nutrition(calories: 89, proteinG: 1.1, carbsG: 22.8, fatG: 0.3),
    servings: [
      ServingOption(label: '1 medium', grams: 118),
      ServingOption.hundredGrams,
    ],
  ),
];

/// Wraps [home] (or the full app when null) in a ProviderScope backed by
/// in-memory stores, a fixed clock and [catalog], so tests never touch the
/// platform.
Widget testApp({
  Widget? home,
  ProfileRepository? repository,
  DatabaseConfig? database,
  DateTime Function()? clock,
  List<FoodItem> catalog = testCatalog,
  ThemeModeStore? themeStore,
  ThemeMode initialThemeMode = ThemeMode.system,
  PhotoSource? photoSource,
  FoodAnalyzer? foodAnalyzer,
  AuthRepository? authRepository,
  BarcodeLookup? barcodeLookup,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        authRepository ??
            InMemoryAuthRepository(account: testAccount, signedIn: true),
      ),
      profileRepositoryProvider.overrideWithValue(
        repository ?? InMemoryProfileRepository(),
      ),
      databaseConfigProvider.overrideWithValue(database ?? memoryDatabase()),
      clockProvider.overrideWithValue(clock ?? () => testNow),
      foodCatalogRepositoryProvider.overrideWithValue(
        InMemoryFoodCatalogRepository(catalog),
      ),
      themeModeStoreProvider.overrideWithValue(
        themeStore ?? InMemoryThemeModeStore(),
      ),
      initialThemeModeProvider.overrideWithValue(initialThemeMode),
      if (photoSource != null)
        photoSourceProvider.overrideWithValue(photoSource),
      if (foodAnalyzer != null)
        foodAnalyzerProvider.overrideWithValue(foodAnalyzer),
      // Keep tests off the platform camera and the network.
      barcodeCameraEnabledProvider.overrideWithValue(false),
      if (barcodeLookup != null)
        barcodeLookupProvider.overrideWithValue(barcodeLookup),
    ],
    child: home == null ? const FoodBabaApp() : _TestApp(home: home),
  );
}

/// Like the real app shell, including the light/dark switch.
class _TestApp extends ConsumerWidget {
  const _TestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    home: home,
  );
}
