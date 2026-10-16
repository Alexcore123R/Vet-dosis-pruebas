abstract interface class PermissionRepository {
  Future<Map<String, dynamic>> permissions(String clinicId);
  Future<Map<String, dynamic>> professionalEvidence(String clinicId);
  Future<void> setJobLabel(String clinicId, String userId, String label);
  Future<void> setProcedure(
    String clinicId,
    String? id,
    String name,
    bool active,
  );
  Future<void> grantPermission(
    String clinicId,
    String userId,
    String code,
    String? procedureId,
    DateTime until,
    String reason,
  );
  Future<void> revokePermission(String grantId, String reason);
  Future<void> proposeResponsible(
    String clinicId,
    String userId,
    DateTime until,
  );
  Future<void> respondResponsible(String designationId, bool accept);
  Future<void> revokeResponsible(String designationId);
  Future<void> reviewProfessional(
    String clinicId,
    String versionId,
    DateTime reviewed,
    String hash,
    String reference,
    DateTime until,
  );
  Future<void> revokeProfessional(String verificationId, String reason);
}
