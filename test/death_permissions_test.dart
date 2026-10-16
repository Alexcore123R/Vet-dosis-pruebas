import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/forms/clinical/death_screen.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_models.dart';
import 'clinical_test.dart' show ClinicalFake;
import 'clinical_screen_contract_test.dart' show admin;

class DeathFake extends ClinicalFake implements DeathPermissionRepository {
  bool allowed = false;
  int version = 1;
  @override
  Future<Map<String, dynamic>> deathWorkspace(String id) async => {
    'version': version,
    'consent_id': id,
    'can_record': allowed,
    'procedures': allowed
        ? [
            {'id': 'p', 'name': 'Synthetic procedure'},
          ]
        : [],
    'records': [],
  };
}

const doc = FormDocument('doc', 'signed', 1, 'v', 'current-person', {}, {
  'patient': {'name': 'Synthetic'},
  'schema': {'type': 'euthanasia'},
}, null);
void main() {
  testWidgets(
    'visual administrator has no recording action without server permission',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: DeathScreen(
            repository: DeathFake(),
            document: doc,
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('Consulta únicamente'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit permission enables empty selections regardless of visual job',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: DeathScreen(
            repository: DeathFake()..allowed = true,
            document: doc,
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      final selections = t.widgetList<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(selections.length, 2);
      expect(selections.every((s) => s.initialValue == null), true);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('observed_at')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('observed_at')))
            .initialValue,
        anyOf(isNull, isEmpty),
      );
    },
  );
  testWidgets('unknown contract fails closed', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: DeathScreen(
          repository: DeathFake()
            ..allowed = true
            ..version = 2,
          document: doc,
          member: admin,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('No se pudo consultar'), findsOneWidget);
  });
  testWidgets(
    'changing repository clears known authority without role fallback',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: DeathScreen(
            repository: DeathFake()..allowed = true,
            document: doc,
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      await t.pumpWidget(
        MaterialApp(
          home: DeathScreen(
            repository: DeathFake(),
            document: doc,
            member: admin,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );
}
