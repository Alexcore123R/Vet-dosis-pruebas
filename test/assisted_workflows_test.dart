import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/ai/domain/assisted_drafts.dart';
import 'package:vetdosis_pro/modules/ai/presentation/dictation_field.dart';
import 'package:vetdosis_pro/modules/patients/application/voice_dictation.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/appointment_message_screen.dart';
import 'package:vetdosis_pro/modules/operations/presentation/promotion_options_screen.dart';
import 'package:vetdosis_pro/modules/forms/presentation/clinical_draft_screen.dart';
import 'ai_plans_test.dart' show AiFake, personal;

Future<void> reveal(WidgetTester tester, Finder target, double delta) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

class ClinicalAi extends AiFake {
  @override
  Future<List<Map<String, dynamic>>> messages(String chat) async => [
    {
      'role': 'assistant',
      'body':
          '{"fields":{"plan":"Indicaciones registradas por el profesional"},"missing":["Fecha de control"]}',
    },
  ];
}

String promotionResponse() => jsonEncode({
  'options': [
    for (var i = 1; i <= 3; i++)
      {
        'title': 'Opción $i',
        'message': 'Mensaje $i',
        'conditions': 'Condiciones $i',
      },
  ],
});

class OptionsAi extends AiFake {
  @override
  Future<List<Map<String, dynamic>>> messages(String chat) async => [
    {'role': 'assistant', 'body': promotionResponse()},
  ];
}

class ContactFake implements ServiceContactRepository {
  bool revoked = false;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> appointmentContact(
    String clinic,
    String appointment,
  ) async {
    reads++;
    return {
      'owner_id': 'owner',
      'name': 'Tutor sintético',
      'phone': '+5215551112222',
      'email': 'synthetic@example.test',
      'version': 1,
      'state': 'agendado',
      'kind': 'consulta',
      'starts_local': '2026-10-22 12:00',
      'timezone': 'UTC',
      'can_record': false,
      'preferences': {
        'appointment': {
          'whatsapp_allowed': !revoked,
          'email_allowed': false,
          'consent_source': 'Synthetic authorization',
        },
        'follow_up': {
          'whatsapp_allowed': false,
          'email_allowed': false,
          'consent_source': '',
        },
      },
    };
  }

  @override
  Future<void> saveServiceContact(
    String clinic,
    String owner,
    String purpose,
    bool whatsapp,
    bool email,
    String source,
  ) async {}
}

class VoiceFake implements VoiceDictation {
  void Function(String)? emit;
  bool stopped = false;
  @override
  Future<bool> start(
    void Function(String) onText,
    void Function(String) onError,
  ) async {
    emit = onText;
    return true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void main() {
  test('Promotion response requires exactly three complete options', () {
    expect(
      PromotionOption.parse('```json\n${promotionResponse()}\n```').length,
      3,
    );
    expect(
      () => PromotionOption.parse('{"options":[]}'),
      throwsFormatException,
    );
    expect(
      () => PromotionOption.parse('{"options":[{}, {}, {}]}'),
      throwsFormatException,
    );
  });
  test(
    'Clinical draft rejects identity or other fields outside the selection',
    () {
      expect(
        () => ClinicalDraft.parse(
          '{"fields":{"owner":"Changed identity"},"missing":[]}',
          {'plan'},
        ),
        throwsFormatException,
      );
      final draft = ClinicalDraft.parse(
        '{"fields":{"plan":"Plan indicado por el profesional"},"missing":["Fecha de control"]}',
        {'plan'},
      );
      expect(draft.fields['plan'], 'Plan indicado por el profesional');
      expect(draft.missing, ['Fecha de control']);
    },
  );
  testWidgets(
    'Chosen promotion transfers title, conditions and captured discount to the form',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PromotionOptionsScreen(
                        ai: OptionsAi(),
                        member: personal,
                      ),
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Estética');
      await tester.enterText(find.byType(TextField).at(1), '10');
      await tester.enterText(find.byType(TextField).at(2), 'Solo con cita');
      for (final label in ['Inicio de vigencia', 'Fin de vigencia']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Generar tres opciones'));
      await tester.tap(find.text('Generar tres opciones'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usar como borrador editable'));
      await tester.tap(find.text('Usar como borrador editable'));
      await tester.pumpAndSettle();
      expect(find.text('Opción 2: Opción 2'), findsOneWidget);
      await reveal(
        tester,
        find.byKey(const ValueKey('promotion-option-1')),
        250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('promotion-option-1')));
      await tester.pumpAndSettle();
      expect(result?['title'], 'Opción 2');
      expect(result?['conditions'], 'Condiciones 2');
      expect(result?['service_name'], 'Estética');
      expect(result?['discount_percent'], '10.0');
      expect(result?['starts_on'], isNotEmpty);
      expect(result?['ends_on'], isNotEmpty);
    },
  );
  testWidgets(
    'Revoked authorization is checked again before opening a message',
    (tester) async {
      final repository = ContactFake();
      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentMessageScreen(
            repository: repository,
            member: personal,
            appointment: 'appointment',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('appointment-message')),
        250,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('appointment-message')),
        'Recordatorio sintético',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text('Revisé el contenido y los datos de la cita'),
        250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisé el contenido y los datos de la cita'));
      await tester.pumpAndSettle();
      repository.revoked = true;
      await reveal(tester, find.text('Abrir WhatsApp'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir WhatsApp'));
      await tester.pumpAndSettle();
      expect(repository.reads, 2);
      await reveal(
        tester,
        find.text('No hay autorización vigente para este propósito y canal.'),
        -250,
      );
      expect(
        find.text('No hay autorización vigente para este propósito y canal.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Clinical output is incorporated only after reviewing the selected fields',
    (tester) async {
      Map<String, String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Map<String, String>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClinicalDraftScreen(
                        ai: ClinicalAi(),
                        member: personal,
                        fields: const {'plan': 'Plan del profesional'},
                        currentValues: const {
                          'plan': 'Indicaciones originales',
                        },
                        documentTitle: 'Alta médica',
                      ),
                    ),
                  );
                },
                child: const Text('Abrir borrador'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir borrador'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Preparar borrador con IA'), 250);
      await tester.tap(find.text('Preparar borrador con IA'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usar como borrador editable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar como borrador editable'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await reveal(tester, find.text('Incorporar al documento'), 250);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Incorporar al documento'),
            )
            .onPressed,
        isNull,
      );
      await reveal(
        tester,
        find.text(
          'Revisé y corregí el borrador; está listo para incorporarse al formato y continuar su revisión profesional',
        ),
        -100,
      );
      await tester.tap(
        find.text(
          'Revisé y corregí el borrador; está listo para incorporarse al formato y continuar su revisión profesional',
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Incorporar al documento'), 150);
      await tester.tap(find.text('Incorporar al documento'));
      await tester.pumpAndSettle();
      expect(result, {'plan': 'Indicaciones registradas por el profesional'});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Dictation replaces partial transcripts and ignores speech after stopping',
    (tester) async {
      final voice = VoiceFake();
      final controller = TextEditingController(text: 'Nota original');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DictationField(
                controller: controller,
                label: 'Nota',
                voice: voice,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Dictar texto'));
      await tester.pumpAndSettle();
      voice.emit!('Texto');
      voice.emit!('Texto completo');
      await tester.pump();
      expect(controller.text, 'Nota original\nTexto completo');
      await tester.tap(find.text('Detener dictado'));
      await tester.pumpAndSettle();
      voice.emit!('Texto tardío');
      expect(controller.text, 'Nota original\nTexto completo');
      expect(voice.stopped, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
