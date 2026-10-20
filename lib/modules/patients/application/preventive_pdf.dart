import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/patient_models.dart';
import '../domain/patient_timeline.dart';
import '../domain/clinical_record_fields.dart';

/// Deliberate allowlist: no clinical notes, contacts, staff IDs or original evidence.
List<String> bookletShareLines(Map<String, dynamic> data) {
  final events = (data['events'] as List)
      .map((e) => PatientEvent.read(Map<String, dynamic>.from(e as Map)))
      .toList();
  final retired = (data['retired'] as List).toSet();
  return [
    'Paciente: ${data['patient_name']} · Especie: ${data['species']}',
    'Copia de consulta. Los antecedentes no acreditan un esquema completo. No sustituye un certificado firmado.',
    for (final e in patientTimeline(events, kind: EventKind.preventive)) ...[
      '${e.data['type']} · ${e.data['coverage'] ?? e.data['product'] ?? 'Cobertura no especificada'}',
      '${preventiveDateLabel(e.data)} · ${preventiveOriginLabel(e.data)}',
      if ('${e.data['batch'] ?? ''}'.isNotEmpty)
        'Lote registrado: ${e.data['batch']}',
    ],
    'Próximas fechas confirmadas por un veterinario en la aplicación:',
    for (final p in data['plans'] as List)
      if (!retired.contains(p['id']))
        '${p['due_date']} · ${p['type']} · ${p['coverage']}',
    'Una fecha indicada no equivale a una cita confirmada ni a una aplicación realizada. Consulta al equipo para revisar el plan vigente.',
  ];
}

Future<Uint8List> preventivePdf(
  Map<String, dynamic> data,
  String clinic,
) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
  );
  final document = pw.Document(
    title: 'Carnet preventivo · copia de consulta',
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  document.addPage(
    pw.MultiPage(
      maxPages: 500,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(clinic),
          pw.Text('Carnet de vacunación y desparasitación'),
          pw.Divider(),
        ],
      ),
      footer: (c) => pw.Text('VetDosis Pro · ${c.pageNumber}/${c.pagesCount}'),
      build: (_) => [
        for (final line in bookletShareLines(data))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(line),
          ),
      ],
    ),
  );
  return document.save();
}
