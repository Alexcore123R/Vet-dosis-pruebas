import 'dart:convert';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/form_models.dart';
import 'clinical_models.dart';
import 'clinical_repository.dart';

class DeathScreen extends StatefulWidget {
  const DeathScreen({
    super.key,
    required this.repository,
    required this.document,
    required this.member,
  });
  final ClinicalRepository repository;
  final FormDocument document;
  final ClinicMembership member;
  @override
  State<DeathScreen> createState() => _DeathScreenState();
}

class _DeathScreenState extends State<DeathScreen> {
  List<Map<String, dynamic>> records = [];
  bool busy = true;
  String? error;
  final data = <String, dynamic>{
    'result': 'no_confirmada',
    'observed_at': DateTime.now().toUtc().toIso8601String(),
  };
  String operation = newOperationId(), lastPayload = '';
  bool get responsible =>
      widget.member.role == ClinicRole.mvz &&
      widget.document.responsibleId == widget.member.userId;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await widget.repository.deathRecords(widget.document.id);
      if (mounted) setState(() => records = rows);
    } catch (_) {
      if (mounted) {
        setState(() {
          records = [];
          error = 'No se pudo consultar. Revisa acceso y conexión.';
        });
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
      clinicalInstant(data['observed_at']);
      if ((data['method'] as String? ?? '').trim().isEmpty ||
          (data['findings'] as String? ?? '').trim().isEmpty) {
        throw const FormatException('Captura método y hallazgos.');
      }
      if (data['replaces_id'] != null &&
          (data['correction_reason'] as String? ?? '').trim().isEmpty) {
        throw const FormatException('Indica el motivo de corrección.');
      }
      final payload = jsonEncode(data);
      if (lastPayload.isNotEmpty && payload != lastPayload) {
        operation = newOperationId();
      }
      lastPayload = payload;
      await widget.repository.recordDeath(widget.document.id, data, operation);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardó. Solo el MVZ responsable puede registrar después de la firma y sin fechas futuras.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Constatación posterior de muerte')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Paciente: ${widget.document.snapshot['patient']['name']}'),
        const Text(
          'Esta entrada se vincula al consentimiento firmado. No cambia sus acuerdos, firmas ni PDF y no cierra automáticamente la hospitalización.',
        ),
        Text(
          'Disposición acordada: ${widget.document.values['body_disposition']}\nCosto acordado: ${widget.document.values['cost']}',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        for (final r in records)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${r['result'] == 'confirmada' ? 'Muerte confirmada' : 'Muerte no confirmada'} · ${r['observed_at']}\nMétodo: ${r['method']}\nHallazgos: ${r['findings']}\nMVZ: ${r['recorded_by']} · Servidor: ${r['created_at']}\nDisposición realizada: ${r['body_disposition']} · Costo registrado: ${r['cost']}\n${r['notes']}\n${r['replaces_id'] == null ? '' : 'Corrige: ${r['replaces_id']} · ${r['correction_reason']}'}',
              ),
            ),
          ),
        if (responsible) ...[
          DropdownButtonFormField<String>(
            initialValue: 'no_confirmada',
            decoration: const InputDecoration(labelText: 'Resultado'),
            items: const [
              DropdownMenuItem(
                value: 'no_confirmada',
                child: Text('Muerte no confirmada'),
              ),
              DropdownMenuItem(
                value: 'confirmada',
                child: Text('Muerte confirmada'),
              ),
            ],
            onChanged: busy ? null : (v) => setState(() => data['result'] = v),
          ),
          if (records.isNotEmpty)
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Corrige una entrada (opcional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Nueva observación'),
                ),
                for (final r in records.where(
                  (r) => !records.any((x) => x['replaces_id'] == r['id']),
                ))
                  DropdownMenuItem(
                    value: r['id'] as String,
                    child: Text('${r['observed_at']} · ${r['id']}'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      if (v == null || v.isEmpty) {
                        data.remove('replaces_id');
                      } else {
                        data['replaces_id'] = v;
                      }
                    }),
            ),
          for (final e in {
            'observed_at': 'Fecha y hora observada (UTC)',
            'method': 'Método de constatación empleado',
            'findings': 'Hallazgos observados',
            'body_disposition':
                'Disposición efectivamente realizada (opcional)',
            'cost': 'Costo registrado (opcional)',
            'notes': 'Notas posteriores',
            'correction_reason': 'Motivo de corrección (si aplica)',
          }.entries)
            TextFormField(
              key: ValueKey(e.key),
              initialValue: data[e.key],
              enabled: !busy,
              maxLines: e.key == 'observed_at' ? 1 : null,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: e.value,
                helperText: e.key == 'observed_at'
                    ? 'AAAA-MM-DDTHH:MM:SSZ'
                    : null,
              ),
              onChanged: (v) => data[e.key] = v,
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Anexar registro del MVZ'),
          ),
        ] else
          const Text(
            'Consulta únicamente. El registro corresponde al MVZ responsable del consentimiento.',
          ),
      ],
    ),
  );
}
