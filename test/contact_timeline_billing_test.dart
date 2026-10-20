import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_view_model.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_contacts.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_timeline.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/operations/domain/appointment_links.dart';

PatientEvent sample(
  String id,
  String date,
  String reason, {
  DateTime? recorded,
}) => PatientEvent(
  id: id,
  kind: EventKind.soap,
  data: {'date': date, 'reason': reason},
  createdAt: recorded ?? DateTime.utc(2026, 10, 20),
  createdBy: 'synthetic',
);

class LinkRepository
    implements OperationsRepository, AppointmentLinksRepository {
  Future<Map<String, Map<String, dynamic>>> Function() handler = () async => {
    'a': {
      'contact': {'phone': 'Synthetic'},
    },
  };
  @override
  Future<Map<String, dynamic>> dashboard(String c) async => {
    'appointments': [
      {'id': 'a'},
    ],
    'permissions': {'appointment.read': true},
  };
  @override
  Future<Map<String, Map<String, dynamic>>> patientLinks(
    String c,
    List<String> ids,
  ) => handler();
  @override
  Future<void> write(
    String c,
    String a,
    Map<String, dynamic> d,
    String op,
  ) async {}
  @override
  Future<List<Map<String, dynamic>>> medical(
    String c, {
    Map<String, dynamic>? details,
    bool consent = false,
  }) async => [];
}

void main() {
  test(
    'Contact URIs reject commands and do not guess an international country',
    () {
      expect(contactCall('+52 (33) 1234-5678')?.scheme, 'tel');
      expect(contactWhatsapp('3312345678', 'synthetic'), isNull);
      expect(
        contactWhatsapp(
          '+52 33 1234 5678',
          'Texto & prueba',
        )?.queryParameters['text'],
        'Texto & prueba',
      );
      expect(contactCall('*123#'), isNull);
      expect(contactCall('tel:12345678?x=1'), isNull);
    },
  );
  test(
    'Contact consent can be withdrawn; incomplete pairs cannot be stored',
    () {
      final out = validateContact({
        'name': 'Tutor sintético',
        'contact_name': 'Contacto sintético',
        'contact_phone': '+520000000001',
        'contact_authorized': false,
      });
      expect(out['contact_authorized'], false);
      expect(
        () => validateContact({
          'name': 'Tutor',
          'contact_phone': '+520000000001',
        }),
        throwsFormatException,
      );
      expect(
        () => validateContact({'name': 'Tutor', 'contact_authorized': true}),
        throwsFormatException,
      );
    },
  );
  test(
    'Timeline uses clinical date, not insertion order, and accent-insensitive reasons',
    () {
      final old = sample('old', '2026-01-01', 'Revisión');
      final recent = sample(
        'recent',
        '2026-10-01',
        'Tos',
        recorded: DateTime.utc(2026, 10, 2),
      );
      expect(patientTimeline([old, recent]).map((e) => e.id), [
        'recent',
        'old',
      ]);
      expect(
        patientTimeline([recent, old], query: 'revision').single.id,
        'old',
      );
      expect(patientTimeline([recent, old], oldestFirst: true).first.id, 'old');
      expect(patientTimeline([recent, old], byReason: true).first.id, 'old');
    },
  );
  test(
    'Unknown preventive application is sorted by recording date, not an invented application',
    () {
      final event = PatientEvent(
        id: 'unknown',
        kind: EventKind.preventive,
        data: {
          'date': '1900-01-01',
          'preventive_version': 1,
          'date_precision': 'unknown',
        },
        createdAt: DateTime.utc(2026, 10, 20),
        createdBy: 'synthetic',
      );
      expect(eventClinicalDate(event), DateTime.utc(2026, 10, 20));
    },
  );
  test('No-charge, unpaid, paid and partially settled groups are distinct', () {
    String label(String state, String total, String paid, int count) =>
        AppointmentBilling.read({
          'state': state,
          'total': total,
          'paid': paid,
          'charge_count': count,
        }).label;
    expect(label('no_charge', '0', '0', 0), 'Sin cargo registrado');
    expect(label('unpaid', '100.00', '0.00', 1), contains('Pendiente de pago'));
    expect(label('paid', '100.00', '100.00', 1), startsWith('Pagado'));
    final partial = AppointmentBilling.read({
      'state': 'partial',
      'total': '0.30',
      'paid': '0.10',
      'charge_count': 2,
    });
    expect(partial.remaining.decimal, '0.20');
    expect(partial.label, contains('Abonado'));
    expect(
      () => AppointmentBilling.read({
        'state': 'paid',
        'total': '100',
        'paid': '30',
        'charge_count': 2,
      }),
      throwsFormatException,
    );
    expect(
      () => AppointmentBilling.read({
        'state': 'paid',
        'total': '100',
        'paid': '150',
        'charge_count': 1,
      }),
      throwsFormatException,
    );
  });
  test(
    'Agenda clears old contact and billing on a failed supplemental refresh',
    () async {
      final repo = LinkRepository();
      final model = OperationsViewModel(repo, 'c');
      await model.load();
      expect(model.links, isNotEmpty);
      repo.handler = () async => throw StateError('revoked');
      await model.load();
      expect(model.links, isEmpty);
      expect(model.linksError, isNotNull);
      model.dispose();
    },
  );
  test(
    'A late agenda contact query cannot restore data after disposal',
    () async {
      final entered = Completer<void>(),
          pending = Completer<Map<String, Map<String, dynamic>>>();
      final repo = LinkRepository()
        ..handler = () {
          entered.complete();
          return pending.future;
        };
      final model = OperationsViewModel(repo, 'c');
      final load = model.load();
      await entered.future;
      model.dispose();
      pending.complete({
        'a': {
          'contact': {'phone': 'Synthetic'},
        },
      });
      await load;
      expect(model.links, isEmpty);
      expect(model.data, isEmpty);
    },
  );
}
