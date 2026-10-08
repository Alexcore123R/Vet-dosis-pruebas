import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/catalog.dart';

abstract interface class CatalogRepository {
  Future<DoseCatalog> load();
}

class AssetCatalogRepository implements CatalogRepository {
  @override
  Future<DoseCatalog> load() async {
    final preferences = await SharedPreferences.getInstance();
    return DoseCatalog.parse(
      preferences.getString('doses.catalog.v1') ??
          await rootBundle.loadString('assets/clinical/catalog.v1.json'),
    );
  }

  Future<void> import(String text) async {
    DoseCatalog.parse(text);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString('doses.catalog.v1', text)) {
      throw const FormatException('No se pudo guardar el catálogo.');
    }
  }
}
