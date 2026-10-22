import 'package:flutter/material.dart';
import '../domain/appointment_care.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import 'operations_view_model.dart' show operationError;

class AppointmentCarePanel extends StatelessWidget {
  const AppointmentCarePanel({
    super.key,
    required this.appointment,
    required this.data,
    required this.repository,
    required this.clinic,
    required this.onSaved,
    required this.isCurrent,
  });
  final Map<String, dynamic> appointment;
  final Map<String, dynamic>? data;
  final AppointmentCareRepository repository;
  final String clinic;
  final Future<void> Function() onSaved;
  final bool Function() isCurrent;

  List<Map<String, dynamic>> get records => (data?['records'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  bool has(String action) => records.any((r) => r['action'] == action);
  Future<void> capture(BuildContext context, String action) async {
    final clinical = appointment['kind'] == 'consulta' && action == 'ready';
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: switch (action) {
            'admit' => 'Ingreso · ${appointment['patient_name']}',
            'ready' =>
              clinical
                  ? 'Cierre clínico e indicaciones'
                  : 'Servicio listo e indicaciones',
            _ => 'Entrega del paciente',
          },
          reviewText: action == 'admit'
              ? 'Registra lo que se recibió y autorizó. Este registro no sustituye un consentimiento firmado ni acredita un pago.'
              : action == 'ready'
              ? 'Las indicaciones las captura el profesional. No se calculan dosis ni se crea una receta o próxima cita automáticamente.'
              : 'Comprueba quién recoge y entrega las indicaciones. El saldo se consulta por separado; este registro no acredita pago.',
          fields: [
            if (action == 'admit') ...const [
              RxField('reason', 'Motivo de ingreso o servicio', required: true),
              RxField(
                'belongings',
                'Pertenencias recibidas (o ninguna)',
                required: true,
              ),
              RxField(
                'authorized_services',
                'Servicios autorizados',
                required: true,
              ),
              RxField('authorized_by', 'Persona que autorizó', required: true),
              RxField(
                'pickup_person',
                'Persona autorizada para recoger',
                required: true,
              ),
              RxField(
                'budget_reference',
                'Referencia del presupuesto revisado',
              ),
              RxField(
                'budget_accepted',
                'Se confirmó la aceptación de ese presupuesto',
                type: 'checkbox',
              ),
            ],
            if (action == 'ready') ...[
              if (clinical)
                const RxField(
                  'clinical_date',
                  'Fecha clínica (AAAA-MM-DD)',
                  required: true,
                ),
              const RxField(
                'instructions',
                'Indicaciones para el tutor',
                required: true,
              ),
              if (clinical)
                const RxField('treatment', 'Tratamiento indicado por el MVZ'),
              const RxField(
                'followup',
                'Seguimiento o próxima revisión indicada',
              ),
            ],
            if (action == 'deliver') ...const [
              RxField('released_to', 'Nombre de quien recoge', required: true),
              RxField(
                'pickup_authorization',
                'Cómo se comprobó su autorización (obligatorio si cambió la persona o no hay ingreso)',
              ),
              RxField(
                'belongings_outcome',
                'Pertenencias devueltas o incidencias',
                required: true,
              ),
              RxField(
                'pickup_verified',
                'Comprobé la autorización de recogida',
                type: 'checkbox',
                required: true,
              ),
              RxField(
                'instructions_delivered',
                'Entregué las indicaciones registradas',
                type: 'checkbox',
                required: true,
              ),
            ],
          ],
          submit: (raw, operation) async {
            if (!isCurrent()) {
              throw const FormatException(
                'La vista cambió. Vuelve a abrir la tarjeta actualizada.',
              );
            }
            final checked = validateCare(action, raw);
            try {
              await repository.careWrite(
                clinic,
                appointment['id'] as String,
                appointment['version'] as int,
                action,
                checked,
                operation,
              );
            } catch (e) {
              throw FormatException(operationError(e));
            }
          },
        ),
      ),
    );
    if (saved == true && isCurrent()) await onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Ingreso y entrega sin comprobar. Actualiza para continuar.',
        ),
      );
    }
    final state = appointment['state'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final record in records) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${switch (record['action']) {
                'admit' => 'Ingreso registrado',
                'ready' => 'Indicaciones registradas',
                _ => 'Entrega registrada',
              }} · ${DateTime.parse(record['created_at'] as String).toLocal()}',
            ),
          ),
          if (record['action'] == 'admit')
            Text('Motivo: ${(record['details'] as Map)['reason']}'),
          if (record['clinical_recorded'] == true)
            const Text('Cierre clínico guardado en el expediente.'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Ver registro'),
            children: [
              for (final entry in (record['details'] as Map).entries)
                if (careLabels.containsKey(entry.key) &&
                    entry.value != '' &&
                    entry.value != null)
                  ListTile(
                    dense: true,
                    title: Text(careLabels[entry.key]!),
                    subtitle: Text(
                      entry.value is bool
                          ? (entry.value == true ? 'Sí' : 'No confirmado')
                          : '${entry.value}',
                    ),
                  ),
            ],
          ),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (data!['can_manage'] == true &&
                !has('admit') &&
                ['agendado', 'en_atencion'].contains(state))
              OutlinedButton.icon(
                onPressed: () => capture(context, 'admit'),
                icon: const Icon(Icons.login),
                label: const Text('Registrar ingreso'),
              ),
            if (data!['can_close'] == true &&
                !has('ready') &&
                ['en_atencion', 'listo'].contains(state))
              OutlinedButton.icon(
                onPressed: () => capture(context, 'ready'),
                icon: const Icon(Icons.assignment_turned_in_outlined),
                label: const Text('Indicaciones y listo'),
              ),
            if (data!['can_manage'] == true && state == 'listo' && has('ready'))
              OutlinedButton.icon(
                onPressed: () => capture(context, 'deliver'),
                icon: const Icon(Icons.logout),
                label: const Text('Registrar entrega'),
              ),
          ],
        ),
        if (appointment['kind'] == 'consulta' &&
            data!['can_manage'] == true &&
            data!['can_close'] != true &&
            ['en_atencion', 'listo'].contains(state) &&
            !has('ready'))
          const Text(
            'El cierre de consulta lo registra el MVZ con acceso al expediente.',
          ),
      ],
    );
  }
}

const careLabels = {
  'reason': 'Motivo',
  'belongings': 'Pertenencias recibidas',
  'authorized_services': 'Servicios autorizados',
  'authorized_by': 'Autorizó',
  'pickup_person': 'Persona autorizada para recoger',
  'budget_reference': 'Presupuesto de referencia',
  'budget_accepted': 'Aceptación del presupuesto',
  'instructions': 'Indicaciones',
  'followup': 'Seguimiento',
  'released_to': 'Recogió',
  'pickup_authorization': 'Comprobación de autorización',
  'belongings_outcome': 'Pertenencias e incidencias de entrega',
  'pickup_verified': 'Autorización comprobada',
  'instructions_delivered': 'Indicaciones entregadas',
};
