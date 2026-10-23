import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/backup/presentation/backup_screen.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_archive.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_cipher.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_recovery_report.dart';
import 'package:vetdosis_pro/modules/backup/domain/backup_repository.dart';
import 'package:vetdosis_pro/modules/backup/presentation/backup_password_dialog.dart';
import 'remaining_test.dart' show FakeBackup;

class HydratingBackup extends FakeBackup {
  HydratingBackup({this.applied = false});
  final bool applied;
  int previewReads = 0;

  @override
  Future<Map<String, dynamic>> workspace(String clinic) async => {
    'schema_version': 1,
    'mode': 'explicit_backup',
    'workspace_kind': 'clinic',
    'exports': {'clinic': true, 'personal': false},
    'statistics': false,
    'restore_preview': true,
  };

  @override
  Future<Map<String, dynamic>> restorePreview(String clinic) async {
    previewReads++;
    return {
      'schema_version': 1,
      'mode': 'restore_preview',
      'stage': {
        'stage_id': '00000000-0000-0000-0000-000000000333',
        'archive_sha256': 'a' * 64,
        'expires_at': '2030-01-14T00:00:00Z',
        'conflicts': null,
        'decisions': null,
        'preflight': null,
        'owner_payload': applied
            ? {
                'payload_sha256': 'b' * 64,
                'rows': 1,
                'apply_report': {
                  'mode': 'restore_apply_owners',
                  'created': 1,
                  'kept_existing': 0,
                  'imports_applied': true,
                },
              }
            : null,
      },
      'imports_applied': applied,
    };
  }
}

class CountingBackup extends FakeBackup {
  int reads = 0;
  bool allow = true;
  @override
  Future<Map<String, dynamic>> workspace(String clinic) async => {
    'schema_version': 1,
    'mode': 'explicit_backup',
    'workspace_kind': 'clinic',
    'exports': {'clinic': allow, 'personal': false},
    'statistics': allow,
  };
  @override
  Future<Map<String, dynamic>> statistics(String clinic) async {
    reads++;
    return {};
  }
}

