import '../../auth/domain/staff_labels.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../prescribing/domain/prescribing_models.dart' show csvCell;
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/attendance_repository.dart';
import 'attendance_view_model.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.repository,
    required this.member,
    this.canManageWorkspace = false,
  });
  final AttendanceRepository repository;
  final ClinicMembership member;
  final bool canManageWorkspace;
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  late final model = AttendanceViewModel(
    widget.repository,
    widget.member.clinicId,
  );
  bool get canManageWorkspace =>
      widget.member.role == ClinicRole.admin &&
      (widget.canManageWorkspace || model.data['can_manage'] == true);
  Timer? timer;
  String? token;
  int remaining = 0;
  bool qrBusy = false, working = false, visible = true;
  final elapsed = Stopwatch();
  int lifetime = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!visible || token == null || !mounted) return;
      final n = lifetime - elapsed.elapsed.inSeconds;
      if (n <= 0) {
        setState(() {
          token = null;
          remaining = 0;
        });
        renew();
      } else {
        setState(() => remaining = n);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    visible = s == AppLifecycleState.resumed;
    if (!visible) {
      setState(() => token = null);
      elapsed.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    model.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() f) async {
    if (working) return;
    setState(() => working = true);
    try {
      await f();
      if (mounted) await model.load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException ? e.message : attendanceError(e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> renew() async {
    if (qrBusy || !visible || !canManageWorkspace) return;
    qrBusy = true;
    try {
      final r = await widget.repository.qr(widget.member.clinicId);
      if (!mounted || !visible) return;
      lifetime =
          DateTime.parse(
            r['expires_at'] as String,
          ).difference(DateTime.parse(r['server_at'] as String)).inSeconds -
          1;
      elapsed
        ..reset()
        ..start();
      setState(() {
        token = lifetime > 0 ? r['token'] as String : null;
        remaining = lifetime;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(attendanceError(e))));
      }
    } finally {
      qrBusy = false;
    }
  }

  Future<void> scan() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AttendanceScanner()),
    );
    if (result == null || !mounted) return;
    await action(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const FormatException('Activa la ubicación para este checado.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const FormatException(
          'Se necesita permiso de ubicación solo al checar.',
        );
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await widget.repository.scan(
        widget.member.clinicId,
        result,
        p.latitude,
        p.longitude,
        p.accuracy,
        newOperationId(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checado registrado con hora del servidor.'),
          ),
        );
      }
    });
  }

  Future<void> configure() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: 'Configurar checado',
          initial: Map<String, dynamic>.from(
            model.data['settings'] as Map? ?? {},
          ),
          fields: const [
            RxField('latitude', 'Latitud de la clínica', required: true),
            RxField('longitude', 'Longitud de la clínica', required: true),
            RxField(
              'radius_m',
              'Radio permitido en metros (10–5000)',
              required: true,
            ),
            RxField(
              'max_accuracy_m',
              'Precisión máxima en metros (5–200)',
              required: true,
            ),
            RxField(
              'privacy_notice',
              'Aviso de privacidad: finalidad, conservación, acceso y contacto',
              required: true,
            ),
          ],
          submit: (d, op) =>
              widget.repository.settings(widget.member.clinicId, d),
        ),
      ),
    );
    if (mounted) await model.load();
  }
  Future<void> configureSchedule() async {
    if (widget.repository is! AttendanceScheduleRepository) return;
    final current = model.data['schedule'] as Map?;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RxEntryScreen(
      title: 'Horario para puntualidad',
      initial: {
        'start': current?['start_local'] ?? '09:00',
        'weekdays': (current?['weekdays'] as List? ?? [1,2,3,4,5]).join(','),
        'grace': '${current?['grace_minutes'] ?? 10}',
      },
      fields: const [
        RxField('start', 'Hora de entrada HH:MM (zona de la clínica)', required: true),
        RxField('weekdays', 'Días 1=lunes a 7=domingo, separados por coma', required: true),
        RxField('grace', 'Minutos de tolerancia (0–120)', required: true),
      ],
      submit: (data, _) async {
        final start = '${data['start']}'.trim();
        final days = '${data['weekdays']}'.split(',').map((x) => int.tryParse(x.trim())).toList();
        final grace = int.tryParse('${data['grace']}');
        if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(start) ||
            days.isEmpty || days.any((d) => d == null || d < 1 || d > 7) ||
            days.toSet().length != days.length || grace == null || grace < 0 || grace > 120) {
          throw const FormatException('Revisa hora, días y tolerancia del horario.');
        }
        await (widget.repository as AttendanceScheduleRepository).saveSchedule(
          widget.member.clinicId, start, days.cast<int>()..sort(), grace);
      },
    )));
    if (saved == true && mounted) await model.load();
  }

  List<Map<String, dynamic>> get events => (model.data['events'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  String person(String id) => staffLabel(
    id,
    (model.data['people'] as List? ?? []).map(
      (p) => Map<String, dynamic>.from(p as Map),
    ),
  );
  Future<void> export(bool pdf) async {
    final rows = <List<String>>[
      [
        'ID de usuario',
        'Nombre visible',
        'Entrada / salida',
        'Hora servidor UTC',
        'Hora efectiva UTC',
        'Distancia m',
        'Precisión m',
      ],
      for (final e in events)
        [
          '${e['user_id']}',
          person(e['user_id'] as String),
          '${e['direction']}',
          '${e['server_at']}',
          '${e['effective_at']}',
          '${e['distance_m']}',
          '${e['accuracy_m']}',
        ],
    ];
    if (pdf) {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Text('Asistencia · ${widget.member.clinicName}'),
            pw.Text('Registro original y hora corregida; no es nómina.'),
            pw.TableHelper.fromTextArray(data: rows),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => doc.save());
    } else {
      await FilePicker.saveFile(
        dialogTitle: 'Exportar asistencia',
        fileName: 'asistencia.csv',
        bytes: Uint8List.fromList(
          utf8.encode(rows.map((r) => r.map(csvCell).join(',')).join('\r\n')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Checado', style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Entrada y salida alternadas. Solo se consulta ubicación al escanear; se guarda distancia y precisión, no tus coordenadas.',
        ),
        if (model.busy || working) const LinearProgressIndicator(),
        if (model.error != null) Text(model.error!),
        if (canManageWorkspace)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: working ? null : configure,
                child: const Text('Ubicación y aviso'),
              ),
              FilledButton(
                onPressed: working ? null : renew,
                child: const Text('Mostrar QR dinámico'),
              ),
              if (widget.repository is AttendanceScheduleRepository)
                OutlinedButton(onPressed: working ? null : configureSchedule,
                  child: const Text('Horario de puntualidad')),
            ],
          ),
        if (token != null) ...[
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: token!, size: 230),
            ),
          ),
          Text('Vence en $remaining s · el servidor verifica la vigencia'),
        ],
        if (model.data['settings'] != null) ...[
          Text('${(model.data['settings'] as Map)['privacy_notice']}'),
          TextButton(
            onPressed: working
                ? null
                : () => action(
                    () => widget.repository.consent(
                      widget.member.clinicId,
                      (model.data['settings'] as Map)['version'] as int,
                      model.data['consented'] != true,
                    ),
                  ),
            child: Text(
              model.data['consented'] == true
                  ? 'Retirar consentimiento'
                  : 'Acepto el aviso para registrar asistencia',
            ),
          ),
          FilledButton.icon(
            onPressed: model.data['consented'] == true && !working
                ? scan
                : null,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear entrada / salida'),
          ),
        ],
        if (model.data['week_summary'] is Map)
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(
            model.data['week_summary']['configured'] == true
                ? 'Esta semana: ${model.data['week_summary']['attended']} asistencias · ${model.data['week_summary']['on_time']} a tiempo · ${model.data['week_summary']['late']} retrasos.'
                : 'Configura un horario para medir puntualidad. Asistencias registradas esta semana: ${model.data['week_summary']['attended']}.'
          ))),
        Wrap(
          children: [
            TextButton(
              onPressed: () => action(() => export(false)),
              child: const Text('CSV'),
            ),
            TextButton(
              onPressed: () => action(() => export(true)),
              child: const Text('PDF'),
            ),
            IconButton(
              onPressed: working ? null : model.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        for (final e in events)
          ListTile(
            title: Text(
              '${e['direction']} · ${person(e['user_id'] as String)}',
            ),
            subtitle: Text(
              'Servidor: ${e['server_at']}\nEfectiva: ${e['effective_at']}',
            ),
            trailing: canManageWorkspace
                ? IconButton(
                    icon: const Icon(Icons.edit_note),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RxEntryScreen(
                            title: 'Anexar corrección de asistencia',
                            fields: const [
                              RxField(
                                'at',
                                'Hora corregida',
                                type: 'local_instant',
                                required: true,
                              ),
                              RxField(
                                'reason',
                                'Motivo (mínimo 5 caracteres)',
                                required: true,
                              ),
                            ],
                            submit: (d, op) => widget.repository.correct(
                              widget.member.clinicId,
                              e['id'] as String,
                              d['at'] as String,
                              d['reason'] as String,
                              op,
                            ),
                          ),
                        ),
                      );
                      if (mounted) model.load();
                    },
                  )
                : null,
          ),
        for (final c in model.data['corrections'] as List? ?? [])
          ListTile(
            title: Text('Corrección: ${c['reason']}'),
            subtitle: Text(
              '${c['created_by']} · ${c['created_at']} · ${c['event_id']}',
            ),
          ),
      ],
    ),
  );
}

class AttendanceScanner extends StatefulWidget {
  const AttendanceScanner({super.key});
  @override
  State<AttendanceScanner> createState() => _AttendanceScannerState();
}

class _AttendanceScannerState extends State<AttendanceScanner> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool returned = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear QR de la clínica')),
    body: MobileScanner(
      controller: controller,
      onDetect: (c) {
        if (returned) return;
        for (final b in c.barcodes) {
          final v = b.rawValue;
          if (v != null && v.startsWith('vetdosis-att:')) {
            returned = true;
            Navigator.pop(context, v);
            break;
          }
        }
      },
      errorBuilder: (_, e) => const Center(
        child: Text('No se pudo abrir la cámara. Revisa el permiso.'),
      ),
    ),
  );
}
