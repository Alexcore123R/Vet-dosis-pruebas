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

abstract interface class ProductivityRepository {
  Future<Map<String, dynamic>> productivity(String clinic, String week);
  Future<void> planWrite(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  );
}

abstract interface class ServiceContactRepository {
  Future<Map<String, dynamic>> appointmentContact(
    String clinic,
    String appointment,
  );
  Future<void> saveServiceContact(
    String clinic,
    String owner,
    String purpose,
    bool whatsapp,
    bool email,
    String source,
  );
}

abstract interface class ContactDirectoryRepository {
  Future<Map<String, dynamic>> contactDirectory(String clinic);
  Future<void> saveContact(
    String clinic,
    String kind,
    String id,
    Map<String, dynamic> data,
  );
  Future<List<Map<String, dynamic>>> clients(String clinic);
  Future<void> saveMarketingPreferences(
    String clinic,
    String owner,
    bool whatsapp,
    bool email,
    String source,
  );
}

abstract interface class MarketingRepository {
  Future<List<Map<String, dynamic>>> promotions(String clinic);
  Future<void> savePromotion(String clinic, Map<String, dynamic> data);
  Future<Map<String, dynamic>> loyaltyAccount(String clinic, String owner);
  Future<void> recordLoyalty(
    String clinic,
    String owner,
    String promotion,
    String action,
    int units,
    String note,
    String operation,
  );
}

abstract interface class CommissionRepository {
  Future<Map<String, dynamic>> commissionAccount(String clinic);
  Future<void> saveCommissionSchedule(
    String clinic,
    String cadence,
    DateTime payOn,
  );
  Future<void> payCommissionPeriod(String clinic);
}

abstract interface class AppointmentPatientRepository {
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  );
}
