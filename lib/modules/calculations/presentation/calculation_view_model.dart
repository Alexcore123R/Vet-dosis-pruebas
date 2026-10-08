import 'package:flutter/foundation.dart';
import '../../doses/data/catalog_repository.dart';
import '../../doses/domain/catalog.dart';
import '../../doses/domain/quantity.dart';
import '../data/calculation_repository.dart';
import '../domain/calculation_catalog.dart';
import '../domain/calculation_engine.dart';

class CalculationViewModel extends ChangeNotifier {
  CalculationViewModel(this.repository, this.doses);
  final CalculationRepository repository;
  final CatalogRepository doses;
  CalculationCatalog? catalog;
  DoseCatalog? doseCatalog;
  CalculationResult? result;
  String? error;
  bool disposed = false;
  Future<void> load() async {
    try {
      final catalogs = await Future.wait<Object>([
        repository.load(),
        doses.load(),
      ]);
      if (disposed) return;
      catalog = catalogs[0] as CalculationCatalog;
      doseCatalog = catalogs[1] as DoseCatalog;
    } on FormatException catch (e) {
      if (!disposed) error = e.message;
    } catch (_) {
      if (!disposed) error = 'No se pudieron cargar las referencias.';
    }
    if (!disposed) notifyListeners();
  }

  void clear() {
    result = null;
    error = null;
    notifyListeners();
  }

  void calculate(
    CalculationDefinition definition,
    Map<String, String> values, {
    ClinicalReference? adjustment,
  }) {
    result = null;
    error = null;
    try {
      final inputs = {
        for (final f in definition.inputs)
          f.id: Quantity.parse(values[f.id] ?? ''),
      };
      if (definition.id == 'adjustment') {
        if (adjustment == null ||
            adjustment.type != 'ajuste' ||
            !adjustment.evidence.verified ||
            adjustment.data['factor'] == null) {
          throw const FormatException(
            'Se necesita una referencia verificada específica de fármaco, especie y condición.',
          );
        }
        final factor = Quantity.parse(adjustment.data['factor'] as String);
        if (inputs['factor']!.compareTo(factor) != 0) {
          throw const FormatException(
            'El factor no corresponde a la referencia.',
          );
        }
        final drugs =
            doseCatalog?.drugs
                .where(
                  (d) =>
                      d.id == adjustment.data['farmaco_id'] &&
                      d.species == adjustment.species,
                )
                .toList() ??
            [];
        if (drugs.length != 1 ||
            !drugs.single.evidence.verified ||
            drugs.single.min == null ||
            drugs.single.max == null) {
          throw const FormatException(
            'Falta rango verificado del fármaco/especie.',
          );
        }
        final presentations = drugs.single.presentations
            .where((p) => p.id == adjustment.data['presentacion_id'])
            .toList();
        if (presentations.length != 1 ||
            !presentations.single.evidence.verified ||
            presentations.single.concentration == null ||
            presentations.single.concentration!.compareTo(
                  inputs['concentration']!,
                ) !=
                0) {
          throw const FormatException(
            'La concentración debe corresponder a la presentación verificada de la referencia.',
          );
        }
        final adjusted = inputs['dose']! * factor;
        if (adjusted.compareTo(drugs.single.min!) < 0 ||
            adjusted.compareTo(drugs.single.max!) > 0) {
          throw const FormatException(
            'El ajuste sale del rango verificado; requiere revisión del MVZ.',
          );
        }
      }
      result = const CalculationEngine().calculate(definition.id, inputs);
    } on FormatException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
