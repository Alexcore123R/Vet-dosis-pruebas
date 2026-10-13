import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/aviculture/data/aviculture_repository.dart';
import 'package:vetdosis_pro/modules/aviculture/domain/aviculture_engine.dart';
import 'package:vetdosis_pro/modules/incubation/data/incubation_repository.dart';
import 'package:vetdosis_pro/modules/incubation/domain/incubation_engine.dart';
import 'package:vetdosis_pro/modules/incubation/presentation/incubation_view_model.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';

void main() {
  Quantity q(String value) => Quantity.parse(value);
  const av = AvicultureEngine();
  const inc = IncubationEngine();
  final capacity = AvicultureCatalog.parseCsv(
    File(
      'assets/clinical/aviculture/capacidad_avicola.v1.csv',
    ).readAsStringSync(),
  );
  final equipment = AvicultureCatalog.parseCsv(
    File(
      'assets/clinical/aviculture/equipos_avicola.v1.csv',
    ).readAsStringSync(),
  );
  final incubation = IncubationCatalog(
    jsonDecode(
          File(
            'assets/clinical/incubation/referencias.v1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  final expectedCapacity = {
    'crianza/piso': [1200, 1500],
    'desarrollo/piso': [800, 1000],
    'postura/piso': [600, 800],
    'crianza/jaula_bateria': [4, 2],
    'desarrollo/jaula_bateria': [2, 2],
    'postura/jaula_bateria': [2, 1],
  };
  final expectedAreas = {
    'crianza/piso': ['83,34', '66,67'],
    'desarrollo/piso': ['125', '100'],
    'postura/piso': ['166,67', '125'],
    'crianza/jaula_bateria': ['25', '35'],
    'desarrollo/jaula_bateria': ['35', '45'],
    'postura/jaula_bateria': ['45', '55'],
  };
  final expectedLinear = {
    'crianza/bebedero_lineal': '15',
    'crianza/comedero_lineal': '30',
    'desarrollo/bebedero_lineal': '25',
    'desarrollo/comedero_lineal': '50',
    'postura/bebedero_lineal': '50',
    'postura/comedero_lineal': '70',
  };
  for (final p in capacity) {
    final key = '${p.fields['etapa']}/${p.fields['sistema']}';
    if (p.fields['sistema'] == 'ambos') {
      test('CSV 1000 aves: ${p.fields['etapa']}/${p.label}', () {
        expect(
          av.linearMeters(q('1000'), q(p.min), q('0.01')).display(),
          expectedLinear['${p.fields['etapa']}/${p.label}'],
        );
      });
      continue;
    }
    for (var i = 0; i < 2; i++) {
      final design = i == 0 ? p.min : p.max;
      test('CSV capacidad $key diseño $design', () {
        final area = p.unit == 'cm2'
            ? q('1000')
            : av.usableArea(q('10'), q('10'), 'm');
        expect(
          av.capacity(
            area,
            q(design),
            p.unit,
            floors: q('1'),
            modules: q('1'),
            houses: q('1'),
          ),
          BigInt.from(expectedCapacity[key]![i]),
        );
      });
      test('CSV área 1000 aves $key diseño $design', () {
        final area = av.requiredArea(q('1000'), q(design), p.unit) / q('10000');
        expect(av.upward(area, q('0.01')).display(), expectedAreas[key]![i]);
      });
    }
  }
  final expectedEquipment = {
    'minitolva': [10, 10],
    'vitrolero': [10, 10],
    'bebedero_campana': [13, 10],
    'comedero_automatico_plato': [23, 19],
    'bebedero_niple': [125, 84],
    'bebedero_copita': [167, 125],
    'criadora_calefactor': [1, 1],
  };
  for (final p in equipment) {
    test('CSV equipos para 1000 aves: ${p.label}, ambos extremos', () {
      expect(
        av.equipment(q('1000'), q(p.min)),
        BigInt.from(expectedEquipment[p.label]![0]),
      );
      expect(
        av.equipment(q('1000'), q(p.max)),
        BigInt.from(expectedEquipment[p.label]![1]),
      );
      expect(p.warnings(q(p.min)), hasLength(1));
    });
  }
  final expectedEggs = {
    3: '63,44',
    6: '62,27',
    9: '61,295',
    12: '59,41',
    15: '58,045',
    18: '56,68',
  };
  for (final entry in expectedEggs.entries) {
    test('Curva subida: huevo 65 g, día ${entry.key}', () {
      expect(
        inc.expectedEgg(q('65'), incubation.points[entry.key]!).display(),
        entry.value,
      );
    });
  }
  test('Curva real: comparación, día ausente y muestra no confirmada', () {
    final model = IncubationViewModel()..catalog = incubation;
    final inputs = {'initial': '65', 'current': '58.5', 'day': '18'};
    model.calculate('loss', inputs, sameSample: true);
    expect(model.output, contains('−2,8 puntos'));
    model.calculate('loss', {...inputs, 'day': '4'}, sameSample: true);
    expect(model.output, contains('No hay un punto documentado'));
    model.calculate('loss', inputs);
    expect(model.output, isEmpty);
    expect(model.error, isNotEmpty);
    model.dispose();
  });
  test('Datos conservan advertencias y parámetros ausentes', () {
    expect(capacity, hasLength(12));
    expect(equipment, hasLength(7));
    for (final p in [...capacity, ...equipment]) {
      expect(p.fields['fuente'], isNotEmpty);
      expect(p.warnings(q(p.min)), hasLength(1));
      expect(p.warnings(q(p.max) * q('2')), hasLength(2));
    }
    final missing =
        jsonDecode(
              File(
                'assets/clinical/aviculture/pendientes_avicola.v1.json',
              ).readAsStringSync(),
            )['parametros']
            as List;
    expect(missing, hasLength(3));
    expect(missing.every((p) => p['min'] == null && p['max'] == null), isTrue);
    expect(
      incubation.parameters.every((p) => p['estado'] == 'sin_verificar'),
      isTrue,
    );
  });
}
