import 'dart:typed_data';

abstract class BackupRepository {
  Future<Map<String, dynamic>> statistics(String clinic);
  Future<String> snapshot(String clinic);
  Future<Uint8List> photo(String path);
}
