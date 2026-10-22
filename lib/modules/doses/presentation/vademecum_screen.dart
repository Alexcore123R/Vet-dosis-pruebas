import 'package:flutter/material.dart';
import '../data/catalog_repository.dart';
import '../data/personal_dose_repository.dart';
import '../domain/catalog.dart';
import 'dose_screen.dart';
import 'personal_dose_screen.dart';

class VademecumScreen extends StatefulWidget {
  const VademecumScreen({super.key, required this.catalog, this.personal,
    this.clinicId, this.userId, this.admin = false, this.canCalculate = false,
    this.offline = false});
  final CatalogRepository catalog;
  final PersonalDoseRepository? personal;
  final String? clinicId, userId;
  final bool admin, canCalculate, offline;
  @override
  State<VademecumScreen> createState() => _VademecumScreenState();
}

class _VademecumScreenState extends State<VademecumScreen> {
  DoseCatalog? catalog;
  List<PersonalDoseEntry> personal = [];
  String query = '', scope = 'todos';
  bool busy = false;
  String? error;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { busy = true; error = null; });
    try {
      final general = await widget.catalog.load();
      final entries = widget.personal == null || widget.clinicId == null || widget.offline
          ? <PersonalDoseEntry>[] : await widget.personal!.list(widget.clinicId!);
      if (mounted) setState(() { catalog = general; personal = entries; });
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo cargar el vademécum. Revisa la conexión y los permisos.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(DrugDose, String)>[
      for (final d in catalog?.drugs ?? <DrugDose>[]) (d, 'Base de la app'),
      for (final e in personal)
        if (e.state == 'approved' || e.userId == widget.userId)
          (e.drug, e.state == 'approved' ? 'Clínica' : 'Personal'),
    ];
    final visible = entries.where((e) =>
      (scope == 'todos' || e.$2 == scope) &&
      ('${e.$1.name} ${e.$1.species} ${e.$1.presentations.map((p) => p.brand).join(' ')}')
        .toLowerCase().contains(query.toLowerCase())).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Vademécum', style: Theme.of(context).textTheme.headlineMedium),
      const Text('Consulta fuentes y presentaciones antes de calcular. La base de la app empieza vacía y no sustituye la revisión profesional.'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      TextField(decoration: const InputDecoration(labelText: 'Buscar fármaco o nombre comercial', prefixIcon: Icon(Icons.search)),
        onChanged: (value) => setState(() => query = value)),
      DropdownButtonFormField<String>(initialValue: scope, decoration: const InputDecoration(labelText: 'Ver fichas'),
        items: const [
          DropdownMenuItem(value: 'todos', child: Text('Todas')),
          DropdownMenuItem(value: 'Base de la app', child: Text('Base de la app')),
          DropdownMenuItem(value: 'Clínica', child: Text('Compartidas con la clínica')),
          DropdownMenuItem(value: 'Personal', child: Text('Solo mías')),
        ], onChanged: (value) => setState(() => scope = value ?? 'todos')),
      if (widget.personal != null && widget.clinicId != null && !widget.offline)
        OutlinedButton.icon(onPressed: () async {
          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => PersonalDoseScreen(
            repository: widget.personal!, clinicId: widget.clinicId!, admin: widget.admin,
            general: catalog?.drugs ?? [])));
          if (mounted) await load();
        }, icon: const Icon(Icons.add), label: const Text('Agregar ficha personal o solicitar compartirla')),
      if (!busy && visible.isEmpty) const Text('Aún no hay fichas en esta vista. Añade una ficha con fuente verificable o importa el catálogo general.'),
      for (final entry in visible)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(entry.$1.name, style: Theme.of(context).textTheme.titleMedium),
            Text('${entry.$1.species} · ${entry.$2} · ${entry.$1.evidence.verified ? 'Verificada' : 'Sin verificar'}'),
            Text('Dosis registrada: ${entry.$1.prescribedDose?.display() ?? 'sin valor único'} mg/kg · ${entry.$1.route ?? 'vía pendiente'}'),
            Text('Fuente: ${entry.$1.evidence.source ?? 'Pendiente'}'),
            for (final p in entry.$1.presentations)
              Text('${p.brand} · ${p.concentration?.display() ?? 'concentración pendiente'} mg/ml'),
            if (widget.canCalculate)
              TextButton.icon(onPressed: () => Navigator.push<void>(context,
                MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(entry.$1.name)),
                  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: DoseScreen(
                    repository: widget.catalog, personalRepository: widget.personal,
                    clinicId: widget.clinicId, userId: widget.userId,
                    admin: widget.admin, offline: widget.offline, initialDrug: entry.$1))))),
                icon: const Icon(Icons.calculate), label: const Text('Calcular dosis')),
          ]))),
    ]);
  }
}
