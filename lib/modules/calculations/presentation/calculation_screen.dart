import '../../../core/widgets/calculator_surface.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../../incubation/presentation/incubation_screen.dart';
import '../../aviculture/presentation/aviculture_screen.dart';
import 'package:flutter/material.dart';
import '../../doses/data/catalog_repository.dart';
import '../../doses/domain/quantity.dart';
import '../data/calculation_repository.dart';
import '../domain/calculation_catalog.dart';
import '../domain/calculation_engine.dart';
import 'calculation_view_model.dart';

class CalculationScreen extends StatefulWidget {
  const CalculationScreen({
    super.key,
    this.repository,
    this.doses,
    this.initialTool = 'fluids',
    this.showAviculture = false,
  });
  final CalculationRepository? repository;
  final CatalogRepository? doses;
  final String initialTool;
  final bool showAviculture;
  @override
  State<CalculationScreen> createState() => _CalculationScreenState();
}

class _CalculationScreenState extends State<CalculationScreen> {
  late final CalculationViewModel model;
  final values = <String, String>{};
  String selected = 'fluids';
  String? referenceId;
  String referenceInput = '',
      referenceStep = '',
      breed = '',
      conditions = '',
      referenceOutput = '',
      referenceError = '';
  int generation = 0;
  bool reviewed = false, confirmed = false;
  @override
  void initState() {
    super.initState();
    selected = widget.initialTool;
    model = CalculationViewModel(
      widget.repository ?? AssetCalculationRepository(),
      widget.doses ?? AssetCatalogRepository(),
    );
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  void reset(String value) {
    setState(() {
      selected = value;
      referenceId = null;
      values.clear();
      referenceInput = '';
      referenceStep = '';
      referenceOutput = '';
      referenceError = '';
      reviewed = false;
      confirmed = false;
      generation++;
    });
    model.clear();
  }

  void referenceCalculate(ClinicalReference r) {
    setState(() {
      referenceOutput = '';
      referenceError = '';
      reviewed = false;
      confirmed = false;
    });
    try {
      if (!r.evidence.verified) {
        throw const FormatException('Referencia sin verificar.');
      }
      final weight = Quantity.parse(referenceInput);
      switch (r.type) {
        case 'constante':
          referenceOutput = r.evaluate(weight);
        case 'metabolico':
          referenceOutput =
              'Peso metabólico aproximado: ${r.metabolicWeight(weight).toStringAsPrecision(7)} kg^${r.data['exponente']}. No es una dosis ni un factor automático de escalamiento.';
        case 'protocolo':
          final results = r.protocol(
            model.doseCatalog!,
            weight,
            Quantity.parse(referenceStep),
            breed: breed,
            conditions: conditions
                .split(';')
                .where((s) => s.trim().isNotEmpty)
                .map((s) => s.trim())
                .toList(),
          );
          referenceOutput = results
              .map(
                (p) =>
                    '${p.stage} · ${p.drug} · ${p.presentation}: ${displayCalculation(p.result.mass)} mg · ${displayCalculation(p.result.volume)} ml · graduado ${displayCalculation(p.result.roundedVolume)} ml${p.result.alerts.isEmpty ? '' : '\nBLOQUEADO: ${p.result.alerts.join(' ')}'}',
              )
              .join('\n\n');
          if (results.any((p) => !p.result.canConfirm)) {
            referenceError =
                'Hay alertas: este protocolo no puede confirmarse.';
          }
        default:
          throw const FormatException('Referencia no calculable.');
      }
    } on FormatException catch (e) {
      referenceError = e.message;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final catalog = model.catalog;
      if (catalog == null) {
        return model.error != null
            ? Text(model.error!)
            : const Center(child: CircularProgressIndicator());
      }
      final defs = catalog.calculations.where((d) => d.id == selected).toList();
      final def = defs.isEmpty ? null : defs.single;
      final type = switch (selected) {
        'vitals' => 'constante',
        'protocols' => 'protocolo',
        'withdrawals' => 'retiro',
        'metabolic' => 'metabolico',
        'adjustment' => 'ajuste',
        _ => '',
      };
      final refs = catalog.references.where((r) => r.type == type).toList();
      final chosen = refs.where((r) => r.id == referenceId).toList();
      final reference = chosen.isEmpty ? null : chosen.single;
      return CalculatorSurface(
        id: selected,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cálculos clínicos',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (widget.showAviculture)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AvicultureScreen(),
                  ),
                ),
                icon: const Icon(Icons.agriculture_outlined),
                label: const Text('Aves · Capacidad e instalaciones'),
              ),
            if (widget.showAviculture)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const IncubationScreen(),
                  ),
                ),
                icon: const Icon(Icons.egg_outlined),
                label: const Text('Aves · Incubación'),
              ),
            const SizedBox(height: 12),
            const Text(
              'Los parámetros son indicados por el MVZ. La app no selecciona tratamientos. Los resultados no se guardan en el expediente ni emiten recetas automáticamente.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Herramienta'),
              items: [
                for (final d in catalog.calculations)
                  DropdownMenuItem(
                    value: d.id,
                    child: Row(
                      children: [
                        CalculatorIcon(d.id),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final entry in {
                  'protocols': 'Protocolos por etapas',
                  'vitals': 'Constantes fisiológicas',
                  'metabolic': 'Peso metabólico en exóticos',
                  'withdrawals': 'Tiempos de retiro',
                }.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) reset(v);
              },
            ),
            const SizedBox(height: 16),
            if (def != null) ...[
              Row(
                children: [
                  CalculatorIcon(selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      def.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (type.isNotEmpty) ...[
              if (refs.isEmpty)
                const Text(
                  'Sin referencias disponibles. Faltan datos con fuente y estado de verificación; no se proponen valores.',
                ),
              if (refs.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('$selected:$generation'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText:
                        'Referencia exacta (especie / producto / condición)',
                  ),
                  items: [
                    for (final r in refs)
                      DropdownMenuItem(
                        value: r.id,
                        child: Text('${r.species} · ${r.title}'),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      referenceId = v;
                      referenceInput = '';
                      referenceStep = '';
                      breed = '';
                      conditions = '';
                      referenceOutput = '';
                      referenceError = '';
                      reviewed = false;
                      confirmed = false;
                    });
                    model.clear();
                  },
                ),
              if (reference != null) ...[
                Text(
                  '${reference.evidence.verified ? 'Verificada' : 'Sin verificar'} · Fuente: ${reference.evidence.source ?? 'pendiente'}',
                ),
                if (selected == 'withdrawals')
                  Text(
                    'Producto: ${reference.data['producto_id']} · ${reference.data['presentacion']}\nEspecie: ${reference.species} · Vía: ${reference.data['via']} · Destino: ${reference.data['destino']} · México\nRetiro: ${reference.evidence.verified && reference.data['tiempo'] != null ? '${reference.data['tiempo']} ${reference.data['unidad']}' : 'No disponible con referencia verificada'}',
                  ),
                if ([
                  'protocols',
                  'vitals',
                  'metabolic',
                ].contains(selected)) ...[
                  TextFormField(
                    key: ValueKey('input:$referenceId'),
                    decoration: InputDecoration(
                      labelText: selected == 'vitals'
                          ? '${reference.data['parametro']} (${reference.data['unidad']})'
                          : 'Peso (kg)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) {
                      setState(() {
                        referenceInput = v;
                        referenceOutput = '';
                        referenceError = '';
                        reviewed = false;
                        confirmed = false;
                      });
                      if (selected == 'vitals' &&
                          v.trim().isNotEmpty &&
                          reference.evidence.verified) {
                        referenceCalculate(reference);
                      }
                    },
                  ),
                  if (selected == 'protocols') ...[
                    TextFormField(
                      key: ValueKey('step:$referenceId'),
                      decoration: const InputDecoration(
                        labelText: 'Graduación de jeringa (ml)',
                      ),
                      onChanged: (v) {
                        setState(() {
                          referenceStep = v;
                          referenceOutput = '';
                          reviewed = false;
                          confirmed = false;
                        });
                      },
                    ),
                    TextFormField(
                      key: ValueKey('breed:$referenceId'),
                      decoration: const InputDecoration(labelText: 'Raza'),
                      onChanged: (v) {
                        setState(() {
                          breed = v;
                          referenceOutput = '';
                          reviewed = false;
                          confirmed = false;
                        });
                      },
                    ),
                    TextFormField(
                      key: ValueKey('conditions:$referenceId'),
                      decoration: const InputDecoration(
                        labelText: 'Condiciones (separadas por ;)',
                      ),
                      onChanged: (v) {
                        setState(() {
                          conditions = v;
                          referenceOutput = '';
                          reviewed = false;
                          confirmed = false;
                        });
                      },
                    ),
                    const Text(
                      'No se verifica automáticamente compatibilidad entre fármacos. Revisa todas las etapas antes de confirmar.',
                    ),
                  ],
                  FilledButton(
                    onPressed: reference.evidence.verified
                        ? () => referenceCalculate(reference)
                        : null,
                    child: const Text('Evaluar referencia'),
                  ),
                ],
              ],
            ],
            if (def != null &&
                (selected != 'adjustment' || reference != null)) ...[
              for (final f in def.inputs)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    key: ValueKey('$selected:$generation:${f.id}:$referenceId'),
                    initialValue: f.id == 'factor'
                        ? reference?.data['factor'] as String?
                        : null,
                    readOnly: f.id == 'factor',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: f.zero
                          ? 'Permite 0 si el MVZ así lo indica.'
                          : null,
                    ),
                    onChanged: (v) {
                      values[f.id] = v;
                      model.clear();
                      setState(() {
                        reviewed = false;
                        confirmed = false;
                      });
                    },
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (reference?.data['factor'] != null) {
                    values['factor'] = reference!.data['factor'] as String;
                  }
                  setState(() {
                    reviewed = false;
                    confirmed = false;
                  });
                  model.calculate(def, values, adjustment: reference);
                },
                child: Text('Calcular · ${def.title}'),
              ),
              if (model.result != null) ...[
                const SizedBox(height: 16),
                WorkspacePanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Resultado matemático · sin redondeo para administración',
                        ),
                        const SizedBox(height: 12),
                        for (final entry in model.result!.values.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${def.outputs[entry.key] ?? entry.key}: ${displayCalculation(entry.value)}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                for (final note in model.result!.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(note),
                  ),
                const Text(
                  'Visualización aproximada a 9 decimales. No redondear a gotas ni graduación de jeringa sin revisar el equipo y la dosis entregada.',
                ),
              ],
            ],
            if (model.error != null)
              Text(
                model.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (referenceOutput.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  referenceOutput,
                  style: TextStyle(
                    color:
                        referenceOutput.contains('Por debajo') ||
                            referenceOutput.contains('Por encima')
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            if (referenceError.isNotEmpty)
              Text(
                referenceError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (model.result != null ||
                (selected == 'protocols' &&
                    referenceOutput.isNotEmpty &&
                    referenceError.isEmpty)) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: reviewed,
                title: const Text(
                  'Revisé especie, unidades, presentación, parámetros y fuentes aplicables.',
                ),
                onChanged: (v) => setState(() {
                  reviewed = v ?? false;
                  confirmed = false;
                }),
              ),
              OutlinedButton(
                onPressed: reviewed && !confirmed
                    ? () => setState(() => confirmed = true)
                    : null,
                child: Text(
                  confirmed
                      ? 'Revisión confirmada; no constituye receta'
                      : 'Confirmar revisión del cálculo',
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
