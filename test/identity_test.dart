import 'dart:async';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/domain/form_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/identity/presentation/identity_panel.dart';

class BrandingFake implements FormRepository {
  final requests = <String>[];
  final pending = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> branding(String clinicId) {
    requests.add(clinicId);
    return (pending[clinicId] ??= Completer<Map<String, dynamic>>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Cambio de clínica no muestra respuesta anterior y recepción no consulta membrete clínico',
    (tester) async {
      final repository = BrandingFake();
      ClinicMembership member(String id, ClinicRole role) => ClinicMembership(
        clinicId: id,
        clinicName: 'Clínica $id',
        userId: 'owner',
        role: role,
      );
      Widget screen(String id, ClinicRole role) => MaterialApp(
        home: Scaffold(
          body: ClinicIdentity(
            key: ValueKey(id),
            member: member(id, role),
            repository: repository,
          ),
        ),
      );
      await tester.pumpWidget(screen('a', ClinicRole.admin));
      await tester.pumpWidget(screen('b', ClinicRole.admin));
      repository.pending['a']!.complete({'header': 'Anterior'});
      repository.pending['b']!.complete({});
      await tester.pumpAndSettle();
      expect(find.text('Clínica b'), findsOneWidget);
      expect(find.text('Clínica a'), findsNothing);
      await tester.pumpWidget(screen('c', ClinicRole.recepcion));
      await tester.pumpAndSettle();
      expect(repository.requests, ['a', 'b']);
      expect(find.text('Clínica c'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'La apariencia personal queda separada entre cuentas y tolera datos dañados',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile.icon.account-a': 1,
        'profile.photo.account-b': 'invalid!',
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AccountAvatar(userId: 'account-a')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pets), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AccountAvatar(userId: 'account-b')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pets), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Buscador sin acentos navega y escáner flotante abre su apartado',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();
      final model = CoreViewModel(repository, await repository.load());
      await tester.pumpWidget(VetDosisApp(model: model));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar apartados y herramientas'),
        'calculos clinicos',
      );
      await tester.pumpAndSettle();
      final result = find.widgetWithText(ListTile, 'Cálculos clínicos');
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(model.screen, 'Cálculos clínicos');
      await tester.tap(find.byTooltip('Escáner'));
      await tester.pumpAndSettle();
      expect(model.screen, 'Escanear producto');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
