import '../../forms/domain/form_models.dart';

abstract interface class PrescribingRepository {
  Future<dynamic> read(String command, Map<String, dynamic> args);
  Future<dynamic> write(String command, Map<String, dynamic> args);
  Future<List<Map<String, dynamic>>> products();
  Future<ReviewedPdf> pdf(String kind, String id);
}
