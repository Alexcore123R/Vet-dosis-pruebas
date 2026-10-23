import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/reference_library_repository.dart';

class ReferenceLibraryScreen extends StatefulWidget {
  const ReferenceLibraryScreen({
    super.key,
    required this.repository,
    required this.clinicId,
    this.initialSection = 'fisiologia',
  });
  final ReferenceLibraryRepository repository;
  final String clinicId;
  final String initialSection;

  @override
  State<ReferenceLibraryScreen> createState() => _ReferenceLibraryScreenState();
}

class _ReferenceLibraryScreenState extends State<ReferenceLibraryScreen> {
  final searchController = TextEditingController();
  late String section = widget.initialSection;
  List<Map<String, dynamic>> items = [];
  int total = 0;
  int generation = 0;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    final request = ++generation;
    final offset = reset ? 0 : items.length;
    final search = searchController.text.trim();
    setState(() {
      busy = true;
      error = null;
      if (reset) {
        items = [];
        total = 0;
      }
    });
    try {
      final page = await widget.repository.list(widget.clinicId, section, search, offset);
      if (!mounted || request != generation) return;
      setState(() {
        items = [...items, ...page.items];
        total = page.total;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'No se pudieron consultar las referencias. Revisa conexión y permisos de lectura clínica.');
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la fuente.')));
    }
  }

  Widget referenceCard(Map<String, dynamic> row) {
    final highlighted = row['review_state'] == 'fuente_contrastada_pendiente_mvz';
    final alternatives = row['alternatives'] as int? ?? 1;
    final distinctIntervals = row['distinct_intervals'] as int? ?? 1;
    String value(String key) => (row[key] ?? '').toString().trim();
    final range = value('min_value').isEmpty && value('max_value').isEmpty
        ? 'Sin intervalo transcrito'
        : '${value('min_value')} – ${value('max_value')} ${value('unit')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${value('species')} · ${value('parameter')}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(range, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(highlighted ? 'Fuente externa contrastada · pendiente de revisión MVZ' : 'Transcripción pendiente de revisión MVZ'),
          if (distinctIntervals > 1) Text('$distinctIntervals intervalos distintos para esta especie, parámetro y unidad. Revisa condiciones y fuentes.'),
          if (distinctIntervals == 1 && alternatives > 1) Text('$alternatives fuentes registradas para este intervalo.'),
          if (value('notes').isNotEmpty) Text(value('notes')),
          const SizedBox(height: 6),
          Text('Fuente: ${value('source_title').isEmpty ? 'No identificada' : value('source_title')}'),
          if (value('source_row').isNotEmpty) Text('Origen: ${value('source_filename')} · ${value('source_sheet')} · fila ${value('source_row')}'),
          if (value('source_url').isNotEmpty)
            TextButton.icon(
              onPressed: () => openSource(value('source_url')),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir fuente'),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Biblioteca de referencias')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Referencias para consulta y evaluación. Los intervalos pendientes no clasifican pacientes ni alimentan recetas o calculadoras. En laboratorio, usa el intervalo del método y analizador que emitió el resultado.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('Constantes y fisiología'), selected: section == 'fisiologia', onSelected: (_) { section = 'fisiologia'; load(reset: true); }),
        ChoiceChip(label: const Text('Laboratorio'), selected: section == 'laboratorio', onSelected: (_) { section = 'laboratorio'; load(reset: true); }),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: searchController,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: 'Buscar especie, parámetro o fuente',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(onPressed: () => load(reset: true), icon: const Icon(Icons.search)),
        ),
        onSubmitted: (_) => load(reset: true),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!busy && error == null) Text('$total referencias encontradas'),
      for (final row in items) referenceCard(row),
      if (items.length < total)
        OutlinedButton(onPressed: busy ? null : () => load(), child: const Text('Ver más referencias')),
    ]),
  );
}
