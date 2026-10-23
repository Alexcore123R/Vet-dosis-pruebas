import 'package:flutter/material.dart';
import '../../calculations/data/reference_library_repository.dart';
import '../../calculations/presentation/reference_library_screen.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart' show newOperationId;
import 'clinical_models.dart';
import 'clinical_repository.dart';
import 'vital_reference_catalog.dart';
import 'vitals_models.dart';

class ClinicalVitalsScreen extends StatefulWidget {
  const ClinicalVitalsScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.caseData,
    this.latestWeight,
    this.referenceCatalog,
    this.referenceLibrary,
  });

  final ClinicalRepository repository;
  final ClinicMembership member;
  final ClinicalCase caseData;
  final String? latestWeight;
  final VitalReferenceCatalog? referenceCatalog;
  final ReferenceLibraryRepository? referenceLibrary;

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
      final payload = Map<String, dynamic>.from(
        validateVitalSet(
          values: values,
          performedBy: widget.member.userId,
          observedAt: observedAt,
          mucosaColor: mucosaColor,
          mucosaHumidity: mucosaHumidity,
          notes: controllers['notes']!.text,
        ),
      );
      final snapshots = widget.referenceCatalog?.snapshotFor(
        species: widget.caseData.patientSpecies,
        values: values,
      );
      if (snapshots != null && snapshots.isNotEmpty) {
        payload['reference_snapshot'] = snapshots;
      }
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

  VitalReferenceEvaluation? referenceEvaluation(String key) {
    final catalog = widget.referenceCatalog;
    if (catalog == null) return null;
    try {
      return catalog.evaluate(
        species: widget.caseData.patientSpecies,
        parameter: key,
        rawValue: controllers[key]?.text,
      );
    } on FormatException {
      return null;
    }
  }

  Widget numberField(
    String key,
    String label,
    String unit, {
    String? helper,
    IconData? icon,
  }) {
    final evaluation = referenceEvaluation(key);
    final theme = Theme.of(context);
    final outside = evaluation != null &&
        evaluation.state != VitalReferenceState.within;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controllers[key],
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            helperText: helper,
            prefixIcon: icon == null ? null : Icon(icon),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (evaluation != null) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: Icon(
                  outside
                      ? Icons.priority_high_rounded
                      : Icons.check_circle_outline,
                  size: 16,
                ),
                label: Text(evaluation.label),
                backgroundColor: outside
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
              ),
              Text(
                'Referencia verificada · ${evaluation.entry.min.display()}–'
                '${evaluation.entry.max.display()} ${evaluation.entry.unit}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }

  BoxDecoration softDecoration(BuildContext context, {bool accent = false}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: accent
            ? [
                theme.colorScheme.primary.withValues(alpha: dark ? 0.28 : 0.18),
                theme.colorScheme.secondary.withValues(alpha: dark ? 0.18 : 0.11),
              ]
            : dark
            ? const [Color(0xFF182536), Color(0xFF101923)]
            : const [Color(0xFFFFFFFF), Color(0xFFF1F6FA)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: dark
            ? const Color(0xFF243547)
            : const Color(0xFFE4EDF3),
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x99000000) : const Color(0xFFD6E1E8),
          offset: const Offset(7, 8),
          blurRadius: 18,
        ),
        BoxShadow(
          color: dark ? const Color(0x162DE6D1) : Colors.white,
          offset: const Offset(-6, -6),
          blurRadius: 15,
        ),
      ],
    );
  }

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
    final theme = Theme.of(context);
    final species = speciesLabel(widget.caseData.patientSpecies);
    final date = observedAt.toLocal();
    final weight = widget.latestWeight?.trim();

    Widget sectionTitle(IconData icon, String title, {String? subtitle}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: softDecoration(context, accent: true),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null)
                Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor de constantes'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: softDecoration(context, accent: true),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    speciesIcon(widget.caseData.patientSpecies),
                    size: 30,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.caseData.patientName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          species,
                          if (widget.caseData.patientBreed.trim().isNotEmpty)
                            widget.caseData.patientBreed.trim(),
                          if (weight != null && weight.isNotEmpty) '$weight kg',
                        ].join(' · '),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(
                    speciesIcon(widget.caseData.patientSpecies),
                    size: 16,
                  ),
                  label: Text(species),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: softDecoration(context),
            child: ListTile(
              leading: Icon(
                Icons.schedule_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Hora observada'),
              subtitle: Text(
                '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · '
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: busy ? null : chooseObservedAt,
            ),
          ),
          const SizedBox(height: 26),
          sectionTitle(
            Icons.monitor_heart_outlined,
            'Constantes',
            subtitle: 'Registro estructurado del examen físico',
          ),
          const SizedBox(height: 16),
          numberField(
            'fc',
            'Frecuencia cardíaca',
            'lpm',
            icon: Icons.favorite_outline,
          ),
          const SizedBox(height: 12),
          numberField(
            'fr',
            'Frecuencia respiratoria',
            'rpm',
            icon: Icons.air_outlined,
          ),
          const SizedBox(height: 12),
          numberField(
            'temperature',
            'Temperatura',
            '°C',
            icon: Icons.thermostat_outlined,
          ),
          const SizedBox(height: 12),
          numberField(
            'tllc',
            'Tiempo de llenado capilar',
            's',
            icon: Icons.timer_outlined,
          ),
          const SizedBox(height: 28),
          sectionTitle(
            Icons.bloodtype_outlined,
            'Presión arterial',
            subtitle: 'PAS y PAD se guardan como pareja',
          ),
          const SizedBox(height: 16),
          numberField(
            'bp_systolic',
            'PAS',
            'mmHg',
            icon: Icons.arrow_upward_rounded,
          ),
          const SizedBox(height: 12),
          numberField(
            'bp_diastolic',
            'PAD',
            'mmHg',
            icon: Icons.arrow_downward_rounded,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: softDecoration(context, accent: true),
            child: Row(
              children: [
                Icon(
                  Icons.calculate_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAM calculada',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('(PAS + 2 × PAD) / 3'),
                    ],
                  ),
                ),
                Text(
                  pam == null ? '—' : '$pam mmHg',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          sectionTitle(
            Icons.water_drop_outlined,
            'Mucosas',
            subtitle: 'Color y humedad se registran por separado',
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 28),
          sectionTitle(
            Icons.notes_outlined,
            'Observaciones',
            subtitle: 'Hallazgos adicionales del examen físico',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controllers['notes'],
            enabled: !busy,
            maxLength: 4000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Observaciones del examen físico',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: softDecoration(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.referenceCatalog == null
                            ? 'Interpretación automática todavía desactivada'
                            : 'Referencias clínicas versionadas activas',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.referenceCatalog == null
                            ? 'Se guardan hechos estructurados. $species aún no tiene rangos '
                                'de referencia verificados cargados en el catálogo, por lo que '
                                'VetDosis no clasificará estos valores como normales o anormales.'
                            : 'Los indicadores solo comparan contra referencias verificadas '
                                'del catálogo ${widget.referenceCatalog!.version}. Estar dentro '
                                'de un rango de referencia no equivale a un diagnóstico.',
                      ),
                      if (widget.referenceLibrary != null)
                        TextButton.icon(
                          onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ReferenceLibraryScreen(
                            repository: widget.referenceLibrary!,
                            clinicId: widget.member.clinicId,
                          ))),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Consultar referencias fisiológicas'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: busy ? null : save,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.save_outlined),
              label: Text(
                busy ? 'Guardando…' : 'Guardar constantes en historial clínico',
              ),
            ),
          ),
        ],
      ),
    );
  }

}
