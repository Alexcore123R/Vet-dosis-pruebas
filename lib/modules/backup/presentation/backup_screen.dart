import '../../identity/domain/identity_repository.dart';
import '../../exports/domain/branded_export.dart';
import '../../exports/presentation/branded_export_action.dart';
import '../domain/backup_cipher.dart';
import '../domain/backup_recovery_report.dart';
import 'backup_password_dialog.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/backup_repository.dart';
import '../domain/backup_archive.dart';
import 'backup_view_model.dart';

/// Reports what the platform picker returned, without claiming remote sync.
@visibleForTesting
String manualBackupSaveStatus({
  required Uri? savedFile,
  required bool encrypted,
}) {
  if (savedFile == null) {
    return 'Guardado cancelado. No se guardó una nueva copia en este intento.';
  }
  if (encrypted) {
    return 'El selector confirmó el guardado de un respaldo .vetbackup cifrado. '
        'Si elegiste Google Drive, comprueba en Drive que el archivo aparezca '
        'y prueba abrirlo con «Revisar respaldo para recuperación». '
        'Esto no confirma la sincronización remota ni restaura todo el servidor.';
  }
  return 'El selector confirmó el guardado de un JSON SIN CIFRAR. '
      'Contiene datos privados: restringe su acceso y evita compartirlo. '
      'Esto no confirma la sincronización remota ni restaura todo el servidor.';
}

@visibleForTesting
String restorePreviewCloseLabel(bool importsApplied) =>
    importsApplied ? 'Cerrar vista previa' : 'Descartar vista previa';

@visibleForTesting
String restorePreviewCloseMessage(bool importsApplied) => importsApplied
    ? 'Vista previa cerrada. Los registros ya restaurados permanecen en la clínica; cerrar la vista previa no los revierte.'
    : 'Vista previa descartada. No se modificó ningún registro.';

