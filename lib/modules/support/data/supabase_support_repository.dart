import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/support_repository.dart';

class SupabaseSupportRepository
    implements SupportRepository, SupportOperatorRepository {
  SupabaseSupportRepository(this.client);
  final SupabaseClient client;
  @override
  Future<bool> operatorEnabled() async =>
      await client.rpc('support_operator_enabled') as bool;
  @override
  Future<List<Map<String, dynamic>>> queue() async =>
      (await client.rpc('support_operator_queue') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> operatorDetail(String ticket) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'support_operator_detail',
              params: {'p_ticket': ticket},
            )
            as Map,
      );
  @override
  Future<void> respond(
    String ticket,
    String body,
    String status,
    String operation,
  ) async {
    await client.rpc(
      'support_operator_reply',
      params: {
        'p_ticket': ticket,
        'p_body': body,
        'p_status': status,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Uri> operatorDownload(String ticket, String path) async {
    final result = await operatorDetail(ticket);
    if (!(result['attachments'] as List).any((a) => a['path'] == path)) {
      throw const FormatException('Acceso no disponible.');
    }
    return Uri.parse(
      await client.storage.from('support-files').createSignedUrl(path, 60),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> tickets(String clinic) async =>
      (await client.rpc('support_list', params: {'p_clinic': clinic}) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<String> create(
    String clinic,
    String category,
    String title,
    String description,
    String operation,
  ) async =>
      await client.rpc(
            'support_create',
            params: {
              'p_clinic': clinic,
              'p_category': category,
              'p_title': title,
              'p_body': description,
              'p_operation': operation,
            },
          )
          as String;
  @override
  Future<Map<String, dynamic>> detail(String ticket) async =>
      Map<String, dynamic>.from(
        await client.rpc('support_detail', params: {'p_ticket': ticket}) as Map,
      );
  @override
  Future<void> message(String ticket, String body, String operation) async {
    await client.rpc(
      'support_message',
      params: {'p_ticket': ticket, 'p_body': body, 'p_operation': operation},
    );
  }

  @override
  Future<void> attach(
    String ticket,
    String name,
    String mime,
    Uint8List bytes,
  ) async {
    final extension = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'application/pdf': 'pdf',
      'text/plain': 'txt',
    }[mime];
    if (extension == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Adjunto no válido.');
    }
    final path =
        await client.rpc(
              'support_attachment_reserve',
              params: {
                'p_ticket': ticket,
                'p_name': name,
                'p_mime': mime,
                'p_size': bytes.length,
                'p_token': newOperationId(),
                'p_extension': extension,
              },
            )
            as String;
    await client.storage
        .from('support-files')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    await client.rpc(
      'support_attachment_finish',
      params: {'p_ticket': ticket, 'p_path': path},
    );
  }

  @override
  Future<Uri> download(String ticket, String path) async {
    final result = await detail(ticket);
    if (!(result['attachments'] as List).any((a) => a['path'] == path)) {
      throw const FormatException('Acceso no disponible.');
    }
    return Uri.parse(
      await client.storage.from('support-files').createSignedUrl(path, 60),
    );
  }
}
