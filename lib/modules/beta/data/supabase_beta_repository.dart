import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/beta_repository.dart';

class SupabaseBetaRepository
    implements BetaRepository, PlatformProfessionalRepository {
  SupabaseBetaRepository(this.client, this.build);
  final SupabaseClient client;
  final int build;
  @override
  Future<BetaState> status(String? clinicId) async => BetaState(
    Map<String, dynamic>.from(
      await client.rpc(
        'beta_status',
        params: {'p_build': build, 'p_clinic': clinicId},
      ),
    ),
  );
  @override
  Future<void> enroll(String version, String hash, String? token) async {
    await client.rpc(
      'beta_enroll',
      params: {'p_terms': version, 'p_hash': hash, 'p_token': token},
    );
  }

  @override
  Future<void> acceptTerms(String version, String hash) async {
    await client.rpc(
      'beta_accept_terms',
      params: {'p_terms': version, 'p_hash': hash},
    );
  }

  @override
  Future<void> sponsor(String clinicId) async {
    await client.rpc('beta_sponsor_accept', params: {'p_clinic': clinicId});
  }

  @override
  Future<Map<String, dynamic>> administration() async =>
      Map<String, dynamic>.from(await client.rpc('platform_beta_list'));
  @override
  Future<void> setEmail(String email, bool enabled, String reason) async {
    await client.rpc(
      'platform_beta_set_email',
      params: {'p_email': email, 'p_enabled': enabled, 'p_reason': reason},
    );
  }

  @override
  Future<Map<String, dynamic>> invite(String email, int hours) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'platform_beta_create_invite',
          params: {'p_email': email, 'p_hours': hours},
        ),
      );
  @override
  Future<void> revokeInvite(String id, String reason) async {
    await client.rpc(
      'platform_beta_revoke_invite',
      params: {'p_id': id, 'p_reason': reason},
    );
  }

  @override
  Future<BetaMfaSetup> prepareMfa() async {
    final factors = await client.auth.mfa.listFactors();
    if (factors.totp.isNotEmpty) return BetaMfaSetup(factors.totp.first.id);
    for (final factor in factors.all) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.unverified &&
          factor.friendlyName == 'Administración VetDosis') {
        await client.auth.mfa.unenroll(factor.id);
      }
    }
    final result = await client.auth.mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: 'Administración VetDosis',
    );
    return BetaMfaSetup(
      result.id,
      uri: result.totp?.uri,
      secret: result.totp?.secret,
    );
  }

  @override
  Future<void> verifyMfa(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
    await client.auth.refreshSession();
  }

  @override
  Future<List<Map<String, dynamic>>> globalProfessionalReviews() async =>
      (await client.rpc('platform_beta_professional_list') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  @override
  Future<void> revokeGlobalProfessionalReview(String id, String reason) async {
    await client.rpc(
      'platform_beta_professional_revoke',
      params: {'p_id': id, 'p_reason': reason},
    );
  }
}
