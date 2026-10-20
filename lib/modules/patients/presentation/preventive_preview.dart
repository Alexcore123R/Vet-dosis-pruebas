import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../domain/preventive_repository.dart';

class PreventivePreview extends StatefulWidget {
  const PreventivePreview({
    super.key,
    required this.load,
    this.shareable = false,
  });
  final Future<Uint8List> Function() load;
  final bool shareable;
  @override
  State<PreventivePreview> createState() => _PreventivePreviewState();
}

class _PreventivePreviewState extends State<PreventivePreview>
    with WidgetsBindingObserver {
  Uint8List? bytes;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    generation++;
    bytes = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
    } else {
      generation++;
      if (mounted) setState(() => bytes = null);
    }
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      bytes = null;
      error = null;
    });
    try {
      final next = await widget.load();
      if (mounted && request == generation) setState(() => bytes = next);
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'No se pudo abrir. Actualiza los permisos o vuelve a intentarlo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = bytes;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.shareable ? 'Carnet para compartir' : 'Comprobante privado',
        ),
      ),
      body: error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('Reintentar')),
                ],
              ),
            )
          : content == null
          ? const Center(child: CircularProgressIndicator())
          : widget.shareable || evidenceMime(content) == 'application/pdf'
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.shareable
                        ? 'Revisa esta copia antes de compartir o imprimir. No incluye notas internas ni comprobantes originales.'
                        : 'Archivo adjunto como referencia. No se acredita su autenticidad ni una aplicación en esta clínica.',
                  ),
                ),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => content,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    allowSharing: widget.shareable,
                    allowPrinting: widget.shareable,
                    pdfFileName: 'VetDosis-carnet.pdf',
                  ),
                ),
              ],
            )
          : InteractiveViewer(
              child: Center(
                child: Image.memory(
                  content,
                  cacheWidth: 1600,
                  errorBuilder: (_, _, _) =>
                      const Text('No se pudo mostrar la imagen.'),
                ),
              ),
            ),
    );
  }
}
