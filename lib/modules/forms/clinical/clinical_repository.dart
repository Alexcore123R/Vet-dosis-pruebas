import 'package:supabase_flutter/supabase_flutter.dart';
import 'clinical_models.dart';

abstract interface class ClinicalRepository {
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId);
  Future<ClinicalBundle> bundle(String caseId);
  Future<void> observation(
    String caseId,
    Map<String, dynamic> data,
    String operationId,
  );
  Future<void> act(
    String caseId,
    String scope,
    String notes,
    String performer,
    String observedAt,
    String operationId,
  );
  Future<void> authorize(
    String caseId,
    String person,
    String scope,
    String until,
    String operationId,
  );
  Future<void> revoke(
    String authorizationId,
    String reason,
    String operationId,
  );
  Future<List<Map<String, dynamic>>> deathRecords(String consentId);
  Future<void> recordDeath(
    String consentId,
    Map<String, dynamic> data,
    String operationId,
  );
}

abstract interface class ClinicalPermissionRepository {
  Future<Map<String, dynamic>?> workspace(String clinicId, String? caseId);
  Future<void> bindScope(
    String caseId,
    String scope,
    String procedure,
    bool professional,
    String source,
    String reason,
  );
}

abstract interface class ClinicalCaseRegistrationRepository {
  Future<String> registerCase(
    String clinicId,
    Map<String, dynamic> data,
    String operationId,
  );
}

abstract interface class DeathPermissionRepository {
  Future<Map<String, dynamic>> deathWorkspace(String consentId);
}

class SupabaseClinicalRepository
    implements
        ClinicalRepository,
        ClinicalPermissionRepository,
        ClinicalCaseRegistrationRepository,
        DeathPermissionRepository {
  SupabaseClinicalRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> deathWorkspace(String consentId) async =>
      Map<String, dynamic>.from(
        await rpc('clinical_death_workspace', {'p_consent': consentId}),
      );
  @override
  Future<String> registerCase(
    String clinicId,
    Map<String, dynamic> data,
    String operationId,
  ) async =>
      await rpc('clinical_case_register', {
            'p_clinic': clinicId,
            'p_data': data,
            'p_operation': operationId,
          })
          as String;

  @override
  Future<Map<String, dynamic>?> workspace(
    String clinicId,
    String? caseId,
  ) async {
    try {
      return Map<String, dynamic>.from(
        await rpc('clinical_workspace', {
              'p_clinic': clinicId,
              'p_case': caseId,
            })
            as Map,
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> bindScope(
    String caseId,
    String scope,
    String procedure,
    bool professional,
    String source,
    String reason,
  ) async {
    await rpc('clinical_scope_bind', {
      'p_case': caseId,
      'p_scope': scope,
      'p_procedure': procedure,
      'p_professional': professional,
      'p_source': source,
      'p_reason': reason,
    });
  }

  Future<dynamic> rpc(String name, Map<String, dynamic> args) =>
      client.rpc(name, params: args);
  @override
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId) async =>
      (await rpc('clinical_cases_list', {
                'p_clinic': clinicId,
                'p_patient': patientId,
              })
              as List)
          .map((r) => ClinicalCase(Map<String, dynamic>.from(r)))
          .toList();
  @override
  Future<ClinicalBundle> bundle(String caseId) async => ClinicalBundle.read(
    Map<String, dynamic>.from(
      await rpc('clinical_case_snapshot', {'p_case': caseId}),
    ),
  );
  @override
  Future<void> observation(
    String caseId,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    await rpc('clinical_observation_add', {
      'p_case': caseId,
      'p_data': validateObservation(data),
      'p_operation': operationId,
    });
  }

  @override
  Future<void> act(
    String caseId,
    String scope,
    String notes,
    String performer,
    String observedAt,
    String operationId,
  ) async {
    await rpc('clinical_act_add', {
      'p_case': caseId,
      'p_scope': scope,
      'p_notes': notes,
      'p_performer': performer,
      'p_observed': clinicalInstant(observedAt).toIso8601String(),
      'p_operation': operationId,
    });
  }

  @override
  Future<void> authorize(
    String caseId,
    String person,
    String scope,
    String until,
    String operationId,
  ) async {
    await rpc('clinical_authorize', {
      'p_case': caseId,
      'p_person': person,
      'p_scope': scope,
      'p_until': clinicalInstant(until).toIso8601String(),
      'p_operation': operationId,
    });
  }

  @override
  Future<void> revoke(
    String authorizationId,
    String reason,
    String operationId,
  ) async {
    await rpc('clinical_authorization_revoke', {
      'p_id': authorizationId,
      'p_reason': reason,
      'p_operation': operationId,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> deathRecords(String consentId) async =>
      (await rpc('clinical_death_list', {'p_consent': consentId}) as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
  @override
  Future<void> recordDeath(
    String consentId,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    await rpc('clinical_death_add', {
      'p_consent': consentId,
      'p_data': data,
      'p_operation': operationId,
    });
  }
}
