import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/widgets/surfaces.dart';
import '../../../core/widgets/top_bar.dart';
import '../application/barcode_providers.dart';

/// Scans a product barcode with the camera, or lets the user type it in.
/// Pops the barcode string, or null if the screen was dismissed.
class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key});

  static Route<String> route() =>
      MaterialPageRoute<String>(builder: (_) => const BarcodeScanPage());

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage> {
  final _manual = TextEditingController();
  MobileScannerController? _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(barcodeCameraEnabledProvider)) {
      _controller = MobileScannerController(
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
      );
    }
  }

  @override
  void dispose() {
    _manual.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _submit(String? code) {
    final value = code?.trim() ?? '';
    if (_handled || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = AppPalette.of(context);
    final controller = _controller;

    return Scaffold(
      appBar: appTopBar(context, title: 'Scan barcode'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (controller != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => _CameraUnavailable(
                        message: switch (error.errorCode) {
                          MobileScannerErrorCode.permissionDenied =>
                            'Camera access was denied. Enter the number below.',
                          _ =>
                            "Camera isn't available. Enter the number below.",
                        },
                      ),
                    ),
                    const IgnorePointer(child: _ScanFrame()),
                  ],
                ),
              ),
            ),
          if (controller != null) const SizedBox(height: 12),
          Text(
            controller != null
                ? 'Point the camera at the product barcode.'
                : 'Enter the barcode number from the product.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: palette.muted),
          ),
          const SizedBox(height: 20),
          Text('Or type the barcode', style: text.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _manual,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'e.g. 5449000000996',
              prefixIcon: Icon(Icons.numbers_rounded),
            ),
            onSubmitted: _submit,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _submit(_manual.text),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Look up product'),
          ),
        ],
      ),
    );
  }
}

/// A translucent frame drawn over the camera to aim the barcode.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.7,
        heightFactor: 0.4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_rounded,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
