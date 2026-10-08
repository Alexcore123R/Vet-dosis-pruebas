import 'package:flutter/foundation.dart';
import '../../forms/clinical/clinical_repository.dart';
import '../../forms/clinical/clinical_models.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/prescribing_repository.dart';

class PrescribingViewModel extends ChangeNotifier {
  PrescribingViewModel(
    this.repository,
    this.clinical,
    this.member,
    this.patientId,
  );
  final PrescribingRepository repository;
  final ClinicalRepository clinical;
  final ClinicMembership member;
  final String? patientId;
  List<Map<String, dynamic>> profiles = [],
      delegations = [],
      products = [],
      prescriptions = [],
      vials = [],
      reports = [],
      medications = [];
  List<ClinicalCase> cases = [];
  String? caseId, error;
  bool busy = false, _disposed = false;
  int _generation = 0;
  Map<String, dynamic>? get ownProfile {
    for (final p in profiles) {
      if (p['user_id'] == member.userId) return p;
    }
    return null;
  }

  bool get professional => ownProfile?['authorized'] == true;
  bool get responsible =>
      cases.any((c) => c.id == caseId && c.responsibleId == member.userId) &&
      professional;
  Future<void> load({String? selectedCase}) async {
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final profileRows = await repository.read('rx_profiles', {
        'p_clinic': member.clinicId,
      });
      final grants = await repository.read('rx_delegations', {
        'p_clinic': member.clinicId,
      });
      final catalog = await repository.products();
      final caseRows = await clinical.cases(member.clinicId, patientId);
      final rx = await repository.read('rx_list', {
        'p_clinic': member.clinicId,
        'p_patient': patientId,
      });
      final vialRows = await repository.read('rx_vials', {
        'p_clinic': member.clinicId,
      });
      final reportRows = member.role == ClinicRole.auxiliar
          ? []
          : await repository.read('rx_reports', {'p_clinic': member.clinicId});
      final selected = selectedCase ?? caseId;
      final valid = caseRows.any((c) => c.id == selected) ? selected : null;
      final records = valid == null
          ? []
          : await repository.read('rx_medications', {'p_case': valid});
      if (_disposed || generation != _generation) return;
      profiles = _maps(profileRows);
      delegations = _maps(grants);
      products = catalog;
      cases = caseRows;
      prescriptions = _maps(rx);
      vials = _maps(vialRows);
      reports = _maps(reportRows);
      caseId = valid;
      medications = _maps(records);
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _clear();
      error =
          'No se pudo consultar. Revisa permisos y conexión; si persiste, contacta a soporte.';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  static List<Map<String, dynamic>> _maps(dynamic rows) =>
      (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
  void _clear() {
    profiles = [];
    delegations = [];
    products = [];
    prescriptions = [];
    vials = [];
    reports = [];
    medications = [];
    cases = [];
    caseId = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _clear();
    super.dispose();
  }
}
