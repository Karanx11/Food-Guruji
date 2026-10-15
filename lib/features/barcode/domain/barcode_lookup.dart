import '../../capture/domain/detected_food.dart';

/// A readable failure the barcode flow can show the user.
class BarcodeException implements Exception {
  const BarcodeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns a scanned barcode into a food, looking the product up in a database.
/// Returns null when no product matches the code; throws [BarcodeException]
/// when the lookup itself fails (offline, server error).
abstract interface class BarcodeLookup {
  Future<DetectedFood?> lookup(String barcode);
}

/// A fixed map of barcode → food. Used in tests.
class InMemoryBarcodeLookup implements BarcodeLookup {
  InMemoryBarcodeLookup([this.products = const {}]);

  final Map<String, DetectedFood> products;

  @override
  Future<DetectedFood?> lookup(String barcode) async =>
      products[barcode.trim()];
}
