import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/incubation/domain/incubation_engine.dart';
import 'package:vetdosis_pro/modules/incubation/data/incubation_repository.dart';
import 'package:vetdosis_pro/modules/incubation/presentation/incubation_view_model.dart';
import 'package:vetdosis_pro/modules/incubation/presentation/incubation_screen.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';

void main() {
  const engine = IncubationEngine();
  Quantity q(String s) => Quantity.parse(s);
  test('Chosen yield, not a universal 70% default', () {
    expect(engine.chickWeight(q('65'), q('70')).display(), '45,5');
    expect(engine.chickWeight(q('65'), q('66')).display(), '42,9');
    expect(() => engine.chickWeight(q('65'), q('101')), throwsFormatException);
    expect(() => engine.chickWeight(q('0'), q('70')), throwsFormatException);
  });
  test('Weight loss and comparison preserve signed differences', () {
    expect(engine.lossPercent(q('65'), q('58.5')).display(), '10');
    expect(engine.expectedEgg(q('65'), q('12.8')).display(), '56,68');
    expect(signedDisplay(engine.lossPercent(q('50'), q('51'))), '−2');
    expect(signedDisplay(difference(q('10'), q('12.8'))), '−2,8');
    expect(engine.lossAtDay(4, {3: q('2.4'), 6: q('4.2')}), isNull);
    expect(engine.lossAtDay(3, {3: q('2.4')})!.display(), '2,4');
  });
  test('Explicit mass/volume conversion, not ambiguous ppm or percent', () {
    expect(engine.massVolume(q('3'), 'percent_mv').display(), '30');
    expect(engine.massVolume(q('1000'), 'mg_l').display(), '1');
    expect(engine.massVolume(q('1000'), 'ppm_mg_l').display(), '1');
    for (final unit in ['ppm', 'percent_mm', 'percent_vv']) {
      expect(() => engine.massVolume(q('3'), unit), throwsFormatException);
    }
    expect(
      () => engine.massVolume(q('101'), 'percent_mv'),
      throwsFormatException,
    );
  });
  test(
    'Synthetic dilution uses final volume, refuses concentration increase',
    () {
      expect(engine.concentrateMl(q('10'), q('1'), q('1000')).display(), '100');
      expect(difference(q('1000'), q('100')).display(), '900');
      expect(
        () => engine.concentrateMl(q('1'), q('2'), q('1000')),
        throwsFormatException,
      );
      expect(
        () => engine.concentrateMl(q('10'), q('0'), q('1000')),
        throwsFormatException,
      );
    },
  );
  testWidgets('Real assets stay unverified and never auto-select design', (
    tester,
  ) async {
    final catalog = await IncubationRepository().load();
    expect(catalog.points.keys, [3, 6, 9, 12, 15, 18]);
    expect(
      catalog.parameters.every((p) => p['estado'] == 'sin_verificar'),
      isTrue,
    );
    expect(catalog.data['curva_clase']['interpolacion'], isNull);
    await tester.pumpWidget(const MaterialApp(home: IncubationScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Incubación · Gallinas'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((f) => f.controller!.text.isEmpty),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  test('View model clears old results and enforces review and provenance', () {
    final model = IncubationViewModel();
    model.catalog = IncubationCatalog({
      'curva_clase': {
        'dias': [3, 18],
        'perdida_porcentaje': ['2.4', '12.8'],
      },
    });
    model.calculate('chick', {'egg': '65', 'yield': '70'});
    expect(model.output, contains('45,5 g'));
    model.calculate('loss', {
      'initial': '65',
      'current': '58.5',
      'day': '4',
    }, sameSample: true);
    expect(model.output, contains('No hay un punto documentado'));
    model.calculate('loss', {
      'initial': '65',
      'current': '58.5',
      'day': '18',
    }, sameSample: true);
    expect(model.output, contains('−2,8 puntos'));
    model.calculate('loss', {'initial': '65', 'current': '58.5', 'day': '18'});
    expect(model.output, isEmpty);
    expect(model.error, contains('Confirma'));
    final values = {
      'product': 'Producto ficticio',
      'source': 'Fuente ficticia: prueba matemática',
      'stock': '10',
      'target': '1000',
      'final_ml': '1000',
    };
    model.calculate('dilution', values);
    expect(model.output, isEmpty);
    model.calculate('dilution', values, reviewed: true);
    expect(model.output, contains('100 ml'));
    model.calculate('dilution', {...values, 'source': ''}, reviewed: true);
    expect(model.output, isEmpty);
    expect(model.error, contains('Identifica'));
    model.clear();
    expect(model.error, isEmpty);
    model.dispose();
  });
}
