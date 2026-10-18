// Development-only previews of real widgets with empty/synthetic data.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import '../agenda_permission_test.dart' show PermissionAgendaFake;

void main() {
  for (final dark in [false, true]) {
    testWidgets('Capture empty views ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final textFont = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await textFont.load();
      await icons.load();
      final core = CoreViewModel(
        SettingsRepository(),
        AppSettings(visualStyle: 'neu', brightness: dark ? 'dark' : 'light'),
      );
      for (final agenda in [false, true]) {
        final boundaryKey = GlobalKey();
        final app = VetDosisApp(model: core);
        final fake = PermissionAgendaFake();
        fake.response['appointments'] = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: agenda
                ? MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: app.theme(dark ? Brightness.dark : Brightness.light),
                    home: Scaffold(
                      appBar: AppBar(
                        title: const Text('Agenda · vista sin registros'),
                      ),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: OperationsScreen(
                          repository: fake,
                          member: const ClinicMembership(
                            clinicId: 'c1',
                            clinicName: 'Espacio ficticio',
                            userId: 'u1',
                            role: ClinicRole.admin,
                          ),
                        ),
                      ),
                    ),
                  )
                : app,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/brand/vetdosis-logo.png'),
            boundaryKey.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'review/ui-kit-20261018/${agenda ? 'agenda' : 'inicio'}-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      core.dispose();
    });
  }
}
