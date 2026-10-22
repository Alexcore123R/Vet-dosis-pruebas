import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../domain/form_models.dart';

class FormPdfScreen extends StatefulWidget {
  const FormPdfScreen({
    super.key,
    required this.pdf,
    required this.title,
    this.confirm,
    this.signed = false,
    this.actionLabel = 'Confirmar y conservar PDF firmado',
    this.confirmLabel =
        'El tutor y el MVZ revisaron este PDF completo y confirman el contenido y sus firmas.',
  });
  final ReviewedPdf pdf;
  final String title;
  final Future<void> Function()? confirm;
  final bool signed;
  final String confirmLabel;
  final String actionLabel;
  @override
  State<FormPdfScreen> createState() => _FormPdfScreenState();
}

class _FormPdfScreenState extends State<FormPdfScreen> {
  bool accepted = false, busy = false;
  String? error;
  Future<void> confirm() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.confirm!();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se confirmó la firma. Actualiza el documento antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.signed
                ? 'Firmado · Archivo original conservado'
                : 'Vista previa · Este archivo exacto se conservará al confirmar.',
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) async => widget.pdf.bytes,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: widget.signed,
            allowSharing: widget.signed,
            pdfFileName: 'VetDosis-documento.pdf',
          ),
        ),
        if (widget.signed)
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => Printing.sharePdf(
                bytes: widget.pdf.bytes,
                filename: 'VetDosis-documento.pdf',
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Enviar PDF por correo o WhatsApp'),
            ),
          )),
        if (widget.confirm != null) ...[
          CheckboxListTile(
            value: accepted,
            onChanged: busy
                ? null
                : (v) => setState(() => accepted = v ?? false),
            title: Text(widget.confirmLabel),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: accepted && !busy ? confirm : null,
                child: Text(busy ? 'Confirmando…' : widget.actionLabel),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
