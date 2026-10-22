import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/doses/presentation/dose_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/doses/domain/catalog.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';
import 'package:vetdosis_pro/modules/doses/domain/dose_engine.dart';
import 'package:vetdosis_pro/modules/doses/data/catalog_repository.dart';
import 'package:vetdosis_pro/modules/doses/presentation/dose_view_model.dart';

// Fictitious arithmetic fixture. Never shipped as a clinical catalog.
Map<String, dynamic> fixture() => jsonDecode(
  jsonEncode({
    'schema_version': 1,
    'catalog_version': 'math-test',
    'farmacos': [
      {
        'id': 'test',
        'farmaco': 'Ficticio',
        'especie': 'Especie ficticia',
        'unidad_dosis': 'mg/kg',
        'min': '1',
        'max': '2',
        'via': 'Vía ficticia',
        'intervalo': 'Intervalo ficticio',
        'estado': 'verificada',
        'fuente': 'Caso aritmético ficticio, no referencia clínica',
        'presentaciones': [
          {
            'id': 'p',
            'nombre_comercial': 'Marca ficticia',
            'concentracion': '10',
            'unidad_concentracion': 'mg/ml',
            'estado': 'verificada',
            'fuente': 'Caso aritmético ficticio',
          },
        ],
        'contraindicaciones': [],
      },
    ],
  }),
);
DrugDose drug() => DoseCatalog.parse(jsonEncode(fixture())).drugs.single;
DoseResult calc(
  DrugDose d, {
  String weight = '10',
  String dose = '2',
  String step = '0.1',
  String breed = '',
}) => const DoseEngine().calculate(
  drug: d,
  presentation: d.presentations.single,
  weightKg: Quantity.parse(weight),
  doseMgKg: Quantity.parse(dose),
  syringeStepMl: Quantity.parse(step),
  breed: breed,
);

class Repo implements CatalogRepository {
  @override
  Future<DoseCatalog> load() async => DoseCatalog.parse(jsonEncode(fixture()));
}

class ExactRepo implements CatalogRepository {
  @override
  Future<DoseCatalog> load() async {
    final data = fixture();
    data['farmacos'][0]['max'] = '1';
    return DoseCatalog.parse(jsonEncode(data));
  }
}

