import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../capture/domain/detected_food.dart';
import '../../log/domain/nutrition.dart';
import '../domain/barcode_lookup.dart';

/// Looks a barcode up in Open Food Facts — a free, keyless product database.
/// Nutrition is reported per declared serving when the product has one,
/// otherwise per 100 g/ml.
class OpenFoodFactsLookup implements BarcodeLookup {
  OpenFoodFactsLookup({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String _base = 'https://world.openfoodfacts.org/api/v2/product';
  static const String _fields =
      'product_name,product_name_en,brands,serving_size,'
      'serving_quantity,nutriments';

  @override
  Future<DetectedFood?> lookup(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final uri = Uri.parse('$_base/$code.json?fields=$_fields');

    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            // Open Food Facts asks callers to identify themselves.
            headers: const {'User-Agent': 'FoodGuruji/1.0 (Flutter app)'},
          )
          .timeout(timeout);
    } on Object {
      throw const BarcodeException(
        "Couldn't reach the product database. Check your connection.",
      );
    }

    if (response.statusCode != 200) {
      throw BarcodeException(
        'The product database had a problem (${response.statusCode}).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on Object {
      throw const BarcodeException('The product database sent bad data.');
    }
    if (decoded is! Map) return null;
    // status 1 = found, 0 = unknown product.
    if (decoded['status'] != 1 || decoded['product'] is! Map) return null;

    return _fromProduct(
      (decoded['product'] as Map).cast<String, Object?>(),
      code,
    );
  }

  DetectedFood? _fromProduct(Map<String, Object?> product, String code) {
    final name = _name(product);
    final n = (product['nutriments'] as Map?)?.cast<String, Object?>() ?? {};

    // Prefer the declared serving; fall back to per 100 g/ml.
    final servingGrams = _toDouble(product['serving_quantity']);
    final hasServing = servingGrams != null && servingGrams > 0;
    final suffix = hasServing && n.containsKey('energy-kcal_serving')
        ? '_serving'
        : '_100g';

    double v(String key) => _toDouble(n['$key$suffix']) ?? 0;

    final energy = n.containsKey('energy-kcal$suffix')
        ? v('energy-kcal')
        // Some products list only kJ; convert (1 kcal = 4.184 kJ).
        : v('energy') / 4.184;

    // Open Food Facts reports sodium in grams.
    final sodiumG = _toDouble(n['sodium$suffix']);
    final saltG = _toDouble(n['salt$suffix']);
    final sodiumMg = (sodiumG ?? (saltG != null ? saltG * 0.4 : 0)) * 1000;

    final nutrition = Nutrition(
      calories: energy,
      proteinG: v('proteins'),
      carbsG: v('carbohydrates'),
      fatG: v('fat'),
      sugarG: v('sugars'),
      fiberG: v('fiber'),
      sodiumMg: sodiumMg,
    );

    // Nothing useful to log if every number is zero.
    if (nutrition.calories == 0 &&
        nutrition.proteinG == 0 &&
        nutrition.carbsG == 0 &&
        nutrition.fatG == 0) {
      return null;
    }

    final double grams = (servingGrams != null && servingGrams > 0)
        ? servingGrams
        : 100;
    final label = hasServing
        ? _servingLabel(product['serving_size'], grams)
        : 'per 100 g';

    return DetectedFood(
      name: name,
      servingLabel: label,
      gramsPerServing: grams,
      perServing: nutrition,
      confidence: 1,
      brand: _brand(product),
      barcode: code,
    );
  }

  String _name(Map<String, Object?> product) {
    String clean(Object? v) => (v as String?)?.trim() ?? '';
    final name = clean(product['product_name_en']).isNotEmpty
        ? clean(product['product_name_en'])
        : clean(product['product_name']);
    final brand = _brand(product) ?? '';
    if (name.isEmpty) return brand.isEmpty ? 'Packaged product' : brand;
    // Prefix the brand unless the name already carries it.
    if (brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())) {
      return '$brand $name';
    }
    return name;
  }

  String? _brand(Map<String, Object?> product) {
    final raw = (product['brands'] as String?)?.split(',').first.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  String _servingLabel(Object? servingSize, double grams) {
    final size = (servingSize as String?)?.trim() ?? '';
    if (size.isNotEmpty) return size;
    return '1 serving (${grams.round()} g)';
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  void dispose() => _client.close();
}
