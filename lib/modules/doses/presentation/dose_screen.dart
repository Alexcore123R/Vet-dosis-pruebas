import 'vademecum_panel.dart';
import '../../../core/widgets/calculator_surface.dart';
import '../../../core/widgets/workspace_panel.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../data/personal_dose_repository.dart';
import 'personal_dose_screen.dart';
import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog.dart';
import 'dose_view_model.dart';

class DoseScreen extends StatefulWidget {
  const DoseScreen({
    super.key,
    this.repository,
    this.personalRepository,
    this.clinicId,
    this.userId,
    this.admin = false,
    this.offline = false,
  });
  final CatalogRepository? repository;
  final PersonalDoseRepository? personalRepository;
  final String? clinicId, userId;
  final bool admin, offline;
  @override
  State<DoseScreen> createState() => _DoseScreenState();
}

class _DoseScreenState extends State<DoseScreen> {
  late final DoseViewModel model;
  final weight = TextEditingController(),
      dose = TextEditingController(),
      step = TextEditingController(),
      breed = TextEditingController(),
      conditions = TextEditingController();
  bool showVademecum = false;
  String query = '';
  String? species;
  List<DrugDose> personal = [];
  Future<void> refreshPersonal() async {
    if (widget.personalRepository == null ||
        widget.clinicId == null ||
        widget.offline) {
      return;
    }
    try {
      final rows = await widget.personalRepository!.list(widget.clinicId!);
      if (mounted) {
        setState(
          () => personal = rows
              .where((e) => e.state == 'approved' || e.userId == widget.userId)
              .map((e) => e.drug)
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => model.error =
              'Las dosis personales aún no están disponibles. Revisa la conexión y su configuración.',
        );
      }
    }
  }

