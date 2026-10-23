import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../data/personal_dose_repository.dart';
import 'personal_dose_screen.dart';
import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog.dart';
import 'dose_view_model.dart';
import 'commercial_package_dose_screen.dart';

class DoseScreen extends StatefulWidget {
  const DoseScreen({
    super.key,
    this.repository,
    this.personalRepository,
    this.clinicId,
    this.userId,
    this.admin = false,
    this.offline = false,
    this.initialDrug,
  });
  final CatalogRepository? repository;
  final PersonalDoseRepository? personalRepository;
  final String? clinicId, userId;
  final bool admin, offline;
  final DrugDose? initialDrug;
  @override
  State<DoseScreen> createState() => _DoseScreenState();
}

class _DoseScreenState extends State<DoseScreen> {
  late final DoseViewModel model;
  final weight = TextEditingController(),
      step = TextEditingController(),
      breed = TextEditingController(),
      conditions = TextEditingController();
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
    model.load().then((_) {
      if (mounted && widget.initialDrug != null) model.select(widget.initialDrug!);
    });
    refreshPersonal();
  }

  @override
  void dispose() {
    for (final c in [weight, step, breed, conditions]) {
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
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Calcular dosis de un producto',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CommercialPackageDoseScreen(),
              ),
            ),
            icon: const Icon(Icons.medication_liquid_outlined),
            label: const Text('Vademécum comercial · dosis del empaque'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Vademécum farmacológico: dosis por principio activo, '
            'presentación y validación clínica independiente.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecciona un fármaco con dosis documentada, elige su presentación e ingresa el peso. La app no propone dosis faltantes ni interpreta rangos.',
          ),
          const SizedBox(height: 12),
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
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'El Vademécum no tiene fármacos disponibles para calcular. Importa un catálogo con fuente, dosis por peso y concentración por presentación. No se calculará una dosis ingresada libremente en este modo.',
                ),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: species,
              decoration: const InputDecoration(labelText: 'Especie'),
              items:
                  (catalog.drugs.map((d) => d.species).toSet().toList()..sort())
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
                selected.prescribedDose == null
                    ? 'Dosis: sin valor único; este modo no calcula rangos automáticamente.'
                    : 'Dosis registrada: ${selected.prescribedDose!.display()} mg/kg',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Presentation>(
                key: ObjectKey(selected),
                initialValue: model.presentation,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Presentación comercial',
                  border: OutlineInputBorder(),
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
              if (selected.prescribedDose != null)
                _bookletDoseValue(selected.prescribedDose!.display()),
              field(
                'Graduación de jeringa (mL, opcional)',
                step,
                numeric: true,
              ),
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
                  selected.prescribedDose?.display() ?? '',
                  step.text,
                  breed.text,
                  conditions.text,
                ),
                child: const Text('Calcular'),
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
              step.text.trim().isEmpty
                  ? 'Masa calculada: ${r.mass.display()} mg\nVolumen calculado: ${r.volume.display()} mL'
                  : 'Masa calculada: ${r.mass.display()} mg\nVolumen teórico: ${r.volume.display()} mL\nVolumen redondeado a la graduación: ${r.roundedVolume.display(places: 9)} mL',
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
                            '${selected!.name} · ${selected.species}\n${model.presentation!.brand}\nPeso: ${weight.text} kg · Dosis: ${selected.prescribedDose!.display()} mg/kg\nVolumen: ${r.roundedVolume.display(places: 9)} mL\nVía: ${selected.route} · Intervalo: ${selected.interval}',
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
      );
    },
  );
}

Widget _bookletDoseValue(String dose) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: InputDecorator(
    decoration: const InputDecoration(
      labelText: 'Dosis del Vademécum',
      border: OutlineInputBorder(),
    ),
    child: Text('$dose mg/kg · no editable'),
  ),
);
