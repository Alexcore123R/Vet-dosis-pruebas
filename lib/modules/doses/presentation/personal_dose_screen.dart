import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../data/personal_dose_repository.dart';
import '../domain/catalog.dart';
import '../domain/dose_engine.dart';
import 'dose_math_tools.dart';

class PersonalDoseScreen extends StatefulWidget {
  const PersonalDoseScreen({
    super.key,
    required this.repository,
    required this.clinicId,
    required this.admin,
    required this.general,
  });
  final PersonalDoseRepository repository;
  final String clinicId;
  final bool admin;
  final List<DrugDose> general;
  @override
  State<PersonalDoseScreen> createState() => _PersonalDoseScreenState();
}

class _PersonalDoseScreenState extends State<PersonalDoseScreen> {
  final labelDraft = TextEditingController();
  final fields = {
    for (final k in [
      'farmaco',
      'especie',
      'min',
      'max',
      'via',
      'intervalo',
      'fuente',
      'nombre_comercial',
      'concentracion',
      'fuente_presentacion',
      'contra_raza',
      'contra_condicion',
      'contra_nota',
      'contra_fuente',
    ])
      k: TextEditingController(),
  };
  List<PersonalDoseEntry> entries = [];
  bool busy = false, share = false, verified = false;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    labelDraft.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo completar la operación. Revisa la conexión y que la configuración de dosis personales esté instalada.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reload() => run(() async {
    final result = await widget.repository.list(widget.clinicId);
    if (mounted) setState(() => entries = result);
  });
  Future<void> scanLabel() => run(() async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera,
      maxWidth: 2200, imageQuality: 90);
    if (image == null) return;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String recognized;
    try {
      recognized = (await recognizer.processImage(InputImage.fromFilePath(image.path))).text;
    } finally {
      await recognizer.close();
    }
    if (!mounted) return;
    if (recognized.trim().isEmpty) throw const FormatException('No se leyó texto en la etiqueta. Captura los datos manualmente.');
    final apply = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Revisar texto de la etiqueta'),
      content: SingleChildScrollView(child: SelectableText(recognized)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Descartar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar como borrador')),
      ],
    ));
    if (apply != true || !mounted) return;
    final lines = recognized.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty);
    final concentration = RegExp(r'(\d+(?:[.,]\d+)?)\s*mg\s*(?:/|per)\s*m[lL]\b', caseSensitive: false).firstMatch(recognized);
    final dose = RegExp(r'(\d+(?:[.,]\d+)?)\s*mg\s*(?:/|per)\s*kg\b', caseSensitive: false).firstMatch(recognized);
    final ingredient = RegExp(r'(?:active ingredient|ingrediente activo|principio activo)\s*[:：]\s*([^\n\r]+)', caseSensitive: false).firstMatch(recognized);
    setState(() {
      labelDraft.text = recognized;
      if (fields['nombre_comercial']!.text.isEmpty && lines.isNotEmpty) fields['nombre_comercial']!.text = lines.first;
      if (fields['farmaco']!.text.isEmpty && ingredient != null) fields['farmaco']!.text = ingredient.group(1)!.trim();
      if (concentration != null) fields['concentracion']!.text = concentration.group(1)!.replaceAll(',', '.');
      if (dose != null) {
        fields['min']!.text = dose.group(1)!.replaceAll(',', '.');
        fields['max']!.text = fields['min']!.text;
      }
      fields['fuente_presentacion']!.text = 'Etiqueta fotografiada; datos OCR pendientes de verificación manual';
      verified = false;
    });
  });
  Future<void> save() => run(() async {
    String value(String k) => fields[k]!.text.trim();
    final payload = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'farmaco': value('farmaco'),
      'especie': value('especie'),
      'min': value('min').replaceAll(',', '.'),
      'max': value('max').replaceAll(',', '.'),
      'unidad_dosis': 'mg/kg',
      'via': value('via'),
      'intervalo': value('intervalo'),
      'fuente': value('fuente'),
      'estado': verified ? 'verificada' : 'sin verificar',
      'presentaciones': [
        {
          'id': 'presentacion',
          'nombre_comercial': value('nombre_comercial'),
          'concentracion': value('concentracion').replaceAll(',', '.'),
          'unidad_concentracion': 'mg/ml',
          'fuente': value('fuente_presentacion'),
          'estado': verified ? 'verificada' : 'sin verificar',
        },
      ],
      'contraindicaciones': <Map<String, dynamic>>[
        for (final pair in <(String, String)>[
          ('raza', 'contra_raza'),
          ('condicion', 'contra_condicion'),
        ])
          for (final item in value(
            pair.$2,
          ).split(';').map((s) => s.trim()).where((s) => s.isNotEmpty))
            {
              'tipo': pair.$1,
              'valor': item,
              'nota': value('contra_nota'),
              'fuente': value('contra_fuente'),
              'estado': verified ? 'verificada' : 'sin verificar',
            },
      ],
    };
    final draft = DrugDose.read(payload, personal: true);
    DrugDose? general;
    for (final d in widget.general) {
      if (d.name.toLowerCase() == draft.name.toLowerCase() &&
          d.species.toLowerCase() == draft.species.toLowerCase()) {
        general = d;
        break;
      }
    }
    final problems = validatePersonalDose(draft, general: general);
    if (problems.isNotEmpty) throw FormatException(problems.join(' '));
    await widget.repository.create(widget.clinicId, payload, share: share);
    final result = await widget.repository.list(widget.clinicId);
    if (mounted) {
      setState(() {
        entries = result;
        labelDraft.clear();
        for (final c in fields.values) {
          c.clear();
        }
        verified = false;
        share = false;
      });
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dosis personales')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Cada entrada conserva la etiqueta personal. Compartirla exige revisión del administrador y no modifica la base general.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : scanLabel,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Escanear etiqueta y crear borrador'),
        ),
        const Text('El texto escaneado puede contener errores. Revisa producto, concentración, dosis y fuente antes de guardar; la foto no se sube automáticamente.'),
        TextField(
          controller: labelDraft,
          enabled: !busy,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Texto de etiqueta (español o inglés; borrador local editable)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Puedes capturar todos los datos manualmente. Conserva las indicaciones originales en inglés y comprueba su interpretación antes de usarlas.'),
        OutlinedButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Fórmula general y cálculos manuales')),
                body: const SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: DoseMathTools(),
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Abrir fórmula general y cálculos manuales'),
        ),
        for (final pair in <(String, String)>[
          ('farmaco', 'Fármaco'),
          ('especie', 'Especie (igual que en el catálogo)'),
          ('min', 'Mínimo (mg/kg)'),
          ('max', 'Máximo (mg/kg)'),
          ('via', 'Vía'),
          ('intervalo', 'Intervalo'),
          ('fuente', 'Fuente de dosis (referencia y página o enlace)'),
          ('nombre_comercial', 'Marca y presentación comercial'),
          ('concentracion', 'Concentración (mg/ml)'),
          (
            'fuente_presentacion',
            'Fuente de concentración (etiqueta o ficha técnica)',
          ),
          ('contra_raza', 'Razas contraindicadas (opcional; separadas por ;)'),
          (
            'contra_condicion',
            'Condiciones contraindicadas (opcional; separadas por ;)',
          ),
          ('contra_nota', 'Motivo de contraindicación (si aplica)'),
          ('contra_fuente', 'Fuente de contraindicaciones (si aplica)'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              enabled: !busy,
              controller: fields[pair.$1],
              decoration: InputDecoration(
                labelText: pair.$2,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        const Text(
          'Dejar las contraindicaciones vacías no demuestra ausencia de riesgo. Revisa las referencias antes de usar una dosis personal.',
        ),
        CheckboxListTile(
          title: const Text(
            'Verifiqué dosis, concentración y contraindicaciones contra las fuentes indicadas.',
          ),
          value: verified,
          onChanged: busy ? null : (v) => setState(() => verified = v ?? false),
        ),
        CheckboxListTile(
          title: const Text(
            'Solicitar aprobación para compartir con mi clínica',
          ),
          value: share,
          onChanged: busy ? null : (v) => setState(() => share = v ?? false),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Guardar dosis personal'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Divider(height: 32),
        TextButton(
          onPressed: busy ? null : reload,
          child: const Text('Actualizar entradas'),
        ),
        for (final entry in entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.drug.name} · ${entry.drug.species}'),
                  Text(
                    'Dosis personal · ${switch (entry.state) {
                      'pending' => 'Pendiente de aprobación',
                      'approved' => 'Compartida: aprobada',
                      'rejected' => 'Solicitud rechazada',
                      _ => 'Solo para su autor',
                    }}',
                  ),
                  Text('Fuente: ${entry.drug.evidence.source ?? 'Pendiente'}'),
                  if (widget.admin && entry.state == 'pending')
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  await widget.repository.review(
                                    entry.id,
                                    approve: false,
                                  );
                                  final result = await widget.repository.list(
                                    widget.clinicId,
                                  );
                                  if (mounted) {
                                    setState(() => entries = result);
                                  }
                                }),
                          child: const Text('Rechazar'),
                        ),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  await widget.repository.review(
                                    entry.id,
                                    approve: true,
                                  );
                                  final result = await widget.repository.list(
                                    widget.clinicId,
                                  );
                                  if (mounted) {
                                    setState(() => entries = result);
                                  }
                                }),
                          child: const Text('Aprobar para compartir'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