@visibleForTesting
Map<String, dynamic> readRestorePreviewState(Map<String, dynamic> value) {
  Map<String, dynamic>? readMap(dynamic raw, String field) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw FormatException('Estado de restauración inválido: $field.');
    }
    return Map<String, dynamic>.from(raw);
  }

  if (value['schema_version'] != 1 ||
      value['mode'] != 'restore_preview' ||
      value['imports_applied'] is! bool) {
    throw const FormatException('Contrato de vista previa desconocido.');
  }
  final stage = readMap(value['stage'], 'stage');
  if (stage == null) {
    return {
      'stage': null,
      'conflicts': null,
      'plan': null,
      'preflight': null,
      'owner_payload': null,
      'owner_apply': null,
      'patient_payload': null,
      'patient_apply': null,
      'imports_applied': false,
    };
  }
  final stageId = stage['stage_id'];
  final archiveSha = stage['archive_sha256'];
  if (stageId is! String ||
      archiveSha is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(archiveSha)) {
    throw const FormatException('La vista previa guardada no es válida.');
  }

  final conflicts = readMap(stage['conflicts'], 'conflicts');
  final plan = readMap(stage['decisions'], 'decisions');
  final preflight = readMap(stage['preflight'], 'preflight');
  final decisionTables = readMap(plan?['tables'], 'decision tables');

  Map<String, dynamic>? normalizePayload(
    String field,
    String table,
    String applyField,
  ) {
    final summary = readMap(stage[field], field);
    if (summary == null) return null;
    final apply = readMap(summary['apply_report'], applyField);
    final decision = decisionTables == null
        ? null
        : readMap(decisionTables[table], '$table decision');
    return {
      ...summary,
      'create_candidate':
          decision?['create_candidate'] ?? apply?['created'] ?? 0,
      'keep_existing':
          decision?['keep_existing'] ?? apply?['kept_existing'] ?? 0,
    };
  }

  final ownerPayload = normalizePayload(
    'owner_payload',
    'vet_owners',
    'owner apply report',
  );
  final patientPayload = normalizePayload(
    'patient_payload',
    'vet_patients',
    'patient apply report',
  );
  final ownerApply = ownerPayload == null
      ? null
      : readMap(ownerPayload['apply_report'], 'owner apply report');
  final patientApply = patientPayload == null
      ? null
      : readMap(patientPayload['apply_report'], 'patient apply report');

  return {
    'stage': stage,
    'conflicts': conflicts,
    'plan': plan,
    'preflight': preflight,
    'owner_payload': ownerPayload,
    'owner_apply': ownerApply,
    'patient_payload': patientPayload,
    'patient_apply': patientApply,
    'imports_applied': value['imports_applied'] as bool,
  };
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.repository,
    required this.member,
    this.identity,
    this.backupOnly = false,
  });
  final BackupRepository repository;
  final ClinicMembership member;
  final IdentityRepository? identity;
  final bool backupOnly;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final model = BackupViewModel(widget.repository, widget.member.clinicId);
  bool working = false, ack = false, protect = true;
  BackupAccess? access;
  BackupScope scope = BackupScope.clinic;
  BackupRecoveryReport? inspection;
  Map<String, dynamic>? restoreStage;
  Map<String, dynamic>? restoreConflicts;
  Map<String, dynamic>? restorePlan;
  Map<String, dynamic>? restoreOwnerPayload;
  Map<String, dynamic>? restorePatientPayload;
  Map<String, dynamic>? restorePreflight;
  Map<String, dynamic>? restoreOwnerApply;
  Map<String, dynamic>? restorePatientApply;
  String? result;
  @override
  void initState() {
    super.initState();
    loadAccess();
  }

  Future<void> loadAccess() async {
    try {
      final next = BackupAccess.read(
        await widget.repository.workspace(widget.member.clinicId),
      );
      if (!mounted) return;
      setState(() {
        access = next;
        scope = next.workspaceKind == 'personal' && next.personal
            ? BackupScope.personal
            : BackupScope.clinic;
      });
      if (next.restorePreview) {
        try {
          await reloadRestorePreview();
        } catch (_) {
          if (mounted) {
            setState(
              () => result =
                  'No se pudo recuperar la vista previa de restauración del servidor.',
            );
          }
        }
      }
      if (next.statistics && !widget.backupOnly) await model.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => result =
              'No se pudo comprobar el alcance del respaldo. Revisa conexión y permisos.',
        );
      }
    }
  }

  void applyRestorePreviewState(Map<String, dynamic> state) {
    final stage = state['stage'] as Map<String, dynamic>?;
    setState(() {
      restoreStage = stage;
      restoreConflicts = state['conflicts'] as Map<String, dynamic>?;
      restorePlan = state['plan'] as Map<String, dynamic>?;
      restoreOwnerPayload = state['owner_payload'] as Map<String, dynamic>?;
      restorePatientPayload =
          state['patient_payload'] as Map<String, dynamic>?;
      restorePreflight = state['preflight'] as Map<String, dynamic>?;
      restoreOwnerApply = state['owner_apply'] as Map<String, dynamic>?;
      restorePatientApply = state['patient_apply'] as Map<String, dynamic>?;
    });
  }

  Future<void> reloadRestorePreview() async {
    final raw = await widget.repository.restorePreview(widget.member.clinicId);
    final state = readRestorePreviewState(raw);
    if (!mounted) return;
    applyRestorePreviewState(state);
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> run(
    Future<void> Function() f, {
    bool clearInspection = true,
  }) async {
    if (working) return;
    setState(() {
      working = true;
      result = null;
      if (clearInspection) inspection = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(
          () => result = e is FormatException
              ? e.message
              : 'No se completó la operación. Revisa el archivo, la conexión y tus permisos.',
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> backup() async {
    final password = protect
        ? await requestBackupPassword(context, creating: true)
        : null;
    if (protect && password == null) return;
    final bytes = await BackupArchive.create(
      widget.repository,
      widget.member.clinicId,
      scope: scope,
      clinicalAssets: {
        for (final name
            in scope == BackupScope.clinic
                ? [
                    'catalog.v1.json',
                    'calculations.v1.json',
                    'regulatory.catalog.v1.json',
                    'forms.reference.v1.json',
                    'forms.clinical.v1.json',
                  ]
                : <String>[])
          name: await rootBundle.loadString('assets/clinical/$name'),
      },
    );
    BackupArchive.verify(bytes);
    final output = protect
        ? await compute(_encryptBackup, (bytes, password!))
        : bytes;
    if (!mounted) return;
    final savedFile = await FilePicker.saveFile(
      dialogTitle: 'Guardar respaldo operacional',
      fileName:
          'vetdosis-${scope.name}-${widget.member.clinicId}-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.${protect ? 'vetbackup' : 'json'}',
      mimeType: protect ? 'application/octet-stream' : 'application/json',
      bytes: output,
    );
    if (!mounted) return;
    setState(() {
      result = manualBackupSaveStatus(
        savedFile: savedFile,
        encrypted: protect,
      );
    });
  }

  Future<void> csv({String format = 'csv'}) async {
    final snapshot =
        jsonDecode(
              await widget.repository.snapshot(
                widget.member.clinicId,
                scope: scope,
              ),
            )
            as Map;
    final tables = snapshot['tables'] as Map;
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Tabla para ${format.toUpperCase()}'),
        children: [
          for (final name in tables.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, name),
              child: Text('$name (${(tables[name] as List).length})'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final data = BackupArchive.tableCsv(
      (tables[selected] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    if (format != 'csv') {
      final branding = await widget.identity!.clinic(widget.member.clinicId);
      final brand = ExportBranding.fromMap(widget.member.clinicName, branding);
      final rows = csvRows(data);
      final bytes = format == 'xlsx'
          ? brandedXlsx(
              brand,
              'Tabla: $selected · Exportación de consulta',
              rows,
            )
          : await brandedPdf(
              brand,
              'Tabla: $selected · Exportación de consulta',
              rows,
            );
      if (!mounted) return;
      await FilePicker.saveFile(
        fileName: '$selected.$format',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [format],
      );
      return;
    }
    await FilePicker.saveFile(
      dialogTitle: 'Exportar tabla',
      fileName: '$selected.csv',
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$data')),
    );
  }

  Future<void> verify() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'vetbackup'],
    );
    if (files.isEmpty) return;
    final file = files.single.xFile;
    if (await file.length() > BackupCipher.maxEncryptedBytes) {
      throw const FormatException('El archivo supera 72 MB.');
    }
    final bytes = await file.readAsBytes();
    final encrypted = BackupCipher.isEncrypted(bytes);
    if (!mounted) return;
    final password = encrypted
        ? await requestBackupPassword(context, creating: false)
        : null;
    if (encrypted && password == null) return;
    final archive = encrypted
        ? await compute(_decryptBackup, (bytes, password!))
        : bytes;
    final report = BackupRecoveryReport.inspect(
      archive,
      widget.member.clinicId,
    );
    if (mounted) {
      setState(() {
        inspection = report;
        final sameServerPreview =
            restoreStage?['archive_sha256'] == report.archiveSha256;
        result =
            '${encrypted ? 'Contraseña y cifrado comprobados. ' : ''}Integridad verificada · ${report.records} registros. '
            'No se modificó la base de datos ni se acreditó el origen del archivo.'
            '${sameServerPreview ? ' Se recuperó la vista previa activa de este mismo respaldo.' : ''}';
      });
    }
  }

  Future<void> stageRestorePreview() async {
    final report = inspection;
    if (report == null || !report.clinicBackup || access?.restorePreview != true) {
      return;
    }
    final staged = await widget.repository.stageRestorePreview(
      widget.member.clinicId,
      format: report.format,
      version: report.version,
      archiveSha256: report.archiveSha256,
      sourceServerAt: DateTime.tryParse(report.serverAt),
      tableCounts: report.tables,
    );
    if (staged['mode'] != 'restore_preview' ||
        staged['imports_applied'] != false ||
        staged['archive_sha256'] != report.archiveSha256) {
      throw const FormatException('El servidor no confirmó una vista previa segura.');
    }
    final stageId = staged['stage_id'];
    if (stageId is! String) {
      throw const FormatException('El servidor no devolvió un identificador de vista previa.');
    }
    final conflicts = report.conflictManifest.isEmpty
        ? <String, dynamic>{
            'schema_version': 1,
            'mode': 'restore_conflicts',
            'archive_sha256': report.archiveSha256,
            'manifest_sha256': report.conflictManifestSha256,
            'incoming': 0,
            'existing': 0,
            'new': 0,
            'tables': <String, dynamic>{},
            'imports_applied': false,
          }
        : await widget.repository.previewRestoreConflicts(
            widget.member.clinicId,
            stageId: stageId,
            archiveSha256: report.archiveSha256,
            manifestSha256: report.conflictManifestSha256,
            manifest: report.conflictManifest,
          );
    if (conflicts['mode'] != 'restore_conflicts' ||
        conflicts['imports_applied'] != false ||
        conflicts['archive_sha256'] != report.archiveSha256 ||
        conflicts['manifest_sha256'] != report.conflictManifestSha256) {
      throw const FormatException('La revisión de conflictos no coincide con el respaldo.');
    }
    final plan = report.conflictManifest.isEmpty
        ? <String, dynamic>{
            'schema_version': 1,
            'mode': 'restore_decision_preview',
            'archive_sha256': report.archiveSha256,
            'conflict_manifest_sha256': report.conflictManifestSha256,
            'dependency_manifest_sha256': report.dependencyManifestSha256,
            'create_candidate': 0,
            'keep_existing': 0,
            'blocked_missing_dependency': 0,
            'blocked_foreign_identity': 0,
            'manual_review': 0,
            'tables': <String, dynamic>{},
            'imports_applied': false,
          }
        : await widget.repository.previewRestorePlan(
            widget.member.clinicId,
            stageId: stageId,
            archiveSha256: report.archiveSha256,
            conflictManifestSha256: report.conflictManifestSha256,
            dependencyManifestSha256: report.dependencyManifestSha256,
            dependencies: report.dependencyManifest,
          );
    if (plan['mode'] != 'restore_decision_preview' ||
        plan['imports_applied'] != false ||
        plan['archive_sha256'] != report.archiveSha256 ||
        plan['conflict_manifest_sha256'] != report.conflictManifestSha256 ||
        plan['dependency_manifest_sha256'] != report.dependencyManifestSha256) {
      throw const FormatException('La simulación de restauración no coincide con el respaldo.');
    }
    Map<String, dynamic>? ownerPayload;
    if (report.restoreOwners.isNotEmpty) {
      ownerPayload = await widget.repository.prepareRestoreOwners(
        widget.member.clinicId,
        stageId: stageId,
        archiveSha256: report.archiveSha256,
        owners: report.restoreOwners,
      );
      if (ownerPayload['mode'] != 'restore_owner_payload' ||
          ownerPayload['imports_applied'] != false ||
          ownerPayload['archive_sha256'] != report.archiveSha256) {
        throw const FormatException(
          'La preparación de tutores no coincide con el respaldo.',
        );
      }
    }

    Map<String, dynamic>? patientPayload;
    final ownerCreates =
        (ownerPayload?['create_candidate'] as num?)?.toInt() ?? 0;
    if (report.restorePatients.isNotEmpty && ownerCreates == 0) {
      patientPayload = await widget.repository.prepareRestorePatients(
        widget.member.clinicId,
        stageId: stageId,
        archiveSha256: report.archiveSha256,
        patients: report.restorePatients,
      );
      if (patientPayload['mode'] != 'restore_patient_payload' ||
          patientPayload['imports_applied'] != false ||
          patientPayload['archive_sha256'] != report.archiveSha256) {
        throw const FormatException(
          'La preparación de pacientes no coincide con el respaldo.',
        );
      }
    }
    final preflight = report.conflictManifest.isEmpty
        ? <String, dynamic>{
            'schema_version': 1,
            'mode': 'restore_preflight',
            'stage_id': stageId,
            'archive_sha256': report.archiveSha256,
            'conflict_manifest_sha256': report.conflictManifestSha256,
            'dependency_manifest_sha256': report.dependencyManifestSha256,
            'checked_entries': 0,
            'applicable': true,
            'blockers': <dynamic>[],
            'imports_applied': false,
          }
        : await widget.repository.preflightRestore(
            widget.member.clinicId,
            stageId: stageId,
            archiveSha256: report.archiveSha256,
            conflictManifestSha256: report.conflictManifestSha256,
            dependencyManifestSha256: report.dependencyManifestSha256,
          );
    if (preflight['mode'] != 'restore_preflight' ||
        preflight['imports_applied'] != false ||
        preflight['archive_sha256'] != report.archiveSha256 ||
        preflight['conflict_manifest_sha256'] != report.conflictManifestSha256 ||
        preflight['dependency_manifest_sha256'] !=
            report.dependencyManifestSha256) {
      throw const FormatException('El preflight no coincide con el respaldo revisado.');
    }
    if (mounted) {
      setState(() {
        restoreStage = staged;
        restoreConflicts = conflicts;
        restorePlan = plan;
        restoreOwnerPayload = ownerPayload;
        restorePatientPayload = patientPayload;
        restorePreflight = preflight;
        restoreOwnerApply = null;
        restorePatientApply = null;
        result = preflight['applicable'] == true
            ? 'Preflight aprobado para este estado actual. Sigue sin existir una importación activa.'
            : 'Preflight bloqueado: hay decisiones o cambios que deben resolverse. No se importó ningún registro.';
      });
    }
  }

  Future<void> applyOwnerRestore() async {
    final stage = restoreStage;
    final payload = restoreOwnerPayload;
    final preflight = restorePreflight;
    if (stage == null ||
        payload == null ||
        preflight?['applicable'] != true ||
        restoreOwnerApply != null) {
      return;
    }
    final stageId = stage['stage_id'];
    final preflightId = preflight?['preflight_id'];
    final payloadSha = payload['payload_sha256'];
    if (stageId is! String || preflightId is! String || payloadSha is! String) {
      throw const FormatException(
        'La restauración preparada no tiene identificadores válidos.',
      );
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restaurar tutores nuevos'),
            content: Text(
              'Se crearán únicamente ${payload['create_candidate'] ?? 0} tutores '
              'que no existen actualmente. Los tutores existentes no se modificarán. '
              'La operación es atómica: si algo cambia, no se crea ninguno.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restaurar tutores'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final applied = await widget.repository.applyRestoreOwners(
      widget.member.clinicId,
      stageId: stageId,
      preflightId: preflightId,
      ownerPayloadSha256: payloadSha,
    );
    if (applied['mode'] != 'restore_apply_owners' ||
        applied['imports_applied'] != true ||
        applied['overwrite'] != false ||
        applied['merge'] != false) {
      throw const FormatException(
        'El servidor no confirmó una restauración limitada y segura.',
      );
    }
    if (mounted) {
      setState(() {
        restoreOwnerApply = applied;
        result =
            'Tutores restaurados: ${applied['created'] ?? 0}. '
            'Existentes conservados: ${applied['kept_existing'] ?? 0}.';
      });
    }
  }

  Future<void> applyPatientRestore() async {
    final stage = restoreStage;
    final payload = restorePatientPayload;
    final preflight = restorePreflight;
    if (stage == null ||
        payload == null ||
        preflight?['applicable'] != true ||
        restorePatientApply != null) {
      return;
    }
    final stageId = stage['stage_id'];
    final preflightId = preflight?['preflight_id'];
    final payloadSha = payload['payload_sha256'];
    if (stageId is! String || preflightId is! String || payloadSha is! String) {
      throw const FormatException(
        'La restauración de pacientes no tiene identificadores válidos.',
      );
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restaurar pacientes nuevos'),
            content: Text(
              'Se crearán únicamente ${payload['create_candidate'] ?? 0} pacientes '
              'que no existen actualmente. Los pacientes existentes no se modificarán '
              'y cada tutor debe seguir existiendo en esta clínica. '
              'La operación es atómica: si algo cambia, no se crea ninguno.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restaurar pacientes'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final applied = await widget.repository.applyRestorePatients(
      widget.member.clinicId,
      stageId: stageId,
      preflightId: preflightId,
      patientPayloadSha256: payloadSha,
    );
    if (applied['mode'] != 'restore_apply_patients' ||
        applied['imports_applied'] != true ||
        applied['overwrite'] != false ||
        applied['merge'] != false) {
      throw const FormatException(
        'El servidor no confirmó una restauración limitada de pacientes.',
      );
    }
    if (mounted) {
      setState(() {
        restorePatientApply = applied;
        result =
            'Pacientes restaurados: ${applied['created'] ?? 0}. '
            'Existentes conservados: ${applied['kept_existing'] ?? 0}.';
      });
    }
  }

  Future<void> discardRestorePreview() async {
    final stage = restoreStage;
    final id = stage?['stage_id'];
    if (id is! String) return;
    final importsApplied =
        restoreOwnerApply?['imports_applied'] == true ||
        restorePatientApply?['imports_applied'] == true;
    await widget.repository.discardRestorePreview(widget.member.clinicId, id);
    if (mounted) {
      setState(() {
        restoreStage = null;
        restoreConflicts = null;
        restorePlan = null;
        restoreOwnerPayload = null;
        restorePatientPayload = null;
        restorePreflight = null;
        restoreOwnerApply = null;
        restorePatientApply = null;
        result = restorePreviewCloseMessage(importsApplied);
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => access == null
        ? Column(
            children: [
              if (result == null) const LinearProgressIndicator(),
              if (result != null) Text(result!),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.backupOnly ? 'Respaldo' : 'Estadísticas y respaldo',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (model.busy || working) const LinearProgressIndicator(),
              if (model.error != null) Text(model.error!),
              IconButton(
                onPressed: working ? null : model.load,
                icon: const Icon(Icons.refresh),
              ),
              if (!widget.backupOnly && access!.statistics) ...[
                const Text(
                  'Ventas mensuales netas de devoluciones registradas en el mes, en MXN. No representan utilidad neta.',
                ),
                for (final s in model.data['sales'] as List? ?? [])
                  metric(
                    '${s['month']}',
                    double.parse('${s['amount']}'),
                    salesMaximum(),
                  ),
                const Divider(),
                const Text('Citas no canceladas del mes por especie'),
                for (final s in model.data['species'] as List? ?? [])
                  metric(
                    '${s['species']}',
                    (s['count'] as num).toDouble(),
                    speciesMaximum(),
                  ),
                const Divider(),
                const Text('Productos en stock mínimo o inferior'),
                for (final p in model.data['low_stock'] as List? ?? [])
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text('${p['name']}'),
                    subtitle: Text('${p['stock']} · mínimo ${p['minimum']}'),
                  ),
                const Divider(),
              ],
              const Text(
                'El respaldo de clínica incluye registros y PDF históricos. '
                'El personal incluye solo datos propios permitidos y nunca expedientes. '
                'En Android puedes escoger Google Drive en el selector «Guardar», '
                'si aparece como destino disponible. Es un guardado MANUAL, '
                'no una conexión automática de VetDosis con Drive ni un respaldo '
                'integral del servidor.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Para comprobar tu copia, abre Google Drive y verifica el archivo. '
                'Luego regresa a «Revisar respaldo para recuperación» y selecciona '
                'ese mismo archivo. No desinstales la app ni borres datos durante la prueba.',
              ),
              if (access!.clinic && access!.personal)
                SegmentedButton<BackupScope>(
                  segments: const [
                    ButtonSegment(
                      value: BackupScope.clinic,
                      label: Text('Clínica'),
                    ),
                    ButtonSegment(
                      value: BackupScope.personal,
                      label: Text('Personal'),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: working
                      ? null
                      : (value) => setState(() => scope = value.single),
                )
              else
                Text(
                  !access!.clinic && !access!.personal
                      ? 'No tienes un alcance de respaldo vigente.'
                      : access!.personal
                      ? 'Alcance: datos personales propios, sin expedientes.'
                      : 'Alcance: operación de la clínica autorizada.',
                ),
              SwitchListTile(
                value: protect,
                onChanged: working
                    ? null
                    : (value) => setState(() => protect = value),
                title: const Text('Proteger respaldo con contraseña'),
                subtitle: const Text(
                  'Activado por defecto. Usa una contraseña distinta para cada tipo. CSV se exporta sin cifrar.',
                ),
              ),
              if (!protect)
                const Text(
                  'El archivo JSON quedará sin cifrar. Guárdalo en un lugar con acceso restringido.',
                ),
              CheckboxListTile(
                value: ack,
                onChanged: working
                    ? null
                    : (v) => setState(() => ack = v ?? false),
                title: const Text(
                  'Guardaré el archivo con acceso restringido: contiene datos de pacientes y propietarios.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        ack &&
                            !working &&
                            ((scope == BackupScope.clinic && access!.clinic) ||
                                (scope == BackupScope.personal &&
                                    access!.personal))
                        ? () => run(backup)
                        : null,
                    child: Text(
                      protect
                          ? 'Exportar respaldo protegido'
                          : 'Exportar respaldo JSON',
                    ),
                  ),
                  TextButton(
                    onPressed:
                        ack &&
                            !working &&
                            ((scope == BackupScope.clinic && access!.clinic) ||
                                (scope == BackupScope.personal &&
                                    access!.personal))
                        ? () => run(() => csv())
                        : null,
                    child: const Text('Tabla CSV'),
                  ),
                  for (final format in ['pdf', 'xlsx'])
                    TextButton(
                      onPressed:
                          ack &&
                              !working &&
                              widget.identity != null &&
                              ((scope == BackupScope.clinic &&
                                      access!.clinic) ||
                                  (scope == BackupScope.personal &&
                                      access!.personal))
                          ? () => run(() => csv(format: format))
                          : null,
                      child: Text('Tabla ${format.toUpperCase()} con membrete'),
                    ),
                  TextButton(
                    onPressed: working ? null : () => run(verify),
                    child: const Text('Revisar respaldo para recuperación'),
                  ),
                ],
              ),
              if (result != null) Text(result!),
              if (restoreStage != null &&
                  access!.restorePreview &&
                  (inspection == null ||
                      restoreStage!['archive_sha256'] !=
                          inspection!.archiveSha256)) ...[
                const Divider(),
                const Text('Vista previa del servidor recuperada'),
                Text(
                  'Respaldo: ${(restoreStage!['archive_sha256'] as String).substring(0, 12)}… · '
                  'vence ${restoreStage!['expires_at'] ?? 'según el servidor'}',
                ),
                Text(
                  restoreOwnerApply?['imports_applied'] == true ||
                          restorePatientApply?['imports_applied'] == true
                      ? 'Esta vista ya aplicó una restauración limitada. Cerrarla no revierte los registros creados.'
                      : 'Para continuar con esta vista previa, revisa de nuevo el mismo archivo de respaldo.',
                ),
                TextButton(
                  onPressed: working
                      ? null
                      : () => run(
                          discardRestorePreview,
                          clearInspection: false,
                        ),
                  child: Text(
                    restorePreviewCloseLabel(
                      restoreOwnerApply?['imports_applied'] == true ||
                          restorePatientApply?['imports_applied'] == true,
                    ),
                  ),
                ),
              ],
              if (inspection != null) ...[
                Text(
                  'Clínica: ${inspection!.clinic} · ${inspection!.serverAt}',
                ),
                const Text(
                  'Resumen del archivo verificado. Las acciones de restauración y su estado se muestran abajo.',
                ),
                for (final table
                    in (inspection!.tables.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key))))
                  ListTile(
                    title: Text(table.key),
                    trailing: Text('${table.value} registros'),
                  ),
                if (inspection!.excluded.isNotEmpty)
                  const Text(
                    'El archivo declara exclusiones. Una recuperación completa requiere el respaldo del servidor.',
                  ),
                if (inspection!.clinicBackup && access!.restorePreview) ...[
                  if (!access!.restoreApplyTest)
                    const Text(
                      'Puedes revisar conflictos y dependencias. La importación requiere un espacio de prueba habilitado.',
                    ),
                  FilledButton.icon(
                    onPressed: working || restoreStage != null
                        ? null
                        : () => run(stageRestorePreview, clearInspection: false),
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preparar vista previa en servidor'),
                  ),
                  if (restoreStage != null &&
                      restoreStage!['archive_sha256'] ==
                          inspection!.archiveSha256) ...[
                    Text(
                      'Vista previa activa · vence ${restoreStage!['expires_at'] ?? 'según el servidor'}',
                    ),
                    if (restoreConflicts != null) ...[
                      Text(
                        'Identificadores revisados: ${restoreConflicts!['incoming'] ?? 0} · '
                        'sin choque: ${restoreConflicts!['new'] ?? 0} · '
                        'ya existentes: ${restoreConflicts!['existing'] ?? 0} · '
                        'ID en otro espacio: ${restoreConflicts!['foreign_conflict'] ?? 0}',
                      ),
                      for (final entry
                          in (Map<String, dynamic>.from(
                            restoreConflicts!['tables'] as Map? ?? const {},
                          ).entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key))))
                        ListTile(
                          dense: true,
                          title: Text(entry.key),
                          subtitle: Text(
                            'Nuevos: ${(entry.value as Map)['new']} · '
                            'existentes: ${(entry.value as Map)['existing']} · '
                            'otro espacio: ${(entry.value as Map)['foreign_conflict'] ?? 0}',
                          ),
                          trailing: Text(
                            '${(entry.value as Map)['incoming']}',
                          ),
                        ),
                    ],
                    if (restorePlan != null) ...[
                      const Divider(),
                      const Text(
                        'Simulación de decisiones: los registros existentes se conservan y nunca se sobrescriben.',
                      ),
                      Text(
                        'Candidatos a crear: ${restorePlan!['create_candidate'] ?? 0} · '
                        'conservar actuales: ${restorePlan!['keep_existing'] ?? 0} · '
                        'bloqueados: ${restorePlan!['blocked_missing_dependency'] ?? 0} · '
                        'ID de otro espacio: ${restorePlan!['blocked_foreign_identity'] ?? 0} · '
                        'revisión manual: ${restorePlan!['manual_review'] ?? 0}',
                      ),
                      for (final entry
                          in (Map<String, dynamic>.from(
                            restorePlan!['tables'] as Map? ?? const {},
                          ).entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key))))
                        ListTile(
                          dense: true,
                          title: Text(entry.key),
                          subtitle: Text(
                            'Crear: ${(entry.value as Map)['create_candidate']} · '
                            'conservar: ${(entry.value as Map)['keep_existing']} · '
                            'bloqueados: ${(entry.value as Map)['blocked_missing_dependency']} · '
                            'otro espacio: ${(entry.value as Map)['blocked_foreign_identity'] ?? 0} · '
                            'manual: ${(entry.value as Map)['manual_review']}',
                          ),
                        ),
                      const Text(
                        'Todavía no se aplican reemplazos, fusiones ni inserciones. Las referencias a personal faltante requieren revisión manual.',
                      ),
                      if (restorePreflight != null) ...[
                        const Divider(),
                        ListTile(
                          leading: Icon(
                            restorePreflight!['applicable'] == true
                                ? Icons.verified_outlined
                                : Icons.block_outlined,
                          ),
                          title: Text(
                            restorePreflight!['applicable'] == true
                                ? 'Preflight: aplicable en el estado actual'
                                : 'Preflight: no aplicable',
                          ),
                          subtitle: Text(
                            'Registros revalidados: ${restorePreflight!['checked_entries'] ?? 0}'
                            '${restorePreflight!['valid_until'] == null ? '' : ' · válido hasta ${restorePreflight!['valid_until']}'}',
                          ),
                        ),
                        if ((restorePreflight!['blockers'] as List? ?? const [])
                            .isNotEmpty)
                          for (final blocker
                              in (restorePreflight!['blockers'] as List))
                            Text(
                              'Bloqueo: ${(blocker as Map)['code']}'
                              '${blocker['count'] == null ? '' : ' (${blocker['count']})'}',
                            ),
                        const Text(
                          'El preflight solo verifica que el plan siga siendo coherente.',
                        ),
                        if (restoreOwnerPayload != null) ...[
                          Text(
                            'Tutores preparados: ${restoreOwnerPayload!['rows'] ?? 0} · '
                            'nuevos: ${restoreOwnerPayload!['create_candidate'] ?? 0} · '
                            'existentes: ${restoreOwnerPayload!['keep_existing'] ?? 0}',
                          ),
                          if (restorePreflight!['applicable'] == true &&
                              (restoreOwnerPayload!['create_candidate'] as num? ?? 0) > 0 &&
                              restoreOwnerApply == null &&
                              access!.restoreApplyTest)
                            FilledButton.icon(
                              onPressed: working
                                  ? null
                                  : () => run(
                                      applyOwnerRestore,
                                      clearInspection: false,
                                    ),
                              icon: const Icon(Icons.restore_outlined),
                              label: const Text(
                                'Restaurar solo tutores nuevos',
                              ),
                            ),
                          if (restoreOwnerApply != null) ...[
                            Text(
                              'Restauración aplicada · creados: ${restoreOwnerApply!['created'] ?? 0} · '
                              'conservados: ${restoreOwnerApply!['kept_existing'] ?? 0}',
                            ),
                            const Text(
                              'Cerrar esta vista previa no deshace los tutores ya restaurados.',
                            ),
                            if (inspection!.restorePatients.isNotEmpty &&
                                restorePatientPayload == null)
                              FilledButton.icon(
                                onPressed: working
                                    ? null
                                    : () => run(
                                        stageRestorePreview,
                                        clearInspection: false,
                                      ),
                                icon: const Icon(Icons.sync_outlined),
                                label: const Text(
                                  'Continuar con pacientes',
                                ),
                              ),
                            if (inspection!.restorePatients.isNotEmpty &&
                                restorePatientPayload == null)
                              const Text(
                                'Se preparará una vista previa nueva del mismo respaldo para revalidar los tutores antes de crear pacientes.',
                              ),
                          ],
                        ],
                        if (restorePatientPayload != null) ...[
                          const Divider(),
                          Text(
                            'Pacientes preparados: ${restorePatientPayload!['rows'] ?? 0} · '
                            'nuevos: ${restorePatientPayload!['create_candidate'] ?? 0} · '
                            'existentes: ${restorePatientPayload!['keep_existing'] ?? 0}',
                          ),
                          if (restorePreflight!['applicable'] == true &&
                              (restorePatientPayload!['create_candidate'] as num? ?? 0) >
                                  0 &&
                              restorePatientApply == null &&
                              access!.restoreApplyTest)
                            FilledButton.icon(
                              onPressed: working
                                  ? null
                                  : () => run(
                                      applyPatientRestore,
                                      clearInspection: false,
                                    ),
                              icon: const Icon(Icons.pets_outlined),
                              label: const Text(
                                'Restaurar solo pacientes nuevos',
                              ),
                            ),
                          if (restorePatientApply != null) ...[
                            Text(
                              'Pacientes restaurados · creados: ${restorePatientApply!['created'] ?? 0} · '
                              'conservados: ${restorePatientApply!['kept_existing'] ?? 0}',
                            ),
                            const Text(
                              'Cerrar esta vista previa no deshace los pacientes ya restaurados.',
                            ),
                          ],
                        ],
                      ],
                    ] else
                      const Text(
                        'Esta revisión compara identificadores de tablas principales. Aún no decide reemplazos, fusiones ni inserciones.',
                      ),
                    TextButton(
                      onPressed: working
                          ? null
                          : () => run(
                              discardRestorePreview,
                              clearInspection: false,
                            ),
                      child: Text(
                        restorePreviewCloseLabel(
                          restoreOwnerApply?['imports_applied'] == true ||
                              restorePatientApply?['imports_applied'] == true,
                        ),
                      ),
                    ),
                  ],
                ] else if (inspection!.clinicBackup)
                  const Text(
                    'La revisión local está disponible, pero tu acceso actual no permite preparar una restauración.',
                  ),
                TextButton(
                  onPressed: working
                      ? null
                      : () => run(() async {
                          final report = inspection;
                          if (report == null) return;
                          await FilePicker.saveFile(
                            fileName: 'revision-recuperacion.json',
                            bytes: Uint8List.fromList(
                              utf8.encode(report.toJson()),
                            ),
                          );
                        }, clearInspection: false),
                  child: const Text('Guardar resumen de revisión'),
                ),
              ],
            ],
          ),
  );
  double salesMaximum() {
    var m = 1.0;
    for (final s in model.data['sales'] as List? ?? []) {
      final n = double.parse('${s['amount']}').abs();
      if (n > m) m = n;
    }
    return m;
  }

  double speciesMaximum() {
    var m = 1.0;
    for (final s in model.data['species'] as List? ?? []) {
      final n = (s['count'] as num).toDouble();
      if (n > m) m = n;
    }
    return m;
  }

  Widget metric(String label, double value, double maximum) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · ${value.toStringAsFixed(2)}'),
        Semantics(
          label: '$label: $value',
          child: LinearProgressIndicator(
            value: (value.abs() / maximum).clamp(0, 1),
            minHeight: 12,
            color: value < 0 ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    ),
  );
}

Future<Uint8List> _encryptBackup((Uint8List, String) input) =>
    BackupCipher.encrypt(input.$1, input.$2);
Future<Uint8List> _decryptBackup((Uint8List, String) input) =>
    BackupCipher.decrypt(input.$1, input.$2);
