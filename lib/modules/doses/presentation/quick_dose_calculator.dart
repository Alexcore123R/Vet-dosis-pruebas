import 'package:flutter/material.dart';
import '../domain/quantity.dart';

/// Arithmetic-only helper: the clinician supplies the dose and concentration.
class QuickDoseCalculator extends StatefulWidget {
  const QuickDoseCalculator({super.key});

  @override
  State<QuickDoseCalculator> createState() => _QuickDoseCalculatorState();
}

class _QuickDoseCalculatorState extends State<QuickDoseCalculator> {
  final weight = TextEditingController();
  final dose = TextEditingController();
  final concentration = TextEditingController();
  String? result;
  String? formula;
  String? error;

  @override
  void dispose() {
    weight.dispose();
    dose.dispose();
    concentration.dispose();
    super.dispose();
  }

  void calculate() {
    setState(() {
      result = null;
      formula = null;
      error = null;
    });
    try {
      final w = Quantity.parse(weight.text);
      final d = Quantity.parse(dose.text);
      final c = Quantity.parse(concentration.text);
      if (!w.positive || !d.positive || !c.positive) {
        throw const FormatException(
          'Todos los valores deben ser mayores que cero.',
        );
      }
      final volume = (w * d) / c;
      setState(() {
        result = '${volume.display()} mL';
        formula =
            '${w.display()} kg × ${d.display()} mg/kg ÷ ${c.display()} mg/mL';
      });
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  Widget _field(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {
        result = null;
        formula = null;
      }),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Cálculo rápido de dosis',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Operación matemática con valores capturados por ti. No recomienda ni valida una dosis veterinaria; confirma unidades, producto y pauta antes de usar el resultado.',
      ),
      const SizedBox(height: 16),
      _field('Peso del paciente (kg)', weight),
      _field('Dosis indicada por el MVZ (mg/kg)', dose),
      _field('Concentración del producto (mg/mL)', concentration),
      FilledButton.icon(
        onPressed: calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Calcular volumen'),
      ),
      if (error case final e?)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            e,
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
              ],
            ),
          ),
        ),
      ],
    ],
  );
}
