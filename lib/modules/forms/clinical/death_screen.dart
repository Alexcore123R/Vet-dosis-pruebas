import 'dart:convert';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/form_models.dart';
import 'clinical_models.dart';
import '../../patients/presentation/signature_pad.dart';
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
  final data = <String, dynamic>{};
  List<Map<String, dynamic>> procedures = [];
  bool responsible = false;
  int generation = 0;
  String operation = newOperationId(), lastPayload = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant DeathScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.id != widget.document.id ||
        oldWidget.member.userId != widget.member.userId ||
        oldWidget.member.clinicId != widget.member.clinicId ||
        oldWidget.repository != widget.repository) {
      data.clear();
      records = [];
      procedures = [];
      responsible = false;
      busy = true;
      error = null;
      operation = newOperationId();
      lastPayload = '';
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    try {
      if (widget.repository is! DeathPermissionRepository) {
        throw const FormatException('Contrato requerido');
      }
      final w = await (widget.repository as DeathPermissionRepository)
          .deathWorkspace(widget.document.id);
      if (!mounted || request != generation) return;
      if (w['version'] != 1 ||
          w['consent_id'] != widget.document.id ||
          w['can_record'] is! bool ||
          w['procedures'] is! List ||
          w['records'] is! List) {
        throw const FormatException('Contrato desconocido');
      }
      final ps = (w['procedures'] as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (ps.any((p) => p['id'] is! String || p['name'] is! String)) {
        throw const FormatException('Procedimientos inválidos');
      }
      if (mounted) {
        setState(() {
          records = (w['records'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          procedures = ps;
          responsible = w['can_record'] == true && ps.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          records = [];
          responsible = false;
          procedures = [];
          error = 'No se pudo consultar. Revisa acceso y conexión.';
        });
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || !responsible) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!['confirmada', 'no_confirmada'].contains(data['result']) ||
          data['procedure_id'] == null ||
          data['confirmed'] != true ||
          (data['signer_name'] as String? ?? '').trim().isEmpty ||
          data['signature'] == null) {
        throw const FormatException(
          'Selecciona resultado y procedimiento; indica tu nombre, firma y confirma la constatación propia.',
        );
      }
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
      key: ValueKey(
        '${widget.member.clinicId}/${widget.member.userId}/${widget.document.id}',
      ),
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
                '${r['result'] == 'confirmada' ? 'Muerte confirmada' : 'Muerte no confirmada'} · ${r['observed_at']}\nMétodo: ${r['method']}\nHallazgos: ${r['findings']}\nConstató: ${r['signer_name'] ?? r['recorded_by']} · Servidor: ${r['created_at']}\nDisposición realizada: ${r['body_disposition']} · Costo registrado: ${r['cost']}\n${r['notes']}\n${r['replaces_id'] == null ? '' : 'Corrige: ${r['replaces_id']} · ${r['correction_reason']}'}',
              ),
            ),
          ),
        if (responsible) ...[
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Tipo de procedimiento',
            ),
            items: procedures
                .map(
                  (p) => DropdownMenuItem(
                    value: p['id'] as String,
                    child: Text(p['name'] as String),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => data['procedure_id'] = v,
          ),
          DropdownButtonFormField<String>(
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
            'signer_name': 'Nombre de quien constató',
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
          IgnorePointer(
            ignoring: busy,
            child: SignaturePad(
              label: 'Firma propia de quien constató',
              onChanged: (v) => data['signature'] = v,
            ),
          ),
          CheckboxListTile(
            value: data['confirmed'] == true,
            title: const Text(
              'Confirmo que realicé esta constatación y que la firma es mía',
            ),
            onChanged: busy
                ? null
                : (v) => setState(() => data['confirmed'] = v),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Anexar registro del MVZ'),
          ),
        ] else
          const Text(
            'Consulta únicamente. El registro requiere al MVZ responsable habilitado y permisos vigentes para el procedimiento.',
          ),
      ],
    ),
  );
}
