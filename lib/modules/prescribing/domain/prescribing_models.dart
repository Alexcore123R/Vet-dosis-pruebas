import '../../doses/domain/quantity.dart';

const medicationUnits = {'ml', 'mg', 'g', 'tableta', 'capsula'};
String exactMedicationQuantity(String raw) {
  final value = raw.trim().replaceAll(',', '.');
  if (!Quantity.parse(value).positive) {
    throw const FormatException('La cantidad debe ser mayor que cero.');
  }
  return value;
}

String csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^[\s]*[=+\-@]').hasMatch(text) ||
      text.startsWith('\t') ||
      text.startsWith('\r')) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

String reportCsv(Map<String, dynamic> report) {
  final entries = (report['snapshot']['entries'] as List).cast<Map>();
  final rows = <List<Object?>>[
    [
      'VetDosis Pro',
      report['official'] == true
          ? 'Formato verificado'
          : 'REFERENCIA · NO OFICIAL',
      report['complete'] == true ? 'Completo al corte' : 'INCOMPLETO',
    ],
    [
      'Inicio UTC',
      report['starts_at'],
      'Fin UTC excluyente',
      report['ends_at'],
      'Corte servidor',
      report['cutoff'],
    ],
    ['Pendientes', ...(report['pending_ids'] as List)],
    [
      'Paciente',
      'Producto',
      'Presentación',
      'Lote',
      'Cantidad',
      'Unidad',
      'Vía',
      'Aplicó',
      'Reportó',
      'Validó',
      'Hora observada',
      'Hora validación',
      'Folio capturado',
    ],
    for (final e in entries)
      [
        e['patient_name'],
        e['name'],
        e['presentation'],
        e['lot'],
        e['quantity'],
        e['unit'],
        e['route'],
        e['performed_by'],
        e['reported_by'],
        e['validated_by'],
        e['observed_at'],
        e['validated_at'],
        e['official_folio'],
      ],
  ];
  return '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

String medicationState(Map<String, dynamic> r) {
  if (r['superseded'] == true) return 'Sustituida por corrección';
  if ((r['incidence'] as String? ?? '').isNotEmpty) {
    return 'Incidencia · requiere revisión';
  }
  return r['review']?['decision'] == 'validada'
      ? 'Validada por el MVZ'
      : r['review']?['decision'] == 'requiere_correccion'
      ? 'Requiere corrección'
      : 'Reportada, pendiente de validación del MVZ';
}
