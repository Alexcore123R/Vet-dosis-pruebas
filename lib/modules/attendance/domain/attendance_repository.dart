abstract class AttendanceRepository {
  Future<Map<String, dynamic>> dashboard(String clinic);
  Future<Map<String, dynamic>> qr(String clinic);
  Future<void> settings(String clinic, Map<String, dynamic> data);
  Future<void> consent(String clinic, int version, bool accept);
  Future<void> scan(
    String clinic,
    String token,
    double latitude,
    double longitude,
    double accuracy,
    String operation,
  );
  Future<void> correct(
    String clinic,
    String event,
    String instant,
    String reason,
    String operation,
  );
}

abstract interface class AttendanceScheduleRepository {
  Future<void> saveSchedule(String clinic, String start, List<int> weekdays, int grace);
}
