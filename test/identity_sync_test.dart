import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/modules/identity/domain/identity_repository.dart';
import 'package:vetdosis_pro/modules/identity/presentation/identity_panel.dart';

class IdentityFake implements IdentityRepository {
  AccountIdentity value = const AccountIdentity(icon: 3);
  bool fail = false;
  int reads = 0, writes = 0;
  @override
  Future<AccountIdentity> account(String id) async {
    reads++;
    if (fail) throw StateError('offline');
    return value;
  }

  @override
  Future<void> saveAccount(String id, AccountIdentity identity) async {
    writes++;
    if (fail) throw StateError('offline');
    value = identity;
  }

  @override
  Future<Map<String, dynamic>> clinic(String id) async => {
    'name': id,
    'header': '',
    'include_logo': false,
  };
}

void main() {
  testWidgets(
    'Perfil remoto nuevo conserva selección local anterior sin subirla',
    (tester) async {
      SharedPreferences.setMockInitialValues({'profile.icon.owner': 1});
      final repository = IdentityFake()
        ..value = const AccountIdentity(configured: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountAvatar(userId: 'owner', repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(repository.writes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('profile.icon.owner'), 1);
    },
  );
  testWidgets(
    'Cuenta nueva recupera icono remoto y guarda copia local sin subir automáticamente',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = IdentityFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountAvatar(userId: 'owner', repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.science), findsOneWidget);
      expect(repository.writes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('profile.icon.owner'), 3);
      expect(prefs.getInt('profile.icon.other'), isNull);
    },
  );
  testWidgets(
    'Fallo de sincronización conserva selección y reintento la publica explícitamente',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = IdentityFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAppearance(userId: 'owner', repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Elegir icono 2'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('profile.pending.owner'), true);
      expect(prefs.getInt('profile.icon.owner'), 1);
      expect(
        find.textContaining('Guardada solo en este dispositivo'),
        findsOneWidget,
      );
      repository.fail = false;
      await tester.tap(find.text('Sincronizar imagen de este dispositivo'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('profile.pending.owner'), false);
      expect(repository.value.icon, 1);
      expect(find.text('Imagen sincronizada con tu cuenta.'), findsOneWidget);
    },
  );
  testWidgets(
    'No se sustituye imagen remota por defecto cuando no hay selección local',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = IdentityFake();
      // Do not complete the initial remote read before the explicit action.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAppearance(userId: 'owner', repository: repository),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sincronizar imagen de este dispositivo'));
      await tester.pumpAndSettle();
      expect(repository.value.icon, 3);
    },
  );
}
