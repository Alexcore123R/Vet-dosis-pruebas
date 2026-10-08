import 'dart:convert';
import 'dart:math' as math;
import '../../doses/domain/catalog.dart';
import '../../doses/domain/dose_engine.dart';
import '../../doses/domain/quantity.dart';

class CalculationField {
  CalculationField(this.id, this.label, this.zero);
  final String id, label;
  final bool zero;
}

class CalculationDefinition {
  CalculationDefinition(this.id, this.title, this.inputs, this.outputs);
  final String id, title;
  final List<CalculationField> inputs;
  final Map<String, String> outputs;
}

class ClinicalReference {
  ClinicalReference(this.data, this.evidence);
  final Map<String, dynamic> data;
  final Evidence evidence;
  String get id => data['id'] as String;
  String get type => data['tipo'] as String;
  String get species => data['especie'] as String;
  String get title => data['titulo'] as String;
  factory ClinicalReference.read(Map<String, dynamic> m) {
    for (final key in ['id', 'tipo', 'especie', 'titulo']) {
      requiredText(m, key);
    }
    final evidence = Evidence.read(m);
    switch (m['tipo']) {
      case 'constante':
        requiredText(m, 'unidad');
        requiredText(m, 'parametro');
        final min = optionalQuantity(m, 'min'),
            max = optionalQuantity(m, 'max');
        if (min != null && max != null && min.compareTo(max) > 0) {
          throw const FormatException('Rango invertido.');
        }
      case 'retiro':
        for (final key in [
          'producto_id',
          'presentacion',
          'via',
          'destino',
          'jurisdiccion',
        ]) {
          requiredText(m, key);
        }
        if (m['jurisdiccion'] != 'MX' ||
            !['horas', 'dias'].contains(m['unidad'])) {
          throw const FormatException(
            'Retiro: jurisdicción o unidad incompatible.',
          );
        }
        final value = m['tiempo'];
        if (value != null &&
            (value is! String || Quantity.parse(value).n < BigInt.zero)) {
          throw const FormatException('Tiempo de retiro inválido.');
        }
      case 'metabolico':
        final exponent = optionalQuantity(m, 'exponente');
        if (exponent != null && exponent.compareTo(Quantity.parse('1')) > 0) {
          throw const FormatException('Exponente fuera del intervalo (0,1].');
        }
      case 'ajuste':
        requiredText(m, 'farmaco_id');
        requiredText(m, 'presentacion_id');
        requiredText(m, 'condicion');
        optionalQuantity(m, 'factor');
      case 'protocolo':
        for (final stage in readList(m, 'etapas')) {
          if (![
            'premedicacion',
            'induccion',
            'analgesia',
            'recuperacion',
          ].contains(stage['etapa'])) {
            throw const FormatException('Etapa no compatible.');
          }
          requiredText(stage, 'dosis_id');
          requiredText(stage, 'presentacion_id');
          optionalQuantity(stage, 'dosis_mg_kg');
        }
      default:
        throw const FormatException('Tipo de referencia no compatible.');
    }
    return ClinicalReference(Map.unmodifiable(m), evidence);
  }
  String evaluate(Quantity value) {
    if (type != 'constante') throw const FormatException('No es constante.');
    final min = optionalQuantity(data, 'min'),
        max = optionalQuantity(data, 'max');
    if (!evidence.verified || min == null || max == null) {
      return 'Sin referencia verificada completa; no se clasifica.';
    }
    if (value.compareTo(min) < 0) return 'Por debajo del rango de referencia.';
    if (value.compareTo(max) > 0) return 'Por encima del rango de referencia.';
    return 'Dentro del rango de referencia; no equivale a diagnóstico.';
  }

  double metabolicWeight(Quantity weight) {
    final exponent = optionalQuantity(data, 'exponente');
    if (type != 'metabolico' ||
        !evidence.verified ||
        exponent == null ||
        !weight.positive) {
      throw const FormatException(
        'Referencia metabólica verificada y peso positivo requeridos.',
      );
    }
    final value = math
        .pow(
          weight.n.toDouble() / weight.d.toDouble(),
          exponent.n.toDouble() / exponent.d.toDouble(),
        )
        .toDouble();
    if (!value.isFinite || value <= 0) {
      throw const FormatException('Resultado metabólico inválido.');
    }
    return value;
  }

