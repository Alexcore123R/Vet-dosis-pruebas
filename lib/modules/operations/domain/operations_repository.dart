abstract class OperationsRepository {
  Future<Map<String, dynamic>> dashboard(String clinic);
  Future<void> write(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  );
  Future<List<Map<String, dynamic>>> medical(
    String clinic, {
    Map<String, dynamic>? details,
    bool consent = false,
  });
}

abstract interface class CommissionRepository {
  Future<Map<String, dynamic>> commissionAccount(String clinic);
  Future<void> saveCommissionSchedule(String clinic, String cadence, DateTime payOn);
  Future<void> payCommissionPeriod(String clinic);
}

abstract interface class AppointmentPatientRepository {
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  );
}
