import 'package:flutter/material.dart';
import '../domain/quantity.dart';

enum DoseMathMode {
  concentration('Volumen desde dosis y concentración'),
  ruleOfThree('Regla de tres por peso'),
  internationalUnits('Unidades internacionales tras reconstitución'),
  conversion('Conversión métrica');

  const DoseMathMode(this.label);
  final String label;
}

/// Arithmetic helpers only. All clinical inputs are supplied by the clinician.
class DoseMathTools extends StatefulWidget {
  const DoseMathTools({super.key});

  @override
  State<DoseMathTools> createState() => _DoseMathToolsState();
}

class _DoseMathToolsState extends State<DoseMathTools> {
  final _controllers = <String, TextEditingController>{
    for (final key in [
      'weight',
      'dose',
      'concentration',
      'baselineVolume',
      'baselineWeight',
      'totalUnits',
      'finalVolume',
      'unitsPerKg',
      'amount',
    ])
      key: TextEditingController(),
  };
  DoseMathMode mode = DoseMathMode.concentration;
  String fromUnit = 'kg';
  String toUnit = 'g';
  String? result;
  String? formula;
  String? concentrationDetail;
  String? error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Quantity _positive(String key, String label) {
    final value = Quantity.parse(_controllers[key]!.text);
    if (!value.positive) {
      throw FormatException('$label debe ser mayor que cero.');
    }
    return value;
  }

  void calculate() {
    setState(() {
      result = null;
      formula = null;
      concentrationDetail = null;
      error = null;
    });
    try {
      late Quantity value;
      late String answer;
      late String equation;
      switch (mode) {
        case DoseMathMode.concentration:
          final weight = _positive('weight', 'Peso');
          final dose = _positive('dose', 'Dosis indicada');
          final concentration = _positive('concentration', 'Concentración');
          value = weight * dose / concentration;
          answer = '${value.display()} mL';
          equation =
              '${weight.display()} kg × ${dose.display()} mg/kg ÷ ${concentration.display()} mg/mL';
        case DoseMathMode.ruleOfThree:
          final targetWeight = _positive('weight', 'Peso del paciente');
          final baselineWeight = _positive(
            'baselineWeight',
            'Peso de referencia',
          );
          final baselineVolume = _positive(
            'baselineVolume',
            'Volumen de referencia',
          );
          value = baselineVolume * targetWeight / baselineWeight;
          answer = '${value.display()} mL';
          equation =
              '${baselineVolume.display()} mL ÷ ${baselineWeight.display()} kg × ${targetWeight.display()} kg';
        case DoseMathMode.internationalUnits:
          final weight = _positive('weight', 'Peso');
          final dose = _positive('unitsPerKg', 'Dosis indicada');
          final totalUnits = _positive('totalUnits', 'UI totales del frasco');
          final finalVolume = _positive(
            'finalVolume',
            'Volumen final reconstituido',
          );
          final concentration = totalUnits / finalVolume;
          value = weight * dose / concentration;
          answer = '${value.display()} mL';
          equation =
              '${weight.display()} kg × ${dose.display()} UI/kg ÷ (${totalUnits.display()} UI ÷ ${finalVolume.display()} mL)';
          concentrationDetail =
              'Concentración reconstituida: ${concentration.display()} UI/mL';
        case DoseMathMode.conversion:
          final amount = _positive('amount', 'Cantidad');
          final from = _unitFactor(fromUnit);
          final to = _unitFactor(toUnit);
          if (from.dimension != to.dimension) {
            throw const FormatException(
              'Elige unidades de la misma dimensión.',
            );
          }
          value = amount * from.factor / to.factor;
          answer = '${value.display()} $toUnit';
          equation = '${amount.display()} $fromUnit → $toUnit';
      }
      setState(() {
        result = answer;
        formula = equation;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  ({Quantity factor, String dimension}) _unitFactor(String unit) =>
      switch (unit) {
        'kg' => (factor: Quantity.parse('1000000'), dimension: 'masa'),
        'g' => (factor: Quantity.parse('1000'), dimension: 'masa'),
        'mg' => (factor: Quantity.parse('1'), dimension: 'masa'),
        'L' => (factor: Quantity.parse('1000'), dimension: 'volumen'),
        'mL' || 'cc' => (factor: Quantity.parse('1'), dimension: 'volumen'),
        _ => throw const FormatException('Unidad no disponible.'),
      };

  Widget _field(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(key),
      controller: _controllers[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {
        result = null;
        formula = null;
        concentrationDetail = null;
      }),
    ),
  );

  List<Widget> _inputs() => switch (mode) {
    DoseMathMode.concentration => [
      _field('weight', 'Peso (kg)'),
      _field('dose', 'Dosis indicada por el MVZ (mg/kg)'),
      _field('concentration', 'Concentración (mg/mL)'),
    ],
    DoseMathMode.ruleOfThree => [
      _field('baselineVolume', 'Volumen indicado de referencia (mL)'),
      _field('baselineWeight', 'Peso de referencia (kg)'),
      _field('weight', 'Peso del paciente (kg)'),
    ],
    DoseMathMode.internationalUnits => [
      _field('totalUnits', 'UI totales declaradas en el frasco'),
      _field('finalVolume', 'Volumen final tras reconstituir (mL)'),
      _field('weight', 'Peso del paciente (kg)'),
      _field('unitsPerKg', 'Dosis indicada por el MVZ (UI/kg)'),
    ],
    DoseMathMode.conversion => [
      _field('amount', 'Cantidad'),
      Row(
        children: [
          Expanded(
            child: _unitPicker(
              fromUnit,
              (value) => setState(() => fromUnit = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward),
          ),
          Expanded(
            child: _unitPicker(
              toUnit,
              (value) => setState(() => toUnit = value),
            ),
          ),
        ],
      ),
    ],
  };

  Widget _unitPicker(String value, ValueChanged<String> changed) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: const ['kg', 'g', 'mg', 'L', 'mL', 'cc']
            .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
            .toList(),
        onChanged: (next) {
          if (next != null) {
            changed(next);
            setState(() {
              result = null;
              formula = null;
              concentrationDetail = null;
            });
          }
        },
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Operaciones de dosis',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Operaciones matemáticas. Ingresa únicamente parámetros ya indicados y confirma las unidades y la presentación con el MVZ.',
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<DoseMathMode>(
        initialValue: mode,
        decoration: const InputDecoration(
          labelText: 'Tipo de cálculo',
          border: OutlineInputBorder(),
        ),
        items: DoseMathMode.values
            .map(
              (item) => DropdownMenuItem(value: item, child: Text(item.label)),
            )
            .toList(),
        onChanged: (value) => setState(() {
          mode = value ?? mode;
          result = null;
          formula = null;
          concentrationDetail = null;
          error = null;
        }),
      ),
      const SizedBox(height: 16),
      ..._inputs(),
      FilledButton.icon(
        onPressed: calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Calcular'),
      ),
      if (error case final message?)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (result case final value?) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resultado matemático'),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(formula ?? ''),
                if (concentrationDetail != null) Text(concentrationDetail!),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}
