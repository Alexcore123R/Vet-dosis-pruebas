import 'package:flutter/material.dart';
import 'package:vetdosis_pro/modules/aviculture/presentation/aviculture_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/aviculture/domain/aviculture_engine.dart';
import 'package:vetdosis_pro/modules/aviculture/data/aviculture_repository.dart';
import 'package:vetdosis_pro/modules/aviculture/presentation/aviculture_screen.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';

void main() {
  const engine = AvicultureEngine();
  Quantity q(String s) => Quantity.parse(s);
  BigInt capacity(String space, {String floors = '1'}) => engine.capacity(
    q('1000'),
    q(space),
    'cm2',
    floors: q(floors),
    modules: q('1'),
    houses: q('1'),
  );
  test('Known capacities round down per independent surface', () {
    expect(capacity('250'), BigInt.from(4));
    expect(capacity('300'), BigInt.from(3));
    expect(capacity('300', floors: '2'), BigInt.from(6));
    expect(capacity('1200'), BigInt.zero);
  });
  test('Equipment rounds up and never omits a fractional requirement', () {
    expect(engine.equipment(q('1000'), q('10')), BigInt.from(100));
    expect(engine.equipment(q('1001'), q('10')), BigInt.from(101));
    expect(
      engine.linearMeters(q('1001'), q('1.5'), q('0.01')).display(),
      '15,02',
    );
    expect(engine.linearMeters(q('1001'), q('1.5'), q('1')).display(), '16');
  });
  test('Reciprocal density, units and count validation', () {
    expect(engine.reciprocalSpace(q('250')).display(), '40');
    expect(engine.reciprocalSpace(q('40')).display(), '250');
    expect(engine.usableArea(q('0.1'), q('1'), 'm').display(), '1000');
    expect(
      engine.requiredArea(q('1000'), q('10'), 'aves_por_m2').display(),
      '1000000',
    );
    expect(() => engine.equipment(q('1.5'), q('10')), throwsFormatException);
    expect(() => engine.equipment(q('1000'), q('0')), throwsFormatException);
    expect(() => engine.reciprocalSpace(q('0')), throwsFormatException);
  });
  test('Design selection warns on unverified and outside range', () {
    final p = AvicultureParameter({
      'parametro': 'espacio_por_ave',
      'min': '250',
      'max': '350',
      'unidad': 'cm2',
      'estado': 'sin_verificar',
    });
    expect(p.warnings(q('300')).length, 1);
    expect(p.warnings(q('200')).length, 2);
    expect(p.warnings(q('250')).length, 1);
    expect(p.warnings(q('350')).length, 1);
  });
  test('CSV rejects shifted columns and reversed limits', () {
    expect(
      () => AvicultureCatalog.parseCsv('parametro,min,max\na,10,5'),
      throwsFormatException,
    );
    expect(
      () => AvicultureCatalog.parseCsv('parametro,min,max\na,10,15,extra'),
      throwsFormatException,
    );
  });
  test(
    'View model reports procedures, invalid values and clears previous result',
    () {
      final model = AvicultureViewModel();
      final space = AvicultureParameter({
        'parametro': 'espacio_por_ave',
        'min': '250',
        'max': '350',
        'unidad': 'cm2',
        'estado': 'sin_verificar',
      });
      final values = {
        'espacio_por_ave': '250',
        'length': '100',
        'width': '10',
        'floors': '1',
        'modules': '1',
        'houses': '1',
      };
      model.calculate(
        [space],
        values: values,
        mode: 'capacidad',
        system: 'jaula_bateria',
        dimensions: 'cm',
      );
      expect(model.output, contains('Capacidad geométrica: 4 aves'));
      expect(model.output, contains('sin verificar'));
      model.calculate(
        [space],
        values: {...values, 'floors': '1.5'},
        mode: 'capacidad',
        system: 'jaula_bateria',
        dimensions: 'cm',
      );
      expect(model.output, isEmpty);
      expect(model.error, contains('enteros'));
      model.clear();
      expect(model.error, isEmpty);
      model.dispose();
    },
  );
  testWidgets(
    'Versioned assets preserve missing data and do not preselect design',
    (tester) async {
      final catalog = await AvicultureRepository().load();
      expect(catalog.capacity.length, 12);
      expect(catalog.equipment.length, 7);
      expect(
        catalog.capacity.every((p) => p.fields['estado'] == 'sin_verificar'),
        isTrue,
      );
      final missing = catalog.additional['parametros'] as List;
      expect(missing.length, 3);
      expect(
        missing.every(
          (p) => p['min'] == null && p['max'] == null && p['fuente'] == null,
        ),
        isTrue,
      );
      await tester.pumpWidget(const MaterialApp(home: AvicultureScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Capacidad e instalaciones avícolas'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.every((f) => f.controller!.text.isEmpty), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
