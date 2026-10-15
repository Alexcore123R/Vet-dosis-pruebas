import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportBranding {
  const ExportBranding({required this.name, this.header = '', this.logo});
  final String name, header;
  final Uint8List? logo;
  factory ExportBranding.fromMap(String name, Map<String, dynamic> value) {
    Uint8List? logo;
    try {
      final text = value['logo'];
      if (value['include_logo'] == true &&
          text is String &&
          text.length <= 334000) {
        final bytes = base64Decode(text);
        if (bytes.length <= 250000 && imageExtension(bytes) != null) {
          logo = bytes;
        }
      }
    } catch (_) {}
    return ExportBranding(
      name: name,
      header: '${value['header'] ?? ''}',
      logo: logo,
    );
  }
}

String? imageExtension(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    final data = ByteData.sublistView(bytes);
    final w = data.getUint32(16), h = data.getUint32(20);
    if (w > 0 && h > 0 && w <= 3000 && h <= 3000 && w * h <= 4000000) {
      return 'png';
    }
  }
  if (bytes.length >= 12 && bytes[0] == 255 && bytes[1] == 216) return 'jpeg';
  return null;
}

/// Parse the existing CSV serializers without losing quoted commas or newlines.
List<List<String>> csvRows(String source) {
  final text = source.replaceFirst(RegExp(r'^\uFEFF'), '');
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && c == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (!quoted && (c == '\r' || c == '\n')) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV incompleto.');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String xmlText(String value) => const HtmlEscape(
  HtmlEscapeMode.element,
).convert(value.replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''));
String columnName(int index) {
  var name = '', n = index + 1;
  while (n > 0) {
    n--;
    name = String.fromCharCode(65 + n % 26) + name;
    n ~/= 26;
  }
  return name;
}

/// Actual OpenXML workbook; every supplied value is text, never a formula.
Uint8List brandedXlsx(
  ExportBranding brand,
  String title,
  List<List<String>> rows,
) {
  if (rows.length > 100000 || rows.any((r) => r.length > 500)) {
    throw const FormatException('Exportación demasiado grande.');
  }
  final archive = Archive();
  void add(String path, String body) {
    final bytes = utf8.encode(body);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final ext = brand.logo == null ? null : imageExtension(brand.logo!);
  var logoWidth = 914400, logoHeight = 457200;
  if (ext != null) {
    final image = pw.MemoryImage(brand.logo!);
    final width = image.width ?? 0, height = image.height ?? 0;
    if (width <= 0 || height <= 0 || width * height > 4000000) {
      throw const FormatException('Dimensiones de logo inválidas.');
    }
    final scale = 914400 / width < 457200 / height
        ? 914400 / width
        : 457200 / height;
    logoWidth = (width * scale).round();
    logoHeight = (height * scale).round();
  }
  final all = [
    [brand.name],
    [brand.header],
    [title],
    <String>[],
    ...rows,
  ];
  if (all.any((row) => row.any((v) => v.length > 32767))) {
    throw const FormatException('Una celda supera el límite de Excel.');
  }
  add(
    '[Content_Types].xml',
    '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${ext == null ? '' : '<Default Extension="$ext" ContentType="image/${ext == 'png' ? 'png' : 'jpeg'}"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>''',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Exportación" sheetId="1" r:id="rId1"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
  );
  final data = StringBuffer();
  for (var r = 0; r < all.length; r++) {
    data.write('<row r="${r + 1}">');
    for (var c = 0; c < all[r].length; c++) {
      data.write(
        '<c r="${columnName(c)}${r + 1}" t="inlineStr"><is><t xml:space="preserve">${xmlText(all[r][c])}</t></is></c>',
      );
    }
    data.write('</row>');
  }
  add(
    'xl/worksheets/sheet1.xml',
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><cols><col min="1" max="500" width="24" customWidth="1"/></cols><sheetData>$data</sheetData>${ext == null ? '' : '<drawing r:id="rId1"/>'}</worksheet>',
  );
  if (ext != null) {
    archive.addFile(
      ArchiveFile('xl/media/logo.$ext', brand.logo!.length, brand.logo!),
    );
    add(
      'xl/worksheets/_rels/sheet1.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>',
    );
    add(
      'xl/drawings/_rels/drawing1.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/logo.$ext"/></Relationships>',
    );
    add(
      'xl/drawings/drawing1.xml',
      '''<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><xdr:oneCellAnchor><xdr:from><xdr:col>5</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="$logoWidth" cy="$logoHeight"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="Logo de clínica"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$logoWidth" cy="$logoHeight"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>''',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
