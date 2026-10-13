import 'package:flutter/foundation.dart';
import '../../doses/domain/quantity.dart';
import '../data/incubation_repository.dart';
import '../domain/incubation_engine.dart';

class IncubationViewModel extends ChangeNotifier {
  IncubationViewModel({IncubationRepository? repository})
    : repository = repository ?? IncubationRepository();
  final IncubationRepository repository;
  final engine = const IncubationEngine();
  IncubationCatalog? catalog;
  String output = '', error = '';
  bool busy = false, _disposed = false;
  Future<void> load() async {
    busy = true;
    notifyListeners();
    try {
      final loaded = await repository.load();
      if (!_disposed) catalog = loaded;
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudieron cargar las referencias de incubación.';
      }
    }
    if (!_disposed) {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    output = '';
    error = '';
    notifyListeners();
  }

  void calculate(
    String tool,
    Map<String, String> inputs, {
    bool sameSample = false,
    bool reviewed = false,
    String stockUnit = 'mg_ml',
    String targetUnit = 'mg_l',
  }) {
    output = '';
    error = '';
    Quantity q(String key) => Quantity.parse(inputs[key] ?? '');
    try {
      switch (tool) {
        case 'chick':
          final egg = q('egg');
          final percent = q('yield');
          output =
              'Peso estimado: ${egg.display()} g × ${percent.display()} / 100 = ${engine.chickWeight(egg, percent).display(places: 9)} g.\nPorcentaje elegido manualmente; sin verificación ni garantía de peso al nacimiento. La línea y el momento de pesaje importan.';
        case 'loss':
          if (!sameSample) {
            throw const FormatException(
              'Confirma que son el mismo huevo o muestra comparable, sin tara y con bajas corregidas.',
            );
          }
          final initial = q('initial');
          final current = q('current');
          final day = int.tryParse(inputs['day'] ?? '');
          if (day == null || day < 0) {
            throw const FormatException('Ingresa un día entero no negativo.');
          }
          final observed = engine.lossPercent(initial, current);
          final reference = engine.lossAtDay(day, catalog?.points ?? {});
          output =
              'Pérdida observada: (${initial.display()} − ${current.display()}) / ${initial.display()} × 100 = ${signedDisplay(observed)} %.\n';
          if (observed.n < BigInt.zero) {
            output +=
                'El peso aumentó. Revisa medición, condensación y comparabilidad; no se interpreta como pérdida normal.\n';
          }
          if (reference == null) {
            output +=
                'No hay un punto documentado para el día $day. No se interpola ni extrapola.';
          } else {
            output +=
                'Referencia de clase sin verificar, día $day: ${reference.display()} %.\nPeso esperado según esa referencia: ${initial.display()} × (1 − ${reference.display()}/100) = ${engine.expectedEgg(initial, reference).display(places: 9)} g.\nDiferencia: ${signedDisplay(difference(observed, reference))} puntos porcentuales; no es diagnóstico ni ajuste automático de humedad.';
          }
        case 'dilution':
          if (!reviewed) {
            throw const FormatException(
              'Confirma composición, unidades y objetivo explícito del prospecto; no lo tomes de una tabla genérica.',
            );
          }
          if ((inputs['product'] ?? '').trim().isEmpty ||
              (inputs['source'] ?? '').trim().isEmpty) {
            throw const FormatException(
              'Identifica producto, presentación y fuente; no completes datos por suposición.',
            );
          }
          final stock = engine.massVolume(q('stock'), stockUnit);
          final target = engine.massVolume(q('target'), targetUnit);
          final volume = q('final_ml');
          final product = engine.concentrateMl(stock, target, volume);
          output =
              'Producto capturado: ${inputs['product']}. Fuente capturada (sin verificar): ${inputs['source']}.\nInicial: ${stock.display(places: 9)} mg/ml. Objetivo: ${target.display(places: 9)} mg/ml.\nC₁ × V₁ = C₂ × Vfinal.\nVolumen de producto = ${target.display(places: 9)} × ${volume.display()} / ${stock.display(places: 9)} = ${product.display(places: 9)} ml.\nCompletar con diluyente compatible hasta ${volume.display()} ml FINALES; diferencia volumétrica teórica: ${signedDisplay(difference(volume, product))} ml.\nVisualización aproximada; no redondea una preparación ni confirma estabilidad, compatibilidad o uso en huevo fértil. No calcula mezclas de varios productos, polvos o fumigación por m³.';
        default:
          throw const FormatException('Herramienta desconocida.');
      }
    } catch (e) {
      output = '';
      error = e is FormatException ? e.message : 'Revisa los datos.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
