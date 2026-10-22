import 'dart:convert';

Map<String, dynamic> readDraftObject(String source) {
  var text = source.trim();
  if (text.startsWith('```')) {
    final newline = text.indexOf('\n');
    if (newline < 0 || !text.endsWith('```')) {
      throw const FormatException(
        'Respuesta incompleta. Pide nuevamente el formato solicitado.',
      );
    }
    text = text.substring(newline + 1, text.length - 3).trim();
  }
  final raw = jsonDecode(text);
  if (raw is! Map<String, dynamic>) {
    throw const FormatException(
      'La respuesta no contiene las opciones solicitadas.',
    );
  }
  return raw;
}

String draftText(dynamic value, int maximum) {
  if (value is! String || value.trim().isEmpty || value.trim().length > maximum) {
    throw const FormatException(
      'La respuesta tiene campos vacíos o demasiado largos. Solicita una nueva versión.',
    );
  }
  return value.trim();
}

class PromotionOption {
  const PromotionOption(this.title, this.message, this.conditions);
  final String title, message, conditions;
  static List<PromotionOption> parse(String source) {
    final raw = readDraftObject(source)['options'];
    if (raw is! List || raw.length != 3) {
      throw const FormatException(
        'Se necesitan exactamente tres opciones. Solicita otra respuesta.',
      );
    }
    return raw.map((row) {
      if (row is! Map) {
        throw const FormatException('Opción de promoción no válida.');
      }
      return PromotionOption(
        draftText(row['title'], 150),
        draftText(row['message'], 2000),
        draftText(row['conditions'], 2000),
      );
    }).toList();
  }
}

class ClinicalDraft {
  const ClinicalDraft(this.fields, this.missing);
  final Map<String, String> fields;
  final List<String> missing;
  static ClinicalDraft parse(String source, Set<String> allowed) {
    final raw = readDraftObject(source);
    if (raw['fields'] is! Map || raw['missing'] is! List) {
      throw const FormatException(
        'Falta el borrador por campos o la lista de datos pendientes.',
      );
    }
    final fields = <String, String>{};
    for (final item in (raw['fields'] as Map).entries) {
      if (item.key is! String || !allowed.contains(item.key)) {
        throw const FormatException(
          'La respuesta intenta cambiar un campo que no fue seleccionado.',
        );
      }
      fields[item.key as String] = draftText(item.value, 4000);
    }
    if (fields.isEmpty) {
      throw const FormatException(
        'La respuesta no incluye campos para revisar.',
      );
    }
    final missing = (raw['missing'] as List)
        .map((e) => draftText(e, 500))
        .toList();
    if (missing.length > 30) {
      throw const FormatException(
        'La lista de datos pendientes es demasiado larga.',
      );
    }
    return ClinicalDraft(fields, missing);
  }
}
