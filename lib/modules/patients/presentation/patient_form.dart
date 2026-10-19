import '../../core/presentation/unsaved_form_scope.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/patient_models.dart';
import 'patient_view_model.dart';

class PatientForm extends StatefulWidget {
  const PatientForm({super.key, required this.owners, required this.save});
  final List<VetOwner> owners;
  final Future<String?> Function(
    Map<String, dynamic>,
    Map<String, dynamic>?,
    String,
  )
  save;
  @override
  State<PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<PatientForm> {
  final fields = {
    for (final key in [
      'name',
      'species',
      'breed',
      'birth_date',
      'owner_name',
      'phone',
      'email',
      'address',
    ])
      key: TextEditingController(),
  };
  String sex = 'sin especificar', ownerMode = 'pending';
  String? ownerId, error;
  final exit = FormExitController();
  bool get dirty =>
      fields.values.any((c) => c.text.isNotEmpty) ||
      sex != 'sin especificar' ||
      ownerMode != 'pending' ||
      ownerId != null;
  @override
  void initState() {
    super.initState();
    for (final c in fields.values) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  bool busy = false;
  String operationId = newOperationId();
  String? attempted;
  @override
  void dispose() {
    exit.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      String value(String key) => fields[key]!.text.trim();
      final patient = <String, dynamic>{
        'name': textField(
          {'name': value('name')},
          'name',
          required: true,
          max: 120,
        ),
        'species': textField(
          {'species': value('species')},
          'species',
          required: true,
          max: 120,
        ),
        'breed': value('breed'),
        'sex': sex,
        'birth_date': value('birth_date').isEmpty
            ? null
            : calendarDate(value('birth_date')),
      };
      if (ownerMode == 'existing') {
        if (ownerId == null) {
          throw const FormatException('Selecciona el tutor.');
        }
        patient['owner_id'] = ownerId;
      }
      final owner = ownerMode == 'new'
          ? <String, dynamic>{
              'name': textField(
                {'name': value('owner_name')},
                'name',
                required: true,
                max: 200,
              ),
              'phone': value('phone'),
              'email': value('email'),
              'address': value('address'),
            }
          : null;
      final fingerprint = jsonEncode([patient, owner]);
      if (attempted != null && attempted != fingerprint) {
        operationId = newOperationId();
      }
      attempted = fingerprint;
      final problem = await widget.save(patient, owner, operationId);
      if (!mounted) return;
      if (problem == null) {
        exit.close(context, true);
        return;
      }
      setState(() => error = problem);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget input(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      enabled: !busy,
      controller: fields[key],
      keyboardType: switch (key) {
        'phone' => TextInputType.phone,
        'email' => TextInputType.emailAddress,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Nuevo paciente')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Datos del paciente',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          input('name', 'Nombre del paciente'),
          input('species', 'Especie'),
          input('breed', 'Raza (opcional)'),
          DropdownButtonFormField<String>(
            initialValue: sex,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sexo'),
            items: const [
              DropdownMenuItem(
                value: 'sin especificar',
                child: Text('Sin especificar'),
              ),
              DropdownMenuItem(value: 'hembra', child: Text('Hembra')),
              DropdownMenuItem(value: 'macho', child: Text('Macho')),
            ],
            onChanged: busy ? null : (v) => setState(() => sex = v ?? sex),
          ),
          const SizedBox(height: 16),
          input('birth_date', 'Fecha de nacimiento (AAAA-MM-DD, opcional)'),
          Text(
            'Tutor y contacto',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: ownerMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tutor / propietario'),
            items: const [
              DropdownMenuItem(
                value: 'pending',
                child: Text('Pendiente de capturar'),
              ),
              DropdownMenuItem(
                value: 'existing',
                child: Text('Tutor ya registrado'),
              ),
              DropdownMenuItem(
                value: 'new',
                child: Text('Registrar tutor nuevo'),
              ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() => ownerMode = v ?? ownerMode),
          ),
          const SizedBox(height: 16),
          if (ownerMode == 'existing')
            DropdownButtonFormField<String>(
              initialValue: ownerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tutor registrado'),
              items: widget.owners
                  .map(
                    (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => ownerId = v),
            ),
          if (ownerMode == 'new') ...[
            input('owner_name', 'Nombre del tutor'),
            input('phone', 'Teléfono internacional (opcional, ej. +52…)'),
            input('email', 'Correo (opcional)'),
            input('address', 'Dirección (opcional)'),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Guardando…' : 'Crear paciente'),
          ),
        ],
      ),
    ),
  );
}
