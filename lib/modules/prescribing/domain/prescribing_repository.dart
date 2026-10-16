import '../../forms/domain/form_models.dart';

abstract interface class PrescribingRepository {
  Future<dynamic> read(String command, Map<String, dynamic> args);
  Future<dynamic> write(String command, Map<String, dynamic> args);
  Future<List<Map<String, dynamic>>> products();
  Future<ReviewedPdf> pdf(String kind, String id);
}

abstract interface class MedicationPermissionRepository {
  Future<Map<String, dynamic>?> medicationPermissions(
    String clinic,
    String? caseId,
  );
}

abstract interface class PrescriptionPermissionRepository {
  Future<Map<String, dynamic>?> prescriptionPermissions(String clinic);
}

abstract interface class ReportPermissionRepository {
  Future<Map<String, dynamic>?> reportPermissions(String clinic);
}
