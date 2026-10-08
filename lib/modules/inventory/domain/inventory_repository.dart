import 'dart:typed_data';

abstract interface class InventoryRepository {
  Future<dynamic> read(String command, Map<String, dynamic> args);
  Future<dynamic> write(String command, Map<String, dynamic> args);
  Future<void> photo(
    String clinic,
    String product,
    int version,
    Uint8List bytes,
    String extension,
  );
  Future<String> photoUrl(String path);
}
