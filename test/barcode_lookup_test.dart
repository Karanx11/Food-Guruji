import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_guruji/features/barcode/data/open_food_facts_lookup.dart';
import 'package:food_guruji/features/barcode/domain/barcode_lookup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

OpenFoodFactsLookup _lookupReturning(Object body, {int status = 200}) {
  final client = MockClient(
    (req) async =>
        http.Response(body is String ? body : jsonEncode(body), status),
  );
  return OpenFoodFactsLookup(client: client);
}

void main() {
  group('OpenFoodFactsLookup', () {
    test('reads per-serving nutrition from a found product', () async {
      final food = await _lookupReturning({
        'status': 1,
        'product': {
          'product_name': 'Coca-Cola',
          'brands': 'Coca-Cola',
          'serving_size': '330 ml',
          'serving_quantity': 330,
          'nutriments': {
            'energy-kcal_serving': 139,
            'proteins_serving': 0,
            'carbohydrates_serving': 35,
            'fat_serving': 0,
            'sugars_serving': 35,
            'sodium_serving': 0,
          },
        },
      }).lookup('5449000000996');

      expect(food, isNotNull);
      expect(food!.name, 'Coca-Cola');
      expect(food.brand, 'Coca-Cola');
      expect(food.barcode, '5449000000996');
      expect(food.servingLabel, '330 ml');
      expect(food.gramsPerServing, 330);
      expect(food.perServing.calories, 139);
      expect(food.perServing.carbsG, 35);
      expect(food.perServing.sugarG, 35);
    });

    test('prefixes the brand when the name omits it', () async {
      final food = await _lookupReturning({
        'status': 1,
        'product': {
          'product_name': 'Hazelnut Spread',
          'brands': 'Nutella, Ferrero',
          'serving_quantity': 15,
          'nutriments': {
            'energy-kcal_serving': 81,
            'proteins_serving': 0.9,
            'carbohydrates_serving': 8.6,
            'fat_serving': 4.6,
          },
        },
      }).lookup('3017620422003');

      expect(food!.name, 'Nutella Hazelnut Spread');
      expect(food.brand, 'Nutella');
    });

    test('shortens a legal brand to the common name', () async {
      Future<String?> brandFor(String brands) async => (await _lookupReturning({
        'status': 1,
        'product': {
          'product_name': 'Soda',
          'brands': brands,
          'nutriments': {'energy-kcal_100g': 42},
        },
      }).lookup('1'))!.brand;

      expect(await brandFor('COCA-COLA SERVICES SA/NV'), 'Coca-Cola');
      expect(await brandFor('Amul (GCMMF) Ltd'), 'Amul');
      expect(await brandFor('The Nestlé Company'), 'Nestlé');
      expect(await brandFor('KFC'), 'KFC'); // short acronym kept
    });

    test('falls back to per 100 g and converts sodium to mg', () async {
      final food = await _lookupReturning({
        'status': 1,
        'product': {
          'product_name': 'Oats',
          'nutriments': {
            'energy-kcal_100g': 389,
            'proteins_100g': 16.9,
            'carbohydrates_100g': 66,
            'fat_100g': 6.9,
            'sodium_100g': 0.1, // grams
          },
        },
      }).lookup('123');

      expect(food!.servingLabel, 'per 100 g');
      expect(food.gramsPerServing, 100);
      expect(food.perServing.calories, 389);
      expect(food.perServing.sodiumMg, closeTo(100, 0.001));
    });

    test('returns null for an unknown product', () async {
      final food = await _lookupReturning({'status': 0}).lookup('000');
      expect(food, isNull);
    });

    test('returns null when the product has no nutrition', () async {
      final food = await _lookupReturning({
        'status': 1,
        'product': {'product_name': 'Mystery', 'nutriments': {}},
      }).lookup('111');
      expect(food, isNull);
    });

    test('throws a readable error on a server failure', () async {
      await expectLater(
        _lookupReturning('oops', status: 500).lookup('222'),
        throwsA(isA<BarcodeException>()),
      );
    });
  });

  group('InMemoryBarcodeLookup', () {
    test('returns the mapped product, trimming the code', () async {
      final cola = (await _lookupReturning({
        'status': 1,
        'product': {
          'product_name': 'Cola',
          'serving_quantity': 330,
          'nutriments': {
            'energy-kcal_serving': 139,
            'carbohydrates_serving': 35,
          },
        },
      }).lookup('999'))!;
      final lookup = InMemoryBarcodeLookup({'999': cola});
      expect((await lookup.lookup('  999 '))!.name, 'Cola');
      expect(await lookup.lookup('nope'), isNull);
    });
  });
}
