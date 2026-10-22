import 'package:flutter/material.dart';

import '../domain/commercial_package_dose.dart';
import '../domain/quantity.dart';

/// Separate from generic pharmacological dosing.
/// Until product labels have been verified and published as reviewed data,
/// the professional transcribes the actual package instruction manually.
class CommercialPackageDoseScreen extends StatefulWidget {
  const CommercialPackageDoseScreen({super.key});

  @override
  State<CommercialPackageDoseScreen> createState() =>
      _CommercialPackageDoseScreenState();
}

class _CommercialPackageDoseScreenState
    extends State<CommercialPackageDoseScreen> {
  final product = TextEditingController();
  final presentation = TextEditingController();
  final labelWording = TextEditingController();
  final species = TextEditingController();
  final route = TextEditingController();
  final frequency = TextEditingController();
  final animalWeight = TextEditingController();
  final labelAmount = TextEditingController();
  final perKg = TextEditingController();

  CommercialPackageUnit unit = CommercialPackageUnit.ml;
  bool proportionalConfirmed = false;
  bool tabletSplitAllowedByLabel = false;
  int tabletParts = 2;
  CommercialPackageResult? result;
  String? error;

  @override
  void dispose() {
    for (final c in [
      product, presentation, labelWording, species, route, frequency,
      animalWeight, labelAmount, perKg,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void invalidate() {
    if (result == null && error == null) return;
    setState(() {
      result = null;
      error = null;
    });
  }

  void calculate() {
    try {
      if (!proportionalConfirmed) {
        throw const FormatException(
          'Confirma que el empaque indica una cantidad estrictamente '
          'proporcional al peso. Las tablas por bandas requieren otra regla.',
        );
      }
      if (species.text.trim().isEmpty ||
          route.text.trim().isEmpty ||
          frequency.text.trim().isEmpty) {
        throw const FormatException(
          'Indica especie, vía e intervalo que figuran en el empaque.',
        );
      }
      final dose = CommercialPackageDose(
        productName: product.text,
        presentation: presentation.text,
        labelInstruction: labelWording.text,
        quantityOnLabel: Quantity.parse(labelAmount.text),
        forWeightKg: Quantity.parse(perKg.text),
        unit: unit,
      );
      final calculated = dose.calculate(
        Quantity.parse(animalWeight.text),
        tabletPartsAllowed: unit == CommercialPackageUnit.tablet &&
                tabletSplitAllowedByLabel
            ? tabletParts
            : 1,
      );
      setState(() {
        result = calculated;
        error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        result = null;
        error = e.message;
      });
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    String? helper,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => invalidate(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vademécum comercial')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Text(
            'Dosificar según el empaque',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'La pauta pertenece a la formulación y presentación específica '
            'del laboratorio. No se sustituye por la dosis general del '
            'principio activo. Hasta cotejar cada ficha, los datos se '
            'transcriben del empaque y no se precargan automáticamente.',
          ),
          const SizedBox(height: 16),
          field(product, 'Nombre comercial'),
          field(presentation, 'Presentación / concentración del empaque'),
          field(species, 'Especie indicada'),
          field(
            labelWording,
            'Posología literal del empaque',
            maxLines: 2,
            helper: 'Ejemplo aritmético ficticio: 1 tableta por 10 kg',
          ),
          field(route, 'Vía de administración indicada'),
          field(frequency, 'Intervalo o frecuencia indicada'),
          const SizedBox(height: 6),
          field(animalWeight, 'Peso del animal (kg)', numeric: true),
          field(
            labelAmount, 'Cantidad indicada en el empaque',
            numeric: true,
          ),
          field(
            perKg, 'Por cada cuántos kg',
            numeric: true,
            helper: 'Ejemplo: 10',
          ),
          DropdownButtonFormField<CommercialPackageUnit>(
            initialValue: unit,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Unidad del empaque',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final u in CommercialPackageUnit.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                unit = value;
                result = null;
                error = null;
              });
            },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: proportionalConfirmed,
            onChanged: (v) => setState(() {
              proportionalConfirmed = v ?? false;
              result = null;
              error = null;
            }),
            title: const Text(
              'La pauta del empaque es proporcional al peso',
            ),
            subtitle: const Text(
              'No usar esta calculadora para dosis fijas por animal, '
              'rangos de peso, escalas ni refuerzos vacunales.',
            ),
          ),
          if (unit == CommercialPackageUnit.tablet) ...[
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: tabletSplitAllowedByLabel,
              onChanged: (v) => setState(() {
                tabletSplitAllowedByLabel = v ?? false;
                result = null;
                error = null;
              }),
              title: const Text('El empaque permite fraccionar la tableta'),
              subtitle: const Text(
                'Confirma que ESTA presentación permite dividirla '
                '(ranura, recubrimiento, liberación y estabilidad). '
                'No se autoriza partirla por el resultado del cálculo.',
              ),
            ),
            if (tabletSplitAllowedByLabel)
              DropdownButtonFormField<int>(
                key: ValueKey(tabletParts),
                initialValue: tabletParts,
                decoration: const InputDecoration(
                  labelText: 'Fracción mínima admitida por la etiqueta',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 2, child: Text('Mitades (½)')),
                  DropdownMenuItem(value: 4, child: Text('Cuartos (¼)')),
                  DropdownMenuItem(value: 8, child: Text('Octavos (⅛)')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    tabletParts = value;
                    result = null;
                    error = null;
                  });
                },
              ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calcular cantidad según empaque'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (result != null) Card(
            margin: const EdgeInsets.only(top: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cantidad aritmética del producto',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result!.quantityText,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (result!.tablets?.fractionWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        result!.tablets!.fractionWarning!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    'No es una prescripción ni indica una administración. '
                    'No se redondean tabletas ni volúmenes. Verifica '
                    'la ficha vigente, especie, vía, contraindicaciones, '
                    'duración y tiempos de retiro cuando apliquen.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
