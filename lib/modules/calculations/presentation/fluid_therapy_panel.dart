import 'package:flutter/material.dart';
import '../../../core/widgets/calculator_surface.dart';
import '../../../core/widgets/neu_header_card.dart';
import '../../doses/domain/quantity.dart';
import '../../patients/domain/patient_models.dart';
import '../../patients/domain/patient_repository.dart';
import '../data/reference_library_repository.dart';
import '../domain/calculation_engine.dart';
import '../domain/fluid_plan.dart';
import 'drip_metronome.dart';
import 'reference_library_screen.dart';

class FluidTherapyPanel extends StatefulWidget {
  const FluidTherapyPanel({
    super.key,
    this.patients,
    this.clinicId,
    this.references,
    this.onReminder,
  });
  final PatientRepository? patients;
  final String? clinicId;
  final ReferenceLibraryRepository? references;
  final void Function(String patientId, String summary)? onReminder;
  @override
  State<FluidTherapyPanel> createState() => _FluidTherapyPanelState();
}

class _FluidTherapyPanelState extends State<FluidTherapyPanel> {
  final fields = {
    for (final key in [
      'weight',
      'maintenance',
      'percent',
      'hours',
      'losses',
      'drop_factor',
      'coefficient',
      'exponent',
      'source',
      'baseK',
      'addedK',
      'maxK',
      'kSource',
      'bolusDose',
      'bolusMinutes',
      'bolusSource',
    ])
      key: TextEditingController(),
  };
  List<VetPatient> patients = [];
  VetPatient? patient;
  String? weightNote, patientError, error;
  String solution = 'Sin seleccionar';
  bool loading = false,
      perDay = false,
      allometric = false,
      potassium = false,
      bolusEnabled = false,
      reviewed = false;
  int generation = 0, revision = 0;
  FluidPlan? plan;
  Quantity? kRate;
  ({Quantity volume, Quantity rate})? bolus;
  bool kExceeded = false;
  @override
  void initState() {
    super.initState();
    loadPatients();
  }

