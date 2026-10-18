import 'package:flutter/material.dart';
import '../../../vet_ui/vet_components.dart';

/// Uses only the currently loaded, authorized appointment rows.
class AppointmentSummary extends StatelessWidget {
  const AppointmentSummary({
    super.key,
    required this.rows,
    required this.selectedState,
    required this.onStateChanged,
  });
  final List<Map<String, dynamic>> rows;
  final String? selectedState;
  final ValueChanged<String?> onStateChanged;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayCount = rows
        .where(
          (row) => DateUtils.isSameDay(
            DateTime.parse(row['starts_at'] as String).toLocal(),
            today,
          ),
        )
        .length;
    const states = {
      'agendado': 'Agendadas',
      'en_atencion': 'En atención',
      'listo': 'Listas',
      'entregado': 'Entregadas',
      'cancelado': 'Canceladas',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tu agenda', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '$todayCount citas para hoy · ${rows.length} citas cargadas',
              ),
              const Text(
                'Resumen de los registros disponibles. Horarios del dispositivo.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('Todas (${rows.length})'),
                selected: selectedState == null,
                onSelected: (_) => onStateChanged(null),
              ),
              for (final state in states.entries)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${state.value} (${rows.where((a) => a['state'] == state.key).length})',
                    ),
                    selected: selectedState == state.key,
                    onSelected: (_) => onStateChanged(state.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class AppointmentDetails extends StatelessWidget {
  const AppointmentDetails({
    super.key,
    required this.appointment,
    required this.stateLabel,
  });
  final Map<String, dynamic> appointment;
  final String stateLabel;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(appointment['starts_at'] as String).toLocal();
    final local = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                '${local.formatShortDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  stateLabel,
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          if ((appointment['notes'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(appointment['notes'] as String),
            ),
        ],
      ),
    );
  }
}
