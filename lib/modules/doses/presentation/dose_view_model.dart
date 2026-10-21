import 'package:flutter/foundation.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog.dart';
import '../domain/dose_engine.dart';
import '../domain/quantity.dart';

enum ConfirmationStage { none, reviewed, confirmed }

class DoseViewModel extends ChangeNotifier {
  DoseViewModel(this.repository);
  final CatalogRepository repository;
  DoseCatalog? catalog;
  DrugDose? drug;
  Presentation? presentation;
  DoseResult? result;
  String? error;
  bool loading = true;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  ConfirmationStage stage = ConfirmationStage.none;
  Future<void> load() async {
    try {
      catalog = await repository.load();
    } catch (_) {
      error = 'No se pudo cargar el catálogo. Revisa el archivo y su versión.';
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    result = null;
    stage = ConfirmationStage.none;
    error = null;
    notifyListeners();
  }

  void select(DrugDose value) {
    drug = value;
    presentation = null;
    invalidate();
  }

  void selectPresentation(Presentation value) {
    presentation = value;
    invalidate();
  }

  void calculate(
    String weight,
    String dose,
    String step,
    String breed,
    String conditions,
  ) {
    invalidate();
    try {
      if (drug == null || presentation == null) {
        throw const FormatException('Elige fármaco y presentación.');
      }
      final prescribed = drug!.prescribedDose;
      if (prescribed == null || dose.trim().isEmpty) {
        throw const FormatException(
          'Este producto no tiene una dosis única y verificada. No se puede calcular automáticamente.',
        );
      }
      if (Quantity.parse(dose).compareTo(prescribed) != 0) {
        throw const FormatException(
          'La dosis no coincide con la dosis única registrada en el Vademécum.',
        );
      }
      result = const DoseEngine().calculate(
        drug: drug!,
        presentation: presentation!,
        weightKg: Quantity.parse(weight),
        doseMgKg: Quantity.parse(dose),
        syringeStepMl: step.trim().isEmpty ? null : Quantity.parse(step),
        breed: breed,
        conditions: conditions
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    } on FormatException catch (e) {
      error = e.message.toString();
    }
    notifyListeners();
  }

  void review() {
    if (result?.canConfirm == true) {
      stage = ConfirmationStage.reviewed;
      notifyListeners();
    }
  }

  void confirm() {
    if (result?.canConfirm == true && stage == ConfirmationStage.reviewed) {
      stage = ConfirmationStage.confirmed;
      notifyListeners();
    }
  }
}
