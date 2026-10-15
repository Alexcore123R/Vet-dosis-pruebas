import '../../core/domain/build_channel.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../offline/domain/offline_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/auth_repository.dart';
import '../domain/clinic_membership.dart';

class SupabaseAuthRepository
    implements
        AuthRepository,
        PersonalWorkspaceRepository,
        PasswordRecoveryRepository,
        TeamRepository {
  SupabaseAuthRepository(this.client, {this.existingSchema = false});
  final bool existingSchema;
  final SupabaseClient client;
  bool _recoveringPassword = false;
  @override
  bool get recoveringPassword => _recoveringPassword;
  @override
  Future<void> requestPasswordRecovery(String email) async {
    await client.auth.resetPasswordForEmail(email.trim(), redirectTo: redirect);
  }

  @override
  Future<void> completePasswordRecovery(String password) async {
    if (!_recoveringPassword || userId == null) {
      throw StateError('recovery_session_required');
    }
    await client.auth.updateUser(UserAttributes(password: password));
    _recoveringPassword = false;
  }

  String? get redirect => kIsWeb
      ? Uri.base.replace(query: '', fragment: '').toString()
      : nativeAuthRedirect(const String.fromEnvironment('APP_CHANNEL'));
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      _recoveringPassword = true;
    } else if (state.event == AuthChangeEvent.signedOut) {
      _recoveringPassword = false;
    }
  });
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> register(String email, String password) async {
    await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: redirect,
    );
  }

  @override
  Future<void> googleSignIn() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirect,
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<List<ClinicMembership>> memberships() async {
    final id = userId;
    if (id == null) return [];
    final List<Map<String, dynamic>> rows;
    try {
      if (existingSchema) {
        final r = await client
            .rpc('workspace_memberships')
            .timeout(const Duration(seconds: 10));
        return (r as List)
            .map(
              (row) => ClinicMembership(
                clinicId: row['clinic_id'] as String,
                userId: row['user_id'] as String,
                clinicName: row['clinic_name'] as String,
                role: ClinicRole.parse(row['role'] as String),
                workspaceKind: row['workspace_kind'] as String,
              ),
            )
            .toList();
      }
      rows = await client
          .from(existingSchema ? 'clinic_members' : 'clinic_memberships')
          .select('clinic_id,user_id,role,clinics(name)')
          .eq('user_id', id)
          .timeout(const Duration(seconds: 10));
    } on http.ClientException {
      throw const NetworkUnavailable();
    } on TimeoutException {
      throw const NetworkUnavailable();
    }
    return rows
        .map(
          (row) => ClinicMembership(
            clinicId: row['clinic_id'] as String,
            userId: row['user_id'] as String,
            clinicName:
                (row['clinics'] as Map<String, dynamic>)['name'] as String,
            role: ClinicRole.parse(row['role'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> createPersonalWorkspace() async {
    await client.rpc('personal_workspace_create');
  }

  @override
  Future<void> createClinic(String name) async {
    await client.rpc(
      'create_clinic',
      params: {existingSchema ? 'p_name' : 'clinic_name': name.trim()},
    );
  }

  @override
  Future<void> joinClinic(String token) async {
    await client.rpc(
      'accept_clinic_invitation',
      params: {'invite_token': token.trim()},
    );
  }

  @override
  Future<String> invite(String clinicId, String email, ClinicRole role) async {
    return await client.rpc(
          'create_clinic_invitation',
          params: {
            'target_clinic': clinicId,
            'invite_email': email.trim(),
            'invite_role': role.name,
          },
        )
        as String;
  }

  @override
  bool get teamManagementAvailable => existingSchema;
  @override
  Future<Map<String, dynamic>> team(String clinicId) async {
    if (!existingSchema) throw StateError('team_schema_required');
    return Map<String, dynamic>.from(
      await client.rpc(
            'clinic_team_snapshot',
            params: {'target_clinic': clinicId},
          )
          as Map,
    );
  }

  @override
  Future<void> setMemberRole(
    String clinicId,
    String userId,
    ClinicRole role,
  ) async {
    await client.rpc(
      'set_clinic_member_role',
      params: {
        'target_clinic': clinicId,
        'target_user': userId,
        'new_role': role.name,
      },
    );
  }

  @override
  Future<void> removeMember(String clinicId, String userId) async {
    await client.rpc(
      'remove_clinic_member',
      params: {'target_clinic': clinicId, 'target_user': userId},
    );
  }

  @override
  Future<void> revokeInvitation(String invitationId) async {
    await client.rpc(
      'revoke_clinic_invitation',
      params: {'invitation_id': invitationId},
    );
  }
}
