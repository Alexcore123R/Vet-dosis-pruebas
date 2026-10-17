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
  test('backup access contract validates both scopes', () {
    final access = BackupAccess.read({
      'schema_version': 1,
      'mode': 'explicit_backup',
      'workspace_kind': 'personal',
      'exports': {'clinic': false, 'personal': true},
      'statistics': false,
    });
    expect(access.personal, true);
    expect(access.clinic, false);
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
            '{"format":"vetdosis-operational-backup","version":1,"clinic_id":"clinic","tables":{"vet_patients":[{"id":"p1","clinic_id":"clinic","name":"Prueba"}]}}';
      final archive = await BackupArchive.create(repo, 'clinic');
      final report = BackupRecoveryReport.inspect(archive, 'clinic');
      expect(report.records, 1);
      expect(jsonDecode(report.toJson())['restored'], false);
      expect(
        () => BackupRecoveryReport.inspect(archive, 'other'),
        throwsFormatException,
      );
      repo.rawSnapshot =
          '{"format":"vetdosis-operational-backup","version":1,"clinic_id":"clinic","tables":{"vet_patients":[{"id":"p1","clinic_id":"other"}]}}';
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
