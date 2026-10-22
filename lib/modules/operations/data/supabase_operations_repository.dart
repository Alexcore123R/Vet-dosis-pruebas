import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/operations_repository.dart';
import '../domain/appointment_links.dart';
import '../domain/appointment_care.dart';

class SupabaseOperationsRepository
    implements
        OperationsRepository,
        AppointmentPatientRepository,
        AppointmentLinksRepository,
        AppointmentCareRepository,
        CommissionRepository,
        ContactDirectoryRepository,
        ProductivityRepository,
        WeeklyTaskPlanRepository,
        ServiceContactRepository,
        MarketingRepository {
  SupabaseOperationsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> commitWeekPlan(
    String clinic,
    String week,
    String expectedBody,
    String body,
    List<Map<String, dynamic>> tasks,
    String operation,
  ) async {
    try {
      await client.rpc(
        'ops_week_plan_commit',
        params: {
          'p_clinic': clinic,
          'p_week': week,
          'p_expected_body': expectedBody,
          'p_body': body,
          'p_tasks': tasks,
          'p_operation': operation,
        },
      );
    } on PostgrestException catch (e) {
      final message = switch (e.message) {
        'week_plan_changed_refresh' =>
          'El plan cambió en otra sesión. Vuelve a abrir la semana para revisar la versión actual.',
        'assignee_wrong_clinic' =>
          'Cambió el equipo de la clínica. Actualiza la semana y revisa los responsables.',
        'assignee_unavailable' =>
          'Un responsable ya no está disponible ese día. Actualiza la disponibilidad antes de guardar.',
        'daily_task_capacity_exceeded' =>
          'La carga diaria supera el tiempo disponible. Actualiza la semana y ajusta las tareas.',
        'task_already_scheduled' =>
          'Una tarea ya está programada. Actualiza la semana para evitar duplicarla.',
        'team_manage_required' =>
          'Se requiere permiso vigente para gestionar el equipo y un plan de clínica compatible.',
        _ =>
          e.code == 'PGRST202'
              ? 'Falta aplicar SQL 14N en Supabase para guardar el plan y sus tareas.'
              : 'No se pudieron guardar las tareas. Actualiza la semana y revisa la conexión antes de reintentar.',
      };
      throw FormatException(message);
    }
  }

  @override
  Future<Map<String, dynamic>> appointmentContact(
    String clinic,
    String appointment,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'ops_appointment_contact',
          params: {'p_clinic': clinic, 'p_appointment': appointment},
        )
        as Map,
  );
  @override
  Future<void> saveServiceContact(
    String clinic,
    String owner,
    String purpose,
    bool whatsapp,
    bool email,
    String source,
  ) async {
    await client.rpc(
      'ops_service_contact_save',
      params: {
        'p_clinic': clinic,
        'p_owner': owner,
        'p_purpose': purpose,
        'p_whatsapp': whatsapp,
        'p_email': email,
        'p_source': source,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> productivity(String clinic, String week) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'ops_productivity_read',
              params: {'p_clinic': clinic, 'p_week': week},
            )
            as Map,
      );
  @override
  Future<void> planWrite(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'ops_productivity_write',
      params: {
        'p_clinic': clinic,
        'p_action': action,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> clients(String clinic) async =>
      (await client.rpc('ops_client_directory', params: {'p_clinic': clinic})
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  @override
  Future<void> saveMarketingPreferences(
    String clinic,
    String owner,
    bool whatsapp,
    bool email,
    String source,
  ) async {
    await client.rpc(
      'ops_marketing_preferences_save',
      params: {
        'p_clinic': clinic,
        'p_owner': owner,
        'p_whatsapp': whatsapp,
        'p_email': email,
        'p_source': source,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> promotions(String clinic) async =>
      (await client.rpc('ops_promotions', params: {'p_clinic': clinic}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  @override
  Future<void> savePromotion(String clinic, Map<String, dynamic> data) async {
    await client.rpc(
      'ops_promotion_save',
      params: {'p_clinic': clinic, 'p_data': data},
    );
  }

  @override
  Future<Map<String, dynamic>> loyaltyAccount(
    String clinic,
    String owner,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'ops_loyalty_account',
          params: {'p_clinic': clinic, 'p_owner': owner},
        )
        as Map,
  );

  @override
  Future<void> recordLoyalty(
    String clinic,
    String owner,
    String promotion,
    String action,
    int units,
    String note,
    String operation,
  ) async {
    await client.rpc(
      'ops_loyalty_record',
      params: {
        'p_clinic': clinic,
        'p_owner': owner,
        'p_promotion': promotion,
        'p_action': action,
        'p_units': units,
        'p_note': note,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> contactDirectory(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('ops_contact_directory', params: {'p_clinic': clinic})
            as Map,
      );

  @override
  Future<void> saveContact(
    String clinic,
    String kind,
    String id,
    Map<String, dynamic> data,
  ) async {
    await client.rpc(
      'ops_contact_save',
      params: {'p_clinic': clinic, 'p_kind': kind, 'p_id': id, 'p_data': data},
    );
  }

  @override
  Future<Map<String, dynamic>> commissionAccount(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('commission_account', params: {'p_clinic': clinic})
            as Map,
      );

  @override
  Future<void> saveCommissionSchedule(
    String clinic,
    String cadence,
    DateTime payOn,
  ) async {
    await client.rpc(
      'commission_schedule_save',
      params: {
        'p_clinic': clinic,
        'p_cadence': cadence,
        'p_next_pay_on':
            '${payOn.year.toString().padLeft(4, '0')}-${payOn.month.toString().padLeft(2, '0')}-${payOn.day.toString().padLeft(2, '0')}',
      },
    );
  }

  @override
  Future<void> payCommissionPeriod(String clinic) async {
    await client.rpc('commission_period_pay', params: {'p_clinic': clinic});
  }

  @override
  Future<Map<String, dynamic>> careSnapshot(
    String clinic,
    List<String> ids,
  ) async {
    final rows = <dynamic>[];
    Map<String, dynamic>? result;
    final unique = ids.toSet().toList();
    for (var offset = 0; offset < unique.length || offset == 0; offset += 100) {
      final batch = unique.skip(offset).take(100).toList();
      final raw = Map<String, dynamic>.from(
        await client.rpc(
              'appointment_care_snapshot',
              params: {'p_clinic': clinic, 'p_appointments': batch},
            )
            as Map,
      );
      if (raw['schema_version'] != 1 ||
          raw['clinic_id'] != clinic ||
          raw['appointments'] is! List ||
          DateTime.tryParse('${raw['day_start']}') == null ||
          DateTime.tryParse('${raw['day_end']}') == null) {
        throw const FormatException('Contrato de atención no compatible.');
      }
      if (result != null && result['day'] != raw['day']) {
        throw const FormatException('Cambió el día de la clínica. Actualiza.');
      }
      for (final row in raw['appointments'] as List) {
        if (row is! Map || !batch.contains(row['appointment_id'])) {
          throw const FormatException('Cita no solicitada.');
        }
        rows.add(row);
      }
      result = raw;
    }
    return {...result!, 'appointments': rows};
  }

  @override
  Future<void> careWrite(
    String clinic,
    String appointment,
    int version,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'appointment_care_write',
      params: {
        'p_clinic': clinic,
        'p_appointment': appointment,
        'p_version': version,
        'p_action': action,
        'p_data': validateCare(action, data),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Map<String, Map<String, dynamic>>> patientLinks(
    String clinic,
    List<String> appointments,
  ) async {
    final output = <String, Map<String, dynamic>>{};
    final unique = appointments.toSet().toList();
    for (var offset = 0; offset < unique.length; offset += 100) {
      final batch = unique.skip(offset).take(100).toList();
      final raw = Map<String, dynamic>.from(
        await client.rpc(
              'appointment_patient_links',
              params: {'p_clinic': clinic, 'p_appointments': batch},
            )
            as Map,
      );
      if (raw['schema_version'] != 1 ||
          raw['clinic_id'] != clinic ||
          raw['appointments'] is! List) {
        throw const FormatException(
          'Contrato de contactos y cobros no compatible.',
        );
      }
      for (final item in raw['appointments'] as List) {
        final row = Map<String, dynamic>.from(item as Map);
        final id = row['appointment_id'] as String;
        if (!batch.contains(id)) {
          throw const FormatException('Cita no solicitada.');
        }
        output[id] = row;
      }
    }
    return output;
  }

  @override
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  ) async =>
      (await client.rpc(
                'ops_patient_search',
                params: {'p_clinic': clinic, 'p_query': query},
              )
              as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('ops_dashboard', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<void> write(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'ops_write',
      params: {
        'p_clinic': clinic,
        'p_action': action,
        'p_data': data,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> medical(
    String clinic, {
    Map<String, dynamic>? details,
    bool consent = false,
  }) async =>
      (await client.rpc(
                'ops_medical',
                params: {
                  'p_clinic': clinic,
                  'p_details': details,
                  'p_consent': consent,
                },
              )
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
