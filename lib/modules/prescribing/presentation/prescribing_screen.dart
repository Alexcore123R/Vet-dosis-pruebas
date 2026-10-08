import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../forms/clinical/clinical_repository.dart';
import '../../forms/clinical/clinical_models.dart';
import '../../forms/domain/form_repository.dart';
import '../../forms/presentation/form_pdf_screen.dart';
import '../domain/prescribing_repository.dart';
import '../domain/prescribing_models.dart';
import 'prescribing_view_model.dart';
import 'rx_entry_screen.dart';

class PrescribingScreen extends StatefulWidget {
  const PrescribingScreen({
    super.key,
    required this.repository,
    required this.clinical,
    required this.forms,
    required this.member,
    this.patientId,
    this.initialCase,
    this.initialTask,
  });
  final PrescribingRepository repository;
  final ClinicalRepository clinical;
  final FormRepository forms;
  final ClinicMembership member;
  final String? patientId, initialCase, initialTask;
  @override
  State<PrescribingScreen> createState() => _PrescribingScreenState();
}

class _PrescribingScreenState extends State<PrescribingScreen> {
  late final model = PrescribingViewModel(
    widget.repository,
    widget.clinical,
    widget.member,
    widget.patientId,
  );
  String section = 'Perfil';
  @override
  void initState() {
    super.initState();
    model.load(selectedCase: widget.initialCase);
    if (widget.initialCase != null) section = 'Medicación';
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> entry(
    String title,
    List<RxField> fields,
    Future<void> Function(Map<String, dynamic>, String) submit, {
    Map<String, dynamic> initial = const {},
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          initial: initial,
          products: model.products,
          submit: submit,
        ),
      ),
    );
    if (mounted) await model.load();
  }

  Future<void> profile() async {
    final p = model.ownProfile;
    await entry(
      'Mi perfil y firma',
      [
        const RxField('name', 'Nombre completo', required: true),
        const RxField(
          'license',
          'Cédula capturada (no verificada automáticamente)',
        ),
        const RxField(
          'registration',
          'Autorización / registro profesional capturado',
        ),
        if (p?['has_signature'] == true)
          const RxField(
            'keep',
            'Conservar mi firma registrada si no dibujo una nueva',
            type: 'checkbox',
          ),
        const RxField(
          'signature',
          'Firma propia (opcional)',
          type: 'signature',
        ),
      ],
      (d, op) async {
        await widget.repository.write('rx_profile_save', {
          'p_clinic': widget.member.clinicId,
          'p_expected': p?['version'] ?? 0,
          'p_name': d['name'],
          'p_license': d['license'] ?? '',
          'p_registration': d['registration'] ?? '',
          'p_signature': (d['signature'] as List?)?.isNotEmpty == true
              ? d['signature']
              : d['keep'] == true
              ? {'keep': true}
              : null,
          'p_operation': op,
        });
      },
      initial: {
        'name': p?['name'] ?? '',
        'license': p?['license'] ?? '',
        'registration': p?['registration'] ?? '',
        'keep': p?['has_signature'] == true,
      },
    );
  }

  Future<void> delegate() async {
    try {
      final staff = await widget.forms.staff(widget.member.clinicId);
      if (!mounted) return;
      await entry(
        'Compartir datos / firma con un miembro',
        [
          RxField(
            'recipient',
            'Miembro receptor',
            type: 'select',
            required: true,
            options: {
              for (final p in staff.where(
                (p) => p['id'] != widget.member.userId,
              ))
                p['id']: p['label'],
            },
          ),
          RxField(
            'case',
            'Caso para permiso de receta ordinaria (obligatorio al delegar receta)',
            type: 'select',
            options: {
              '': 'Solo compartir datos / firma',
              for (final c in model.cases.where(
                (c) => c.responsibleId == widget.member.userId,
              ))
                c.id: '${c.patientName} · ${c.title}',
            },
          ),
          const RxField(
            'use_data',
            'Compartir nombre y cédula',
            type: 'checkbox',
          ),
          const RxField(
            'use_signature',
            'Permitir usar mi firma',
            type: 'checkbox',
          ),
          const RxField(
            'prepare_ordinary',
            'Permitir preparar receta ordinaria del caso',
            type: 'checkbox',
          ),
          const RxField(
            'issue_ordinary',
            'Permitir emitir receta ordinaria del caso',
            type: 'checkbox',
          ),
          const RxField(
            'dispense_ordinary',
            'Permiso de dispensación ordinaria (para punto de venta)',
            type: 'checkbox',
          ),
          const RxField(
            'until',
            'Vigente hasta (UTC)',
            type: 'instant',
            required: true,
          ),
        ],
        (d, op) async {
          await widget.repository.write('rx_delegate', {
            'p_profile': model.ownProfile!['id'],
            'p_recipient': d['recipient'],
            'p_case': (d['case'] as String? ?? '').isEmpty ? null : d['case'],
            'p_permissions': {
              for (final key in [
                'use_data',
                'use_signature',
                'prepare_ordinary',
                'issue_ordinary',
                'dispense_ordinary',
              ])
                key: d[key] == true,
            },
            'p_until': d['until'],
            'p_operation': op,
          });
        },
        initial: {
          'case': '',
          'until': DateTime.now()
              .toUtc()
              .add(const Duration(days: 7))
              .toIso8601String(),
        },
      );
    } catch (e) {
      message(rxError(e));
    }
  }

  Future<void> revoke(Map<String, dynamic> grant) async => entry(
    'Revocar permiso',
    [const RxField('reason', 'Motivo', required: true)],
    (d, op) async {
      await widget.repository.write('rx_delegate_revoke', {
        'p_id': grant['id'],
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> schedule(Map<String, dynamic> r) async {
    try {
      final info = Map<String, dynamic>.from(
        await widget.repository.read('rx_hospital', {'p_case': r['case_id']}),
      );
      final detail = Map<String, dynamic>.from(
        await widget.repository.read('rx_snapshot', {'p_id': r['id']}),
      );
      if (!mounted) return;
      await entry(
        'Programar administración en hospitalización',
        [
          RxField(
            'stay',
            'Estancia activa',
            type: 'select',
            required: true,
            options: {
              for (final st in info['stays']) st['id']: 'Jaula ${st['cage']}',
            },
          ),
          RxField(
            'item',
            'Indicación de la receta emitida',
            type: 'select',
            required: true,
            options: {
              for (final it in detail['items'])
                it['id']:
                    '${it['product_name']} · ${it['quantity']} ${it['unit']}',
            },
          ),
          const RxField(
            'times',
            'Horas explícitas UTC: una por línea (no se infiere el intervalo)',
            required: true,
          ),
        ],
        (d, op) async {
          final times = (d['times'] as String)
              .split(RegExp(r'[\n,]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          for (final t in times) {
            clinicalInstant(t);
          }
          await widget.repository.write('rx_schedule', {
            'p_id': r['id'],
            'p_item': d['item'],
            'p_stay': d['stay'],
            'p_times': times,
            'p_operation': op,
          });
        },
      );
    } catch (e) {
      message(rxError(e));
    }
  }

  Future<void> createRx() async {
    if (model.caseId == null) return;
    await entry(
      'Nueva receta · indicaciones manuales',
      [
        const RxField(
          'items',
          'Productos y presentaciones',
          type: 'items',
          required: true,
        ),
        const RxField(
          'folio',
          'Folio oficial propio, si aplica (captura manual)',
        ),
        const RxField('instructions', 'Indicaciones adicionales'),
      ],
      (d, op) async {
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        for (final i in items) {
          i['quantity'] = exactMedicationQuantity(i['quantity'] ?? '');
        }
        await widget.repository.write('rx_create', {
          'p_case': model.caseId,
          'p_items': items,
          'p_folio': d['folio'] ?? '',
          'p_instructions': d['instructions'] ?? '',
          'p_operation': op,
        });
      },
      initial: {
        'items': [<String, dynamic>{}],
      },
    );
  }

  Future<void> openRx(Map<String, dynamic> r) async {
    try {
      if (r['state'] == 'draft') {
        final detail = Map<String, dynamic>.from(
          await widget.repository.read('rx_snapshot', {'p_id': r['id']}),
        );
        if (!mounted) return;
        await entry(
          'Editar borrador',
          [
            const RxField(
              'items',
              'Indicaciones',
              type: 'items',
              required: true,
            ),
            const RxField('folio', 'Folio oficial capturado'),
            const RxField('instructions', 'Indicaciones adicionales'),
          ],
          (d, op) async {
            final items = (d['items'] as List).cast<Map<String, dynamic>>();
            for (final i in items) {
              i['quantity'] = exactMedicationQuantity(i['quantity'] ?? '');
            }
            await widget.repository.write('rx_save', {
              'p_id': r['id'],
              'p_revision': r['revision'],
              'p_items': items,
              'p_folio': d['folio'] ?? '',
              'p_instructions': d['instructions'] ?? '',
            });
          },
          initial: {
            'items': [
              for (final i in detail['items'])
                {
                  'product_version_id': i['product_version_id'],
                  'quantity': i['quantity'],
                  'unit': i['unit'],
                  'route': i['route'],
                  'interval': i['interval_text'],
                  'duration': i['duration_text'],
                  'care': i['care'],
                },
            ],
            'folio': r['official_folio'],
            'instructions': r['instructions'],
          },
        );
      } else {
        await review('prescription', r);
      }
    } catch (e) {
      message(rxError(e));
    }
  }

  Future<void> prepare(Map<String, dynamic> r) async {
    await entry(
      'Datos profesionales y firma para esta receta',
      [
        RxField(
          'profile',
          'Perfil titular de los datos',
          type: 'select',
          required: true,
          options: {
            for (final p in model.profiles)
              p['id']: '${p['name']} · cédula ${p['license']}',
          },
        ),
        const RxField(
          'shared',
          'Usar firma del titular solo con permiso vigente',
          type: 'checkbox',
        ),
        const RxField(
          'signature',
          'Mi firma propia para este documento (opcional si ya está registrada)',
          type: 'signature',
        ),
      ],
      (d, op) async {
        await widget.repository.write('rx_prepare', {
          'p_id': r['id'],
          'p_revision': r['revision'],
          'p_profile': d['profile'],
          'p_shared_signature': d['shared'] == true,
          'p_signature': d['signature'],
        });
      },
      initial: {'profile': model.ownProfile?['id'], 'shared': false},
    );
  }

  Future<void> review(String kind, Map<String, dynamic> record) async {
    try {
      final pdf = await widget.repository.pdf(kind, record['id']);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: kind == 'report' ? 'Reporte del periodo' : 'Receta médica',
            signed: record['state'] == 'issued',
            confirmLabel:
                'Revisé el PDF completo y confirmo sus datos, la firma utilizada y mi responsabilidad al emitirlo.',
            confirm: record['state'] == 'issued'
                ? null
                : () async {
                    await widget.repository.write(
                      kind == 'report' ? 'rx_report_finalize' : 'rx_finalize',
                      {
                        'p_id': record['id'],
                        'p_hash': pdf.hash,
                        if (kind == 'prescription')
                          'p_revision': record['revision'],
                      },
                    );
                  },
          ),
        ),
      );
      if (mounted) await model.load();
    } catch (e) {
      message(rxError(e));
    }
  }

  Future<void> medication({Map<String, dynamic>? correction}) async {
    if (model.caseId == null) return;
    try {
      final staff = await widget.forms.staff(widget.member.clinicId);
      final hospital = Map<String, dynamic>.from(
        await widget.repository.read('rx_hospital', {'p_case': model.caseId}),
      );
      if (!mounted) return;
      await entry(
        correction == null
            ? 'Reportar aplicación realizada'
            : 'Anexar corrección (no devolución física)',
        [
          RxField(
            'product',
            'Producto y presentación',
            type: 'select',
            required: true,
            options: {
              for (final p in model.products)
                p['id']: '${p['name']} · ${p['presentation']}',
            },
          ),
          const RxField(
            'quantity',
            'Cantidad realmente utilizada',
            type: 'quantity',
            required: true,
          ),
          const RxField('route', 'Vía aplicada', required: true),
          RxField(
            'procedure',
            'Procedimiento / etapa',
            type: 'select',
            required: true,
            options: Map<String, String>.from(clinicalScopes)
              ..remove('observaciones'),
          ),
          RxField(
            'performer',
            'Quién aplicó',
            type: 'select',
            required: true,
            options: {
              for (final p in staff.where(
                (p) =>
                    widget.member.role != ClinicRole.auxiliar ||
                    p['id'] == widget.member.userId,
              ))
                p['id']: p['label'],
            },
          ),
          const RxField(
            'observed',
            'Fecha y hora de aplicación observada (UTC)',
            type: 'instant',
            required: true,
          ),
          RxField(
            'vial',
            'Frasco usado (opcional)',
            type: 'select',
            options: {
              '': 'Sin frasco vinculado',
              for (final v in model.vials)
                v['id']:
                    '${v['product_name']} · lote ${v['lot']} · saldo ${v['balance']} ml${v['closed'] == true ? ' · cerrado' : ''}',
            },
          ),
          const RxField('lot', 'Lote exacto (si no se vincula un frasco)'),
          if (correction == null) ...[
            RxField(
              'prescription',
              'Receta emitida vinculada (opcional)',
              type: 'select',
              options: {
                '': 'Sin receta vinculada',
                for (final r in model.prescriptions.where(
                  (r) => r['case_id'] == model.caseId && r['state'] == 'issued',
                ))
                  r['id']: '${r['patient_name']} · ${r['id']}',
              },
            ),
            RxField(
              'task',
              'Tarea hospitalaria (se confirma con este registro)',
              type: 'select',
              options: {
                '': 'Sin tarea vinculada',
                for (final t in hospital['tasks'])
                  t['id']: '${t['label']} · ${t['due_at']}',
              },
            ),
          ],
          if (correction != null)
            const RxField('reason', 'Motivo de corrección', required: true),
        ],
        (d, op) async {
          final product = model.products.firstWhere(
            (p) => p['id'] == d['product'],
          );
          await widget.repository.write('rx_medication_report', {
            'p_case': model.caseId,
            'p_data': {
              'product_version_id': d['product'],
              'quantity': d['quantity'],
              'unit': product['unit'],
              'route': d['route'],
              'procedure': d['procedure'],
              'performed_by': d['performer'],
              'observed_at': d['observed'],
              'vial_id': d['vial'] ?? '',
              'lot': d['lot'] ?? '',
              'prescription_id': d['prescription'] ?? '',
              'hospital_task_id': d['task'] ?? '',
              if (correction != null) 'replaces_id': correction['id'],
              if (correction != null) 'correction_reason': d['reason'],
            },
            'p_operation': op,
          });
        },
        initial: {
          'product': correction?['product_version_id'],
          'quantity': correction?['quantity'],
          'route': correction?['route'],
          'procedure': correction?['procedure'] ?? 'cuidados',
          'performer': correction?['performed_by'] ?? widget.member.userId,
          'vial': correction?['vial_id'] ?? '',
          'prescription': '',
          'task': correction == null ? widget.initialTask ?? '' : '',
          'lot': correction?['lot'] ?? '',
          'observed': correction == null
              ? DateTime.now().toUtc().toIso8601String()
              : DateTime.parse(
                  correction['observed_at'],
                ).toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      message(rxError(e));
    }
  }

  Future<void> validate(Map<String, dynamic> r) async => entry(
    'Revisión del MVZ responsable',
    [
      const RxField(
        'decision',
        'Decisión',
        type: 'select',
        required: true,
        options: {
          'validada': 'Validar este contenido exacto',
          'requiere_correccion': 'Solicitar corrección',
        },
      ),
      const RxField(
        'reason',
        'Motivo / observaciones de revisión',
        required: true,
      ),
    ],
    (d, op) async {
      await widget.repository.write('rx_medication_review', {
        'p_id': r['id'],
        'p_hash': r['content_hash'],
        'p_decision': d['decision'],
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> vial() async => entry(
    'Abrir frasco',
    [
      RxField(
        'product',
        'Producto volumétrico',
        type: 'select',
        required: true,
        options: {
          for (final p in model.products.where((p) => p['unit'] == 'ml'))
            p['id']: '${p['name']} · ${p['presentation']}',
        },
      ),
      const RxField('lot', 'Lote', required: true),
      const RxField(
        'volume',
        'Volumen inicial exacto (ml)',
        type: 'quantity',
        required: true,
      ),
      const RxField(
        'opened',
        'Fecha y hora de apertura (UTC)',
        type: 'instant',
        required: true,
      ),
    ],
    (d, op) async {
      await widget.repository.write('rx_vial_open', {
        'p_clinic': widget.member.clinicId,
        'p_product': d['product'],
        'p_lot': d['lot'],
        'p_volume': d['volume'],
        'p_opened': d['opened'],
        'p_inventory': null,
        'p_inventory_lot': null,
        'p_operation': op,
      });
    },
    initial: {'opened': DateTime.now().toUtc().toIso8601String()},
  );
  Future<void> adjustVial(Map<String, dynamic> v) async => entry(
    'Anexar movimiento físico / contable del frasco',
    [
      const RxField(
        'kind',
        'Tipo',
        type: 'select',
        required: true,
        options: {
          'merma': 'Merma real (delta negativo)',
          'devolucion': 'Devolución físicamente verificada (delta positivo)',
          'ajuste': 'Ajuste contable justificado',
        },
      ),
      const RxField(
        'delta',
        'Cambio exacto en ml, con signo si resta',
        required: true,
      ),
      const RxField(
        'reason',
        'Motivo y evidencia del movimiento',
        required: true,
      ),
    ],
    (d, op) async {
      await widget.repository.write('rx_vial_adjust', {
        'p_id': v['id'],
        'p_kind': d['kind'],
        'p_delta': d['delta'],
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> closeVial(Map<String, dynamic> v) async => entry(
    'Conciliar y cerrar frasco',
    [
      const RxField(
        'measured',
        'Saldo físico medido (ml), puede ser cero',
        required: true,
      ),
      const RxField('reason', 'Nota del MVZ (obligatoria si hay discrepancia)'),
    ],
    (d, op) async {
      await widget.repository.write('rx_vial_close', {
        'p_id': v['id'],
        'p_measured': d['measured'],
        'p_reason': d['reason'] ?? '',
        'p_operation': op,
      });
    },
  );
  Future<void> report() async => entry(
    'Corte del registro de control',
    [
      const RxField(
        'start',
        'Inicio inclusivo (UTC)',
        type: 'instant',
        required: true,
      ),
      const RxField(
        'end',
        'Fin excluyente (UTC)',
        type: 'instant',
        required: true,
      ),
      const RxField(
        'official',
        'Solicitar formato oficial (requiere fuente verificada)',
        type: 'checkbox',
      ),
    ],
    (d, op) async {
      await widget.repository.write('rx_report_create', {
        'p_clinic': widget.member.clinicId,
        'p_start': d['start'],
        'p_end': d['end'],
        'p_official': d['official'] == true,
        'p_operation': op,
      });
    },
  );
  Future<void> csv(Map<String, dynamic> r) async {
    try {
      await FilePicker.saveFile(
        fileName: 'VetDosis-control-${r['id']}.csv',
        bytes: Uint8List.fromList(utf8.encode(reportCsv(r))),
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
    } catch (_) {
      message('No se pudo exportar el CSV.');
    }
  }

  Future<void> whatsapp(Map<String, dynamic> r) async => entry(
    'Preparar mensaje para WhatsApp',
    [
      const RxField(
        'phone',
        'Teléfono del propietario con código de país',
        required: true,
      ),
    ],
    (d, op) async {
      final phone = (d['phone'] as String).replaceAll(RegExp(r'[\s()+-]'), '');
      if (!RegExp(r'^\d{8,15}$').hasMatch(phone)) {
        throw const FormatException('Usa un teléfono internacional válido.');
      }
      final detail = Map<String, dynamic>.from(
        await widget.repository.read('rx_snapshot', {'p_id': r['id']}),
      );
      if (detail['state'] != 'issued') {
        throw const FormatException('La receta debe estar emitida.');
      }
      final rows = detail['items'] as List;
      final text =
          '${widget.member.clinicName} · Indicaciones para ${r['patient_name']}\n${rows.map((i) => '${i['product_name']} (${i['presentation']}): ${i['quantity']} ${i['unit']}, ${i['route']}, ${i['interval_text']}, ${i['duration_text']}. ${i['care']}').join('\n')}\n${detail['instructions']}\nConsulta a tu clínica ante dudas.';
      if (!await launchUrl(
        Uri.https('wa.me', '/$phone', {'text': text}),
        mode: LaunchMode.externalApplication,
      )) {
        throw const FormatException('No se pudo abrir WhatsApp.');
      }
    },
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recetas y control de medicamentos',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Aplicar, reportar, validar y emitir son actos separados. Pasante usa el rol auxiliar. Ningún permiso de firma autoriza controlados a auxiliares.',
        ),
        OutlinedButton.icon(
          onPressed: model.busy ? null : () => model.load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
        DropdownButtonFormField<String>(
          initialValue: section,
          decoration: const InputDecoration(labelText: 'Apartado'),
          items: [
            for (final s in [
              'Perfil',
              'Recetas',
              'Medicación',
              'Frascos',
              'Reportes',
            ])
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: model.busy ? null : (v) => setState(() => section = v!),
        ),
        if (model.busy) const LinearProgressIndicator(),
        if (model.error != null) Text(model.error!),
        if (['Recetas', 'Medicación'].contains(section))
          DropdownButtonFormField<String>(
            key: ValueKey('case-${model.caseId}-${model.cases.length}'),
            initialValue: model.caseId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Caso del paciente'),
            items: [
              for (final c in model.cases)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    '${c.patientName} · ${c.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: model.busy ? null : (id) => model.load(selectedCase: id),
          ),
        if (section == 'Perfil') ...[
          Text(
            model.ownProfile == null
                ? 'Perfil pendiente'
                : '${model.ownProfile!['name']} · cédula ${model.ownProfile!['license']} · versión ${model.ownProfile!['version']}',
          ),
          Text(
            model.professional
                ? 'Habilitación profesional vigente en servidor'
                : 'Habilitación profesional pendiente o no vigente. Capturar una cédula no la concede.',
          ),
          FilledButton(
            onPressed: model.busy ? null : profile,
            child: const Text('Editar mis datos / firma en nueva versión'),
          ),
          if (model.professional)
            OutlinedButton(
              onPressed: model.busy ? null : delegate,
              child: const Text('Compartir datos, firma o permisos ordinarios'),
            ),
          for (final d in model.delegations)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receptor: ${d['recipient_id']}\nDatos: ${d['use_data']} · Firma: ${d['use_signature']}\nPreparar ordinaria: ${d['prepare_ordinary']} · Emitir ordinaria: ${d['issue_ordinary']}\nVigencia: ${d['valid_until']} · ${d['revoked'] == true ? 'Revocado' : 'Sin revocación registrada'}',
                    ),
                    if (d['created_by'] == widget.member.userId &&
                        d['revoked'] != true)
                      TextButton(
                        onPressed: model.busy ? null : () => revoke(d),
                        child: const Text('Revocar permiso'),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (section == 'Recetas') ...[
          if (model.products.isEmpty)
            const Text(
              'No hay productos con clasificación publicada. Se pueden completar perfiles; faltan los datos de productos para preparar recetas.',
            ),
          FilledButton(
            onPressed:
                model.busy || model.caseId == null || model.products.isEmpty
                ? null
                : createRx,
            child: const Text('Nueva receta del caso'),
          ),
          for (final r in model.prescriptions.where(
            (r) => model.caseId == null || r['case_id'] == model.caseId,
          ))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['patient_name']} · ${r['controlled'] == true ? 'Restringida' : 'Ordinaria'} · ${rxState(r['state'])}',
                    ),
                    Text(
                      'Folio capturado: ${r['official_folio'] == '' ? 'pendiente / no aplica' : r['official_folio']}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: model.busy ? null : () => openRx(r),
                          child: Text(
                            r['state'] == 'draft'
                                ? 'Editar borrador'
                                : 'Ver PDF / confirmar',
                          ),
                        ),
                        if (r['state'] == 'draft')
                          TextButton(
                            onPressed: model.busy ? null : () => prepare(r),
                            child: const Text(
                              'Preparar PDF con identidad y firma',
                            ),
                          ),
                        if (r['state'] == 'issued' &&
                            r['responsible_id'] == widget.member.userId &&
                            model.professional)
                          TextButton(
                            onPressed: model.busy ? null : () => schedule(r),
                            child: const Text('Programar en hospitalización'),
                          ),
                        if (r['state'] == 'issued')
                          TextButton(
                            onPressed: model.busy ? null : () => whatsapp(r),
                            child: const Text(
                              'Abrir WhatsApp con indicaciones',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (section == 'Medicación') ...[
          FilledButton(
            onPressed:
                model.busy || model.caseId == null || model.products.isEmpty
                ? null
                : () => medication(),
            child: const Text('Reportar aplicación realizada'),
          ),
          for (final r in model.medications)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['product_name']} · ${r['quantity']} ${r['unit']} · lote ${r['lot']}',
                    ),
                    Text(
                      '${medicationState(r)}\nAplicó: ${r['performed_by']} · Reportó: ${r['reported_by']}\nObservada: ${r['observed_at']} · Servidor: ${r['reported_at']}',
                    ),
                    if (r['review'] != null)
                      Text(
                        'Validó: ${r['review']['validated_by']} · ${r['review']['validated_at']}',
                      ),
                    Text(
                      'Dosis calculada como referencia: ${r['dose_reference'] ?? 'no disponible'}',
                    ),
                    if (r['incidence'] != '') Text(r['incidence']),
                    if (r['replaces_id'] != null)
                      Text(
                        'Corrige: ${r['replaces_id']} · ${r['correction_reason']}',
                      ),
                    if (model.responsible && r['superseded'] != true)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: model.busy ? null : () => validate(r),
                            child: const Text('Validar / solicitar corrección'),
                          ),
                          TextButton(
                            onPressed: model.busy
                                ? null
                                : () => medication(correction: r),
                            child: const Text('Anexar corrección'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (section == 'Frascos') ...[
          if (model.professional)
            FilledButton(
              onPressed: model.busy || model.products.isEmpty ? null : vial,
              child: const Text('Abrir frasco'),
            ),
          for (final v in model.vials)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v['product_name']} · lote ${v['lot']}\nSaldo exacto registrado: ${v['balance']} ml · ${v['closed'] == true ? 'Cerrado' : 'Abierto'}',
                    ),
                    for (final m in v['movements'] as List? ?? [])
                      Text(
                        '${m['kind']} · ${m['delta']} ml · ${m['created_at']}\n${m['reason']}',
                      ),
                    if (v['closure'] != null)
                      Text(
                        'Diferencia conservada al cierre: ${v['closure']['difference']} ml\nNota: ${v['closure']['reason']}',
                      ),
                    if (v['closed'] != true &&
                        v['responsible_id'] == widget.member.userId &&
                        model.professional)
                      TextButton(
                        onPressed: model.busy ? null : () => adjustVial(v),
                        child: const Text('Anexar merma / devolución / ajuste'),
                      ),
                    if (v['closed'] != true &&
                        v['responsible_id'] == widget.member.userId &&
                        model.professional)
                      TextButton(
                        onPressed: model.busy ? null : () => closeVial(v),
                        child: const Text('Conciliar y cerrar'),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (section == 'Reportes') ...[
          if (model.professional)
            FilledButton(
              onPressed: model.busy ? null : report,
              child: const Text('Crear corte del periodo'),
            ),
          const Text(
            'Los reportes incluyen solo aplicaciones validadas y conservan los pendientes al corte. Una validación posterior no cambia el archivo emitido.',
          ),
          for (final r in model.reports)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['official'] == true ? 'Formato verificado' : 'Referencia · NO OFICIAL'} · ${r['complete'] == true ? 'Completo al corte' : 'INCOMPLETO'}\n${r['starts_at']} — ${r['ends_at']}\nPendientes: ${(r['pending_ids'] as List).length}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: model.busy
                              ? null
                              : () => review('report', r),
                          child: const Text('Ver PDF / confirmar'),
                        ),
                        if (r['state'] == 'issued')
                          TextButton(
                            onPressed: model.busy ? null : () => csv(r),
                            child: const Text('Exportar CSV para Excel'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

String rxState(String s) => switch (s) {
  'draft' => 'Borrador',
  'awaiting_review' => 'Pendiente de generar PDF',
  'ready' => 'PDF pendiente de confirmación',
  'issued' => 'Emitida',
  _ => 'Estado desconocido',
};
