import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../identity/domain/identity_repository.dart';
import '../domain/branded_export.dart';

Future<Uint8List> brandedPdf(
  ExportBranding brand,
  String title,
  List<List<String>> rows,
) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
  );
  final pdf = pw.Document(
    title: title,
    author: brand.name,
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  pw.ImageProvider? logo;
  if (brand.logo != null) {
    try {
      final memory = pw.MemoryImage(brand.logo!);
      if ((memory.width ?? 0) * (memory.height ?? 0) <= 4000000) logo = memory;
    } catch (_) {}
  }
  // Keep wide source tables readable by grouping each record into column blocks.
  const blockSize = 6;
  final count = rows.fold<int>(
    0,
    (max, row) => row.length > max ? row.length : max,
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 1000,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  brand.name,
                  style: const pw.TextStyle(fontSize: 14),
                ),
              ),
              if (logo != null)
                pw.Image(logo, width: 90, height: 45, fit: pw.BoxFit.contain),
            ],
          ),
          if (brand.header.isNotEmpty)
            pw.Text(brand.header, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(title, style: const pw.TextStyle(fontSize: 11)),
          pw.Divider(),
        ],
      ),
      footer: (context) => pw.Text(
        'VetDosis Pro · Exportación de consulta · ${context.pageNumber}/${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8),
      ),
      build: (_) => [
        for (var start = 0; start < count; start += blockSize) ...[
          if (count > blockSize)
            pw.Text(
              'Columnas ${start + 1} a ${(start + blockSize).clamp(0, count)} · mismo orden de registros',
            ),
          pw.TableHelper.fromTextArray(
            headerCount: 0,
            cellStyle: const pw.TextStyle(fontSize: 7),
            data: [
              for (final row in rows)
                [
                  for (
                    var c = start;
                    c < (start + blockSize).clamp(0, count);
                    c++
                  )
                    c < row.length ? row[c] : '',
                ],
            ],
          ),
          pw.SizedBox(height: 12),
        ],
      ],
    ),
  );
  return pdf.save();
}

/// Requires a successful identity read; never silently exports another brand or no logo on failure.
class BrandedExportAction extends StatefulWidget {
  const BrandedExportAction({
    super.key,
    required this.repository,
    required this.clinicId,
    required this.clinicName,
    required this.title,
    required this.fileName,
    required this.rows,
  });
  final IdentityRepository? repository;
  final String clinicId, clinicName, title, fileName;
  final Future<List<List<String>>> Function() rows;
  @override
  State<BrandedExportAction> createState() => _BrandedExportActionState();
}

class _BrandedExportActionState extends State<BrandedExportAction> {
  bool busy = false;
  Future<void> export(String format) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final request = widget;
      final id = request.clinicId;
      final rows = await request.rows();
      final branding = await request.repository!.clinic(id);
      if (!mounted ||
          id != widget.clinicId ||
          request.fileName != widget.fileName) {
        return;
      }
      final brand = ExportBranding.fromMap(request.clinicName, branding);
      final bytes = format == 'xlsx'
          ? brandedXlsx(brand, request.title, rows)
          : await brandedPdf(brand, request.title, rows);
      if (!mounted ||
          id != widget.clinicId ||
          request.fileName != widget.fileName) {
        return;
      }
      await FilePicker.saveFile(
        fileName: '${request.fileName}.$format',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [format],
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo exportar. Revisa conexión, acceso al membrete y tamaño del reporte.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final format in ['pdf', 'xlsx'])
        TextButton.icon(
          onPressed: busy || widget.repository == null
              ? null
              : () => export(format),
          icon: Icon(
            format == 'pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.table_chart_outlined,
          ),
          label: Text('Exportar ${format.toUpperCase()} con membrete'),
        ),
      if (busy)
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );
}
