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
    await FilePicker.saveFile(
      dialogTitle: 'Guardar respaldo operacional',
      fileName:
          'vetdosis-${scope.name}-${widget.member.clinicId}-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.${protect ? 'vetbackup' : 'json'}',
      bytes: output,
    );
    if (mounted) {
      setState(
        () => result =
            '${protect ? 'Respaldo cifrado' : 'Respaldo sin cifrar'} preparado y verificado. Comprueba que el archivo se guardó. Drive y restauración de servidor siguen pendientes.',
      );
    }
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
        result =
            '${encrypted ? 'Contraseña y cifrado comprobados. ' : ''}Integridad verificada · ${report.records} registros. No se modificó la base de datos ni se acreditó el origen del archivo.';
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
                'El respaldo de clínica incluye registros y PDF históricos. El personal incluye solo datos propios permitidos y nunca expedientes. Drive y restauración de servidor siguen pendientes.',
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
              if (inspection != null) ...[
                Text(
                  'Clínica: ${inspection!.clinic} · ${inspection!.serverAt}',
                ),
                const Text(
                  'Resumen del archivo: no se ha restaurado ni importado ningún registro.',
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
