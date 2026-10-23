import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/calculations/data/reference_library_repository.dart';
import 'package:vetdosis_pro/modules/calculations/presentation/reference_library_screen.dart';

class LibraryFixture implements ReferenceLibraryRepository {
  final sections = <String>[];

  @override
  Future<ReferenceLibraryPage> list(String clinicId, String section, String search, int offset) async {
    sections.add(section);
    if (section == 'laboratorio') {
      return ReferenceLibraryPage([
        {
          'id': 'lab-1', 'species': 'Canino', 'parameter': 'Albúmina',
          'min_value': '2.3', 'max_value': '3.8', 'unit': 'g/dL',
          'source_title': 'Método A', 'review_state': 'pendiente', 'alternatives': 2, 'distinct_intervals': 2,
        },
      ], 1);
    }
    return ReferenceLibraryPage([
      {
        'id': 'temp-1', 'species': 'Canino', 'parameter': 'Temperatura rectal',
        'min_value': '37.5', 'max_value': '39.2', 'unit': '°C',
        'source_title': 'Merck Veterinary Manual',
        'review_state': 'fuente_contrastada_pendiente_mvz', 'alternatives': 2, 'distinct_intervals': 2,
      },
    ], 1);
  }
}

void main() {
  testWidgets('Shows sourced alternatives without automatic patient classification', (tester) async {
    final fixture = LibraryFixture();
    await tester.pumpWidget(MaterialApp(home: ReferenceLibraryScreen(
      repository: fixture, clinicId: 'synthetic-clinic',
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Merck Veterinary Manual'), findsOneWidget);
    expect(find.textContaining('pendiente de revisión MVZ'), findsWidgets);
    expect(find.textContaining('2 intervalos distintos'), findsOneWidget);
    expect(find.textContaining('Dentro del rango'), findsNothing);
    await tester.tap(find.text('Laboratorio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Albúmina'), findsOneWidget);
    expect(fixture.sections, ['fisiologia', 'laboratorio']);
  });
}
