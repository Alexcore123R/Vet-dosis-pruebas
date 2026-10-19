import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../domain/feeding_calculation.dart';

class FeedingPanel extends StatefulWidget {
  const FeedingPanel({super.key});
  @override
  State<FeedingPanel> createState() => _FeedingPanelState();
}

class _FeedingPanelState extends State<FeedingPanel> {
  final inputs = List.generate(4, (_) => TextEditingController());
  FeedingCalculation? result;
  String? error;
  @override
  void dispose() {
    for (final input in inputs) {
      input.dispose();
    }
    super.dispose();
  }

  double number(int index) {
    final raw = inputs[index].text.trim();
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(raw)) {
      throw const FormatException('Usa números sin separadores de miles.');
    }
    return double.parse(raw.replaceAll(',', '.'));
  }

  void calculate() => setState(() {
    result = null;
    error = null;
    try {
      final animals = int.tryParse(inputs[0].text.trim());
      final meals = int.tryParse(inputs[3].text.trim());
      if (animals == null || meals == null) {
        throw const FormatException(
          'Peces y raciones deben ser números enteros.',
        );
      }
      result = FeedingCalculation(
        animals: animals,
        averageGrams: number(1),
        dailyPercent: number(2),
        meals: meals,
      );
    } on FormatException catch (e) {
      error = e.message;
    }
  });
  @override
  Widget build(BuildContext context) {
    final r = result;
    return WorkspacePanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Biomasa y ración diaria',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Estimación de sesión para Tilapia. Usa un peso promedio representativo del lote actual. No guarda registros ni confirma que sea adecuado alimentar.',
            ),
            for (final (i, label) in [
              'Peces actuales',
              'Peso promedio por pez (g)',
              'Tasa diaria (% de biomasa)',
              'Número de raciones al día',
            ].indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  key: ValueKey('feeding-input-$i'),
                  controller: inputs[i],
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: i == 1 || i == 2,
                  ),
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {
                    result = null;
                    error = null;
                  }),
                ),
              ),
            const Text(
              'La tasa se captura expresamente; esta herramienta no prescribe porcentajes por talla, temperatura o calidad del agua.',
            ),
            FilledButton(
              onPressed: calculate,
              child: const Text('Calcular ración'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (r != null) ...[
              Text('Biomasa estimada: ${r.biomassKg.toStringAsFixed(3)} kg'),
              Text(
                'Alimento diario calculado: ${r.dailyKg.toStringAsFixed(3)} kg',
              ),
              Text(
                'Por ración (${r.meals} iguales): ${r.perMealKg.toStringAsFixed(3)} kg',
              ),
              Text(
                'Procedimiento: ${r.animals} × ${r.averageGrams} g ÷ 1000 = biomasa en kg; biomasa × ${r.dailyPercent} ÷ 100 = alimento diario; alimento diario ÷ ${r.meals} = cada ración.',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Base: biomasa × tasa de alimentación. Las tablas por talla y temperatura de los apuntes aportados están pendientes de verificación; no se aplican automáticamente.',
            ),
          ],
        ),
      ),
    );
  }
}
