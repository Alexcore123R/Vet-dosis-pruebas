import 'dart:typed_data';

abstract interface class PreventiveRepository {
  Future<Map<String, dynamic>> booklet(String clinic, String patient);
  Future<void> attachEvidence(
    String clinic,
    String patient,
    String event,
    String label,
    Uint8List bytes,
    String mime,
    String operation,
  );
  Future<Uint8List> evidence(String clinic, String patient, String attachment);
  Future<void> planPreventive(
    String clinic,
    String patient,
    Map<String, dynamic> data,
    String operation,
  );
  Future<void> retirePlan(
    String clinic,
    String patient,
    String plan,
    String reason,
    String operation,
  );
  Future<void> schedulePreventive(
    String clinic,
    String patient,
    String plan,
    Map<String, dynamic> data,
    String operation,
  );
}

const maxPreventiveEvidence = 3 * 1024 * 1024;
String evidenceMime(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxPreventiveEvidence) {
    throw const FormatException('Selecciona un comprobante de hasta 3 MB.');
  }
  if (bytes.length > 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    return 'image/png';
  }
  if (bytes.length > 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  if (bytes.length > 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-') {
    return 'application/pdf';
  }
  throw const FormatException('Usa una imagen JPG/PNG o un PDF.');
}
