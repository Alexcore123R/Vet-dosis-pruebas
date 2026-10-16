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

  bool operationalKnown = false;
  bool prescriptionKnown = false;
  bool standingKnown = false;
  List<Map<String, dynamic>> standingMembers = [],
      standingOffers = [],
      standingEvents = [];
  bool get standingAvailable =>
      prescriptionPermissions?['mode'] == 'individual_standing' &&
      error == null;
  bool get canOfferStanding =>
      standingAvailable &&
      prescriptionPermissions?['can_authorize'] == true &&
      standingError == null &&
      !busy;
  List<Map<String, dynamic>> standingFor(Map<String, dynamic> r) =>
      standingOffers
          .where(
            (d) =>
                d['case_id'] == r['case_id'] &&
                d['recipient_id'] == member.userId &&
                d['active'] == true,
          )
          .toList();
  bool _refreshingStanding = false;
  String? standingError;
  Future<void> refreshStanding() async {
    if (_disposed || busy || !standingAvailable || _refreshingStanding) return;
    _refreshingStanding = true;
    final generation = _generation;
    try {
      final data = Map<String, dynamic>.from(
        await repository.read('rx_standing_workspace', {
              'p_clinic': member.clinicId,
            })
            as Map,
      );
      if (_disposed || generation != _generation) return;
      standingMembers = _maps(data['members']);
      standingOffers = _maps(data['offers']);
      standingEvents = _maps(data['events']);
      standingError = null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      standingMembers = [];
      standingOffers = [];
      standingEvents = [];
      standingError =
          'No se pudieron actualizar los avisos. Actualiza antes de continuar.';
    } finally {
      _refreshingStanding = false;
      if (!_disposed && generation == _generation) notifyListeners();
    }
  }

  Map<String, dynamic>? prescriptionPermissions;
  bool get canPreparePrescription => prescriptionKnown
      ? (prescriptionPermissions?['can_prepare'] == true)
      : true;
  bool prescriptionAction(Map<String, dynamic> row, String action) {
    if (!prescriptionKnown || busy || error != null) return false;
    if ((action == 'prepare_standing' ||
            (action == 'issue' && row['authorization_mode'] == 'standing')) &&
        (!standingAvailable || standingError != null)) {
      return false;
    }
    if (!prescriptions.any(
      (current) =>
          current['id'] == row['id'] && current['revision'] == row['revision'],
    )) {
      return false;
    }
    return (prescriptionPermissions?['recipes'] as List? ?? []).any(
      (r) =>
          r['id'] == row['id'] &&
          r['revision'] == row['revision'] &&
          r[action] == true,
    );
  }

  Map<String, dynamic>? operational;
  bool get canManageVials =>
      operationalKnown ? (operational?['vial.manage'] == true) : professional;
  bool get canValidateMedication => operationalKnown
      ? (operational?['medication.validate'] == true)
      : responsible;
  bool canCorrectMedication(Map<String, dynamic> r) => operationalKnown
      ? canValidateMedication &&
            medications.contains(r) &&
            r['can_correct'] == true
      : responsible;
  bool get canReportMedication =>
      operationalKnown ? medicationScopes.isNotEmpty : caseId != null;
  bool get canScheduleMedication => operationalKnown
      ? (operational?['hospital.schedule'] == true &&
            operational?['hospital.read'] == true)
      : professional;
  Map<String, String> get medicationScopes => operationalKnown
      ? {
          for (final s in (operational?['scopes'] as List? ?? []))
            if (s['administer'] == true)
              s['scope'] as String:
                  clinicalScopes[s['scope']] ?? s['scope'] as String,
        }
      : (Map<String, String>.from(clinicalScopes)..remove('observaciones'));
  bool canDraw(String scope) =>
      !operationalKnown ||
      (operational?['scopes'] as List? ?? []).any(
        (s) =>
            s['scope'] == scope && s['administer'] == true && s['draw'] == true,
      );
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
      final repo = repository;
      final rxPermissions = repo is PrescriptionPermissionRepository
          ? await (repo as PrescriptionPermissionRepository)
                .prescriptionPermissions(member.clinicId)
          : null;
      if (_disposed || generation != _generation) return;
      if (rxPermissions != null) {
        prescriptionKnown = true;
        if (rxPermissions['schema_version'] != 1 ||
            !(rxPermissions['mode'] == 'individual' ||
                (rxPermissions['mode'] == 'individual_standing' &&
                    rxPermissions['standing_version'] == 1))) {
          throw StateError('unknown_prescription_permission_contract');
        }
      } else if (prescriptionKnown) {
        throw StateError('prescription_permission_contract_lost');
      }
      if (rxPermissions?['mode'] == 'individual_standing') {
        standingKnown = true;
      } else if (standingKnown) {
        throw StateError('standing_contract_lost');
      }
      final standing = standingKnown
          ? Map<String, dynamic>.from(
              await repository.read('rx_standing_workspace', {
                    'p_clinic': member.clinicId,
                  })
                  as Map,
            )
          : null;
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
      final selected = selectedCase ?? caseId;
      final valid = caseRows.any((c) => c.id == selected) ? selected : null;
      final source = repository;
      final permissionRows = source is MedicationPermissionRepository
          ? await (source as MedicationPermissionRepository)
                .medicationPermissions(member.clinicId, valid)
          : null;
      if (permissionRows != null) {
        operationalKnown = true;
        if (permissionRows['schema_version'] != 1) {
          throw StateError('unknown_medication_permission_contract');
        }
      } else if (operationalKnown) {
        throw StateError('medication_permission_contract_lost');
      }
      final vialRows =
          permissionRows != null && permissionRows['vial.read'] != true
          ? []
          : await repository.read('rx_vials', {'p_clinic': member.clinicId});
      final reportRows =
          rxPermissions != null || member.role == ClinicRole.auxiliar
          ? []
          : await repository.read('rx_reports', {'p_clinic': member.clinicId});
      final records = valid == null
          ? []
          : await repository.read('rx_medications', {'p_case': valid});
      if (_disposed || generation != _generation) return;
      operational = permissionRows;
      prescriptionPermissions = rxPermissions;
      standingMembers = standing == null ? [] : _maps(standing['members']);
      standingOffers = standing == null ? [] : _maps(standing['offers']);
      standingEvents = standing == null ? [] : _maps(standing['events']);
      standingError = null;
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
    standingMembers = [];
    standingOffers = [];
    standingEvents = [];
    standingError = null;
    prescriptionPermissions = null;
    operational = null;
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
