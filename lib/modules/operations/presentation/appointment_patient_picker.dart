import 'package:flutter/material.dart';
import '../domain/operations_repository.dart';

class AppointmentPatientPicker extends StatefulWidget {
  const AppointmentPatientPicker({
    super.key,
    required this.repository,
    required this.clinic,
  });
  final AppointmentPatientRepository repository;
  final String clinic;
  @override
  State<AppointmentPatientPicker> createState() =>
      _AppointmentPatientPickerState();
}

class _AppointmentPatientPickerState extends State<AppointmentPatientPicker> {
  final query = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool busy = false, searched = false;
  String? error;
  int revision = 0;
  @override
  void dispose() {
    revision++;
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final text = query.text.trim();
    final request = ++revision;
    setState(() {
      results = [];
      error = null;
      searched = false;
      busy = text.isNotEmpty;
    });
    if (text.isEmpty) return;
    try {
      final rows = await widget.repository.searchPatients(widget.clinic, text);
      if (!mounted || request != revision) return;
      setState(() {
        results = rows;
        searched = true;
      });
    } catch (_) {
      if (mounted && request == revision) {
        setState(
          () => error = 'No se pudo buscar. Revisa la conexión y tus permisos.',
        );
      }
    } finally {
      if (mounted && request == revision) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paciente de la cita')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Busca un paciente por nombre, especie, tutor, teléfono o una nota clínica autorizada. Solo se muestran coincidencias permitidas por tus permisos.',
        ),
        TextField(
          controller: query,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Paciente, tutor, teléfono o nota clínica',
          ),
          onChanged: (_) => setState(() {
            revision++;
            results = [];
            searched = false;
            busy = false;
            error = null;
          }),
          onSubmitted: (_) => search(),
        ),
        FilledButton(
          onPressed: busy ? null : search,
          child: const Text('Buscar paciente'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (searched && results.isEmpty)
          const Text('No se encontraron pacientes con ese nombre.'),
        if (results.length == 50)
          const Text(
            'Se muestran hasta 50 coincidencias. Escribe un nombre más específico.',
          ),
        for (final patient in results)
          ListTile(
            title: Text(patient['name']),
            subtitle: Text(
              [
                patient['species'],
                if ((patient['owner_name'] as String? ?? '').isNotEmpty)
                  'Tutor: ${patient['owner_name']}',
                if ((patient['owner_phone'] as String? ?? '').isNotEmpty)
                  patient['owner_phone'],
              ].join(' · '),
            ),
            onTap: () => Navigator.pop(context, patient),
          ),
        const Divider(),
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.pop(context, <String, dynamic>{}),
          child: const Text('Agendar sin expediente vinculado'),
        ),
        const Text(
          'Agendar sin expediente no crea un paciente ni un propietario. Puedes registrar sus datos desde Pacientes.',
        ),
      ],
    ),
  );
}
