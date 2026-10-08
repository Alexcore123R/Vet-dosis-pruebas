import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/form_repository.dart';
import 'form_pdf_screen.dart';

class BrandingEditor extends StatefulWidget {
  const BrandingEditor({
    super.key,
    required this.repository,
    required this.clinicId,
    required this.schema,
    required this.initial,
  });
  final FormRepository repository;
  final String clinicId;
  final Map<String, dynamic> schema, initial;
  @override
  State<BrandingEditor> createState() => _BrandingEditorState();
}

class _BrandingEditorState extends State<BrandingEditor> {
  final exit = FormExitController();
  late final String original = jsonEncode(widget.initial);
  bool get dirty => jsonEncode(brand) != original;
  @override
  void dispose() {
    exit.dispose();
    super.dispose();
  }

  late Map<String, dynamic> brand;
  bool busy = false;
  String? error, reviewed;
  @override
  void initState() {
    super.initState();
    brand = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.initial)) as Map,
    );
  }

  void changed() {
    setState(() => reviewed = null);
  }

  Future<void> logo() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (!mounted || result.isEmpty) return;
      final file = result.single.xFile;
      if (await file.length() > 250000) {
        throw const FormatException('El logo admite hasta 250 KB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 250000) {
        throw const FormatException('El logo admite hasta 250 KB.');
      }
      brand['logo'] = base64Encode(bytes);
      brand['include_logo'] = true;
      changed();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'No se pudo abrir el logo. Usa PNG/JPG de hasta 250 KB.',
        );
      }
    }
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final fingerprint = jsonEncode(brand);
      final pdf = await widget.repository.templatePreview(
        widget.clinicId,
        widget.schema,
        brand,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: 'Vista previa del membrete y logo',
          ),
        ),
      );
      if (mounted && fingerprint == jsonEncode(brand)) {
        setState(() => reviewed = fingerprint);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo generar el PDF. Revisa imagen, tamaño y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (reviewed != jsonEncode(brand)) throw StateError('Preview required');
      await widget.repository.saveBranding(widget.clinicId, brand);
      if (mounted) exit.close(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se guardó la configuración. Revisa permisos y conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Membrete y logo de la clínica')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Se usarán como valores iniciales en nuevos documentos. Los PDFs ya firmados conservan su membrete y logo originales.',
            ),
            TextFormField(
              initialValue: brand['header'],
              maxLength: 2000,
              maxLines: null,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Membrete y contactos',
              ),
              onChanged: (v) {
                brand['header'] = v;
                changed();
              },
            ),
            OutlinedButton(
              onPressed: busy ? null : logo,
              child: const Text('Seleccionar logo PNG/JPG'),
            ),
            SwitchListTile(
              value: brand['include_logo'] == true,
              title: const Text('Incluir logo en PDF'),
              onChanged: busy
                  ? null
                  : (v) {
                      brand['include_logo'] = v;
                      changed();
                    },
            ),
            if (error != null) Text(error!),
            OutlinedButton(
              onPressed: busy ? null : preview,
              child: const Text('Vista previa PDF'),
            ),
            FilledButton(
              onPressed: busy || reviewed != jsonEncode(brand) ? null : save,
              child: const Text('Guardar configuración nueva'),
            ),
          ],
        ),
      ),
    ),
  );
}
