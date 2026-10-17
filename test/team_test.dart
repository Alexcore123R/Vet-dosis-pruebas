import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/auth/presentation/team_screen.dart';
import 'support/fake_auth.dart';

const admin = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Clínica A',
  userId: 'user-a',
  role: ClinicRole.admin,
);

class TeamFake extends FakeAuth implements TeamRepository {
  @override
  Future<bool?> canManageWorkspace(String clinicId) async => clinicId == 'a';
  @override
  bool get teamManagementAvailable => true;
  int removals = 0;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> team(String clinicId) async {
    if (fail) throw StateError('denied');
    return {
      'members': [
        {'user_id': 'user-b', 'email': 'team@example.test', 'role': 'auxiliar'},
      ],
      'invitations': [],
    };
  }

  @override
  Future<void> removeMember(String clinicId, String userId) async {
    removals++;
  }

  @override
  Future<void> setMemberRole(
    String clinicId,
    String userId,
    ClinicRole role,
  ) async {}
  @override
  Future<void> revokeInvitation(String invitationId) async {}
}

void main() {
  testWidgets(
    'Team removal requires confirmation and failed refresh hides private data',
    (tester) async {
      final repo = TeamFake()..rows = [admin];
      final model = AuthViewModel(repo);
      await model.start();
      await tester.pumpWidget(
        MaterialApp(
          home: TeamScreen(model: model, clinic: admin),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('team@example.test'), findsOneWidget);
      await tester.tap(find.text('Dar de baja de esta clínica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.removals, 0);
      await tester.tap(find.text('Dar de baja de esta clínica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(repo.removals, 1);
      repo.fail = true;
      await tester.tap(find.text('Actualizar equipo'));
      await tester.pumpAndSettle();
      expect(find.text('team@example.test'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await repo.controller.close();
    },
  );
  test(
    'Invitation status distinguishes accepted revoked expired and pending',
    () {
      expect(invitationState({'accepted_at': 'now'}), 'Aceptada');
      expect(invitationState({'revoked_at': 'now'}), 'Revocada');
      expect(
        invitationState({'expires_at': '2000-01-01T00:00:00Z'}),
        'Vencida',
      );
      expect(
        invitationState({'expires_at': '2100-01-01T00:00:00Z'}),
        'Pendiente',
      );
    },
  );
}
