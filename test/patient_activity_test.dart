import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_activity.dart';
import 'package:vetdosis_pro/modules/patients/application/patient_activity_model.dart';

Map<String, dynamic> data({
  String clinic = 'c',
  List<Map<String, dynamic>> rows = const [],
}) => {
  'schema_version': 1,
  'clinic_id': clinic,
  'day': '2026-10-20',
  'timezone': 'America/Mexico_City',
  'server_time': '2026-10-20T12:00:00Z',
  'hospital_allowed': true,
  'appointments_allowed': true,
  'items': rows,
};
Map<String, dynamic> row(String patient, String kind, String record) => {
  'patient_id': patient,
  'record_id': record,
  'kind': kind,
  'detail': 'Synthetic',
  'local_time': '2026-10-19 23:00',
  'responsible': '',
};

class FakeActivity implements PatientActivityRepository {
  Future<PatientActivitySnapshot> Function() handler = () async =>
      PatientActivitySnapshot.read(data(), 'c');
  @override
  Future<PatientActivitySnapshot> activity(String clinic) => handler();
}

void main() {
  test('Counts patients rather than stays or visits; statuses coexist', () {
    final snapshot = PatientActivitySnapshot.read(
      data(
        rows: [
          row('p', 'hospitalized', 's1'),
          row('p', 'hospitalized', 's2'),
          row('p', 'consultation', 'a1'),
          row('other', 'service', 'a2'),
        ],
      ),
      'c',
    );
    expect(snapshot.count(PatientActivityKind.hospitalized, {'p'}), 1);
    expect(snapshot.count(PatientActivityKind.consultation, {'p'}), 1);
    expect(snapshot.count(PatientActivityKind.service, {'p'}), 0);
    expect(snapshot.forPatient('p').length, 3);
  });
  test('Unknown schema, different clinic or unauthorized rows fail closed', () {
    expect(
      () => PatientActivitySnapshot.read({...data(), 'schema_version': 2}, 'c'),
      throwsFormatException,
    );
    expect(
      () => PatientActivitySnapshot.read(data(clinic: 'other'), 'c'),
      throwsFormatException,
    );
    expect(
      () => PatientActivitySnapshot.read({
        ...data(rows: [row('p', 'hospitalized', 's')]),
        'hospital_allowed': false,
      }, 'c'),
      throwsFormatException,
    );
  });
  test(
    'Failure clears a successful snapshot; resume cannot revive an old request',
    () async {
      final repository = FakeActivity();
      final model = PatientActivityModel(repository, 'c');
      await model.load();
      expect(model.snapshot, isNotNull);
      repository.handler = () async => throw StateError('revoked');
      await model.load();
      expect(model.snapshot, isNull);
      expect(model.error, isNotNull);
      final pending = Completer<PatientActivitySnapshot>();
      repository.handler = () => pending.future;
      final load = model.load();
      model.clear();
      pending.complete(PatientActivitySnapshot.read(data(), 'c'));
      await load;
      expect(model.snapshot, isNull);
      model.dispose();
    },
  );
  test('Disposal discards in-flight private rows', () async {
    final pending = Completer<PatientActivitySnapshot>();
    final repository = FakeActivity()..handler = () => pending.future;
    final model = PatientActivityModel(repository, 'c');
    final load = model.load();
    model.dispose();
    pending.complete(PatientActivitySnapshot.read(data(), 'c'));
    await load;
    expect(model.snapshot, isNull);
  });
}
