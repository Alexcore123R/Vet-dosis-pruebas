import '../domain/patient_timeline.dart';
import 'package:flutter/material.dart';
import '../domain/patient_models.dart';
import '../domain/clinical_record_fields.dart';

class PreventiveBooklet extends StatelessWidget {
  const PreventiveBooklet({super.key, required this.events});
  final List<PatientEvent> events;

  @override
  Widget build(BuildContext context) {
    final preventive = patientTimeline(events, kind: EventKind.preventive);
    final upcoming =
        preventive.where((e) => e.data['next_date'] != null).toList()..sort(
          (a, b) =>
              '${a.data['next_date']}'.compareTo('${b.data['next_date']}'),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Carnet de vacunación y desparasitación',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Las entradas externas y referidas son antecedentes; no acreditan una aplicación en esta clínica ni un esquema completo.',
        ),
        for (final type in ['vacuna', 'desparasitación'])
          ExpansionTile(
            title: Text(type == 'vacuna' ? 'Vacunas' : 'Desparasitaciones'),
            children: [
              if (!preventive.any((e) => e.data['type'] == type))
                const ListTile(
                  title: Text(
                    'Sin registros. No significa que no haya recibido aplicaciones.',
                  ),
                ),
              for (final event in preventive.where(
                (e) => e.data['type'] == type,
              ))
                ListTile(
                  title: Text(
                    (event.data['coverage'] as String?)?.isNotEmpty == true
                        ? event.data['coverage'] as String
                        : event.data['product'] as String? ??
                              'Producto desconocido',
                  ),
                  subtitle: Text(
                    [
                      preventiveOriginLabel(event.data),
                      preventiveDateLabel(event.data),
                      if ('${event.data['product'] ?? ''}'.isNotEmpty)
                        'Producto: ${event.data['product']}',
                      if ('${event.data['batch'] ?? ''}'.isNotEmpty)
                        'Lote: ${event.data['batch']}',
                      for (final field in const {
                        'performer': 'Aplicador declarado',
                        'informant': 'Referido por',
                        'evidence_reference': 'Comprobante revisado',
                        'next_date_by': 'Próxima fecha indicada por',
                        'notes': 'Notas',
                      }.entries)
                        if ('${event.data[field.key] ?? ''}'.isNotEmpty)
                          '${field.value}: ${event.data[field.key]}',
                      'Capturado: ${event.createdAt.toLocal()} · Usuario: ${event.createdBy}',
                    ].join('\n'),
                  ),
                ),
            ],
          ),
        ExpansionTile(
          title: const Text('Calendario de próximas fechas indicadas'),
          children: [
            const ListTile(
              title: Text(
                'Fechas capturadas por el equipo. No se generan esquemas ni se crean citas automáticamente. Una fecha pasada no confirma incumplimiento; revisa el historial.',
              ),
            ),
            if (upcoming.isEmpty)
              const ListTile(title: Text('Sin próximas fechas registradas.')),
            for (final e in upcoming)
              ListTile(
                title: Text(
                  '${e.data['next_date']} · ${e.data['coverage'] ?? e.data['product']}',
                ),
                subtitle: Text(
                  '${preventiveOriginLabel(e.data)} · No equivale a una aplicación realizada.',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
