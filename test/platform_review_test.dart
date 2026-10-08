import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'package:vetdosis_pro/modules/core/domain/plan_errors.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'package:vetdosis_pro/modules/ai/domain/ai_repository.dart';
import 'package:vetdosis_pro/modules/ai/presentation/starter_help_panel.dart';
import 'package:vetdosis_pro/modules/ai/presentation/ai_screen.dart';
import 'package:vetdosis_pro/modules/subscriptions/presentation/subscription_screen.dart';
import 'ai_plans_test.dart' show AiFake, PlanFake, personal;

class LongChatFake extends AiFake {
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    final d = await super.dashboard(clinic);
    d['chats'][0]['title'] =
        'Conversación muy larga sobre configuración de la clínica y soporte técnico sin datos reales';
    return d;
  }
}

class StarterFake implements StarterAiRepository {
  int calls = 0;
  bool enabled = true;
  @override
  Future<Map<String, dynamic>> starterStatus(String clinic) async => {
    'enabled': enabled,
    'provider': 'google',
    'model': 'gemini-2.5-flash',
    'limit': 5,
    'used': 0,
  };
  @override
  Future<String> starterHelp(
    String clinic,
    String topic,
    String operation,
  ) async {
    calls++;
    expect(starterTopics.containsKey(topic), isTrue);
    return 'new-private-chat';
  }
}

void main() {
  test(
    'Plan limits have an actionable message without exposing server codes',
    () {
      expect(
        planActionError(StateError('patient_plan_limit')),
        contains('Planes'),
      );
      expect(
        planActionError(StateError('storage_plan_limit')),
        contains('almacenamiento'),
      );
      expect(planActionError(StateError('other_error')), isNull);
    },
  );
  test(
    'All five themes keep primary actions and surface text readable in both modes',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
      }

      for (var palette = 0; palette < 5; palette++) {
        final app = VetDosisApp(
          model: CoreViewModel(
            SettingsRepository(),
            AppSettings(palette: palette),
          ),
        );
        for (final brightness in Brightness.values) {
          final theme = app.theme(brightness);
          expect(
            contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.scaffoldBackgroundColor,
              theme.colorScheme.onSurface,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test(
    'Navigation does not offer reserved screens to reception or attendance to personal spaces',
    () {
      const reception = ClinicMembership(
        clinicId: 'c',
        clinicName: 'c',
        userId: 'u',
        role: ClinicRole.recepcion,
      );
      expect(navigationAllowed('Receta', reception), false);
      expect(navigationAllowed('Inventario', reception), true);
      expect(navigationAllowed('Checado', personal), false);
      expect(navigationAllowed('Planes', reception), true);
    },
  );
  testWidgets(
    'Required authorization checkbox must be true before generic form submit',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RxEntryScreen(
            title: 'Authorization',
            fields: const [
              RxField('consent', 'Autorizo', type: 'checkbox', required: true),
            ],
            submit: (d, op) async {
              calls++;
            },
          ),
        ),
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Completa Autorizo.'), findsOneWidget);
    },
  );
  testWidgets(
    'A failed submit cannot delete fields from the original retry payload',
    (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RxEntryScreen(
            title: 'Retry',
            fields: const [RxField('name', 'Nombre', required: true)],
            initial: const {'name': 'Synthetic'},
            submit: (d, op) async {
              seen.add(d.remove('name') as String);
              throw const FormatException('Synthetic failure');
            },
          ),
        ),
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(seen, ['Synthetic', 'Synthetic']);
    },
  );
  testWidgets(
    'Included help requires consent and has no arbitrary message field',
    (tester) async {
      final r = StarterFake();
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StarterHelpPanel(
                repository: r,
                clinic: 'c',
                onCompleted: (id) async => opened = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Consultar ayuda incluida'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consultar ayuda incluida'));
      await tester.pumpAndSettle();
      expect(r.calls, 1);
      expect(opened, 'new-private-chat');
    },
  );
  testWidgets(
    'Included help stays disabled when server key is not configured',
    (tester) async {
      final r = StarterFake()..enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StarterHelpPanel(
                repository: r,
                clinic: 'c',
                onCompleted: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Consultar ayuda incluida'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'Home labels existing actions correctly and Back returns to Home',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final m = CoreViewModel(SettingsRepository(), const AppSettings());
      await tester.pumpWidget(VetDosisApp(model: m));
      await tester.pumpAndSettle();
      expect(find.text('Pendiente de implementar'), findsNothing);
      m.navigate('Ajustes');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(m.screen, 'Inicio');
    },
  );
  testWidgets('Phone IA history and plans fit at increased text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget wrap(Widget child) => MaterialApp(
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: w!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
    await tester.pumpWidget(
      wrap(AiScreen(repository: LongChatFake(), member: personal)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      wrap(SubscriptionScreen(repository: PlanFake(), member: personal)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