void main() {
  test('Known fictitious vector: 10 kg × 2 mg/kg / 10 mg/ml', () {
    final r = calc(drug());
    expect(r.mass.display(), '20');
    expect(r.volume.display(), '2');
    expect(r.canConfirm, true);
  });
  test('Exact decimal boundary, comma input and half-step rounding', () {
    expect(
      (Quantity.parse('0,1') * Quantity.parse('3')).compareTo(
        Quantity.parse('0.3'),
      ),
      0,
    );
    expect(
      Quantity.parse('0.15').nearestStep(Quantity.parse('0.1')).display(),
      '0,2',
    );
  });
  test('Above and below limits block; equality allowed', () {
    expect(calc(drug(), dose: '2.000000001').canConfirm, false);
    expect(calc(drug(), dose: '0.999999999').canConfirm, false);
    expect(calc(drug(), dose: '1').canConfirm, true);
  });
  test('Rounding must not exceed max or produce zero', () {
    expect(
      calc(
        drug(),
        weight: '1',
        step: '0.3',
      ).alerts.any((a) => a.contains('redondeo')),
      true,
    );
    expect(calc(drug(), weight: '0.1', step: '1').canConfirm, false);
  });
  test('Nonpositive or ambiguous input rejected', () {
    expect(() => calc(drug(), weight: '0'), throwsFormatException);
    for (final s in ['NaN', 'Infinity', '-1', '1e3', '1,000.5', '']) {
      expect(() => Quantity.parse(s), throwsFormatException);
    }
  });
  test('Missing concentration never inferred', () {
    final map = fixture();
    map['farmacos'][0]['presentaciones'][0]['concentracion'] = null;
    final d = DoseCatalog.parse(jsonEncode(map)).drugs.single;
    expect(() => calc(d), throwsFormatException);
  });
  test('Unverified, missing range and missing route block confirmation', () {
    final map = fixture();
    map['farmacos'][0]['estado'] = 'sin verificar';
    map['farmacos'][0]['min'] = null;
    map['farmacos'][0]['via'] = null;
    expect(
      calc(DoseCatalog.parse(jsonEncode(map)).drugs.single).alerts.length,
      3,
    );
  });
  test('Breed contraindication matched ignoring case', () {
    final map = fixture();
    map['farmacos'][0]['contraindicaciones'] = [
      {
        'tipo': 'raza',
        'valor': 'Ficticia',
        'nota': 'Regla de prueba',
        'estado': 'verificada',
        'fuente': 'Caso ficticio',
      },
    ];
    expect(
      calc(
        DoseCatalog.parse(jsonEncode(map)).drugs.single,
        breed: 'FICTICIA',
      ).canConfirm,
      false,
    );
  });
  test('Invalid units, source, reversed ranges and duplicates rejected', () {
    for (final change in ['unit', 'source', 'range', 'duplicate']) {
      final m = fixture();
      final d = m['farmacos'][0];
      if (change == 'unit') d['unidad_dosis'] = 'mcg/kg';
      if (change == 'source') d['fuente'] = null;
      if (change == 'range') d['min'] = '3';
      if (change == 'duplicate') {
        m['farmacos'].add(Map<String, dynamic>.from(d));
      }
      expect(() => DoseCatalog.parse(jsonEncode(m)), throwsFormatException);
    }
  });
  test('Search by brand with species filter', () {
    final c = DoseCatalog.parse(jsonEncode(fixture()));
    expect(c.search('marca').length, 1);
    expect(c.search('marca', species: 'Otra').isEmpty, true);
  });
  test(
    'Only an exact dose entry can drive weight-only catalog calculation',
    () {
      final map = fixture();
      map['farmacos'][0]['max'] = '1';
      final single = DoseCatalog.parse(jsonEncode(map)).drugs.single;
      expect(single.prescribedDose?.display(), '1');
      map['farmacos'][0]['max'] = '2';
      final ranged = DoseCatalog.parse(jsonEncode(map)).drugs.single;
      expect(ranged.prescribedDose, isNull);
    },
  );
  test('Personal draft required fields and 100× warning', () {
    final m = fixture()['farmacos'][0] as Map<String, dynamic>;
    m['max'] = '200';
    final p = DrugDose.read(m, personal: true);
    expect(validatePersonalDose(p, general: drug()).single, contains('100'));
    expect(drug().max!.display(), '2');
  });
  test(
    'Double confirmation cannot skip review and edits invalidate it',
    () async {
      final vm = DoseViewModel(ExactRepo());
      await vm.load();
      vm.select(vm.catalog!.drugs.single);
      vm.selectPresentation(vm.drug!.presentations.single);
      vm.calculate('10', '1', '0.1', '', '');
      vm.confirm();
      expect(vm.stage, ConfirmationStage.none);
      vm.review();
      vm.confirm();
      expect(vm.stage, ConfirmationStage.confirmed);
      vm.invalidate();
      expect(vm.stage, ConfirmationStage.none);
      expect(vm.result, isNull);
      vm.dispose();
    },
  );
  test(
    'Invalid import preserves the previous catalog across reloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AssetCatalogRepository();
      await repo.import(jsonEncode(fixture()));
      await expectLater(repo.import('{}'), throwsFormatException);
      expect((await AssetCatalogRepository().load()).version, 'math-test');
    },
  );
  testWidgets('Calculator fits a phone and exposes presentation and source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DoseScreen(repository: ExactRepo()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ficticio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fuente: Caso aritmético'), findsOneWidget);
    expect(find.text('Presentación comercial'), findsOneWidget);
    expect(find.text('1 mg/kg · no editable'), findsOneWidget);
    expect(find.textContaining('Dosis seleccionada (mg/kg)'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<Presentation>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Marca ficticia').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.ensureVisible(find.text('Calcular'));
    await tester.tap(find.text('Calcular'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Volumen calculado: 1 mL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
