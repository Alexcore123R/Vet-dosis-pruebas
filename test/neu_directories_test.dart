import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/core/widgets/workspace_panel.dart';
import 'package:vetdosis_pro/modules/doses/domain/catalog.dart';
import 'package:vetdosis_pro/modules/doses/presentation/vademecum_panel.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/presentation/phone_directory.dart';
import 'dose_test.dart' as fixture;

void main() {
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [WorkspaceStyle(neumorphic: true)]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Directory filters real owners by name and phone availability', (
    tester,
  ) async {
    await mount(
      tester,
      const PhoneDirectory(
        owners: [
          VetOwner('1', 'Ana', '+525511112222', '', ''),
          VetOwner('2', 'Luis', '', '', ''),
        ],
      ),
    );
    expect(find.text('Ana'), findsOneWidget);
    await tester.tap(find.text('Con teléfono'));
    await tester.pumpAndSettle();
    expect(find.text('Luis'), findsNothing);
    await tester.enterText(find.byType(TextField), 'no existe');
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsNothing);
    expect(find.text('No hay contactos para esta búsqueda.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Vademecum searches the catalog and expands actual evidence', (
    tester,
  ) async {
    final catalog = DoseCatalog.parse(jsonEncode(fixture.fixture()));
    await mount(tester, VademecumPanel(catalog: catalog));
    final drug = catalog.drugs.first;
    await tester.tap(find.text(drug.name).first);
    await tester.pumpAndSettle();
    expect(find.text('Fuente: ${drug.evidence.source}'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no existe');
    await tester.pumpAndSettle();
    expect(find.text(drug.name), findsNothing);
    expect(find.text('0 registros'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
