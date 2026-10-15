import '../../log/domain/nutrition.dart';

/// One food the analyzer found in a photo, with an estimated portion and its
/// nutrition for that portion.
class DetectedFood {
  const DetectedFood({
    required this.name,
    required this.servingLabel,
    required this.gramsPerServing,
    this.servings = 1,
    required this.perServing,
    this.confidence,
    this.notes,
    this.brand,
    this.barcode,
  });

  final String name;

  /// The maker, e.g. "Nutella". Null for an unbranded or cooked item.
  final String? brand;

  /// The scanned product code, set only when this came from a barcode scan.
  final String? barcode;

  /// Human description of one serving, e.g. "1 bowl" or "2 rotis".
  final String servingLabel;

  /// Weight of one serving in grams; used when the portion is rescaled.
  final double gramsPerServing;

  /// How many servings the analyzer estimated are on the plate.
  final double servings;

  /// Nutrition for a single serving.
  final Nutrition perServing;

  /// 0..1, if the analyzer reported how sure it was.
  final double? confidence;

  /// A short note on notable micronutrients or health facts, e.g.
  /// "High in calcium and vitamin B12". Null when the analyzer gave none.
  final String? notes;

  Nutrition get total => perServing * servings;

  DetectedFood copyWith({
    String? name,
    String? servingLabel,
    double? gramsPerServing,
    double? servings,
    Nutrition? perServing,
  }) => DetectedFood(
    name: name ?? this.name,
    servingLabel: servingLabel ?? this.servingLabel,
    gramsPerServing: gramsPerServing ?? this.gramsPerServing,
    servings: servings ?? this.servings,
    perServing: perServing ?? this.perServing,
    confidence: confidence,
    notes: notes,
    brand: brand,
    barcode: barcode,
  );

  factory DetectedFood.fromJson(Map<String, Object?> json) {
    double toNum(Object? v) => (v as num?)?.toDouble() ?? 0;
    final grams = toNum(json['gramsPerServing']);
    return DetectedFood(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Food',
      servingLabel: (json['servingLabel'] as String?)?.trim().isNotEmpty == true
          ? (json['servingLabel'] as String).trim()
          : '1 serving',
      gramsPerServing: grams > 0 ? grams : 100,
      servings: toNum(json['servings']) > 0 ? toNum(json['servings']) : 1,
      perServing: Nutrition(
        calories: toNum(json['calories']),
        proteinG: toNum(json['proteinG']),
        carbsG: toNum(json['carbsG']),
        fatG: toNum(json['fatG']),
        sugarG: toNum(json['sugarG']),
        fiberG: toNum(json['fiberG']),
        sodiumMg: toNum(json['sodiumMg']),
      ),
      confidence: json['confidence'] == null ? null : toNum(json['confidence']),
      notes: (json['notes'] as String?)?.trim().isNotEmpty == true
          ? (json['notes'] as String).trim()
          : null,
      brand: (json['brand'] as String?)?.trim().isNotEmpty == true
          ? (json['brand'] as String).trim()
          : null,
      barcode: (json['barcode'] as String?)?.trim().isNotEmpty == true
          ? (json['barcode'] as String).trim()
          : null,
    );
  }

  @override
  String toString() => 'DetectedFood($name, x$servings)';
}
