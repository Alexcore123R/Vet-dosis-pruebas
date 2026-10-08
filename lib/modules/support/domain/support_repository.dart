import 'dart:typed_data';

abstract interface class SupportRepository {
  Future<List<Map<String, dynamic>>> tickets(String clinic);
  Future<String> create(
    String clinic,
    String category,
    String title,
    String description,
    String operation,
  );
  Future<Map<String, dynamic>> detail(String ticket);
  Future<void> message(String ticket, String body, String operation);
  Future<void> attach(String ticket, String name, String mime, Uint8List bytes);
  Future<Uri> download(String ticket, String path);
}

abstract interface class SupportOperatorRepository {
  Future<bool> operatorEnabled();
  Future<List<Map<String, dynamic>>> queue();
  Future<Map<String, dynamic>> operatorDetail(String ticket);
  Future<void> respond(
    String ticket,
    String body,
    String status,
    String operation,
  );
  Future<Uri> operatorDownload(String ticket, String path);
}
