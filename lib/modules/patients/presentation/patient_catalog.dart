import '../../../core/widgets/neu_header_card.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../domain/patient_models.dart';

String patientSearchText(String text) {
  var value = text.toLowerCase().trim();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final entry in accents.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  return value.replaceAll(RegExp(r'\s+'), ' ');
}

String patientEventTimestamp(BuildContext context, DateTime timestamp) {
  final date = timestamp.toLocal();
  final local = MaterialLocalizations.of(context);
  return '${local.formatShortDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

class PatientCatalogTile extends StatelessWidget {
  const PatientCatalogTile({
    super.key,
    required this.patient,
    required this.selected,
    this.onTap,
  });
  final VetPatient patient;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => NeuHeaderCard(
    title: patient.name,
    icon: Icons.pets_outlined,
    color: const Color(0xFF61C7BA),
    onTap: onTap,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      selected: selected,
      leading: Icon(
        Icons.pets_outlined,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      subtitle: Text(
        [
          patient.species,
          if (patient.breed.isNotEmpty) patient.breed,
        ].join(' · '),
      ),
      trailing: Icon(
        selected ? Icons.check_circle_outline : Icons.chevron_right,
      ),
      onTap: onTap,
    ),
  );
}

class PatientIdentity extends StatelessWidget {
  const PatientIdentity({super.key, required this.patient});
  final VetPatient patient;
  @override
  Widget build(BuildContext context) => WorkspacePanel(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Expediente abierto'),
          const SizedBox(height: 8),
          Text(
            '${patient.name} · ${patient.species}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (patient.breed.isNotEmpty) Text(patient.breed),
          Text(
            '${patient.sex} · Nacimiento: ${patient.birthDate ?? 'Pendiente'}',
          ),
        ],
      ),
    ),
  );
}
