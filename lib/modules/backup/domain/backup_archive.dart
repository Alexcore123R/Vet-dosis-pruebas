import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../prescribing/domain/prescribing_models.dart' show csvCell;
import 'backup_repository.dart';

/// Original PostgreSQL snapshot is preserved as text, avoiding numeric precision loss.
class BackupArchive {
  static const maxBytes = 50 * 1024 * 1024;
  static Future<Uint8List> create(
    BackupRepository repository,
    String clinic, {
    BackupScope scope = BackupScope.clinic,
    Map<String, String> clinicalAssets = const {},
  }) async {
    final snapshot = await repository.snapshot(clinic, scope: scope);
    final data = jsonDecode(snapshot) as Map;
    if (data['clinic_id'] != clinic || data['version'] != 1) {
      throw const FormatException('El respaldo no corresponde a esta clínica.');
    }
    if (utf8.encode(snapshot).length > maxBytes) {
      throw const FormatException(
        'El respaldo requiere exportación por lotes; supera 50 MB.',
      );
    }
    final attachments = <String, dynamic>{};
    var total = utf8.encode(snapshot).length;
    final tables = data['tables'] as Map;
    for (final product in tables['inventario'] as List? ?? []) {
      final path = product['photo_path'];
      if (path == null || attachments.containsKey(path)) continue;
      if (path is! String || !_clinicPath(path, clinic)) {
        throw const FormatException('Foto fuera del alcance de la clínica.');
      }
      final bytes = await repository.photo(path);
      total += bytes.length * 4 ~/ 3;
      if (total > maxBytes) {
        throw const FormatException(
          'El respaldo con fotos requiere exportación por lotes; supera 50 MB.',
        );
      }
      attachments[path] = {
        'sha256': sha256.convert(bytes).toString(),
        'base64': base64Encode(bytes),
      };
    }
    final archive = {
      'format': 'vetdosis-archive',
      'version': 1,
      'snapshot_json': snapshot,
      'snapshot_sha256': sha256.convert(utf8.encode(snapshot)).toString(),
      'attachments': attachments,
      'clinical_assets': {
        for (final e in clinicalAssets.entries)
          e.key: {
            'json': e.value,
            'sha256': sha256.convert(utf8.encode(e.value)).toString(),
          },
      },
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(archive)));
    if (bytes.length > maxBytes) {
      throw const FormatException(
        'El respaldo completo requiere exportación por lotes; supera 50 MB.',
      );
    }
    return bytes;
  }

  static Map<String, dynamic> verify(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('El respaldo supera 50 MB.');
    }
    try {
      return _verify(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Estructura de respaldo inválida o incompleta.',
      );
    }
  }

  static bool _clinicPath(String path, String clinic) =>
      path.startsWith('$clinic/') &&
      !path.contains('\\') &&
      !path
          .split('/')
          .any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          );
  static Map<String, dynamic> _verify(Uint8List bytes) {
    final a = jsonDecode(utf8.decode(bytes)) as Map;
    if (a['format'] != 'vetdosis-archive' ||
        a['version'] != 1 ||
        a['snapshot_json'] is! String) {
      throw const FormatException('Formato de respaldo no compatible.');
    }
    if (sha256.convert(utf8.encode(a['snapshot_json'] as String)).toString() !=
        a['snapshot_sha256']) {
      throw const FormatException(
        'El respaldo fue alterado o está incompleto.',
      );
    }
    for (final attachment in (a['attachments'] as Map).values) {
      if (sha256
              .convert(base64Decode(attachment['base64'] as String))
              .toString() !=
          attachment['sha256']) {
        throw const FormatException('Una fotografía no coincide con su hash.');
      }
    }
    for (final asset in (a['clinical_assets'] as Map? ?? {}).values) {
      if (sha256.convert(utf8.encode(asset['json'] as String)).toString() !=
          asset['sha256']) {
        throw const FormatException('Un catálogo no coincide con su hash.');
      }
    }
    final snapshot = Map<String, dynamic>.from(
      jsonDecode(a['snapshot_json'] as String) as Map,
    );
    if (snapshot['version'] != 1 ||
        snapshot['clinic_id'] is! String ||
        (snapshot['clinic_id'] as String).isEmpty) {
      throw const FormatException('Identificación del respaldo inválida.');
    }
    for (final path in (a['attachments'] as Map).keys) {
      if (path is! String ||
          !_clinicPath(path, snapshot['clinic_id'] as String)) {
        throw const FormatException(
          'Una foto está fuera de la clínica del respaldo.',
        );
      }
    }
    final tables = snapshot['tables'] as Map;
    for (final product in tables['inventario'] as List? ?? []) {
      final path = product['photo_path'];
      if (path == null) continue;
      if (path is! String ||
          !_clinicPath(path, '${snapshot['clinic_id']}') ||
          !(a['attachments'] as Map).containsKey(path)) {
        throw const FormatException('Falta una foto declarada en el respaldo.');
      }
    }
    for (final name in ['form_artifacts', 'rx_artifacts']) {
      for (final artifact in tables[name] as List? ?? []) {
        final hex = artifact['pdf'];
        if (hex is! String || !hex.startsWith(r'\x') || hex.length.isOdd) {
          throw const FormatException('PDF histórico inválido.');
        }
        final pdf = Uint8List.fromList([
          for (var i = 2; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
        if (sha256.convert(pdf).toString() != artifact['pdf_hash']) {
          throw const FormatException(
            'El PDF histórico no coincide con el documento congelado.',
          );
        }
      }
    }
    return snapshot;
  }

  static String tableCsv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    final fields = rows.expand((r) => r.keys).toSet().toList()..sort();
    return [
      fields.map(csvCell).join(','),
      for (final row in rows)
        fields
            .map(
              (k) => csvCell(
                row[k] is Map || row[k] is List ? jsonEncode(row[k]) : row[k],
              ),
            )
            .join(','),
    ].join('\r\n');
  }
}
