import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/domain/module_access.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/core/presentation/section_menu.dart';
import 'package:vetdosis_pro/modules/production/presentation/production_menu.dart';
import 'package:vetdosis_pro/modules/aviculture/presentation/aviculture_screen.dart';
import 'package:vetdosis_pro/modules/incubation/presentation/incubation_screen.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'module_navigation_dashboard_test.dart' show contract;
import 'support/fake_auth.dart';
import 'remaining_test.dart' show FakeOperations;

const admin = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Sintética',
  userId: 'user-a',
  role: ClinicRole.admin,
);

Future<void> host(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Drawer uses the shared palette and omits bottom shortcuts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final core = CoreViewModel(SettingsRepository(), const AppSettings());
    await tester.pumpWidget(VetDosisApp(model: core));
    await tester.pumpAndSettle();
    for (final page in ['Inicio', 'Más', 'Cálculos']) {
      core.navigate(page);
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      final drawer = find.byType(Drawer);
      expect(
        find.descendant(of: drawer, matching: find.text('Inicio')),
        findsNothing,
      );
      expect(
        find.descendant(of: drawer, matching: find.text('Cálculos')),
        findsNothing,
      );
      final theme = Theme.of(tester.element(drawer));
      expect(theme.drawerTheme.backgroundColor, theme.colorScheme.surface);
      expect(theme.colorScheme.primary, const Color(0xFF632CE5));
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(NavigationDestination, 'Inicio'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  test(
    'Service and supplier routes require the existing operations module',
    () {
      expect(navigationAllowed('Servicios', admin, ModuleAccess.denied), false);
      expect(
        navigationAllowed('Proveedores', admin, ModuleAccess.denied),
        false,
      );
      expect(
        navigationAllowed(
          'Servicios',
          admin,
          ModuleAccess.read(contract(enabled: 'agenda')),
        ),
        true,
      );
    },
  );

  testWidgets('Grouped search cannot reveal unavailable finance destinations', (
    tester,
  ) async {
    await host(
      tester,
      SectionMenu(
        member: admin,
        access: ModuleAccess.denied,
        onNavigate: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextField), 'caja');
    await tester.pumpAndSettle();
    expect(find.text('Caja'), findsNothing);
    expect(
      find.text('No hay secciones disponibles para esa búsqueda.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'planeacion');
    await tester.pumpAndSettle();
    expect(find.text('Planeación financiera'), findsNothing);
  });

  testWidgets('Planning opens the simulator from the grouped menu', (
    tester,
  ) async {
    String? opened;
    await host(
      tester,
      SectionMenu(member: admin, onNavigate: (page) => opened = page),
    );
    await tester.enterText(find.byType(TextField), 'planeacion');
    await tester.pumpAndSettle();
    expect(find.text('Planeación financiera'), findsOneWidget);
    expect(find.text('En preparación'), findsNothing);
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Planeación financiera'),
    );
    expect(tile.enabled, true);
    await tester.tap(find.widgetWithText(ListTile, 'Planeación financiera'));
    expect(opened, 'Planeación financiera');
  });

  testWidgets('All species open an honest activity outline and shared tools', (
    tester,
  ) async {
    String? opened;
    await host(
      tester,
      ProductionMenu(member: admin, onNavigate: (page) => opened = page),
    );
    for (final name in productionSpecies.keys) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Porcinos'));
    await tester.tap(find.text('Porcinos'));
    await tester.pumpAndSettle();
    expect(find.text('Maternidad y destete'), findsOneWidget);
    expect(find.text('Reproductores y servicios'), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Reproductores y servicios'),
    );
    expect(tile.onTap, isNull);
    await tester.ensureVisible(find.text('Agenda del espacio'));
    await tester.tap(find.text('Agenda del espacio'));
    expect(opened, 'Agenda');
    expect(find.textContaining('todavía no aplican un filtro'), findsOneWidget);
  });

  testWidgets(
    'Avian routes reuse existing tools and preserve activity on return',
    (tester) async {
      await host(tester, ProductionMenu(member: admin, onNavigate: (_) {}));
      await tester.tap(find.text('Aves'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Postura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capacidad e instalaciones avícolas'));
      await tester.pumpAndSettle();
      expect(find.byType(AvicultureScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reproducción e incubación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir herramientas de incubación'));
      await tester.pumpAndSettle();
      expect(find.byType(IncubationScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Reproducción e incubación'),
            )
            .selected,
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'The species menu does not bypass existing calculator restrictions',
    (tester) async {
      await host(
        tester,
        ProductionMenu(
          member: member,
          access: ModuleAccess.denied,
          onNavigate: (_) {},
        ),
      );
      await tester.tap(find.text('Aves'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Postura'));
      await tester.pumpAndSettle();
      expect(find.text('Capacidad e instalaciones avícolas'), findsNothing);
      expect(find.textContaining('no están habilitadas'), findsOneWidget);
    },
  );

  testWidgets(
    'Bottom destinations adapt to revoked access without invalid indices',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = FakeAuth();
      final auth = AuthViewModel(repo);
      await auth.start();
      final core = CoreViewModel(SettingsRepository(), const AppSettings());
      Widget app(ModuleAccess access) => MaterialApp(
        home: CoreShell(model: core, auth: auth, moduleAccess: access),
      );
      await tester.pumpWidget(
        app(ModuleAccess.read(contract(enabled: 'patients'))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Inicio', 'Pacientes', 'Más'],
      );
      core.navigate('Pacientes');
      await tester.pumpWidget(app(ModuleAccess.denied));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Inicio', 'Más'],
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.textContaining('permisos actuales'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      core.dispose();
      auth.dispose();
      await repo.controller.close();
    },
  );

  testWidgets('Service destination reuses the operations screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeAuth()..rows = [admin];
    final auth = AuthViewModel(repo);
    await auth.start();
    final core = CoreViewModel(SettingsRepository(), const AppSettings())
      ..navigate('Servicios');
    await tester.pumpWidget(
      MaterialApp(
        home: CoreShell(
          model: core,
          auth: auth,
          operations: FakeOperations(),
          moduleAccess: ModuleAccess.read(contract(enabled: 'agenda')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OperationsScreen>(find.byType(OperationsScreen))
          .initialSection,
      'services',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    core.dispose();
    auth.dispose();
    await repo.controller.close();
  });
  testWidgets('Section navigation fits 320px and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final core = CoreViewModel(SettingsRepository(), const AppSettings());
    for (final page in ['Más', 'Producción y grandes especies']) {
      core.navigate(page);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: CoreShell(model: core),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });
}
