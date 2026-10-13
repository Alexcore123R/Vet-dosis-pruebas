import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'incubation_view_model.dart';

class IncubationScreen extends StatefulWidget {
  const IncubationScreen({super.key});
  @override
  State<IncubationScreen> createState() => _IncubationScreenState();
}

class _IncubationScreenState extends State<IncubationScreen> {
  final model = IncubationViewModel();
  final fields = <String, TextEditingController>{};
  String tool = 'chick', stockUnit = 'mg_ml', targetUnit = 'mg_l';
  bool sameSample = false, reviewed = false;
  TextEditingController controller(String id) =>
      fields.putIfAbsent(id, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void change(VoidCallback action) {
    setState(action);
    model.clear();
  }

  Widget input(String key, String label, {bool numeric = true, String? help}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: controller(key),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label, helperText: help),
          onChanged: (_) => change(() {
            if (tool == 'dilution') reviewed = false;
            if (tool == 'loss') sameSample = false;
          }),
        ),
      );
  Widget unit(String value, String label, ValueChanged<String> select) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 'mg_ml', child: Text('mg/ml')),
          DropdownMenuItem(value: 'mg_l', child: Text('mg/L')),
          DropdownMenuItem(
            value: 'percent_mv',
            child: Text('% m/v · g por 100 ml'),
          ),
          DropdownMenuItem(
            value: 'ppm_mg_l',
            child: Text('ppm con equivalencia mg/L documentada'),
          ),
        ],
        onChanged: (v) {
          if (v != null) {
            change(() {
              select(v);
              reviewed = false;
            });
          }
        },
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Incubación · Gallinas')),
    body: AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        if (model.busy) return const Center(child: CircularProgressIndicator());
        if (model.catalog == null) return Center(child: Text(model.error));
        final catalog = model.catalog!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Referencias sin verificar · Simulación matemática',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const Text(
              'No sustituye un perfil validado de línea genética y equipo. No controla incubadoras ni prescribe desinfectantes.',
            ),
            DropdownButtonFormField<String>(
              initialValue: tool,
              decoration: const InputDecoration(labelText: 'Calculadora'),
              items: const [
                DropdownMenuItem(
                  value: 'chick',
                  child: Text('Peso estimado del pollito'),
                ),
                DropdownMenuItem(
                  value: 'loss',
                  child: Text('Pérdida de peso del huevo'),
                ),
                DropdownMenuItem(
                  value: 'dilution',
                  child: Text('Dilución masa/volumen'),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  change(() {
                    tool = v;
                    sameSample = false;
                    reviewed = false;
                    for (final c in fields.values) {
                      c.clear();
                    }
                  });
                }
              },
            ),
            if (tool == 'chick') ...[
              input('egg', 'Peso del huevo (g)'),
              input(
                'yield',
                'Porcentaje de rendimiento elegido (%)',
                help:
                    'Sin valor predeterminado; no asumir 70% para todas las líneas.',
              ),
            ],
            if (tool == 'loss') ...[
              input('initial', 'Peso inicial neto (g)'),
              input('current', 'Peso actual neto (g)'),
              input('day', 'Día entero de incubación'),
              CheckboxListTile(
                value: sameSample,
                onChanged: (v) => change(() => sameSample = v ?? false),
                title: const Text(
                  'Mismo huevo o muestra comparable, sin tara y con huevos retirados corregidos',
                ),
              ),
              Text(
                'Puntos de clase sin verificar: ${catalog.points.entries.map((e) => 'día ${e.key}: ${e.value.display()}%').join('; ')}.',
              ),
              const Text(
                'Entre puntos: solo pérdida observada. No se inventan valores diarios ni se promedian fuentes.',
              ),
            ],
            if (tool == 'dilution') ...[
              input('product', 'Producto y presentación', numeric: false),
              input(
                'source',
                'Fuente del objetivo y composición',
                numeric: false,
              ),
              input('stock', 'Concentración inicial del MISMO activo'),
              unit(stockUnit, 'Unidad inicial', (v) => stockUnit = v),
              input('target', 'Concentración objetivo del MISMO activo'),
              unit(targetUnit, 'Unidad objetivo', (v) => targetUnit = v),
              input(
                'final_ml',
                'Volumen final de mezcla (ml)',
                help: 'Incluye producto y diluyente; no es solo agua añadida.',
              ),
              const Text(
                'ppm sin base explícita, % m/m y % v/v no se convierten automáticamente. No se usa la tabla genérica como objetivo comercial.',
              ),
              CheckboxListTile(
                value: reviewed,
                onChanged: (v) => change(() => reviewed = v ?? false),
                title: const Text(
                  'Comprobé en el prospecto el activo, las bases de concentración y el objetivo para ese uso',
                ),
              ),
            ],
            FilledButton(
              onPressed: () => model.calculate(
                tool,
                {for (final e in fields.entries) e.key: e.value.text},
                sameSample: sameSample,
                reviewed: reviewed,
                stockUnit: stockUnit,
                targetUnit: targetUnit,
              ),
              child: const Text('Calcular'),
            ),
            if (model.error.isNotEmpty)
              Text(
                model.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (model.output.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(model.output),
                ),
              ),
            ExpansionTile(
              title: const Text('Referencias y contextos · sin verificar'),
              children: [
                for (final p in catalog.parameters)
                  ListTile(
                    title: Text(
                      '${p['parametro']}: ${p['min']}–${p['max']} ${p['unidad']}',
                    ),
                    subtitle: Text(
                      '${p['contexto']}\n${p['nota']}\n${catalog.source(p['fuente_id'] as String)['titulo']} · ${catalog.source(p['fuente_id'] as String)['localizador']}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Abrir fuente externa',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () async {
                        final url = Uri.tryParse(
                          catalog.source(p['fuente_id'] as String)['url']
                              as String,
                        );
                        if (url != null && url.scheme == 'https') {
                          final opened = await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No se pudo abrir la fuente.'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text(
                'Productos encontrados · consulta, no protocolos',
              ),
              children: [
                for (final p in catalog.data['productos_candidatos'] as List)
                  ListTile(
                    title: Text(
                      '${p['nombre'] ?? (p['nombre_originales'] as List).join(' / ')}',
                    ),
                    subtitle: Text('${p['nota']}\nEstado: ${p['estado']}'),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('Datos pendientes y discrepancias'),
              children: [
                const ListTile(
                  title: Text(
                    'La diapositiva combina 35 °C con 99,5–100 °F; no son equivalentes. No se corrige un objetivo técnico por suposición.',
                  ),
                ),
                for (final p in catalog.data['pendientes'] as List)
                  ListTile(title: Text('$p')),
              ],
            ),
            const Text(
              'Las capturas y resultados no se guardan ni crean tratamientos. Cambiar entradas invalida el resultado; no hay alertas ambientales automáticas.',
            ),
          ],
        );
      },
    ),
  );
}