  List<({String stage, String drug, String presentation, DoseResult result})>
  protocol(
    DoseCatalog catalog,
    Quantity weight,
    Quantity step, {
    String breed = '',
    List<String> conditions = const [],
  }) {
    if (type != 'protocolo' || !evidence.verified) {
      throw const FormatException('Protocolo verificado requerido.');
    }
    final results =
        <
          ({String stage, String drug, String presentation, DoseResult result})
        >[];
    for (final stage in readList(data, 'etapas')) {
      final drugs = catalog.drugs
          .where((d) => d.id == stage['dosis_id'] && d.species == species)
          .toList();
      if (drugs.length != 1) {
        throw const FormatException('Falta el fármaco/especie del protocolo.');
      }
      final drug = drugs.single;
      final presentations = drug.presentations
          .where((p) => p.id == stage['presentacion_id'])
          .toList();
      final dose = optionalQuantity(stage, 'dosis_mg_kg');
      if (presentations.length != 1 || dose == null) {
        throw const FormatException(
          'Falta presentación o dosis del protocolo.',
        );
      }
      results.add((
        stage: stage['etapa'] as String,
        drug: drug.name,
        presentation: presentations.single.brand,
        result: const DoseEngine().calculate(
          drug: drug,
          presentation: presentations.single,
          weightKg: weight,
          doseMgKg: dose,
          syringeStepMl: step,
          breed: breed,
          conditions: conditions,
        ),
      ));
    }
    if (results.isEmpty) throw const FormatException('Protocolo sin etapas.');
    return List.unmodifiable(results);
  }
}

class CalculationCatalog {
  CalculationCatalog(this.version, this.calculations, this.references);
  final String version;
  final List<CalculationDefinition> calculations;
  final List<ClinicalReference> references;
  factory CalculationCatalog.parse(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> || raw['schema_version'] != 1) {
      throw const FormatException('Versión M7 incompatible.');
    }
    final definitions = readList(raw, 'calculos').map((m) {
      final id = requiredText(m, 'id');
      if (![
        'fluids',
        'cri',
        'herd',
        'water',
        'feed',
        'adjustment',
      ].contains(id)) {
        throw const FormatException('Fórmula incompatible.');
      }
      final fields = readList(m, 'entradas')
          .map(
            (f) => CalculationField(
              requiredText(f, 'id'),
              requiredText(f, 'etiqueta'),
              f['permite_cero'] == true,
            ),
          )
          .toList();
      const expectedInputs = {
        'fluids': {
          'weight',
          'maintenance',
          'percent',
          'hours',
          'losses',
          'drop_factor',
        },
        'cri': {
          'weight',
          'dose',
          'concentration',
          'final_volume',
          'pump_rate',
          'drop_factor',
        },
        'herd': {'weight', 'count', 'dose', 'concentration'},
        'water': {'target', 'litres', 'strength'},
        'feed': {'target', 'tonnes', 'strength'},
        'adjustment': {'weight', 'dose', 'factor', 'concentration'},
      };
      final actualInputs = fields.map((f) => f.id).toSet();
      if (actualInputs.length != expectedInputs[id]!.length ||
          !actualInputs.containsAll(expectedInputs[id]!)) {
        throw const FormatException(
          'Las entradas no corresponden a la fórmula versionada.',
        );
      }
      final outputs = {
        for (final f in readList(m, 'salidas'))
          requiredText(f, 'id'): requiredText(f, 'etiqueta'),
      };
      if (fields.map((f) => f.id).toSet().length != fields.length) {
        throw const FormatException('Entradas repetidas.');
      }
      return CalculationDefinition(
        id,
        requiredText(m, 'titulo'),
        List.unmodifiable(fields),
        Map.unmodifiable(outputs),
      );
    }).toList();
    final refs = readList(
      raw,
      'referencias',
    ).map(ClinicalReference.read).toList();
    if (definitions.map((d) => d.id).toSet().length != definitions.length ||
        refs.map((r) => r.id).toSet().length != refs.length) {
      throw const FormatException('Identificadores repetidos.');
    }
    return CalculationCatalog(
      requiredText(raw, 'catalog_version'),
      List.unmodifiable(definitions),
      List.unmodifiable(refs),
    );
  }
}
