import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/catalog.dart';
import '../domain/dose_engine.dart';

class PersonalDoseEntry {
  PersonalDoseEntry(this.id, this.userId, this.state, this.drug);
  final String id, userId, state;
  final DrugDose drug;
}

abstract interface class PersonalDoseRepository {
  Future<List<PersonalDoseEntry>> list(String clinicId);
  Future<void> create(
    String clinicId,
    Map<String, dynamic> payload, {
    required bool share,
  });
  Future<void> review(String id, {required bool approve});
}

class SupabasePersonalDoseRepository implements PersonalDoseRepository {
  SupabasePersonalDoseRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<PersonalDoseEntry>> list(String clinicId) async {
    final rows = await client
        .from('dose_personal_entries')
        .select('id,user_id,state,payload')
        .eq('clinic_id', clinicId)
        .order('created_at');
    return rows
        .map(
          (row) => PersonalDoseEntry(
            row['id'] as String,
            row['user_id'] as String,
            row['state'] as String,
            DrugDose.read(
              Map<String, dynamic>.from(row['payload'] as Map),
              personal: true,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> create(
    String clinicId,
    Map<String, dynamic> payload, {
    required bool share,
  }) async {
    final errors = validatePersonalDose(DrugDose.read(payload, personal: true));
    if (errors.isNotEmpty) throw FormatException(errors.join(' '));
    await client.rpc(
      'create_personal_dose',
      params: {'p_clinic_id': clinicId, 'p_payload': payload, 'p_share': share},
    );
  }

  @override
  Future<void> review(String id, {required bool approve}) async {
    await client.rpc(
      'review_personal_dose',
      params: {'p_id': id, 'p_approve': approve},
    );
  }
}
