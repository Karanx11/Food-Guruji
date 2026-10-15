import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_food_facts_lookup.dart';
import '../domain/barcode_lookup.dart';

/// Where barcodes are resolved to products. Tests override this.
final barcodeLookupProvider = Provider<BarcodeLookup>((ref) {
  final lookup = OpenFoodFactsLookup();
  ref.onDispose(lookup.dispose);
  return lookup;
});

/// Whether to mount the live camera scanner. Tests turn this off so the scan
/// screen shows only its manual-entry field, with no platform camera.
final barcodeCameraEnabledProvider = Provider<bool>((_) => true);