  @override
  void dispose() {
    generation++;
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void invalidate() {
    setState(() {
      plan = null;
      kRate = null;
      bolus = null;
      error = null;
      reviewed = false;
      revision++;
    });
  }

  Future<void> loadPatients() async {
    if (widget.patients == null || widget.clinicId == null) return;
    final request = ++generation;
    setState(() {
      loading = true;
      patientError = null;
      patients = [];
      patient = null;
    });
    try {
      final rows = await widget.patients!.patients(widget.clinicId!);
      if (!mounted || request != generation) return;
      setState(
        () => patients = rows
            .where((p) => p.clinicId == widget.clinicId)
            .toList(),
      );
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => patientError =
              'No se pudieron consultar pacientes. Reintenta o captura el peso manualmente.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> selectPatient(VetPatient? value) async {
    final request = ++generation;
    invalidate();
    setState(() {
      patient = value;
      fields['weight']!.clear();
      weightNote = null;
      patientError = null;
      loading = value != null;
    });
    if (value == null) return;
    try {
      final events = await widget.patients!.events(widget.clinicId!, value.id);
      if (!mounted || request != generation) return;
      final weights = events.where((e) => e.kind == EventKind.weight).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        if (weights.isEmpty) {
          weightNote = 'Sin peso registrado; captura el peso actual.';
        } else {
          fields['weight']!.text = '${weights.first.data['kg'] ?? ''}';
          weightNote =
              'Peso del expediente (${weights.first.createdAt.toLocal()}). Confirma que sea actual.';
        }
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => patientError =
              'No se pudo leer el peso del expediente; captura y verifica el peso actual.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Quantity q(String key) =>
      Quantity.parse(fields[key]!.text.replaceAll(',', '.'));
  void calculate() {
    invalidate();
    try {
      if (allometric && fields['source']!.text.trim().isEmpty) {
        throw const FormatException(
          'Indica la fuente y especie del coeficiente alométrico.',
        );
      }
      final values = {
        for (final key in [
          'weight',
          'maintenance',
          'percent',
          'hours',
          'losses',
          'drop_factor',
        ])
          key: fields[key]!.text,
      };
      if (allometric) {
        values['maintenance'] = '0';
        values['coefficient'] = fields['coefficient']!.text;
        values['exponent'] = fields['exponent']!.text;
      }
      final result = FluidPlan.calculate(
        values,
        lossesPerDay: perDay,
        allometric: allometric,
      );
      Quantity? computedK;
      bool exceeded = false;
      if (potassium) {
        if (fields['kSource']!.text.trim().isEmpty ||
            solution == 'Sin seleccionar') {
          throw const FormatException(
            'Identifica la solución y la fuente del límite de potasio.',
          );
        }
        final limit = q('maxK');
        if (!limit.positive) {
          throw const FormatException(
            'El límite de potasio debe ser positivo.',
          );
        }
        computedK = result.potassiumRate(q('baseK'), q('addedK'));
        exceeded = computedK.compareTo(limit) > 0;
      }
      ({Quantity volume, Quantity rate})? computedBolus;
      if (bolusEnabled) {
        if (potassium) {
          throw const FormatException(
            'El bolo se calcula por separado, sin suplementación de KCl. Desactiva una de las dos opciones.',
          );
        }
        if (fields['bolusSource']!.text.trim().isEmpty) {
          throw const FormatException(
            'Indica la fuente y el contexto clínico del bolo.',
          );
        }
        computedBolus = FluidPlan.bolus(
          q('weight'),
          q('bolusDose'),
          q('bolusMinutes'),
        );
      }
      setState(() {
        plan = result;
        kRate = computedK;
        kExceeded = exceeded;
        bolus = computedBolus;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message.toString());
    }
  }

  Widget input(String key, String label, {bool numeric = true}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('fluid:$key'),
      controller: fields[key],
      enabled: !loading,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => invalidate(),
    ),
  );
  String dehydrationNote() {
    final p = double.tryParse(fields['percent']!.text.replaceAll(',', '.'));
    if (p == null || p < 0) {
      return 'Selecciona o captura el porcentaje estimado.';
    }
    if (p < 4) {
      return 'La ausencia de signos evidentes no descarta un déficit leve.';
    }
    if (p >= 5 && p <= 6) {
      return 'Referencia orientativa: cambios leves en la elasticidad cutánea.';
    }
    if (p >= 7 && p <= 8) {
      return 'Referencia orientativa: retraso del pliegue cutáneo y cambios en mucosas y perfusión.';
    }
    if (p >= 9 && p <= 10) {
      return 'Referencia orientativa: alteraciones marcadas de turgencia y perfusión; requiere reevaluación clínica.';
    }
    if (p >= 11) {
      return 'Referencia orientativa: pueden coexistir hipoperfusión grave y choque; requiere valoración inmediata.';
    }
    return 'La tabla no clasifica este valor intermedio; requiere criterio clínico.';
  }

  Widget section(String title, IconData icon, List<Widget> children) =>
      NeuHeaderCard(
        title: title,
        icon: icon,
        color: const Color(0xFF61C7BA),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
  String number(Quantity q) => displayCalculation(q);
  String summary() =>
      'Revisar fluidoterapia de ${patient!.name} (${patient!.species}). Peso: ${fields['weight']!.text} kg. Solución: $solution. Volumen del periodo: ${number(plan!.values['total']!)} ml en ${fields['hours']!.text} h; velocidad teórica: ${number(plan!.rate)} ml/h. Déficit: ${number(plan!.values['deficit']!)} ml; pérdidas: ${number(plan!.losses)} ml. Parámetros y equipo revisados por el profesional. Reevaluar; no registra administración.${potassium ? ' Potasio total: ${number(kRate!)} mEq/kg/h; límite capturado ${fields['maxK']!.text}; fuente: ${fields['kSource']!.text}.' : ''}';
  @override
  Widget build(BuildContext context) => CalculatorSurface(
    id: 'fluids',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Fluidoterapia y deshidratación',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Parámetros indicados por el MVZ. Los resultados son cálculos, no una selección automática de tratamiento.',
        ),
        if (widget.patients != null && widget.clinicId != null) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('patient:${patient?.id}'),
            initialValue: patient?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Paciente del expediente',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Captura manual'),
              ),
              for (final p in patients)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.name} · ${p.species}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: loading
                ? null
                : (v) => selectPatient(
                    patients.where((p) => p.id == v).firstOrNull,
                  ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (patientError != null) Text(patientError!),
          if (patientError != null && patient == null)
            TextButton(
              onPressed: loadPatients,
              child: const Text('Reintentar pacientes'),
            ),
          if (weightNote != null) Text(weightNote!),
        ],
        section('1. Paciente y mantenimiento', Icons.pets_outlined, [
          input('weight', 'Peso (kg)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fórmula alométrica indicada'),
            value: allometric,
            onChanged: (v) {
              invalidate();
              setState(() => allometric = v);
            },
          ),
          if (!allometric)
            input('maintenance', 'Mantenimiento indicado (ml/kg/día)'),
          if (allometric) ...[
            const Text(
              'Mantenimiento diario = coeficiente × peso^exponente. Introduce la fórmula específica de la fuente; no hay coeficientes universales precargados.',
            ),
            input('coefficient', 'Coeficiente (ml/día por kg^exponente)'),
            input('exponent', 'Exponente (mayor que 0 y hasta 1)'),
            input(
              'source',
              'Fuente, especie y contexto de la fórmula',
              numeric: false,
            ),
          ],
        ]),
        section('2. Deshidratación estimada', Icons.water_drop_outlined, [
          input('percent', 'Deshidratación estimada (%)'),
          Wrap(
            spacing: 8,
            children: [
              for (final p in [0, 5, 7, 8, 10, 12])
                ChoiceChip(
                  label: Text('$p%'),
                  selected: fields['percent']!.text == '$p',
                  onSelected: (_) {
                    invalidate();
                    setState(() => fields['percent']!.text = '$p');
                  },
                ),
            ],
          ),
          const Text(
            'Porcentaje elegido por el profesional tras la evaluación clínica; estos accesos no clasifican al paciente.',
          ),
        ]),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${dehydrationNote()}\nFuente: Salom Morell y Soler Aracil, 2023, p. 56, tabla 5.1 (PDF p. 72).',
          ),
        ),
        section('3. Pérdidas, periodo y equipo', Icons.schedule, [
          input('hours', 'Periodo de reposición (h)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pérdidas expresadas en ml/día'),
            value: perDay,
            onChanged: (v) {
              invalidate();
              setState(() {
                perDay = v;
                fields['losses']!.clear();
              });
            },
          ),
          input(
            'losses',
            perDay
                ? 'Pérdidas continuas (ml/día)'
                : 'Pérdidas adicionales TOTALES del periodo (ml)',
          ),
          input('drop_factor', 'Factor real del equipo (gotas/ml)'),
          DropdownButtonFormField<String>(
            initialValue: solution,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Solución seleccionada por el MVZ',
            ),
            items: [
              for (final name in [
                'Sin seleccionar',
                'Hartmann / Ringer lactato',
                'NaCl 0.9%',
                'NaCl + glucosa (ver etiqueta)',
                'Dextrosa 5%',
                'Otra (documentar en indicaciones)',
              ])
                DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              invalidate();
              setState(() => solution = v!);
            },
          ),
          const Text(
            'Confirma composición, indicación y presentación del fabricante. El nombre no implica recomendación ni compatibilidad.',
          ),
        ]),
        section('4. Potasio y bolo (opcionales)', Icons.science_outlined, [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Comprobar aporte de potasio'),
            value: potassium,
            onChanged: (v) {
              invalidate();
              setState(() => potassium = v);
            },
          ),
          if (potassium) ...[
            input('baseK', 'Potasio basal de la solución (mEq/L)'),
            input('addedK', 'Potasio añadido por litro FINAL (mEq/L)'),
            input('maxK', 'Límite indicado (mEq/kg/h)'),
            input(
              'kSource',
              'Fuente del límite y contexto clínico',
              numeric: false,
            ),
            const Text(
              'Incluye el potasio basal. No administra KCl en bolo ni calcula automáticamente cuánto concentrado añadir. Requiere revisión de función renal, diuresis y electrolitos.',
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Calcular bolo indicado por el MVZ'),
            value: bolusEnabled,
            onChanged: (v) {
              invalidate();
              setState(() => bolusEnabled = v);
            },
          ),
          if (bolusEnabled) ...[
            input('bolusDose', 'Dosis de bolo indicada (ml/kg)'),
            input('bolusMinutes', 'Duración indicada del bolo (min)'),
            input(
              'bolusSource',
              'Fuente, especie y contexto del bolo',
              numeric: false,
            ),
            const Text(
              'Resultado separado del plan de rehidratación. Reevaluar antes de repetir; no se precarga una dosis de choque.',
            ),
          ],
        ]),
        FilledButton(
          onPressed: loading ? null : calculate,
          child: const Text('Calcular · Fluidoterapia'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (plan != null)
          section('Plan de rehidratación', Icons.water, [
            if (allometric)
              const Text('Mantenimiento alométrico aproximado a 9 decimales.'),
            for (final e in {
              'Déficit estimado (ml)': plan!.values['deficit']!,
              'Mantenimiento (ml/día)': plan!.values['maintenance_day']!,
              'Pérdidas del periodo (ml)': plan!.losses,
              'Volumen del periodo (ml)': plan!.values['total']!,
              'Velocidad (ml/h)': plan!.rate,
              'Velocidad (ml/min)': plan!.perMinute,
              'Goteo teórico (gotas/min)': plan!.values['drops']!,
            }.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: SelectableText('${e.key}: ${number(e.value)}'),
              ),
            for (final factor in [20, 60])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${factor == 20 ? 'Normogotero' : 'Microgotero'} ($factor gotas/ml): ${number(plan!.drops(factor))} gotas/min · ${plan!.secondsPerDrop(factor) == null ? 'Sin flujo' : '${number(plan!.secondsPerDrop(factor)!)} segundos/gota'}',
                ),
              ),
            const Text(
              'Resultados teóricos sin redondeo para administración. Confirma el factor impreso en tu equipo y el ajuste real.',
            ),
            if (kRate != null)
              Text(
                'Potasio total: ${number(kRate!)} mEq/kg/h. ${kExceeded ? 'SUPERA el límite capturado. Revisa el plan.' : 'No supera el límite capturado; no equivale a validación clínica.'}',
                style: TextStyle(
                  color: kExceeded ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            if (bolus != null)
              Text(
                'Bolo separado: ${number(bolus!.volume)} ml en ${fields['bolusMinutes']!.text} min · ${number(bolus!.rate)} ml/h. No se suma al plan ni se repite automáticamente.',
              ),
            if (!kExceeded)
              DripMetronome(
                key: ValueKey(revision),
                dropsPerMinute:
                    plan!.values['drops']!.n.toDouble() /
                    plan!.values['drops']!.d.toDouble(),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Revisé paciente, peso, unidades, solución, equipo y fuentes.',
              ),
              value: reviewed,
              onChanged: kExceeded
                  ? null
                  : (v) => setState(() => reviewed = v ?? false),
            ),
            if (widget.onReminder != null)
              FilledButton.icon(
                onPressed: reviewed && !kExceeded && patient != null
                    ? () => widget.onReminder!(patient!.id, summary())
                    : null,
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Programar revisión de fluidoterapia'),
              ),
            if (widget.onReminder != null && patient == null)
              const Text(
                'Selecciona un paciente para abrir su hoja de hospitalización y programar la revisión.',
              ),
          ]),
        if (widget.references != null && widget.clinicId != null)
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                'fisiologia': 'Constantes con fuentes',
                'laboratorio': 'Valores de laboratorio',
              }.entries)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReferenceLibraryScreen(
                        repository: widget.references!,
                        clinicId: widget.clinicId!,
                        initialSection: entry.key,
                      ),
                    ),
                  ),
                  child: Text(entry.value),
                ),
            ],
          ),
        const ExpansionTile(
          title: Text('Fuentes y alcance'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Manual de protocolos de anestesia en perros, gatos y exóticos, Salom Morell y Soler Aracil, 2023, capítulo 5, pp. 51–60; tabla 5.1 en p. 56; plan de fluidoterapia en p. 58 (PDF pp. 67–76). Las pautas anestésicas no son una recomendación automática de rehidratación. Las referencias de Supabase conservan su estado de revisión; no se convierten en dosis ni límites por defecto.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