  Future<void> importCatalog() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || selection.isEmpty) return;
      final length = await selection.single.xFile.length();
      if (length > 2 * 1024 * 1024) {
        throw const FormatException('Selecciona un catálogo de hasta 2 MB.');
      }
      final bytes = await selection.single.xFile.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Selecciona un catálogo de hasta 2 MB.');
      }
      if (!mounted) return;
      final text = utf8.decode(bytes);
      final incoming = DoseCatalog.parse(text);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importar catálogo'),
          content: Text(
            'Versión ${incoming.version} · ${incoming.drugs.length} entradas. Reemplazará el catálogo general guardado en este dispositivo. Las fuentes y estados provienen del archivo; la app no los verifica automáticamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final repository = model.repository;
      if (repository is! AssetCatalogRepository) {
        throw const FormatException('Importación no disponible.');
      }
      await repository.import(text);
      if (!mounted) return;
      model.drug = null;
      model.presentation = null;
      model.invalidate();
      setState(() {
        species = null;
        query = '';
      });
      await model.load();
      refreshPersonal();
    } on FormatException catch (e) {
      if (mounted) setState(() => model.error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() => model.error = 'No se pudo importar el catálogo.');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    model = DoseViewModel(widget.repository ?? AssetCatalogRepository());
    model.load();
    refreshPersonal();
  }

  @override
  void dispose() {
    for (final c in [weight, dose, step, breed, conditions]) {
      c.dispose();
    }
    model.dispose();
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => model.invalidate(),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      if (model.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final general = model.catalog;
      final catalog = general == null
          ? null
          : DoseCatalog(general.version, [...general.drugs, ...personal]);
      final selected = model.drug;
      if (showVademecum && catalog != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => showVademecum = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver a cálculo rápido'),
            ),
            VademecumPanel(catalog: catalog),
          ],
        );
      }

      return CalculatorSurface(
        id: 'dose',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CalculatorIcon('dose'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cálculo rápido',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (catalog != null)
              OutlinedButton.icon(
                onPressed: () => setState(() => showVademecum = true),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Abrir vademécum'),
              ),
            if (widget.admin)
              OutlinedButton.icon(
                onPressed: importCatalog,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Importar catálogo'),
              ),
            if (widget.personalRepository != null &&
                widget.clinicId != null &&
                !widget.offline)
              OutlinedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PersonalDoseScreen(
                        repository: widget.personalRepository!,
                        clinicId: widget.clinicId!,
                        admin: widget.admin,
                        general: general?.drugs ?? [],
                      ),
                    ),
                  );
                  if (mounted) {
                    model.drug = null;
                    model.presentation = null;
                    model.invalidate();
                    await refreshPersonal();
                  }
                },
                child: const Text('Mis dosis personales y solicitudes'),
              ),
            if (catalog == null)
              Text(model.error ?? 'Catálogo no disponible.')
            else if (catalog.drugs.isEmpty)
              const WorkspacePanel(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Tu catálogo está pendiente de importar. Necesitamos dosis con fuente y concentración por presentación comercial. No hay dosis precargadas ni recomendaciones inventadas.',
                  ),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: species,
                decoration: const InputDecoration(labelText: 'Especie'),
                items:
                    (catalog.drugs.map((d) => d.species).toSet().toList()
                          ..sort())
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged: (s) {
                  setState(() {
                    species = s;
                    model.drug = null;
                    model.presentation = null;
                  });
                  model.invalidate();
                },
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar fármaco o marca comercial',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (s) => setState(() => query = s),
              ),
              for (final item in catalog.search(query, species: species))
                ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.species} · ${item.personal ? 'Dosis personal' : 'Base general'} · ${item.evidence.verified ? 'Verificada' : 'Sin verificar'}',
                  ),
                  selected: selected == item,
                  onTap: () => model.select(item),
                ),
              if (selected != null) ...[
                const Divider(),
                Text(
                  '${selected.name} · ${selected.species}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('Fuente: ${selected.evidence.source ?? 'Pendiente'}'),
                Text(
                  'Vía: ${selected.route ?? 'Pendiente'} · Intervalo: ${selected.interval ?? 'Pendiente'}',
                ),
                Text(
                  'Rango: ${selected.min?.display() ?? 'Pendiente'}–${selected.max?.display() ?? 'Pendiente'} mg/kg',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Presentation>(
                  key: ObjectKey(selected),
                  initialValue: model.presentation,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Presentación comercial',
                  ),
                  items: selected.presentations
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.brand} · ${p.concentration?.display() ?? 'Pendiente'} mg/ml',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (p) {
                    if (p != null) model.selectPresentation(p);
                  },
                ),
                if (model.presentation != null)
                  Text(
                    'Fuente de presentación: ${model.presentation!.evidence.source ?? 'Pendiente'}',
                  ),
                const SizedBox(height: 16),
                field('Peso (kg)', weight, numeric: true),
                field('Dosis seleccionada (mg/kg)', dose, numeric: true),
                field('Graduación de jeringa (ml)', step, numeric: true),
                field('Raza', breed),
                field(
                  'Condiciones del paciente (separadas por coma)',
                  conditions,
                ),
                if (selected.contraindications.isNotEmpty) ...[
                  const Text('Revisa las contraindicaciones publicadas:'),
                  for (final c in selected.contraindications)
                    Text(
                      '${c.kind}: ${c.value} · ${c.note} · Fuente: ${c.evidence.source ?? 'Pendiente'}',
                    ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => model.calculate(
                    weight.text,
                    dose.text,
                    step.text,
                    breed.text,
                    conditions.text,
                  ),
                  child: const Text('Calcular dosis'),
                ),
              ],
            ],
            if (model.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  model.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (model.result case final r?) ...[
              const SizedBox(height: 20),
              Text(
                'Masa: ≈ ${r.mass.display()} mg\nVolumen teórico: ≈ ${r.volume.display()} ml\nVolumen a la graduación elegida: ≈ ${r.roundedVolume.display(places: 9)} ml',
              ),
              const Text(
                'La visualización se aproxima; los límites se evalúan con valores exactos.',
              ),
              for (final alert in r.alerts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    alert,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              CheckboxListTile(
                title: const Text(
                  'Revisé paciente, peso, dosis, presentación, vía y contraindicaciones.',
                ),
                value: model.stage != ConfirmationStage.none,
                onChanged: r.canConfirm && model.stage == ConfirmationStage.none
                    ? (_) => model.review()
                    : null,
              ),
              FilledButton(
                onPressed:
                    model.stage == ConfirmationStage.reviewed && r.canConfirm
                    ? () async {
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Segunda confirmación'),
                            content: Text(
                              '${selected!.name} · ${selected.species}\n${model.presentation!.brand}\nPeso: ${weight.text} kg · Dosis: ${dose.text} mg/kg\nVolumen: ≈ ${r.roundedVolume.display(places: 9)} ml\nVía: ${selected.route} · Intervalo: ${selected.interval}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Volver a revisar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Confirmar cálculo'),
                              ),
                            ],
                          ),
                        );
                        if (accepted == true &&
                            mounted &&
                            identical(model.result, r)) {
                          model.confirm();
                        }
                      }
                    : null,
                child: const Text('Confirmar por segunda vez'),
              ),
              if (model.stage == ConfirmationStage.confirmed)
                const Text(
                  'Cálculo confirmado. No registra una administración ni genera una receta.',
                ),
            ],
          ],
        ),
      );
    },
  );
}
