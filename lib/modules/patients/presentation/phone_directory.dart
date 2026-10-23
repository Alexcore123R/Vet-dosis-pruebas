import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/neu_record_card.dart';
import '../domain/patient_models.dart';

class PhoneDirectory extends StatefulWidget {
  const PhoneDirectory({super.key, required this.owners});
  final List<VetOwner> owners;
  @override
  State<PhoneDirectory> createState() => _PhoneDirectoryState();
}

class _PhoneDirectoryState extends State<PhoneDirectory> {
  String query = '';
  bool withPhone = false;
  @override
  Widget build(BuildContext context) {
    final rows =
        widget.owners
            .where(
              (o) =>
                  (!withPhone || o.phone.trim().isNotEmpty) &&
                  '${o.name} ${o.phone}'.toLowerCase().contains(query),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Agenda telefónica',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text('Tutores de la clínica'),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar nombre o teléfono',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: !withPhone,
              onSelected: (_) => setState(() => withPhone = false),
            ),
            ChoiceChip(
              label: const Text('Con teléfono'),
              selected: withPhone,
              onSelected: (_) => setState(() => withPhone = true),
            ),
          ],
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No hay contactos para esta búsqueda.'),
          ),
        for (final owner in rows)
          NeuRecordCard(
            color: const Color(0xFF72C8B6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  owner.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  owner.phone.trim().isEmpty
                      ? 'Teléfono pendiente'
                      : owner.phone,
                ),
                if (owner.email.isNotEmpty) Text(owner.email),
                if (owner.phone.trim().isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copiar teléfono'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: owner.phone));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Teléfono copiado')),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
