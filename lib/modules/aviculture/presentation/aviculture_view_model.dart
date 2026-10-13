import 'package:flutter/foundation.dart';
import '../../doses/domain/quantity.dart';
import '../data/aviculture_repository.dart';
import '../domain/aviculture_engine.dart';

class AvicultureViewModel extends ChangeNotifier {
  final engine = const AvicultureEngine();
  String output = '', error = '';
  void publish(VoidCallback change) {
    change();
    notifyListeners();
  }

  void clear() {
    output = '';
    error = '';
    notifyListeners();
  }

  void calculate(
    List<AvicultureParameter> parameters, {
    required Map<String, String> values,
    required String mode,
    required String system,
    required String dimensions,
  }) {
    Quantity q(String key) => Quantity.parse(values[key] ?? '');
    try {
      final lines = <String>[];
      final space = parameters.firstWhere(
        (p) => p.label == 'densidad' || p.label == 'espacio_por_ave',
      );
      final design = q(space.label);
      engine.positive(design);
      lines.addAll(space.warnings(design));
      final cm2 = engine.areaPerBird(design, space.unit);
      lines.add(
        'Conversión: 10 000 / valor = ${engine.reciprocalSpace(design).display()} ${space.unit == 'cm2' ? 'aves/m²' : 'cm²/ave'} (visualización aproximada).',
      );
      if (mode == 'capacidad') {
        final area = engine.usableArea(q('length'), q('width'), dimensions);
        final floors = engine.integer(q('floors'));
        if (system == 'piso' && floors != BigInt.one) {
          throw const FormatException(
            'En sistema piso usa 1 superficie por módulo.',
          );
        }
        final count = engine.capacity(
          area,
          design,
          space.unit,
          floors: q('floors'),
          modules: q('modules'),
          houses: q('houses'),
        );
        final perSurface = engine.floor(area / cm2);
        lines.addAll([
          '1. Superficie útil por módulo y piso: ${q('length').display()} × ${q('width').display()} $dimensions${dimensions == 'm' ? ' × 10 000' : ''} = ${area.display()} cm².',
          '2. Aves por superficie independiente: piso(${area.display()} cm² / ${cm2.display()} cm²/ave) = $perSurface aves.',
          '3. Superficies: $floors pisos × ${q('modules').display()} módulos por caseta × ${q('houses').display()} casetas.',
          'Capacidad geométrica: $count aves. Se redondea hacia abajo en cada superficie; no se agrupan sobrantes entre jaulas.',
        ]);
      } else {
        final birds = q('birds');
        engine.integer(birds);
        final step = q('step');
        engine.positive(step);
        final area =
            engine.requiredArea(birds, design, space.unit) /
            Quantity.parse('10000');
        lines.add(
          'Área: ${birds.display()} aves × ${cm2.display()} cm²/ave / 10 000 = ${area.display()} m² (aproximado; cálculo racional exacto).',
        );
        // Required area must not be displayed rounded down: explicit user step.
        final areaStep = q('area_step');
        lines.add(
          'Área necesaria, redondeada arriba a ${areaStep.display()} m²: ${engine.upward(area, areaStep).display(places: 9)} m².',
        );
        for (final p in parameters.where((p) => p.label.endsWith('_lineal'))) {
          final v = q(p.label);
          engine.positive(v);
          lines.addAll(p.warnings(v));
          final result = engine.linearMeters(birds, v, step);
          lines.add(
            '${p.label.replaceAll('_', ' ')}: ${birds.display()} × ${v.display()} cm/ave / 100; redondeo arriba a ${step.display()} m = ${result.display(places: 9)} m.',
          );
        }
      }
      publish(() {
        output = lines.join('\n\n');
        error = '';
      });
    } catch (e) {
      publish(() {
        output = '';
        error = e is FormatException ? e.message : 'Revisa los campos.';
      });
    }
  }

  void equipment(AvicultureParameter p, Map<String, String> values) {
    Quantity q(String key) => Quantity.parse(values[key] ?? '');
    try {
      final birds = q('birds');
      final design = q(p.label);
      final count = engine.equipment(birds, design);
      publish(() {
        error = '';
        output = [
          ...p.warnings(design),
          'Etapa indicada en fuente: ${p.fields['etapa']}. Confirma que corresponde a este lote; no se extrapola automáticamente a las semanas seleccionadas.',
          'Equipos: techo(${birds.display()} aves / ${design.display()} aves/unidad) = $count unidades de ${p.label.replaceAll('_', ' ')}.',
          'Fuente: ${p.fields['fuente']}. ${p.fields['nota'] ?? ''}',
        ].join('\n\n');
      });
    } catch (e) {
      publish(() {
        output = '';
        error = e is FormatException ? e.message : 'Revisa los campos.';
      });
    }
  }
}
