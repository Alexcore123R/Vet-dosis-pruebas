import 'package:flutter/material.dart';
import '../../../core/widgets/neu_record_card.dart';
import '../domain/catalog.dart';

class VademecumPanel extends StatefulWidget {
  const VademecumPanel({super.key, required this.catalog});
  final DoseCatalog catalog;
  @override
  State<VademecumPanel> createState() => _VademecumPanelState();
}

class _VademecumPanelState extends State<VademecumPanel> {
  String query = '';
  String? species;
  @override
  Widget build(BuildContext context) {
    final rows = widget.catalog.search(query, species: species).toList();
    final speciesList =
        widget.catalog.drugs.map((d) => d.species).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vademécum',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const Icon(Icons.menu_book_outlined, color: Color(0xFF7860B5)),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar medicamento o marca',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: species == null,
              onSelected: (_) => setState(() => species = null),
            ),
            for (final s in speciesList)
              ChoiceChip(
                label: Text(s),
                selected: species == s,
                onSelected: (_) => setState(() => species = s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${rows.length} registros'),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No hay medicamentos para esta búsqueda. El catálogo utiliza únicamente los registros importados.',
            ),
          ),
        for (final drug in rows)
          NeuRecordCard(
            color: drug.personal
                ? const Color(0xFFB098DC)
                : const Color(0xFF51BAC6),
            child: ExpansionTile(
              key: ValueKey(drug.id),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
              title: Text(drug.name),
              subtitle: Text(
                '${drug.species} · ${drug.personal ? 'Dosis personal' : 'Base general'}',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drug.evidence.verified ? 'Verificada' : 'Sin verificar',
                      ),
                      Text('Fuente: ${drug.evidence.source ?? 'Pendiente'}'),
                      const SizedBox(height: 8),
                      Text('Vía: ${drug.route ?? 'Pendiente'}'),
                      Text('Intervalo: ${drug.interval ?? 'Pendiente'}'),
                      Text(
                        'Rango registrado: ${drug.min?.display() ?? 'Pendiente'}–${drug.max?.display() ?? 'Pendiente'} mg/kg',
                      ),
                      for (final p in drug.presentations)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '${p.brand} · ${p.concentration?.display() ?? 'Pendiente'} mg/ml\n${p.evidence.verified ? 'Verificada' : 'Sin verificar'} · Fuente: ${p.evidence.source ?? 'Pendiente'}',
                          ),
                        ),
                      for (final c in drug.contraindications)
                        Text(
                          '${c.kind}: ${c.value} · ${c.note} · Fuente: ${c.evidence.source ?? 'Pendiente'}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
