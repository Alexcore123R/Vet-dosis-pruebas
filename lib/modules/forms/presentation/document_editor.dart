import '../../core/presentation/unsaved_form_scope.dart';
import '../../prescribing/domain/prescribing_repository.dart';
import 'dart:convert';
import '../clinical/clinical_models.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/domain/patient_models.dart';
import '../../patients/presentation/signature_pad.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/form_models.dart';
import '../domain/form_repository.dart';
import 'form_pdf_screen.dart';
import 'form_view_model.dart';

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.repository,
    required this.member,
    this.template,
    this.document,
    this.patients = const [],
    this.initialBranding = const {},
    this.professionalAdmin = false,
    this.prescribing,
    this.draftOnly = false,
    this.deferAuthorship = false,
    this.fieldChoices = const {},
    this.draftResponsibles = const [],
  });
  final bool draftOnly, deferAuthorship;
  final Map<String, dynamic> fieldChoices;
  final List<Map<String, dynamic>> draftResponsibles;
  final FormRepository repository;
  final bool professionalAdmin;
  final PrescribingRepository? prescribing;
  final ClinicMembership member;
  final FormTemplateVersion? template;
  final FormDocument? document;
  final List<VetPatient> patients;
  final Map<String, dynamic> initialBranding;
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  final exit = FormExitController();
  bool signatureDirty = false;
  @override
  void dispose() {
    exit.dispose();
    super.dispose();
  }

  late Map<String, dynamic> schema, values, branding;
  FormDocument? document;
  final reviewSession = PdfReviewSession();
  String? patientId, error;
  bool busy = false, dirty = false;
  List<Map<String, dynamic>> staff = [];
  List<FormDocument> consents = [];
  List<Map<String, dynamic>> professionalProfiles = [];
  String? selectedProfile, draftResponsible;
  String authorName = '';
  bool authorshipConfirmed = false;
  String authorshipOperation = newOperationId();
  String? authorshipFingerprint;
  bool shareProfileSignature = false;
  int professionalGeneration = 0;
  bool get clinical => clinicalTypes.contains(schema['type']);
  int signatureGeneration = 0;
  List<List<double>?> tutor = [], mvz = [];
  String operation = newOperationId();
  String? operationFingerprint;
  bool get responsible =>
      (widget.member.role == ClinicRole.mvz ||
          (widget.member.role == ClinicRole.admin &&
              widget.professionalAdmin)) &&
      (document == null || document!.responsibleId == widget.member.userId);
  @override
  void initState() {
    super.initState();
    document = widget.document;
    schema = Map<String, dynamic>.from(
      document?.snapshot['schema'] ?? widget.template!.schema,
    );
    values = jsonDecode(jsonEncode(document?.values ?? {}));
    branding = Map<String, dynamic>.from(
      document?.branding ??
          {
            'header': widget.member.clinicName,
            'include_logo': false,
            ...widget.initialBranding,
          },
    );
    draftResponsible = document?.responsibleId;
    if (clinical && !widget.draftOnly) loadClinicalChoices();
    if (widget.prescribing != null && !widget.draftOnly) loadProfiles();
  }

  Future<void> loadClinicalChoices() async {
    try {
      final people = await widget.repository.staff(widget.member.clinicId);
      final docs = await widget.repository.documents(widget.member.clinicId);
      if (mounted) {
        setState(() {
          staff = people;
          consents = docs
              .where(
                (d) => d.signed && d.snapshot['schema']['type'] == 'surgery',
              )
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudieron cargar los responsables. Actualiza antes de confirmar.',
        );
      }
    }
  }

  Future<void> loadProfiles() async {
    try {
      final rows = await widget.prescribing!.read('rx_profiles', {
        'p_clinic': widget.member.clinicId,
      });
      if (mounted) {
        setState(
          () => professionalProfiles = (rows as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => professionalProfiles = []);
    }
  }

  Future<void> bindProfile() async {
    if (selectedProfile == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await saveDraft();
      document = await widget.repository.useProfile(
        document!.id,
        document!.revision,
        selectedProfile!,
        shareProfileSignature,
      );
      if (mounted) {
        setState(() {
          values = Map<String, dynamic>.from(document!.values);
          dirty = false;
          reviewSession.invalidate();
          tutor = [];
          mvz = [];
          signatureGeneration++;
          professionalGeneration++;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se vincularon los datos/firma. Revisa habilitación, permiso y versión vigente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void changed() {
    setState(() {
      dirty = true;
      reviewSession.invalidate();
      tutor = [];
      mvz = [];
      signatureGeneration++;
    });
  }

  Future<void> logo() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (!mounted || result.isEmpty) return;
      final file = result.single.xFile;
      if (await file.length() > 250000) {
        if (mounted) {
          setState(() => error = 'El logo debe ser PNG/JPG de hasta 250 KB.');
        }
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 250000) {
        setState(() => error = 'El logo debe ser PNG/JPG de hasta 250 KB.');
        return;
      }
      branding['logo'] = base64Encode(bytes);
      branding['include_logo'] = true;
      changed();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo leer el logo. Usa PNG/JPG de hasta 250 KB.',
        );
      }
    }
  }

  Future<void> saveDraft() async {
    validateValues(schema, values);
    if (document == null) {
      if (patientId == null) {
        throw const FormatException('Selecciona paciente.');
      }
      final fingerprint = jsonEncode([
        patientId,
        values,
        branding,
        if (widget.draftOnly) draftResponsible,
      ]);
      if (operationFingerprint != null && operationFingerprint != fingerprint) {
        operation = newOperationId();
      }
      operationFingerprint = fingerprint;
      if (widget.draftOnly) {
        if (draftResponsible == null) {
          throw const FormatException(
            'Elige explícitamente al MVZ responsable.',
          );
        }
        document = await (widget.repository as FormDraftRepository)
            .createAttributedDraft(
              widget.member.clinicId,
              patientId!,
              widget.template!.id,
              draftResponsible!,
              values,
              branding,
              operation,
            );
        values = Map<String, dynamic>.from(document!.values);
        professionalGeneration++;
      } else {
        document = await widget.repository.createDocument(
          widget.member.clinicId,
          patientId!,
          widget.template!.id,
          values,
          branding,
          operation,
        );
      }
    } else if (dirty) {
      document = await widget.repository.saveDocument(
        document!.id,
        document!.revision,
        values,
        branding,
      );
    }
    dirty = false;
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await saveDraft();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se guardó el borrador. Actualiza antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signAuthorship() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!authorshipConfirmed || authorName.trim().isEmpty || mvz.isEmpty) {
        throw const FormatException(
          'Escribe tu nombre, dibuja tu firma y confirma la elaboración.',
        );
      }
      final signature = List<List<double>?>.from(mvz);
      await saveDraft();
      final fingerprint = jsonEncode([
        document!.id,
        document!.revision,
        authorName.trim(),
        signature,
      ]);
      if (authorshipFingerprint != null &&
          authorshipFingerprint != fingerprint) {
        authorshipOperation = newOperationId();
      }
      authorshipFingerprint = fingerprint;
      await (widget.repository as FormDraftRepository).signAuthorship(
        document!.id,
        document!.revision,
        authorName.trim(),
        signature,
        true,
        authorshipOperation,
      );
      if (mounted) exit.close(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se registró la firma. Revisa el permiso y la versión actual del borrador.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      validateValues(schema, values, complete: true);
      await saveDraft();
      if (document!.state == 'draft') {
        document = await widget.repository.prepare(
          document!.id,
          document!.revision,
          tutor,
          mvz,
        );
      }
      signatureDirty = false;
      final id = document!.id, revision = document!.revision;
      reviewSession.setDocument(document!);
      final pdf = await widget.repository.pdf(id);
      reviewSession.setPdf(pdf);
      if (!mounted) return;
      final signed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FormPdfScreen(
            pdf: pdf,
            title: clinical
                ? 'Revisión del MVZ responsable'
                : 'Revisión del tutor y del MVZ',
            confirmLabel: clinical
                ? 'El MVZ responsable revisó este PDF completo y confirma sus datos clínicos y su firma.'
                : 'El tutor y el MVZ revisaron este PDF completo y confirman el contenido y sus firmas.',
            confirm: () async {
              reviewSession.accepted = true;
              if (!reviewSession.canFinalize) {
                throw StateError('Revisión invalidada.');
              }
              document = await widget.repository.finalize(
                id,
                revision,
                pdf.hash,
              );
            },
          ),
        ),
      );
      if (mounted) {
        if (signed == true) {
          exit.close(context, true);
        } else {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'No se preparó/confirmó el PDF. Puede faltar una firma o existir un cambio de versión. Actualiza el documento.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> assign() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await saveDraft();
      final ids = await widget.repository.auxiliaries(widget.member.clinicId);
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Asignar borrador a auxiliar'),
          children: [
            for (final id in ids)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, id),
                child: Text('Auxiliar · $id'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Retirar asignación'),
            ),
            if (ids.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay auxiliares en esta clínica.'),
              ),
          ],
        ),
      );
      if (selected != null) {
        await widget.repository.assign(
          document!.id,
          selected.isEmpty ? null : selected,
        );
        if (mounted) exit.close(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo asignar. Actualiza el documento.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(Map f) {
    final id = f['id'] as String, type = f['type'];
    if (type == 'signature') return const SizedBox.shrink();
    if (type == 'binding') {
      final patientData = document?.snapshot['patient'] as Map? ?? const {};
      final ownerData = document?.snapshot['owner'] as Map? ?? const {};
      final linkedValue = document == null
          ? 'Se vincula al crear el borrador.'
          : id == 'patient'
          ? [
              patientData['name'],
              patientData['species'],
              if ('${patientData['breed'] ?? ''}'.isNotEmpty)
                'Raza: ${patientData['breed']}',
              if ('${patientData['sex'] ?? ''}'.isNotEmpty)
                'Sexo: ${patientData['sex']}',
            ].where((value) => value != null && '$value'.isNotEmpty).join(' · ')
          : '${ownerData['name'] ?? 'Sin propietario registrado'}';
      return ListTile(
        leading: const Icon(Icons.link),
        title: Text(f['label']),
        subtitle: Text(linkedValue),
      );
    }
    final label = '${f['label']}${f['required'] == true ? ' *' : ''}';
    if (type == 'person' || type == 'consent') {
      final patient = patientId ?? document?.snapshot['patient']['id'];
      final choices = widget.draftOnly
          ? ((widget.fieldChoices[id] as List?) ?? [])
                .map((r) => (r['id'] as String, r['label'] as String))
                .toList()
          : type == 'person'
          ? staff
                .where((p) => p['role'] == 'mvz' || p['professional'] == true)
                .map((p) => (p['id'] as String, p['label'] as String))
                .toList()
          : consents
                .where((d) => d.snapshot['patient']['id'] == patient)
                .map(
                  (d) => (d.id, '${d.snapshot['schema']['title']} · ${d.id}'),
                )
                .toList();
      final selected = values[id] as String?;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$id-$patient-${choices.length}'),
          initialValue: choices.any((c) => c.$1 == selected) ? selected : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (f['required'] != true)
              const DropdownMenuItem(value: '', child: Text('Sin vincular')),
            for (final c in choices)
              DropdownMenuItem(value: c.$1, child: Text(c.$2)),
          ],
          onChanged: busy
              ? null
              : (v) {
                  values[id] = v ?? '';
                  changed();
                },
        ),
      );
    }
    if (type == 'checkbox') {
      return CheckboxListTile(
        value: values[id] == true,
        title: Text(label),
        onChanged: busy
            ? null
            : (v) {
                values[id] = v ?? false;
                changed();
              },
      );
    }
    if (type == 'single') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          initialValue: values[id],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: (f['options'] as List)
              .map((o) => DropdownMenuItem(value: o as String, child: Text(o)))
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  values[id] = v;
                  changed();
                },
        ),
      );
    }
    if (type == 'multiple') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          for (final o in f['options'])
            CheckboxListTile(
              title: Text(o),
              value: (values[id] as List? ?? []).contains(o),
              onChanged: busy
                  ? null
                  : (checked) {
                      final selected = List<String>.from(values[id] ?? []);
                      if (checked == true) {
                        selected.add(o);
                      } else {
                        selected.remove(o);
                      }
                      values[id] = selected;
                      changed();
                    },
            ),
        ],
      );
    }
    if (type == 'table') {
      final rows = values[id] as List? ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          for (var i = 0; i < rows.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (var c = 0; c < (f['columns'] as List).length; c++)
                      TextFormField(
                        key: ValueKey('$id-${identityHashCode(rows[i])}-$c'),
                        initialValue: rows[i][c],
                        enabled: !busy,
                        maxLength: 1000,
                        decoration: InputDecoration(labelText: f['columns'][c]),
                        onChanged: (v) {
                          rows[i][c] = v;
                          changed();
                        },
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              rows.removeAt(i);
                              values[id] = rows;
                              changed();
                            },
                      child: const Text('Eliminar fila'),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton(
            onPressed: busy || rows.length >= 100
                ? null
                : () {
                    values[id] = [
                      ...rows,
                      List.filled((f['columns'] as List).length, ''),
                    ];
                    changed();
                  },
            child: const Text('Agregar fila'),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: ValueKey('$id-$professionalGeneration'),
        initialValue: values[id] ?? '',
        enabled: !busy,
        maxLines: type == 'text' ? null : 1,
        maxLength:
            clinical &&
                [
                  'antecedents',
                  'subjective',
                  'objective',
                  'assessment',
                  'plan',
                  'asa',
                  'ekg',
                  'notes',
                ].contains(id)
            ? 4000
            : clinical && id == 'reason'
            ? 300
            : 12000,
        decoration: InputDecoration(
          labelText: label,
          hintText: type == 'instant'
              ? 'AAAA-MM-DDTHH:MM:SSZ (UTC)'
              : type == 'date'
              ? 'AAAA-MM-DD'
              : type == 'number'
              ? 'Decimal con punto'
              : null,
        ),
        onChanged: (v) {
          values[id] = v;
          changed();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => UnsavedFormScope(
    controller: exit,
    dirty: dirty || signatureDirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: Text(schema['title'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              clinical
                  ? 'Contenido de la clínica. Modificar contenido invalida la firma y la revisión anterior. Mediciones sin captura permanecen pendientes.'
                  : 'Contenido de la clínica · Identificación: solo número, sin foto. Modificar contenido invalida las firmas y la revisión anterior.',
            ),
            Text(
              widget.draftOnly
                  ? 'Borrador sin autorización del MVZ ni aceptación firmada del tutor.'
                  : 'Estado: ${document == null ? 'Borrador nuevo' : formStateLabel(document!.state)} · Las firmas dibujadas no finalizan el documento hasta revisar y confirmar el PDF.',
            ),
            if (schema['type'] == 'euthanasia')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Constatación de muerte: se registrará después en una entrada vinculada. No se modifica este consentimiento firmado.',
                ),
              ),
            if (document == null)
              DropdownButtonFormField<String>(
                initialValue: patientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Paciente'),
                items: widget.patients
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name} · ${p.species}'),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (id) {
                        patientId = id;
                        changed();
                      },
              ),
            if (widget.draftOnly && document != null)
              Text(
                'MVZ responsable seleccionado: ${values['mvz_name']} · ${values['mvz_license']}. Autorización pendiente.',
              ),
            if (widget.draftOnly && document == null)
              DropdownButtonFormField<String>(
                initialValue: draftResponsible,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText:
                      'MVZ responsable (su autorización quedará pendiente)',
                ),
                items: [
                  for (final r in widget.draftResponsibles)
                    DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(
                        '${r['name']} · ${r['license']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (id) {
                        draftResponsible = id;
                        changed();
                      },
              ),
            TextFormField(
              initialValue: branding['header'],
              maxLength: 2000,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Membrete de la clínica para este documento',
              ),
              onChanged: (v) {
                branding['header'] = v;
                changed();
              },
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : logo,
                  child: const Text('Seleccionar logo PNG/JPG'),
                ),
                if (branding['logo'] != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            branding.remove('logo');
                            branding['include_logo'] = false;
                            changed();
                          },
                    child: const Text('Quitar logo'),
                  ),
              ],
            ),
            SwitchListTile(
              value: branding['include_logo'] == true,
              onChanged: busy
                  ? null
                  : (v) {
                      branding['include_logo'] = v;
                      changed();
                    },
              title: const Text('Incluir logo en el PDF'),
            ),
            if (!widget.draftOnly &&
                responsible &&
                widget.prescribing != null) ...[
              DropdownButtonFormField<String>(
                initialValue: selectedProfile,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Perfil titular de los datos profesionales',
                ),
                items: [
                  for (final p in professionalProfiles)
                    DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        '${p['name']} · cédula capturada ${p['license']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => selectedProfile = v),
              ),
              CheckboxListTile(
                value: shareProfileSignature,
                onChanged: busy
                    ? null
                    : (v) => setState(() => shareProfileSignature = v ?? false),
                title: const Text('Usar firma del titular con permiso vigente'),
              ),
              OutlinedButton(
                onPressed: busy || selectedProfile == null ? null : bindProfile,
                child: const Text('Vincular datos / firma del perfil'),
              ),
              const Text(
                'Cambiar el perfil exige revisar y firmar de nuevo. Sin firma compartida se usa la firma propia de quien emite.',
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                'Datos para completar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const Text(
              'El tutor completa o confirma sus datos personales; el equipo registra la información clínica y del procedimiento. Los datos vinculados del expediente se muestran como referencia.',
            ),
            for (final f in (schema['fields'] as List).cast<Map>())
              if (!(widget.draftOnly &&
                  ['mvz_name', 'mvz_license'].contains(f['id'])))
                field(f),
            const Padding(
              padding: EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                'Cláusulas e indicaciones para revisar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in schema['clauses'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(c['text']),
              ),
            if (!widget.draftOnly &&
                responsible &&
                (document == null || document!.state == 'draft' || dirty)) ...[
              if (!clinical)
                SignaturePad(
                  key: ValueKey('tutor-$signatureGeneration'),
                  onChanged: (points) => setState(() {
                    tutor = points;
                    signatureDirty = true;
                  }),
                ),
              SignaturePad(
                key: ValueKey('mvz-$signatureGeneration'),
                label: 'Firma propia del MVZ responsable',
                onChanged: (points) => setState(() {
                  mvz = points;
                  signatureDirty = true;
                }),
              ),
            ],
            if (widget.draftOnly && !widget.deferAuthorship) ...[
              const Text(
                'Firma de elaboración: solo acredita quién elaboró esta versión. No autoriza el documento, no es firma del tutor y no acredita un procedimiento realizado.',
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tu nombre completo',
                ),
                enabled: !busy,
                onChanged: (v) {
                  authorName = v;
                  signatureDirty = true;
                  authorshipConfirmed = false;
                  setState(() {});
                },
              ),
              SignaturePad(
                key: ValueKey('authorship-$signatureGeneration'),
                label: 'Tu firma de elaboración',
                onChanged: (points) => setState(() {
                  mvz = points;
                  signatureDirty = true;
                  authorshipConfirmed = false;
                }),
              ),
              CheckboxListTile(
                value: authorshipConfirmed,
                onChanged: busy
                    ? null
                    : (v) => setState(() => authorshipConfirmed = v ?? false),
                title: const Text(
                  'Confirmo que elaboré y revisé esta versión con mi propia identidad y firma.',
                ),
              ),
              FilledButton(
                onPressed: busy ? null : signAuthorship,
                child: const Text('Guardar firma de elaboración'),
              ),
            ],
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            OutlinedButton(
              onPressed: busy ? null : save,
              child: const Text('Guardar borrador'),
            ),
            if (!widget.draftOnly &&
                responsible &&
                (document == null || document!.state == 'draft'))
              TextButton(
                onPressed: busy ? null : assign,
                child: const Text('Asignar borrador a auxiliar'),
              ),
            if (!widget.draftOnly && responsible)
              FilledButton(
                onPressed: busy ? null : review,
                child: Text(
                  document?.state == 'awaiting_review' ||
                          document?.state == 'ready'
                      ? 'Reabrir PDF para revisión'
                      : 'Preparar PDF con firmas para revisar',
                ),
              ),
            if (!widget.draftOnly && !responsible)
              const Text(
                'El auxiliar puede llenar el borrador asignado. Solo el MVZ responsable prepara y confirma las firmas.',
              ),
          ],
        ),
      ),
    ),
  );
}
