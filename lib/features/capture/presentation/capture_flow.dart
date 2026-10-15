import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/loaders/pan_loader.dart';
import '../../../core/widgets/surfaces.dart';
import '../../barcode/application/barcode_providers.dart';
import '../../barcode/presentation/barcode_scan_page.dart';
import '../application/capture_providers.dart';
import '../data/photo_source.dart';
import '../domain/detected_food.dart';
import 'review_page.dart';

/// What the user picked from the Snap sheet.
enum _SnapChoice { camera, gallery, barcode }

/// Runs the Snap flow: pick a source, analyze (photo) or look up (barcode),
/// then open the review screen. Call [start] from the Snap button.
abstract final class CaptureFlow {
  static Future<void> start(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_SnapChoice>(
      context: context,
      builder: (_) => const _SourceSheet(),
    );
    if (choice == null || !context.mounted) return;

    if (choice == _SnapChoice.barcode) {
      await _scanBarcode(context, ref);
      return;
    }

    final origin = choice == _SnapChoice.camera
        ? PhotoOrigin.camera
        : PhotoOrigin.gallery;

    final CapturedPhoto? photo;
    try {
      photo = await ref.read(photoSourceProvider).pick(origin);
    } on Object {
      if (context.mounted) _toast(context, "Couldn't open the camera.");
      return;
    }
    if (photo == null || !context.mounted) return;

    // Analyze behind a blocking loader, then hand off to the review screen.
    final analyzer = ref.read(foodAnalyzerProvider);
    final result = await showDialog<List<DetectedFood>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnalyzingDialog(
        run: () => analyzer.analyze(photo!.bytes, photo.mimeType),
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.isEmpty) {
      _toast(context, 'No food found in that photo. Try another shot.');
      return;
    }
    await Navigator.of(context).push(
      ReviewPage.route(
        photoBytes: photo.bytes,
        foods: result,
        isDemo: analyzer.isDemo,
      ),
    );
  }

  /// Scans a barcode, looks the product up, then opens the review screen.
  static Future<void> _scanBarcode(BuildContext context, WidgetRef ref) async {
    final code = await Navigator.of(context).push(BarcodeScanPage.route());
    if (code == null || code.isEmpty || !context.mounted) return;

    final lookup = ref.read(barcodeLookupProvider);
    final result = await showDialog<List<DetectedFood>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnalyzingDialog(
        title: 'Looking up the product…',
        subtitle: 'Finding it in the food database.',
        run: () async {
          final food = await lookup.lookup(code);
          return food == null ? <DetectedFood>[] : [food];
        },
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.isEmpty) {
      _toast(context, "No product found for barcode $code.");
      return;
    }
    await Navigator.of(context)
        .push(ReviewPage.route(foods: result, isDemo: false));
  }

  static void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add food', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Snap a meal, pick a photo, or scan a product barcode.',
              style: text.bodyMedium?.copyWith(
                color: AppPalette.of(context).muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    onTap: () => Navigator.of(context).pop(_SnapChoice.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () => Navigator.of(context).pop(_SnapChoice.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SourceButton(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan barcode',
              compact: true,
              onTap: () => Navigator.of(context).pop(_SnapChoice.barcode),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A short, full-width row instead of a tall tile.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final title = Theme.of(context).textTheme.titleSmall;
    return AppCard(
      key: Key('snap-source-$label'),
      margin: EdgeInsets.zero,
      color: palette.cardMuted,
      elevated: false,
      onTap: onTap,
      padding: compact
          ? const EdgeInsets.symmetric(vertical: 16)
          : const EdgeInsets.symmetric(vertical: 22),
      child: compact
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: primary),
                const SizedBox(width: 10),
                Text(label, style: title),
              ],
            )
          : Column(
              children: [
                Icon(icon, size: 30, color: primary),
                const SizedBox(height: 8),
                Text(label, style: title),
              ],
            ),
    );
  }
}

/// Runs the analysis once and pops with the result, or pops null after
/// showing the error.
class _AnalyzingDialog extends StatefulWidget {
  const _AnalyzingDialog({
    required this.run,
    this.title = 'Analyzing your food…',
    this.subtitle = 'Spotting each item and its nutrition.',
  });

  final Future<List<DetectedFood>> Function() run;
  final String title;
  final String subtitle;

  @override
  State<_AnalyzingDialog> createState() => _AnalyzingDialogState();
}

class _AnalyzingDialogState extends State<_AnalyzingDialog> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    // Guard setState: the first call comes from initState, before the first
    // build, where a plain assignment is correct; the retry button is safe.
    if (_error != null) setState(() => _error = null);
    try {
      final foods = await widget.run();
      if (mounted) Navigator.of(context).pop(foods);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = AppPalette.of(context);
    final error = _error;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: error == null
              ? [
                  const PanLoader(size: 120),
                  const SizedBox(height: 8),
                  Text(widget.title, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: palette.muted),
                  ),
                ]
              : [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: palette.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _analyze,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ],
        ),
      ),
    );
  }
}
