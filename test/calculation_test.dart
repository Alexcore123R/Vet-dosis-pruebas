import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/calculations/data/calculation_repository.dart';
import 'package:vetdosis_pro/modules/calculations/domain/calculation_catalog.dart';
import 'package:vetdosis_pro/modules/calculations/domain/calculation_engine.dart';
import 'package:vetdosis_pro/modules/calculations/presentation/calculation_screen.dart';
import 'package:vetdosis_pro/modules/calculations/presentation/calculation_view_model.dart';
import 'package:vetdosis_pro/modules/doses/data/catalog_repository.dart';
import 'package:vetdosis_pro/modules/doses/domain/catalog.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';
import 'dose_test.dart' as fixture;

Map<String, Quantity> input(Map<String, String> values) =>
    values.map((k, v) => MapEntry(k, Quantity.parse(v)));
CalculationCatalog catalog() => CalculationCatalog.parse(
  File('assets/clinical/calculations.v1.json').readAsStringSync(),
);

class CalcRepo implements CalculationRepository {
  @override
  Future<CalculationCatalog> load() async => catalog();
}

class DoseRepo implements CatalogRepository {
  @override
  Future<DoseCatalog> load() async =>
      DoseCatalog.parse(jsonEncode(fixture.fixture()));
}

ClinicalReference reference(String type, Map<String, dynamic> values) =>
    ClinicalReference.read({
      'id': 'test',
      'tipo': type,
      'especie': 'Especie ficticia',
      'titulo': 'Referencia ficticia, no clínica',
      'estado': 'verificada',
      'fuente': 'Prueba matemática sintética',
      ...values,
    });

