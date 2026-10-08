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
  });
  final BackupRepository repository;
  final ClinicMembership member;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final model = BackupViewModel(widget.repository, widget.member.clinicId);
  bool working = false, ack = false, protect = true;
  BackupRecoveryReport? inspection;
  String? result;
  @override
  void initState() {
    super.initState();
    if (widget.member.role == ClinicRole.admin) model.load();
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
      clinicalAssets: {
        for (final name in [
          'catalog.v1.json',
          'calculations.v1.json',
          'regulatory.catalog.v1.json',
          'forms.reference.v1.json',
          'forms.clinical.v1.json',
        ])
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
          'vetdosis-${widget.member.clinicId}-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.${protect ? 'vetbackup' : 'json'}',
      bytes: output,
    );
    if (mounted) {
      setState(
        () => result =
            '${protect ? 'Respaldo cifrado' : 'Respaldo sin cifrar'} preparado y verificado. Comprueba que el archivo se guardó. Drive y restauración de servidor siguen pendientes.',
      );
    }
  }

  Future<void> csv() async {
    final snapshot =
        jsonDecode(await widget.repository.snapshot(widget.member.clinicId))
            as Map;
    final tables = snapshot['tables'] as Map;
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Tabla para CSV / Excel'),
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
    builder: (context, _) => widget.member.role != ClinicRole.admin
        ? const Text('Los respaldos requieren acceso de administrador.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Estadísticas y respaldo',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (model.busy || working) const LinearProgressIndicator(),
              if (model.error != null) Text(model.error!),
              IconButton(
                onPressed: working ? null : model.load,
                icon: const Icon(Icons.refresh),
              ),
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
              const Text(
                'El respaldo operacional incluye registros y PDF históricos; agrega las fotos de inventario. Excluye credenciales, firmas reutilizables y fichas médicas de otros empleados. Drive, restauración y respaldo integral del servidor quedan para la integración final.',
              ),
              SwitchListTile(
                value: protect,
                onChanged: working
                    ? null
                    : (value) => setState(() => protect = value),
                title: const Text('Proteger respaldo con contraseña'),
                subtitle: const Text(
                  'Activado por defecto. CSV se exporta sin cifrar.',
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
                    onPressed: ack && !working ? () => run(backup) : null,
                    child: Text(
                      protect
                          ? 'Exportar respaldo protegido'
                          : 'Exportar respaldo JSON',
                    ),
                  ),
                  TextButton(
                    onPressed: ack && !working ? () => run(csv) : null,
                    child: const Text('Tabla CSV / Excel'),
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
