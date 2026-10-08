import '../../core/domain/plan_errors.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/patient_repository.dart';
import '../domain/patient_models.dart';

String newOperationId() {
  final r = Random.secure();
  return List.generate(
    24,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class PatientViewModel extends ChangeNotifier {
  PatientViewModel(this.repository, this.member)
    : access = PatientAccess(member.role);
  final PatientRepository repository;
  final ClinicMembership member;
  final PatientAccess access;
  List<VetPatient> patients = [];
  List<VetOwner> owners = [];
  List<PatientEvent> events = [];
  VetPatient? selected;
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _revision = 0;
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    patients = [];
    owners = [];
    events = [];
    selected = null;
    super.dispose();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || busy) return;
    final revision = ++_revision;
    busy = true;
    error = null;
    selected = null;
    events = [];
    changed();
    try {
      final p = await repository.patients(member.clinicId);
      final o = access.owners
          ? await repository.owners(member.clinicId)
          : <VetOwner>[];
      if (_disposed || revision != _revision) return;
      patients = p;
      owners = o;
    } catch (e) {
      if (!_disposed && revision == _revision) {
        patients = [];
        owners = [];
        events = [];
        selected = null;
        error =
            'No se pudo cargar el expediente. Revisa la conexión y la configuración de pacientes.';
      }
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        changed();
      }
    }
  }

  Future<void> select(VetPatient patient) async {
    if (_disposed) return;
    if (patient.clinicId != member.clinicId) {
      throw StateError('Clínica incorrecta');
    }
    final revision = ++_revision;
    selected = patient;
    events = [];
    busy = true;
    error = null;
    changed();
    try {
      final result = access.clinical
          ? await repository.events(member.clinicId, patient.id)
          : <PatientEvent>[];
      if (!_disposed && revision == _revision) {
        events = result
            .where((e) => e.kind != EventKind.consent || access.medical)
            .toList();
      }
    } catch (e) {
      if (!_disposed && revision == _revision) {
        error = 'No se pudo cargar el historial.';
      }
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        changed();
      }
    }
  }

  Future<bool> create(
    Map<String, dynamic> patient,
    Map<String, dynamic>? owner,
    String operationId,
  ) async {
    if (_disposed || busy || !access.createPatient) return false;
    busy = true;
    error = null;
    changed();
    try {
      textField(patient, 'name', required: true, max: 120);
      textField(patient, 'species', required: true, max: 120);
      if (owner != null) textField(owner, 'name', required: true, max: 200);
      await repository.createPatient(
        member.clinicId,
        patient,
        owner,
        operationId,
      );
      if (_disposed) return false;
      busy = false;
      await load();
      return error == null;
    } on FormatException catch (e) {
      if (!_disposed) error = e.message.toString();
    } catch (e) {
      if (!_disposed) {
        error =
            planActionError(e) ??
            'No se pudo guardar. Puedes reintentar sin duplicar el registro; revisa la conexión.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        changed();
      }
    }
    return false;
  }

  Future<bool> add(
    EventKind kind,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    final patient = selected;
    if (_disposed || busy || patient == null || !access.canAdd(kind)) {
      return false;
    }
    final revision = ++_revision;
    busy = true;
    error = null;
    changed();
    try {
      await repository.addEvent(
        member.clinicId,
        patient.id,
        kind,
        validateEvent(kind, data),
        operationId,
      );
      if (_disposed || revision != _revision) return false;
      busy = false;
      await select(patient);
      return error == null;
    } on FormatException catch (e) {
      if (!_disposed && revision == _revision) error = e.message.toString();
    } catch (e) {
      if (!_disposed && revision == _revision) {
        error =
            planActionError(e) ??
            'No se pudo guardar. Reintenta con el mismo formulario para evitar duplicados.';
      }
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        changed();
      }
    }
    return false;
  }
}
