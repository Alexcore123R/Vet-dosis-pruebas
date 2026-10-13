import 'dart:convert';
import 'package:flutter/services.dart';
import '../../doses/domain/quantity.dart';

class IncubationCatalog {
  IncubationCatalog(this.data) {
    final curve = data['curva_clase'] as Map<String, dynamic>;
    final days = curve['dias'] as List;
    final loss = curve['perdida_porcentaje'] as List;
    if (days.length != loss.length) {
      throw const FormatException('Curva incompleta.');
    }
    int previous = -1;
    for (var i = 0; i < days.length; i++) {
      final day = days[i] as int;
      final p = Quantity.parse(loss[i] as String);
      if (day <= previous || p.compareTo(Quantity.parse('100')) > 0) {
        throw const FormatException('Curva inválida.');
      }
      points[day] = p;
      previous = day;
    }
  }
  final Map<String, dynamic> data;
  final points = <int, Quantity>{};
  List<Map<String, dynamic>> get parameters => (data['parametros'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Map<String, dynamic> source(String id) => Map<String, dynamic>.from(
    (data['fuentes'] as List).firstWhere((s) => s['id'] == id) as Map,
  );
}

class IncubationRepository {
  Future<IncubationCatalog> load() async => IncubationCatalog(
    jsonDecode(
          await rootBundle.loadString(
            'assets/clinical/incubation/referencias.v1.json',
          ),
        )
        as Map<String, dynamic>,
  );
}
