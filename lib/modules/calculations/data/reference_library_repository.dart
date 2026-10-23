import 'package:supabase_flutter/supabase_flutter.dart';

class ReferenceLibraryPage {
  const ReferenceLibraryPage(this.items, this.total);
  final List<Map<String, dynamic>> items;
  final int total;
}

abstract interface class ReferenceLibraryRepository {
  Future<ReferenceLibraryPage> list(
    String clinicId,
    String section,
    String search,
    int offset,
  );
}

class SupabaseReferenceLibraryRepository implements ReferenceLibraryRepository {
  const SupabaseReferenceLibraryRepository(this.client);
  final SupabaseClient client;

  @override
  Future<ReferenceLibraryPage> list(
    String clinicId,
    String section,
    String search,
    int offset,
  ) async {
    final raw = await client.rpc('reference_review_list', params: {
      'p_clinic': clinicId,
      'p_section': section,
      'p_search': search,
      'p_offset': offset,
      'p_limit': 50,
    });
    final data = Map<String, dynamic>.from(raw as Map);
    return ReferenceLibraryPage(
      [for (final row in data['items'] as List) Map<String, dynamic>.from(row as Map)],
      data['total'] as int,
    );
  }
}
