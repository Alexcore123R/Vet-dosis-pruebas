import 'package:flutter/services.dart';
import '../domain/calculation_catalog.dart';

abstract interface class CalculationRepository {
  Future<CalculationCatalog> load();
}

class AssetCalculationRepository implements CalculationRepository {
  @override
  Future<CalculationCatalog> load() async => CalculationCatalog.parse(
    await rootBundle.loadString('assets/clinical/calculations.v1.json'),
  );
}
