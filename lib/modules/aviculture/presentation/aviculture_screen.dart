import 'package:flutter/material.dart';
import '../../doses/domain/quantity.dart';
import '../data/aviculture_repository.dart';
import '../domain/aviculture_engine.dart';
import 'aviculture_view_model.dart';

class AvicultureScreen extends StatefulWidget {
  const AvicultureScreen({super.key});
  @override
  State<AvicultureScreen> createState() => _AvicultureScreenState();
}

class _AvicultureScreenState extends State<AvicultureScreen> {
  final repository = AvicultureRepository();
  final engine = const AvicultureEngine();
  late final future = repository.load();
  final inputs = <String, TextEditingController>{};
  String stage = 'crianza',
      system = 'piso',
      mode = 'capacidad',
      dimensions = 'm';
  final model = AvicultureViewModel();
  String get output => model.output;
  String get error => model.error;
  Map<String, String> get captured => {
    for (final e in inputs.entries) e.key: e.value.text,
  };
  TextEditingController controller(String key) =>
      inputs.putIfAbsent(key, TextEditingController.new);
  Quantity q(String key) => Quantity.parse(controller(key).text);
  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    model.dispose();
    super.dispose();
  }

  void reset() {
    setState(() {
      model.clear();
    });
  }

  void selection(VoidCallback change) {
    setState(() {
      change();
      model.clear();
      for (final c in inputs.values) {
        c.clear();
      }
    });
  }

  Widget input(String key, String label, {String? help}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller(key),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, helperText: help),
      onChanged: (_) => reset(),
    ),
  );
  Widget parameter(AvicultureParameter p) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.label.replaceAll('_', ' '),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Etapa de la fuente: ${p.fields['etapa']}'),
          Text('Rango: ${p.min}–${p.max} ${p.unit} · ${p.fields['estado']}'),
          Text(
            'Referencia sin verificar',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Text('Fuente: ${p.fields['fuente']}'),
          if ((p.fields['nota'] ?? '').isNotEmpty) Text(p.fields['nota']!),
          if (_outsideRange(p))
            Text(
              'Valor fuera del rango de la fuente',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          input(
            p.label,
            'Valor de diseño (${p.unit})',
            help: 'Elige expresamente; la app no selecciona el valor.',
          ),
        ],
      ),
    ),
  );
  bool _outsideRange(AvicultureParameter p) {
    try {
      final value = q(p.label);
      return value.compareTo(Quantity.parse(p.min)) < 0 ||
          value.compareTo(Quantity.parse(p.max)) > 0;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Capacidad e instalaciones avícolas')),
    body: FutureBuilder<AvicultureCatalog>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('No se pudieron cargar los parámetros avícolas.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final catalog = snapshot.data!;
        final parameters = catalog.capacity
            .where(
              (p) =>
                  p.fields['etapa'] == stage &&
                  (p.fields['sistema'] == system ||
                      p.fields['sistema'] == 'ambos'),
            )
            .toList();
        final space = parameters
            .where((p) => ['densidad', 'espacio_por_ave'].contains(p.label))
            .single;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Gallinas · Referencias v1 sin verificar. Estimación geométrica; no certifica bienestar, ventilación ni capacidad operativa. No se elige un valor de diseño automáticamente.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: stage,
              decoration: const InputDecoration(labelText: 'Etapa'),
              items: const [
                DropdownMenuItem(
                  value: 'crianza',
                  child: Text('Crianza · 0–6 semanas'),
                ),
                DropdownMenuItem(
                  value: 'desarrollo',
                  child: Text('Desarrollo · 7–12 semanas'),
                ),
                DropdownMenuItem(
                  value: 'postura',
                  child: Text('Postura · 13+ semanas'),
                ),
              ],
              onChanged: (v) {
                if (v != null) selection(() => stage = v);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: system,
              decoration: const InputDecoration(labelText: 'Sistema'),
              items: const [
                DropdownMenuItem(value: 'piso', child: Text('Piso')),
                DropdownMenuItem(
                  value: 'jaula_bateria',
                  child: Text('Jaula / batería'),
                ),
              ],
              onChanged: (v) {
                if (v != null) selection(() => system = v);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(
                labelText: 'Dirección del cálculo',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'capacidad',
                  child: Text('Dimensiones → aves'),
                ),
                DropdownMenuItem(
                  value: 'equipo',
                  child: Text('Aves → área y equipos'),
                ),
              ],
              onChanged: (v) {
                if (v != null) selection(() => mode = v);
              },
            ),
            parameter(space),
            if (mode == 'capacidad') ...[
              DropdownButtonFormField<String>(
                initialValue: dimensions,
                decoration: const InputDecoration(
                  labelText: 'Unidad de las dimensiones',
                ),
                items: const [
                  DropdownMenuItem(value: 'm', child: Text('Metros')),
                  DropdownMenuItem(value: 'cm', child: Text('Centímetros')),
                ],
                onChanged: (v) {
                  if (v != null) selection(() => dimensions = v);
                },
              ),
              input('length', 'Largo útil de una superficie'),
              input('width', 'Ancho útil de una superficie'),
              input(
                'floors',
                'Pisos útiles por módulo',
                help: system == 'piso'
                    ? 'En piso: 1. No contar techos o zonas no utilizables.'
                    : 'Superficies independientes con iguales dimensiones.',
              ),
              input('modules', 'Módulos iguales por caseta'),
              input('houses', 'Casetas iguales'),
            ] else ...[
              input('birds', 'Número de aves'),
              input(
                'area_step',
                'Incremento para redondear área (m²)',
                help: 'Precisión elegida por ti; siempre hacia arriba.',
              ),
              input(
                'step',
                'Incremento para redondear longitudes (m)',
                help: 'Precisión elegida por ti; siempre hacia arriba.',
              ),
              for (final p in parameters.where(
                (p) => p.label.endsWith('_lineal'),
              ))
                parameter(p),
            ],
            FilledButton(
              onPressed: () {
                model.calculate(
                  parameters,
                  values: captured,
                  mode: mode,
                  system: system,
                  dimensions: dimensions,
                );
                setState(() {});
              },
              child: Text(
                mode == 'capacidad'
                    ? 'Calcular capacidad'
                    : 'Calcular área y longitudes',
              ),
            ),
            if (mode == 'equipo') ...[
              const SizedBox(height: 12),
              const Text(
                'Equipos: elige el aplicable al lote. Las etapas de estos apuntes son distintas de las bandas por semanas; se conservan tal como llegaron.',
              ),
              for (final p in catalog.equipment) ...[
                parameter(p),
                OutlinedButton(
                  onPressed: () {
                    model.equipment(p, captured);
                    setState(() {});
                  },
                  child: Text('Calcular ${p.label.replaceAll('_', ' ')}'),
                ),
              ],
            ],
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (output.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(output),
                ),
              ),
            ExpansionTile(
              title: const Text('Datos pendientes e incubación'),
              children: [
                for (final p in catalog.additional['parametros'] as List)
                  ListTile(
                    title: Text('${p['parametro']}'),
                    subtitle: const Text(
                      'Sin valor, unidad o fuente disponibles · pendiente',
                    ),
                  ),
                for (final p in catalog.additional['incubacion'] as List)
                  ListTile(
                    title: Text(
                      '${p['parametro']}: ${p['valor']} ${p['unidad']}',
                    ),
                    subtitle: Text('${p['fuente']} · ${p['estado']}'),
                  ),
              ],
            ),
            const Text(
              'Fase 2 pendiente: redistribución, vínculo con medicación en agua/alimento y retiro del huevo. Estos cálculos no crean tratamientos.',
            ),
          ],
        );
      },
    ),
  );
}
