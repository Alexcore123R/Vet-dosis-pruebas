import 'package:flutter/material.dart';
import '../domain/appointment_links.dart';
import '../../patients/presentation/contact_actions.dart';

class AppointmentLinksPanel extends StatelessWidget {
  const AppointmentLinksPanel({
    super.key,
    required this.data,
    required this.patientName,
  });
  final Map<String, dynamic>? data;
  final String patientName;
  @override
  Widget build(BuildContext context) {
    String billing =
        'Estado de pago no disponible con esta consulta o permiso.';
    if (data?['billing'] is Map) {
      try {
        billing = AppointmentBilling.read(
          Map<String, dynamic>.from(data!['billing'] as Map),
        ).label;
      } on FormatException {
        billing = 'Importes pendientes de revisión en Caja.';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(billing),
        if (data?['billing'] is Map)
          const Text(
            'Servicios registrados vinculados a esta cita; atención, entrega y pago son estados independientes.',
          ),
        if (data?['contact'] is Map)
          ExpansionTile(
            title: const Text('Contacto del tutor'),
            subtitle: Text((data!['contact'] as Map)['phone'] as String? ?? ''),
            children: [
              ContactActions(
                owner: Map<String, dynamic>.from(data!['contact'] as Map),
                patientName: patientName,
              ),
            ],
          ),
      ],
    );
  }
}
