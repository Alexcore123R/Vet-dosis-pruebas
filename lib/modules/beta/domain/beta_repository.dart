class BetaState {
  const BetaState(this.data);
  final Map<String, dynamic> data;
  String get mode => data['mode'] as String? ?? 'unavailable';
  bool get canEnter => const [
    'internal',
    'active',
    'sponsor_grace',
    'read_export',
  ].contains(mode);
  bool get termsPending => data['terms_acceptance_required'] == true;
  bool get readOnly => mode == 'read_export' || termsPending;
  bool get warning => data['expiry_warning'] == true;
  bool get admissionsOpen => data['admissions_enabled'] == true;
  bool get platform => mode == 'platform_admin';
  bool get mfaReady => data['mfa_ready'] == true;
  Map<String, dynamic>? get terms =>
      data['terms'] is Map ? Map<String, dynamic>.from(data['terms']) : null;
}

class BetaMfaSetup {
  const BetaMfaSetup(this.factorId, {this.uri, this.secret});
  final String factorId;
  final String? uri, secret;
}

abstract interface class BetaRepository {
  Future<BetaState> status(String? clinicId);
  Future<void> enroll(String version, String hash, String? token);
  Future<void> acceptTerms(String version, String hash);
  Future<void> sponsor(String clinicId);
  Future<Map<String, dynamic>> administration();
  Future<void> setEmail(String email, bool enabled, String reason);
  Future<Map<String, dynamic>> invite(String email, int hours);
  Future<void> revokeInvite(String id, String reason);
  Future<BetaMfaSetup> prepareMfa();
  Future<void> verifyMfa(String factorId, String code);
}

abstract interface class PlatformProfessionalRepository {
  Future<List<Map<String, dynamic>>> globalProfessionalReviews();
  Future<void> revokeGlobalProfessionalReview(String id, String reason);
}
