import 'dart:async';
import 'patients_test.dart' as fixture;
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/calculations/presentation/fluid_therapy_panel.dart';
import 'package:vetdosis_pro/modules/calculations/presentation/drip_metronome.dart';
import 'package:vetdosis_pro/core/widgets/workspace_panel.dart';

void main() {
  testWidgets(
    'Patient selection reads the last recorded weight and never reads owners',
    (tester) async {
      final repo = fixture.FakePatients()
        ..rows = [
          fixture.event(EventKind.weight, data: {'kg': '12.3'}),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FluidTherapyPanel(patients: repo, clinicId: 'a'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Paciente ficticio').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fluid:weight')))
            .controller!
            .text,
        '12.3',
      );
      expect(repo.ownerReads, 0);
      expect(find.textContaining('Confirma que sea actual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Late patient weight cannot repopulate a disposed calculator', (
    tester,
  ) async {
    final repo = fixture.FakePatients()
      ..pending = Completer<List<PatientEvent>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FluidTherapyPanel(patients: repo, clinicId: 'a'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Paciente ficticio').last);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Otra sesión')));
    repo.pending!.complete([
      fixture.event(EventKind.weight, data: {'kg': '15'}),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Otra sesión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Phone plan invalidates and stops metronome when an input changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [WorkspaceStyle(neumorphic: true)],
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: FluidTherapyPanel()),
          ),
        ),
      );
      for (final entry in {
        'weight': '28.5',
        'maintenance': '60',
        'percent': '5',
        'hours': '24',
        'losses': '100',
        'drop_factor': '20',
      }.entries) {
        final field = find.byKey(ValueKey('fluid:${entry.key}'));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      await tester.ensureVisible(find.text('Calcular · Fluidoterapia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calcular · Fluidoterapia'));
      await tester.pumpAndSettle();
      expect(find.text('Volumen del periodo (ml): 3235'), findsOneWidget);
      final start = find.text('Iniciar metrónomo');
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pump();
      expect(find.text('Detener metrónomo'), findsOneWidget);
      final weight = find.byKey(const ValueKey('fluid:weight'));
      await tester.ensureVisible(weight);
      await tester.enterText(weight, '29');
      await tester.pump();
      expect(find.byType(DripMetronome), findsNothing);
      expect(find.text('Volumen del periodo (ml): 3235'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Metronome stops when app leaves foreground', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DripMetronome(dropsPerMinute: 60)),
      ),
    );
    await tester.tap(find.text('Iniciar metrónomo'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Iniciar metrónomo'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
