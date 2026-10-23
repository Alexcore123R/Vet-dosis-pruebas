import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/attendance_repository.dart';

class SupabaseAttendanceRepository implements AttendanceRepository, AttendanceScheduleRepository {
  SupabaseAttendanceRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> saveSchedule(String clinic, String start, List<int> weekdays, int grace) async {
    await client.rpc('att_schedule_save', params: {
      'p_clinic': clinic, 'p_start': start, 'p_weekdays': weekdays, 'p_grace': grace,
    });
  }
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('att_dashboard', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<Map<String, dynamic>> qr(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('att_qr', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<void> settings(String clinic, Map<String, dynamic> data) async {
    await client.rpc(
      'att_settings_save',
      params: {'p_clinic': clinic, 'p_data': data},
    );
  }

  @override
  Future<void> consent(String clinic, int version, bool accept) async {
    await client.rpc(
      'att_consent',
      params: {'p_clinic': clinic, 'p_version': version, 'p_accept': accept},
    );
  }

  @override
  Future<void> scan(
    String clinic,
    String token,
    double latitude,
    double longitude,
    double accuracy,
    String operation,
  ) async {
    await client.rpc(
      'att_scan',
      params: {
        'p_clinic': clinic,
        'p_token': token,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_accuracy': accuracy,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> correct(
    String clinic,
    String event,
    String instant,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'att_correct',
      params: {
        'p_clinic': clinic,
        'p_event': event,
        'p_at': instant,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }
}
