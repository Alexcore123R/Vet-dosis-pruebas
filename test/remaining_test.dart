import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/payments_screen.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_archive.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_repository.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_view_model.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_screen.dart';
import 'package:vetdosis_pro/modules/attendance/domain/attendance_repository.dart';
import 'package:vetdosis_pro/modules/attendance/presentation/attendance_view_model.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';

class FakeBackup implements BackupRepository {
  String path = 'clinic/photo.png';
  String? rawSnapshot;
  bool fail = false;
  @override
  Future<String> snapshot(String clinic) async =>
      rawSnapshot ??
      ' {"clinic_id":"$clinic","version":1,"tables":{"inventario":[{"photo_path":"$path","stock":123456789012345.123456789}]}} ';
  @override
  Future<Uint8List> photo(String path) async {
    if (fail) throw StateError('download failed');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Map<String, dynamic>> statistics(String clinic) async => {};
}

class FakeOperations implements OperationsRepository {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    if (fail) throw StateError('forbidden');
    return {
      'tasks': [
        {
          'title': 'Preparar turno',
          'priority': 'media',
          'assigned_to': 'user',
          'completed_at': null,
        },
      ],
      'members': [],
    };
  }

  @override
  Future<void> write(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {}
  @override
  Future<List<Map<String, dynamic>>> medical(
    String clinic, {
    Map<String, dynamic>? details,
    bool consent = false,
  }) async => [];
}

class FakeAttendance implements AttendanceRepository {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    if (fail) throw StateError('forbidden');
    return {
      'events': [
        {'direction': 'entrada'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> qr(String clinic) async => {};
  @override
  Future<void> settings(String clinic, Map<String, dynamic> data) async {}
  @override
  Future<void> consent(String clinic, int version, bool accept) async {}
  @override
  Future<void> scan(
    String clinic,
    String token,
    double latitude,
    double longitude,
    double accuracy,
    String operation,
  ) async {}
  @override
  Future<void> correct(
    String clinic,
    String event,
    String instant,
    String reason,
    String operation,
  ) async {}
}

class PaymentFake implements InventoryRepository {
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async => {
    'sales': [],
    'transactions': [
      {
        'id': 'external',
        'direction': 'ingreso',
        'method': 'tarjeta',
        'amount': '100.00',
        'provider': 'stripe',
        'external_reference': 'ficticio',
        'state': 'pendiente_revision',
        'occurred_at': '2026-10-08T00:00:00Z',
        'net': null,
      },
    ],
  };
  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async =>
      null;
  @override
  Future<void> photo(
    String clinic,
    String product,
    int version,
    Uint8List bytes,
    String extension,
  ) async {}
  @override
  Future<String> photoUrl(String path) async => '';
}

void main() {
  test('Backup rejects deleted attachments declared in snapshot', () async {
    final bytes = await BackupArchive.create(FakeBackup(), 'clinic');
    final a = jsonDecode(utf8.decode(bytes)) as Map;
    a['attachments'] = {};
    expect(
      () =>
          BackupArchive.verify(Uint8List.fromList(utf8.encode(jsonEncode(a)))),
      throwsFormatException,
    );
  });
  test('Frozen PDF is checked against historical hash', () async {
    final pdf = Uint8List.fromList([1, 2]);
    final hash = sha256.convert(pdf).toString();
    final repo = FakeBackup()
      ..rawSnapshot = jsonEncode({
        'clinic_id': 'clinic',
        'version': 1,
        'tables': {
          'inventario': [],
          'form_artifacts': [
            {'pdf': r'\x0102', 'pdf_hash': hash},
          ],
        },
      });
    final bytes = await BackupArchive.create(repo, 'clinic');
    expect(BackupArchive.verify(bytes)['clinic_id'], 'clinic');
    repo.rawSnapshot = jsonEncode({
      'clinic_id': 'clinic',
      'version': 1,
      'tables': {
        'inventario': [],
        'form_artifacts': [
          {'pdf': r'\x0103', 'pdf_hash': hash},
        ],
      },
    });
    final changed = await BackupArchive.create(repo, 'clinic');
    expect(() => BackupArchive.verify(changed), throwsFormatException);
  });
  test('Clinical catalog alteration invalidates its hash', () async {
    final bytes = await BackupArchive.create(
      FakeBackup(),
      'clinic',
      clinicalAssets: {'catalog.json': '{"entries":[]}'},
    );
    final a = jsonDecode(utf8.decode(bytes)) as Map;
    a['clinical_assets']['catalog.json']['json'] = '{}';
    expect(
      () =>
          BackupArchive.verify(Uint8List.fromList(utf8.encode(jsonEncode(a)))),
      throwsFormatException,
    );
  });
  testWidgets(
    'Reception sees reported platform payment pending, without verification privileges',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentsScreen(
            repository: PaymentFake(),
            member: const ClinicMembership(
              clinicId: 'clinic',
              clinicName: 'Clinic',
              userId: 'user',
              role: ClinicRole.recepcion,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('pendiente_revision'), findsOneWidget);
      expect(find.byIcon(Icons.fact_check_outlined), findsNothing);
      expect(
        find.textContaining('Cobrar desde esta app requiere'),
        findsOneWidget,
      );
    },
  );

  test(
    'Backup preserves canonical PostgreSQL numeric text and verifies photos',
    () async {
      final repo = FakeBackup();
      final bytes = await BackupArchive.create(repo, 'clinic');
      final envelope = jsonDecode(utf8.decode(bytes)) as Map;
      expect(envelope['snapshot_json'], await repo.snapshot('clinic'));
      expect(envelope['snapshot_json'], contains('123456789012345.123456789'));
      expect(BackupArchive.verify(bytes)['clinic_id'], 'clinic');
    },
  );
  test('Backup detects changed snapshot and changed attachment', () async {
    final bytes = await BackupArchive.create(FakeBackup(), 'clinic');
    final a = jsonDecode(utf8.decode(bytes)) as Map;
    a['snapshot_json'] = '{}';
    expect(
      () =>
          BackupArchive.verify(Uint8List.fromList(utf8.encode(jsonEncode(a)))),
      throwsFormatException,
    );
    final b = jsonDecode(utf8.decode(bytes)) as Map;
    b['attachments']['clinic/photo.png']['base64'] = base64Encode([9]);
    expect(
      () =>
          BackupArchive.verify(Uint8List.fromList(utf8.encode(jsonEncode(b)))),
      throwsFormatException,
    );
  });
  test(
    'Failed or foreign-clinic photo cannot create a seemingly complete archive',
    () async {
      final failed = FakeBackup()..fail = true;
      await expectLater(
        BackupArchive.create(failed, 'clinic'),
        throwsStateError,
      );
      final foreign = FakeBackup()..path = 'another-clinic/photo.png';
      await expectLater(
        BackupArchive.create(foreign, 'clinic'),
        throwsFormatException,
      );
    },
  );
  test(
    'Operations refresh clears previous records after permission failure',
    () async {
      final repo = FakeOperations();
      final model = OperationsViewModel(repo, 'clinic');
      await model.load();
      expect(model.rows('tasks'), hasLength(1));
      repo.fail = true;
      await model.load();
      expect(model.rows('tasks'), isEmpty);
      expect(model.error, isNotNull);
      model.dispose();
    },
  );
  test('Attendance refresh clears records after permission failure', () async {
    final repo = FakeAttendance();
    final model = AttendanceViewModel(repo, 'clinic');
    await model.load();
    expect(model.data['events'], hasLength(1));
    repo.fail = true;
    await model.load();
    expect(model.data, isEmpty);
    model.dispose();
  });
  testWidgets('Groomer sees assigned tasks but no service editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OperationsScreen(
              repository: FakeOperations(),
              member: const ClinicMembership(
                clinicId: 'clinic',
                clinicName: 'Clinic',
                userId: 'user',
                role: ClinicRole.estilista,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pendientes'));
    await tester.pumpAndSettle();
    expect(find.text('Preparar turno · media'), findsOneWidget);
    await tester.tap(find.text('Servicios'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo servicio'), findsNothing);
  });
}
