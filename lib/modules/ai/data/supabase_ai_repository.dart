import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/ai_repository.dart';

class SupabaseAiRepository implements AiRepository, StarterAiRepository {
  SupabaseAiRepository(this.client);
  final SupabaseClient client;
  Future<dynamic> gateway(Map<String, dynamic> body) async {
    final r = await client.functions.invoke('ai-gateway', body: body);
    if (r.status != 200 || r.data is! Map || r.data['error'] != null) {
      throw const FormatException(
        'IA no disponible. Revisa configuración, permisos o límite de uso.',
      );
    }
    return r.data;
  }

  Future<Map<String, dynamic>> starterCall(Map<String, dynamic> body) async {
    final response = await client.functions.invoke('starter-ai', body: body);
    if (response.status != 200 ||
        response.data is! Map ||
        response.data['error'] != null) {
      throw const FormatException(
        'Ayuda incluida no disponible. Puede faltar configuración o haberse alcanzado la cuota; no se cambió a un modelo de pago.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<Map<String, dynamic>> starterStatus(String clinic) =>
      starterCall({'action': 'status', 'clinic': clinic});
  @override
  Future<String> starterHelp(
    String clinic,
    String topic,
    String operation,
  ) async =>
      (await starterCall({
            'action': 'send',
            'clinic': clinic,
            'topic': topic,
            'operation': operation,
            'consent': true,
          }))['chat']
          as String;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('ai_dashboard', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<String> create(String clinic, String title, String operation) async =>
      await client.rpc(
            'ai_chat_create',
            params: {
              'p_clinic': clinic,
              'p_title': title,
              'p_operation': operation,
            },
          )
          as String;
  @override
  Future<List<Map<String, dynamic>>> messages(String chat) async =>
      (await client.rpc('ai_messages_read', params: {'p_chat': chat}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<void> policy(
    String chat,
    int version,
    String visibility,
    String context,
    List<String> audience,
  ) async {
    await client.rpc(
      'ai_chat_policy',
      params: {
        'p_id': chat,
        'p_version': version,
        'p_visibility': visibility,
        'p_context': context,
        'p_audience': audience,
      },
    );
  }

  @override
  Future<void> abandon(String chat) async {
    await client.rpc('ai_request_abandon', params: {'p_chat': chat});
  }

  @override
  Future<void> delete(String chat) async {
    await client.rpc('ai_chat_delete', params: {'p_chat': chat});
  }

  @override
  Future<void> saveKey(
    String provider,
    String scope,
    String clinic,
    String key,
  ) async {
    await gateway({
      'action': 'save_key',
      'provider': provider,
      'scope': scope,
      'clinic': clinic,
      'key': key,
    });
  }

  @override
  Future<void> disableKey(String connection) async {
    await client.rpc('ai_connection_disable', params: {'p_id': connection});
  }

  @override
  Future<List<Map<String, dynamic>>> models(String connection) async =>
      ((await gateway({'action': 'models', 'connection': connection}))['models']
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<void> send(
    String chat,
    String connection,
    String model,
    String message,
    String operation,
    bool personal,
    bool team,
  ) async {
    await gateway({
      'action': 'send',
      'chat': chat,
      'connection': connection,
      'model': model,
      'message': message,
      'operation': operation,
      'personal': personal,
      'team': team,
    });
  }
}
