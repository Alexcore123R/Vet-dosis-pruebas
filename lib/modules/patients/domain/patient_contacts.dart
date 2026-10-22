import 'patient_models.dart';

abstract interface class PatientContactRepository {
  Future<Map<String, dynamic>> contact(String clinic, String patient);
  Future<void> saveContact(
    String clinic,
    String patient,
    String owner,
    int version,
    Map<String, dynamic> data,
    String operation,
  );
  Future<void> logContact(
    String clinic,
    String patient,
    String owner,
    Map<String, dynamic> data,
    String operation,
  );
}

String? contactPhone(String raw) {
  final normalized = raw.trim().replaceAll(RegExp(r'[\s().-]'), '');
  return RegExp(r'^\+?[1-9]\d{7,14}$').hasMatch(normalized) ? normalized : null;
}

Uri? contactCall(String raw) {
  final phone = contactPhone(raw);
  return phone == null ? null : Uri(scheme: 'tel', path: phone);
}

Uri? contactWhatsapp(String raw, String message) {
  final phone = contactPhone(raw);
  // Do not guess the country for a locally formatted number.
  if (phone == null || !phone.startsWith('+')) return null;
  return Uri.https('wa.me', '/${phone.substring(1)}', {'text': message});
}

Map<String, dynamic> validateContact(Map<String, dynamic> raw) {
  final out = <String, dynamic>{};
  for (final key in [
    'name',
    'phone',
    'phone_alt',
    'email',
    'address',
    'contact_name',
    'contact_phone',
    'contact_relationship',
  ]) {
    out[key] = textField(
      raw,
      key,
      required: key == 'name',
      max: key == 'name'
          ? 200
          : key == 'address'
          ? 1000
          : 300,
    );
  }
  out['contact_authorized'] = raw['contact_authorized'] == true;
  final hasName = out['contact_name'] != '',
      hasPhone = out['contact_phone'] != '';
  if (hasName != hasPhone || (out['contact_authorized'] == true && !hasName)) {
    throw const FormatException(
      'Completa nombre y teléfono del contacto adicional. Puedes retirar su autorización sin borrar el historial.',
    );
  }
  return out;
}
