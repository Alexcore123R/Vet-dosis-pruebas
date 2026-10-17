import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart' show newOperationId;
import 'clinical_models.dart';
import 'clinical_repository.dart';
import 'vitals_models.dart';

class ClinicalVitalsScreen extends StatefulWidget {
  const ClinicalVitalsScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.caseData,
    this.latestWeight,
  });

  final ClinicalRepository repository;
  final ClinicMembership member;
  final ClinicalCase caseData;
  final String? latestWeight;

  @override
  State<ClinicalVitalsScreen> createState() => _ClinicalVitalsScreenState();
}

class _ClinicalVitalsScreenState extends State<ClinicalVitalsScreen> {
  final controllers = <String, TextEditingController>{
    for (final key in const [
      'fc',
      'fr',
      'temperature',
      'tllc',
      'bp_systolic',
      'bp_diastolic',
      'notes',
    ])
      key: TextEditingController(),
  };
  String? mucosaColor, mucosaHumidity;
  DateTime observedAt = DateTime.now();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  IconData speciesIcon(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('equin') || s.contains('bovin') || s.contains('porcin')) {
      return Icons.agriculture_outlined;
    }
    if (s.contains('ave') || s.contains('avian')) return Icons.egg_outlined;
    if (s.contains('conej')) return Icons.cruelty_free_outlined;
    if (s.contains('rept')) return Icons.terrain_outlined;
    return Icons.pets_outlined;
  }

  String? get pam {
    try {
      return calculatedPam(
        controllers['bp_systolic']!.text,
        controllers['bp_diastolic']!.text,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> chooseObservedAt() async {
    final local = observedAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null || !mounted) return;
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (next.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      setState(() => error = 'La hora observada no puede estar en el futuro.');
      return;
    }
    setState(() {
      observedAt = next;
      error = null;
    });
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = <String, String?>{
        for (final key in const [
          'fc',
          'fr',
          'temperature',
          'tllc',
          'bp_systolic',
          'bp_diastolic',
        ])
          key: controllers[key]!.text,
      };
      final payload = validateVitalSet(
        values: values,
        performedBy: widget.member.userId,
        observedAt: observedAt,
        mucosaColor: mucosaColor,
        mucosaHumidity: mucosaHumidity,
        notes: controllers['notes']!.text,
      );
      await widget.repository.vitals(
        widget.caseData.id,
        payload,
        newOperationId(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardaron las constantes. Actualiza y revisa permisos.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget numberField(
    String key,
    String label,
    String unit, {
    String? helper,
  }) =>
      TextField(
        controller: controllers[key],
        enabled: !busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget choiceGroup(
    String title,
    Map<String, String> options,
    String? value,
    ValueChanged<String?> changed,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options.entries)
                ChoiceChip(
                  label: Text(option.value),
                  selected: value == option.key,
                  onSelected: busy
                      ? null
                      : (selected) => changed(selected ? option.key : null),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final species = speciesLabel(widget.caseData.patientSpecies);
    final date = observedAt.toLocal();
    final weight = widget.latestWeight?.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Monitor de constantes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(speciesIcon(widget.caseData.patientSpecies)),
              ),
              title: Text(widget.caseData.patientName),
              subtitle: Text(
                [
                  species,
                  if (widget.caseData.patientBreed.trim().isNotEmpty)
                    widget.caseData.patientBreed.trim(),
                  if (weight != null && weight.isNotEmpty) '$weight kg',
                ].join(' · '),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hora observada'),
            subtitle: Text(
              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · '
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: busy ? null : chooseObservedAt,
          ),
          const Divider(),
          Text('Constantes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          numberField('fc', 'Frecuencia cardíaca', 'lpm'),
          const SizedBox(height: 12),
          numberField('fr', 'Frecuencia respiratoria', 'rpm'),
          const SizedBox(height: 12),
          numberField('temperature', 'Temperatura', '°C'),
          const SizedBox(height: 12),
          numberField('tllc', 'Tiempo de llenado capilar', 's'),
          const SizedBox(height: 20),
          Text(
            'Presión arterial',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          numberField('bp_systolic', 'PAS', 'mmHg'),
          const SizedBox(height: 12),
          numberField('bp_diastolic', 'PAD', 'mmHg'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('PAM calculada'),
              subtitle: const Text('(PAS + 2 × PAD) / 3'),
              trailing: Text(
                pam == null ? '—' : '$pam mmHg',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 20),
          choiceGroup(
            'Color de mucosas',
            vitalMucosaColors,
            mucosaColor,
            (value) => setState(() => mucosaColor = value),
          ),
          const SizedBox(height: 20),
          choiceGroup(
            'Humedad de mucosas',
            vitalMucosaHumidity,
            mucosaHumidity,
            (value) => setState(() => mucosaHumidity = value),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controllers['notes'],
            enabled: !busy,
            maxLength: 4000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Observaciones del examen físico',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Interpretación automática todavía desactivada'),
              subtitle: Text(
                'Se guardan hechos estructurados. $species aún no tiene rangos '
                'de referencia verificados cargados en el catálogo, por lo que '
                'VetDosis no clasificará estos valores como normales o anormales.',
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              busy ? 'Guardando…' : 'Guardar constantes en historial clínico',
            ),
          ),
        ],
      ),
    );
  }
}
