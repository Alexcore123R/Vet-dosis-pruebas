import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});
  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final controller = MobileScannerController();
  bool returned = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear código de barras')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'El código identifica un producto; no verifica fármaco, concentración ni dosis. También puedes escribirlo en inventario.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (returned) return;
              final values = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .where((v) => v.trim().isNotEmpty)
                  .toList();
              if (values.isEmpty) return;
              returned = true;
              Navigator.pop(context, values.first);
            },
            errorBuilder: (context, error) => const Center(
              child: Text(
                'No se pudo abrir la cámara. Revisa permisos o escribe el código manualmente.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