// Synthetic arithmetic vectors, NOT treatment recommendations.
void main() {
  const engine = CalculationEngine();
  test(
    'Fluid volume uses requested period and total losses, not hourly losses',
    () {
      final r = engine.calculate(
        'fluids',
        input({
          'weight': '10',
          'maintenance': '48',
          'percent': '5',
          'hours': '12',
          'losses': '60',
          'drop_factor': '20',
        }),
      );
      expect(r.values['deficit']!.display(), '500');
      expect(r.values['total']!.display(), '800');
      expect(
        r.values['rate']!.compareTo(Quantity(BigInt.from(200), BigInt.from(3))),
        0,
      );
      expect(
        r.values['drops']!.compareTo(
          Quantity(BigInt.from(200), BigInt.from(9)),
        ),
        0,
      );
    },
  );
  test(
    'Zero deficit and losses permitted; invalid period or percentage rejected',
    () {
      final v = {
        'weight': '1',
        'maintenance': '0',
        'percent': '0',
        'hours': '24',
        'losses': '0',
        'drop_factor': '60',
      };
      expect(
        engine.calculate('fluids', input(v)).values['total']!.display(),
        '0',
      );
      expect(
        () => engine.calculate('fluids', input({...v, 'hours': '0'})),
        throwsFormatException,
      );
      expect(
        () => engine.calculate('fluids', input({...v, 'percent': '100'})),
        throwsFormatException,
      );
    },
  );
  test('CRI mcg/min to mg/hour, exact mixture includes drug volume', () {
    final r = engine.calculate(
      'cri',
      input({
        'weight': '10',
        'dose': '1',
        'concentration': '10',
        'final_volume': '100',
        'pump_rate': '10',
        'drop_factor': '60',
      }),
    );
    expect(r.values['mass_hour']!.display(), '0,6');
    expect(r.values['duration']!.display(), '10');
    expect(r.values['mass']!.display(), '6');
    expect(r.values['drug_volume']!.display(), '0,6');
    expect(r.values['solvent_volume']!.display(), '99,4');
    expect(r.values['mixture_concentration']!.display(), '0,06');
    expect(r.values['drops']!.display(), '10');
  });
  test('CRI rejects drug volume larger than final mixture', () {
    expect(
      () => engine.calculate(
        'cri',
        input({
          'weight': '10',
          'dose': '100',
          'concentration': '0.1',
          'final_volume': '10',
          'pump_rate': '1',
          'drop_factor': '60',
        }),
      ),
      throwsFormatException,
    );
  });
  test('Herd head and lot use exact decimals and require integer count', () {
    final v = {
      'weight': '100',
      'count': '3',
      'dose': '0,1',
      'concentration': '20',
    };
    final r = engine.calculate('herd', input(v));
    expect(r.values['volume_head']!.display(), '0,5');
    expect(r.values['volume_lot']!.display(), '1,5');
    expect(
      () => engine.calculate('herd', input({...v, 'count': '1.5'})),
      throwsFormatException,
    );
  });
  test('Water mg/L to product grams, feed mg/kg to grams per tonne', () {
    final r = engine.calculate(
      'water',
      input({'target': '2', 'litres': '1000', 'strength': '100'}),
    );
    expect(r.values['mass']!.display(), '2000');
    expect(r.values['product_grams']!.display(), '20');
    final f = engine.calculate(
      'feed',
      input({'target': '2', 'tonnes': '1.5', 'strength': '100'}),
    );
    expect(f.values['mass']!.display(), '3000');
    expect(f.values['product_grams']!.display(), '30');
  });
  test('Positive tiny output never displays a false zero', () {
    expect(
      displayCalculation(Quantity(BigInt.one, BigInt.from(10).pow(12))),
      '<0,000000001',
    );
    expect(displayCalculation(Quantity.parse('0')), '0');
  });
  test('Reference ranges include limits and block missing/unverified data', () {
    final r = reference('constante', {
      'parametro': 'Prueba',
      'unidad': 'u',
      'min': '1',
      'max': '2',
    });
    expect(r.evaluate(Quantity.parse('1')), contains('Dentro'));
    expect(r.evaluate(Quantity.parse('2')), contains('Dentro'));
    expect(r.evaluate(Quantity.parse('0.5')), contains('debajo'));
    expect(r.evaluate(Quantity.parse('3')), contains('encima'));
    final absent = reference('constante', {
      'parametro': 'Prueba',
      'unidad': 'u',
      'min': null,
      'max': null,
    });
    expect(absent.evaluate(Quantity.parse('10')), contains('Sin referencia'));
    expect(
      () => reference('constante', {
        'parametro': 'Prueba',
        'unidad': 'u',
        'min': '2',
        'max': '1',
      }),
      throwsFormatException,
    );
    expect(
      () => reference('constante', {
        'parametro': 'Prueba',
        'unidad': 'u',
        'estado': 'verificada',
        'fuente': null,
      }),
      throwsFormatException,
    );
  });
  test(
    'Metabolic weight uses only reference exponent, never a medication dose',
    () {
      final r = reference('metabolico', {'exponente': '0.5'});
      expect(r.metabolicWeight(Quantity.parse('9')), closeTo(3, 1e-10));
      expect(
        () => r.metabolicWeight(Quantity.parse('0')),
        throwsFormatException,
      );
      expect(
        () => reference('metabolico', {'exponente': '1.5'}),
        throwsFormatException,
      );
    },
  );
  test(
    'Stage protocol reuses M3 presentation/range/rounding and contraindications',
    () {
      final r = reference('protocolo', {
        'etapas': [
          {
            'etapa': 'induccion',
            'dosis_id': 'test',
            'presentacion_id': 'p',
            'dosis_mg_kg': '2',
          },
        ],
      });
      final doses = DoseCatalog.parse(jsonEncode(fixture.fixture()));
      final result = r
          .protocol(doses, Quantity.parse('10'), Quantity.parse('0.1'))
          .single;
      expect(result.drug, 'Ficticio');
      expect(result.presentation, 'Marca ficticia');
      expect(result.result.volume.display(), '2');
      expect(result.result.canConfirm, true);
      final overdose = reference('protocolo', {
        'etapas': [
          {
            'etapa': 'induccion',
            'dosis_id': 'test',
            'presentacion_id': 'p',
            'dosis_mg_kg': '3',
          },
        ],
      });
      expect(
        overdose
            .protocol(doses, Quantity.parse('10'), Quantity.parse('0.1'))
            .single
            .result
            .canConfirm,
        false,
      );
      expect(
        () => r.protocol(
          DoseCatalog('empty', []),
          Quantity.parse('10'),
          Quantity.parse('0.1'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Withdrawal requires exact commercial presentation, route, destination and MX; zero is distinct from missing',
    () {
      final data = {
        'producto_id': 'test',
        'presentacion': 'Ficticia',
        'via': 'Ficticia',
        'destino': 'Ficticio',
        'jurisdiccion': 'MX',
        'unidad': 'horas',
        'tiempo': '0',
      };
      expect(reference('retiro', data).data['tiempo'], '0');
      expect(
        reference('retiro', {...data, 'tiempo': null}).data['tiempo'],
        isNull,
      );
      expect(
        () => reference('retiro', {...data, 'jurisdiccion': 'OTHER'}),
        throwsFormatException,
      );
    },
  );
  test('Shipped catalog has no invented clinical entries', () {
    expect(catalog().references, isEmpty);
    expect(catalog().calculations.length, 6);
  });
  test(
    'Age adjustment blocks absent sources and rejects outside verified range',
    () async {
      final model = CalculationViewModel(CalcRepo(), DoseRepo());
      await model.load();
      final def = model.catalog!.calculations.firstWhere(
        (d) => d.id == 'adjustment',
      );
      final values = {
        'weight': '10',
        'dose': '2',
        'factor': '1',
        'concentration': '10',
      };
      model.calculate(def, values);
      expect(model.result, isNull);
      expect(model.error, contains('referencia'));
      final r = reference('ajuste', {
        'farmaco_id': 'test',
        'presentacion_id': 'p',
        'condicion': 'Ficticia',
        'factor': '1',
      });
      model.calculate(def, values, adjustment: r);
      expect(model.result!.values['volume']!.display(), '2');
      model.calculate(def, {...values, 'dose': '3'}, adjustment: r);
      expect(model.result, isNull);
      expect(model.error, contains('rango'));
      model.dispose();
    },
  );
  testWidgets(
    'Phone screen calculates, invalidates changed input, shows missing reference',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: CalculationScreen(
                repository: CalcRepo(),
                doses: DoseRepo(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final pair in <(int, String)>[
        (0, '10'),
        (1, '48'),
        (2, '5'),
        (3, '12'),
        (4, '60'),
        (5, '20'),
      ]) {
        await tester.ensureVisible(fields.at(pair.$1));
        await tester.enterText(fields.at(pair.$1), pair.$2);
      }
      final button = find.text('Calcular · Fluidoterapia');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Volumen del periodo (ml): 800'), findsOneWidget);
      await tester.ensureVisible(fields.first);
      await tester.enterText(fields.first, '');
      await tester.pump();
      expect(find.text('Volumen del periodo (ml): 800'), findsNothing);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Constantes fisiológicas').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sin referencias disponibles'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
