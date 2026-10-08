import 'package:flutter/foundation.dart';
import '../domain/attendance_repository.dart';

class AttendanceViewModel extends ChangeNotifier {
  AttendanceViewModel(this.repository, this.clinic);
  final AttendanceRepository repository;
  final String clinic;
  Map<String, dynamic> data = {};
  bool busy = false, _disposed = false;
  String? error;
  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      data = await repository.dashboard(clinic);
    } catch (e) {
      data = {};
      error = attendanceError(e);
    }
    if (_disposed) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String attendanceError(Object e) {
  final t = e.toString();
  const m = {
    'expired_qr': 'El QR venció. Escanea el nuevo.',
    'invalid_qr': 'QR inválido o de otra clínica.',
    'outside_radius': 'Estás fuera del radio autorizado.',
    'invalid_location':
        'La ubicación no tiene la precisión requerida. Intenta de nuevo cerca de la clínica.',
    'consent_required': 'Lee y acepta el aviso antes de checar.',
    'attendance_settings_required':
        'El admin debe configurar primero la ubicación y el aviso.',
    'attendance_events_clinic_id_user_id_qr_bucket_key':
        'Ya registraste este QR. Espera el siguiente para otra entrada o salida.',
    'admin_required': 'Esta acción requiere administrador.',
  };
  for (final e in m.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return 'No se pudo completar el checado. Revisa la conexión y los permisos.';
}
