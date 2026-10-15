import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/exports/domain/branded_export.dart';
import 'package:vetdosis_pro/modules/exports/presentation/branded_export_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABQAAAAKCAIAAAA7N+mxAAAAF0lEQVR4nGNkqK1lIBcwka1zVPOI0QwAa5cBDr6p6gIAAAAASUVORK5CYII=',
  );
  final branding = ExportBranding(
    name: 'Clínica Águila & Sol',
    header: 'Contacto\nMembrete de prueba',
    logo: logo,
  );
  test('CSV conserva comas, comillas, saltos y columnas vacías', () {
    expect(
      csvRows(
        '\uFEFF"Nombre","Nota"\r\n"Águila, Sol","Dos ""comillas""\ny líneas"\r\n"",',
      ),
      [
        ['Nombre', 'Nota'],
        ['Águila, Sol', 'Dos "comillas"\ny líneas'],
        ['', ''],
      ],
    );
    expect(() => csvRows('"incompleto'), throwsFormatException);
  });
  test('XLSX real lleva logo embebido y texto sin fórmulas ejecutables', () {
    final bytes = brandedXlsx(branding, 'Consulta no oficial', [
      ['Producto', 'Dato'],
      ['=HYPERLINK("bad")', '00123'],
      ['A & B', '<etiqueta>'],
    ]);
    final archive = ZipDecoder().decodeBytes(bytes);
    String read(String path) => utf8.decode(archive.findFile(path)!.content);
    expect(read('xl/workbook.xml'), contains('spreadsheetml/2006/main'));
    expect(
      read('xl/worksheets/sheet1.xml'),
      contains('Clínica Águila &amp; Sol'),
    );
    expect(read('xl/worksheets/sheet1.xml'), contains('00123'));
    expect(read('xl/worksheets/sheet1.xml'), isNot(contains('<f>')));
    expect(archive.findFile('xl/media/logo.png')!.content, logo);
    expect(
      read('xl/drawings/_rels/drawing1.xml.rels'),
      contains('../media/logo.png'),
    );
    // Optional interoperability artifact for an independent Excel reader.
    if (Platform.environment['EXPORT_TEST_DIR'] case final String dir) {
      File('$dir/identidad.xlsx').writeAsBytesSync(bytes);
    }
  });
  test(
    'PDF con acentos y logo produce un archivo real, incluso con tablas anchas',
    () async {
      final bytes = await brandedPdf(
        branding,
        'Registro · basado en Anexo 5, no oficial',
        [
          List.generate(13, (i) => 'Columna $i'),
          List.generate(13, (i) => 'Valor $i'),
        ],
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1500));
      if (Platform.environment['EXPORT_TEST_DIR'] case final String dir) {
        File('$dir/identidad.pdf').writeAsBytesSync(bytes);
      }
    },
  );
  test(
    'Logo desactivado o inválido se omite y se respetan límites de Excel',
    () {
      expect(
        ExportBranding.fromMap('A', {
          'include_logo': false,
          'logo': base64Encode(logo),
        }).logo,
        isNull,
      );
      expect(
        ExportBranding.fromMap('A', {
          'include_logo': true,
          'logo': 'invalid!',
        }).logo,
        isNull,
      );
      expect(
        () => brandedXlsx(branding, 'Consulta', [
          ['x' * 32768],
        ]),
        throwsFormatException,
      );
    },
  );
}
