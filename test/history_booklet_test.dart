import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/patients/domain/patient_models.dart';
import 'package:vetdosis_pro/modules/patients/domain/clinical_record_fields.dart';

void main() {
  Map<String, dynamic> preventive() => {
    'date': '2026-10-20', 'type': 'vacuna', 'product': '',
    'preventive_version': 1, 'origin': 'owner_report',
    'date_precision': 'unknown', 'coverage': 'Cobertura referida de prueba',
    'informant': 'Tutor sintético',
  };

  test('Unknown application is not presented as a vaccination on record date', () {
    final out = validateEvent(EventKind.preventive, preventive());
    expect(out['date_precision'], 'unknown');
    expect(preventiveDateLabel(out), 'Fecha de aplicación desconocida');
    expect(out['product'], 'No especificado');
    expect(validateEvent(EventKind.preventive, out), out);
  });
  test('Legacy provenance remains unspecified', () {
    final out = validateEvent(EventKind.preventive, {
      'date': '2026-10-19', 'type': 'vacuna', 'product': 'Producto sintético',
    });
    expect(out.containsKey('origin'), false);
    expect(preventiveOriginLabel(out), 'Origen no especificado');
  });
  test('Origin is explicit; documentary and reported claims require a reference', () {
    for (final edit in [
      {'origin': ''},
      {'informant': ''},
      {'origin': 'external_document', 'evidence_reference': ''},
      {'origin': 'clinic', 'date_precision': 'unknown', 'performer': 'Persona sintética'},
      {'date_precision': 'approximate', 'date_description': ''},
      {'next_date': '2026-11-01', 'next_date_by': ''},
    ]) {
      expect(() => validateEvent(EventKind.preventive, {...preventive(), ...edit}),
        throwsFormatException);
    }
  });
  test('A next date is retained only with its stated professional', () {
    final out = validateEvent(EventKind.preventive, {...preventive(),
      'next_date': '2026-11-01', 'next_date_by': 'Profesional sintético'});
    expect(out['next_date_by'], 'Profesional sintético');
  });
  test('History sections survive both validation passes before RPC', () {
    final out = validateEvent(EventKind.soap, {
      'date': '2026-10-20', 'reason': 'Historia sintética',
      'species_template': 'Especie sintética', 'record_type': 'clinical_history',
      'subjective': 'Antecedentes referidos',
      'medical_history': 'Antecedente sintético',
      for (final key in historyFields.keys.where((k) => k != 'medical_history')) key: '',
    });
    expect(out['medical_history'], 'Antecedente sintético');
    expect(validateEvent(EventKind.soap, out), out);
    expect(out['feeding'], '');
  });
}
