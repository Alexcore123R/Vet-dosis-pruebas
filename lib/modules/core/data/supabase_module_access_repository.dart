import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/module_access.dart';

class SupabaseModuleAccessRepository implements ModuleAccessRepository {
  const SupabaseModuleAccessRepository(this.client);

  final SupabaseClient client;

  @override
  Future<Map<String, dynamic>> workspace(String clinicId) async =>
      Map<String, dynamic>.from(
        await client.rpc('app_module_workspace', params: {'p_clinic': clinicId})
            as Map,
      );
}