void main() {
  test('Manual backup picker cancellation is not reported as a saved backup', () {
    expect(
      manualBackupSaveStatus(savedFile: null, encrypted: true),
      contains('cancelado'),
    );
    expect(
      manualBackupSaveStatus(savedFile: null, encrypted: true),
      isNot(contains('selector confirmó')),
    );
  });

  test('Manual Drive target is acknowledged without claiming cloud sync', () {
    final encrypted = manualBackupSaveStatus(
      savedFile: Uri.parse(
        'content://com.google.android.apps.docs.storage/document/synthetic',
      ),
      encrypted: true,
    );
    expect(encrypted, contains('.vetbackup cifrado'));
    expect(encrypted, contains('comprueba en Drive'));
    expect(encrypted, contains('no confirma la sincronización'));
    expect(encrypted, isNot(contains('content://')));

    final plain = manualBackupSaveStatus(
      savedFile: Uri.parse('file:///synthetic/backup.json'),
      encrypted: false,
    );
    expect(plain, contains('SIN CIFRAR'));
    expect(plain, isNot(contains('.vetbackup cifrado')));
  });
  test('persisted restore preview is normalized with owner apply state', () {
    final state = readRestorePreviewState({
      'schema_version': 1,
      'mode': 'restore_preview',
      'stage': {
        'stage_id': '00000000-0000-0000-0000-000000000333',
        'archive_sha256': 'a' * 64,
        'decisions': {
          'tables': {
            'vet_owners': {
              'create_candidate': 2,
              'keep_existing': 1,
            },
            'vet_patients': {
              'create_candidate': 3,
              'keep_existing': 2,
            },
          },
        },
        'owner_payload': {
          'payload_sha256': 'b' * 64,
          'rows': 3,
          'apply_report': {
            'created': 2,
            'kept_existing': 1,
            'imports_applied': true,
          },
        },
        'patient_payload': {
          'payload_sha256': 'c' * 64,
          'rows': 5,
          'apply_report': {
            'created': 3,
            'kept_existing': 2,
            'imports_applied': true,
          },
        },
      },
      'imports_applied': true,
    });
    expect(state['stage'], isNotNull);
    expect((state['owner_payload'] as Map)['create_candidate'], 2);
    expect((state['owner_payload'] as Map)['keep_existing'], 1);
    expect((state['owner_apply'] as Map)['created'], 2);
    expect((state['patient_payload'] as Map)['create_candidate'], 3);
    expect((state['patient_payload'] as Map)['keep_existing'], 2);
    expect((state['patient_apply'] as Map)['created'], 3);
    expect(state['imports_applied'], true);
  });

  testWidgets('active restore preview is rehydrated after reopening screen', (
    tester,
  ) async {
    final repo = HydratingBackup(applied: true);
    const admin = ClinicMembership(
      clinicId: 'clinic',
      clinicName: 'Prueba',
      userId: 'user',
      role: ClinicRole.admin,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupScreen(repository: repo, member: admin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.previewReads, 1);
    expect(find.text('Vista previa del servidor recuperada'), findsOneWidget);
    expect(find.text('Cerrar vista previa'), findsOneWidget);
    expect(find.textContaining('no revierte'), findsOneWidget);
  });

  test('restore preview close wording distinguishes applied imports', () {
    expect(restorePreviewCloseLabel(false), 'Descartar vista previa');
    expect(
      restorePreviewCloseMessage(false),
      'Vista previa descartada. No se modificó ningún registro.',
    );
    expect(restorePreviewCloseLabel(true), 'Cerrar vista previa');
    expect(
      restorePreviewCloseMessage(true),
      contains('no los revierte'),
    );
  });

  test('backup access contract validates both scopes', () {
    final access = BackupAccess.read({
      'schema_version': 1,
      'mode': 'explicit_backup',
      'workspace_kind': 'personal',
      'exports': {'clinic': false, 'personal': true},
      'statistics': false,
      'restore_preview': true,
    });
    expect(access.personal, true);
    expect(access.clinic, false);
    expect(access.restorePreview, true);
    expect(access.restoreApplyTest, false);
    expect(
      () => BackupAccess.read({
        'schema_version': 1,
        'mode': 'explicit_backup',
        'workspace_kind': 'personal',
        'exports': {'clinic': false},
        'statistics': false,
      }),
      throwsFormatException,
    );
  });

  testWidgets(
    'Backup protection is on and server capability controls statistics',
    (tester) async {
      final repo = CountingBackup();
      const admin = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Prueba',
        userId: 'user',
        role: ClinicRole.admin,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackupScreen(repository: repo, member: admin),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      final calls = repo.reads;
      repo.allow = false;
      const auxiliary = ClinicMembership(
        clinicId: 'clinic',
        clinicName: 'Prueba',
        userId: 'aux',
        role: ClinicRole.auxiliar,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackupScreen(
              key: const ValueKey('aux'),
              repository: repo,
              member: auxiliary,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, calls);
      expect(
        find.text('No tienes un alcance de respaldo vigente.'),
        findsOneWidget,
      );
    },
  );

  test(
    'Password protection preserves bytes and rejects wrong password or modified authentication',
    () async {
      final repo = FakeBackup()
        ..rawSnapshot =
            '{"format":"vetdosis-operational-backup","version":1,"clinic_id":"clinic","server_at":"2030-01-01T00:00:00Z","tables":{"inventario":[{"photo_path":"clinic/photo.png","stock":123456789012345.123456789}],"vet_owners":[{"id":"owner","name":"Propietario ficticio"}]}}';
      final archive = await BackupArchive.create(repo, 'clinic');
      const password = 'contraseña ficticia de pruebas';
      final first = await BackupCipher.encrypt(archive, password);
      final second = await BackupCipher.encrypt(archive, password);
      expect(first, isNot(equals(second)));
      expect(utf8.decode(first), isNot(contains('Propietario ficticio')));
      expect(await BackupCipher.decrypt(first, password), equals(archive));
      expect(
        BackupArchive.verify(
          await BackupCipher.decrypt(second, password),
        )['clinic_id'],
        'clinic',
      );
      await expectLater(
        BackupCipher.decrypt(first, 'contraseña incorrecta'),
        throwsFormatException,
      );
      final changed = jsonDecode(utf8.decode(first)) as Map;
      final mac = base64Decode(changed['mac'] as String)..[0] ^= 1;
      changed['mac'] = base64Encode(mac);
      await expectLater(
        BackupCipher.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(changed))),
          password,
        ),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
    tags: const ['crypto-slow'],
  );
  test(
    'Recovery inspection cannot mix clinics and exposes counts without rewriting numeric data',
    () async {
      final repo = FakeBackup()
        ..rawSnapshot =
            '{"format":"vetdosis-operational-backup","version":1,"clinic_id":"clinic","tables":{"vet_owners":[{"id":"00000000-0000-0000-0000-000000000200","clinic_id":"clinic","name":"Tutor"}],"vet_patients":[{"id":"00000000-0000-0000-0000-000000000201","clinic_id":"clinic","owner_id":"00000000-0000-0000-0000-000000000200","name":"Prueba","species":"felino","breed":"doméstico","sex":"hembra","birth_date":"2021-02-03"}]}}';
      final archive = await BackupArchive.create(repo, 'clinic');
      final report = BackupRecoveryReport.inspect(archive, 'clinic');
      expect(report.records, 2);
      expect(report.clinicBackup, true);
      expect(report.archiveSha256, hasLength(64));
      expect(report.conflictManifestSha256, hasLength(64));
      expect(
        report.conflictManifest['vet_patients'],
        ['00000000-0000-0000-0000-000000000201'],
      );
      expect(
        report.dependencyManifest['vet_patients']![
            '00000000-0000-0000-0000-000000000201'],
        [
          {
            'table': 'vet_owners',
            'id': '00000000-0000-0000-0000-000000000200',
          },
        ],
      );
      expect(report.dependencyManifestSha256, hasLength(64));
      expect(report.restoreOwners, hasLength(1));
      expect(
        report.restoreOwners.single['id'],
        '00000000-0000-0000-0000-000000000200',
      );
      expect(report.restoreOwners.single['name'], 'Tutor');
      expect(report.restorePatients, hasLength(1));
      expect(
        report.restorePatients.single['id'],
        '00000000-0000-0000-0000-000000000201',
      );
      expect(report.restorePatients.single['species'], 'felino');
      expect(
        report.restorePatients.single['owner_id'],
        '00000000-0000-0000-0000-000000000200',
      );
      expect(
        jsonDecode(report.toJson())['restore_patient_candidates'],
        1,
      );
      expect(jsonDecode(report.toJson())['restored'], false);
      expect(
        () => BackupRecoveryReport.inspect(archive, 'other'),
        throwsFormatException,
      );
      repo.rawSnapshot =
          '{"format":"vetdosis-operational-backup","version":1,"clinic_id":"clinic","tables":{"vet_patients":[{"id":"00000000-0000-0000-0000-000000000201","clinic_id":"other"}]}}';
      final mixed = await BackupArchive.create(repo, 'clinic');
      expect(
        () => BackupRecoveryReport.inspect(mixed, 'clinic'),
        throwsFormatException,
      );
    },
  );
  test(
    'Malformed archives and photographs outside their clinic are rejected',
    () async {
      expect(
        () => BackupArchive.verify(Uint8List.fromList(utf8.encode('{}'))),
        throwsFormatException,
      );
      final repo = FakeBackup()..path = 'clinic/../other/photo.png';
      await expectLater(
        BackupArchive.create(repo, 'clinic'),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'Password dialog enforces confirmation and cancellation releases controls',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await requestBackupPassword(context, creating: true);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'contraseña larga',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'distinta');
      await tester.tap(find.text('Proteger'));
      await tester.pumpAndSettle();
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
