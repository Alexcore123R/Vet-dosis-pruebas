import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../domain/growth_calculation.dart';

class GrowthPanel extends StatefulWidget {
  const GrowthPanel({super.key, required this.showCosts});
  final bool showCosts;
  @override
  State<GrowthPanel> createState() => _GrowthPanelState();
}

class _GrowthPanelState extends State<GrowthPanel> {
  final inputs = List.generate(6, (_) => TextEditingController());
  bool comparable = false;
  GrowthCalculation? result;
  String? error;

  @override
  void didUpdateWidget(covariant GrowthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showCosts != widget.showCosts) {
      inputs[5].clear();
      result = null;
      error = null;
    }
  }

  @override
  void dispose() {
    for (final input in inputs) {
      input.dispose();
    }
    super.dispose();
  }

  double number(int i) {
    final raw = inputs[i].text.trim();
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(raw)) {
      throw const FormatException('Usa números sin separadores de miles.');
    }
    return double.parse(raw.replaceAll(',', '.'));
  }

  void calculate() {
    setState(() {
      result = null;
      error = null;
      try {
        if (!comparable) {
          throw const FormatException(
            'Confirma que se midió el mismo grupo sin movimientos.',
          );
        }
        final animals = int.tryParse(inputs[0].text.trim());
        final days = int.tryParse(inputs[1].text.trim());
        if (animals == null || days == null) {
          throw const FormatException(
            'Animales y días deben ser números enteros.',
          );
        }
        result = GrowthCalculation(
          animals: animals,
          days: days,
          initialKg: number(2),
          finalKg: number(3),
          consumedKg: number(4),
          feedCost: widget.showCosts && inputs[5].text.trim().isNotEmpty
              ? number(5)
              : null,
        );
      } on FormatException catch (e) {
        error = e.message;
      }
    });
  }

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
              'Indicadores de crecimiento y engorda',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Cálculo de sesión: no guarda registros de granja. Captura el peso total del mismo grupo al inicio y al final del periodo.',
            ),
            for (final (index, label) in [
              (0, 'Animales pesados'),
              (1, 'Días transcurridos'),
              (2, 'Peso total inicial (kg)'),
              (3, 'Peso total final (kg)'),
              (4, 'Alimento consumido (kg)'),
              if (widget.showCosts) (5, 'Costo de alimento (MXN)'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  key: ValueKey('growth-input-$index'),
                  controller: inputs[index],
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: index >= 2,
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: index == 5
                        ? 'Total consumido del periodo · opcional'
                        : null,
                  ),
                  onChanged: (_) => setState(() {
                    result = null;
                    error = null;
                  }),
                ),
              ),
            const Text(
              'Consumo medido, descontando sobrantes y desperdicio; no equivale automáticamente al alimento servido.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Es el mismo grupo, sin entradas, salidas ni bajas durante el periodo.',
              ),
              value: comparable,
              onChanged: (value) => setState(() {
                comparable = value ?? false;
                result = null;
                error = null;
              }),
            ),
            const Text(
              'Si hubo movimientos o no aumentó el peso, esta calculadora no es aplicable.',
            ),
            FilledButton(
              onPressed: calculate,
              child: const Text('Calcular indicadores'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (r != null) ...[
              const SizedBox(height: 12),
              Text('Ganancia de peso vivo: ${r.gainKg.toStringAsFixed(3)} kg'),
              Text(
                'Ganancia diaria por animal: ${r.dailyPerAnimalKg.toStringAsFixed(3)} kg/día',
              ),
              Text(
                'Conversión alimenticia: ${r.conversion.toStringAsFixed(3)} kg alimento/kg ganado',
              ),
              if (widget.showCosts && r.costPerGainKg != null)
                Text(
                  'Costo de alimento por kg ganado: ${r.costPerGainKg!.toStringAsFixed(2)} MXN',
                ),
              Text(
                'Procedimiento: (${r.finalKg} − ${r.initialKg}) = ${r.gainKg} kg; ganancia diaria = ganancia ÷ ${r.animals} ÷ ${r.days}; conversión = ${r.consumedKg} ÷ ganancia.',
              ),
              if (widget.showCosts && r.feedCost != null)
                Text(
                  'Costo por kg ganado = ${r.feedCost} MXN ÷ ${r.gainKg} kg. No incluye otros costos de granja ni rendimiento de canal.',
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Base documental: Cruzas Razas.pdf, Producción de Cerdos, UDG/CUCBA, p. 53. Valores capturados por el usuario; no se califican como metas de rendimiento.',
            ),
          ],
        ),
      ),
    );
  }
}
