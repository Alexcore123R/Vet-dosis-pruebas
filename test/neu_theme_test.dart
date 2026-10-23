import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/core/widgets/workspace_panel.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_screen.dart';
import 'package:vetdosis_pro/modules/dashboard/presentation/dashboard_view_model.dart';

void main() {
  test(
    'Style persists independently of palette and brightness; unknown falls back',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SettingsRepository();
      expect((await repo.load()).visualStyle, 'neu');
      await repo.save(const AppSettings(visualStyle: 'standard'));
      expect((await repo.load()).visualStyle, 'standard');
      final model = CoreViewModel(repo, await repo.load());
      await model.updateSettings(visualStyle: 'neu');
      await model.updateSettings(palette: 2, brightness: 'dark');
      final saved = await repo.load();
      expect(saved.visualStyle, 'neu');
      expect(saved.palette, 2);
      expect(saved.brightness, 'dark');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('visualStyle', 'unknown');
      expect((await repo.load()).visualStyle, 'standard');
      model.dispose();
    },
  );
  for (final mode in ['light', 'dark']) {
    testWidgets('Neu cards fit mobile and large text in $mode', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final repo = SettingsRepository();
      final core = CoreViewModel(
        repo,
        AppSettings(visualStyle: 'neu', brightness: mode),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: VetDosisApp(
            model: core,
          ).theme(mode == 'dark' ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: DashboardScreen(
                  model: DashboardViewModel(member: null),
                  onNavigate: core.navigate,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePanel), findsWidgets);
      expect(find.text('Escáner'), findsOneWidget);
      await tester.ensureVisible(find.text('Escáner'));
      await tester.tap(find.text('Escáner'));
      expect(core.screen, 'Escanear producto');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      core.dispose();
    });
  }
}
