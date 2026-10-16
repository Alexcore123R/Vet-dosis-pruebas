import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';
import 'sale_screen.dart';

class InventoryWorkflowScreen extends StatefulWidget {
  const InventoryWorkflowScreen({
    super.key,
    required this.repository,
    required this.member,
    required this.dashboard,
  });
  final InventoryRepository repository;
  final ClinicMembership member;
  final Map<String, dynamic> dashboard;
  @override
  State<InventoryWorkflowScreen> createState() =>
      _InventoryWorkflowScreenState();
}

class _InventoryWorkflowScreenState extends State<InventoryWorkflowScreen> {
  Map<String, dynamic>? data;
  String? error;
  int _generation = 0;
  bool loading = false;
  bool managementKnown = false;
  Map<String, dynamic>? management;
  bool get canManage =>
      !loading &&
      error == null &&
      (managementKnown
          ? (management?['actions']?['inventory.manage'] == true)
          : widget.member.role == ClinicRole.admin);
  bool get canPrepareCharge =>
      !loading &&
      error == null &&
      (managementKnown ? (management?['can_prepare_charge'] == true) : true);
  bool dispensingKnown = false;
  Map<String, dynamic>? dispensing;
  bool get canDispense =>
      !loading &&
      error == null &&
      (dispensingKnown
          ? (dispensing?['can_dispense'] == true)
          : widget.dashboard['professional'] == true);

  List<Map<String, dynamic>> rows(String key) => (data?[key] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant InventoryWorkflowScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.userId != widget.member.userId ||
        oldWidget.member.clinicId != widget.member.clinicId ||
        oldWidget.repository != widget.repository) {
      data = null;
      dispensing = null;
      dispensingKnown = false;
      management = null;
      managementKnown = false;
      load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> load() async {
    final generation = ++_generation;
    setState(() => loading = true);
    try {
      final repo = widget.repository;
      final managementContract = repo is InventoryManagementRepository
          ? await (repo as InventoryManagementRepository).managementPermissions(
              widget.member.clinicId,
            )
          : null;
      if (!mounted || generation != _generation) return;
      if (managementContract != null) {
        managementKnown = true;
        if (managementContract['schema_version'] != 1 ||
            managementContract['mode'] != 'explicit_inventory' ||
            managementContract['actions'] is! Map) {
          throw StateError('unknown_inventory_contract');
        }
      } else if (managementKnown) {
        throw StateError('inventory_contract_lost');
      }
      final permissions = repo is DispensingPermissionRepository
          ? await (repo as DispensingPermissionRepository)
                .dispensingPermissions(widget.member.clinicId)
          : null;
      if (!mounted || generation != _generation) return;
      if (permissions != null) {
        dispensingKnown = true;
        if (permissions['schema_version'] != 1 ||
            permissions['mode'] != 'verified_dispensing') {
          throw StateError('unknown_dispensing_contract');
        }
      } else if (dispensingKnown) {
        throw StateError('dispensing_contract_lost');
      }
      final d = await widget.repository.read('inv_workflow_dashboard', {
        'p_clinic': widget.member.clinicId,
      });
      if (mounted && generation == _generation) {
        setState(() {
          loading = false;
          management = managementContract;
          dispensing = permissions;
          data = Map<String, dynamic>.from(d);
          error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          loading = false;
          management = null;
          dispensing = null;
          data = null;
          error = 'No se pudo cargar el flujo de entregas y aplicaciones.';
        });
      }
    }
  }

  Future<void> entry(
    String title,
    List<RxField> fields,
    String command,
    Map<String, dynamic> Function(Map<String, dynamic>, String) args,
  ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          submit: (d, op) async {
            try {
              await widget.repository.write(command, args(d, op));
            } on FormatException {
              rethrow;
            } catch (e) {
              throw FormatException(inventoryError(e));
            }
          },
        ),
      ),
    );
    if (result == true && mounted) await load();
  }

  Future<void> tariff() => entry(
    'Precio por aplicación (no precio del frasco)',
    [
      RxField(
        'product',
        'Presentación comercial',
        type: 'select',
        required: true,
        options: {
          for (final p in (widget.dashboard['catalog'] as List).cast<Map>())
            p['id'] as String: '${p['name']} · ${p['presentation']}',
        },
      ),
      const RxField('price', 'Precio total por aplicación MXN', required: true),
    ],
    'inv_application_tariff',
    (d, op) => {
      'p_clinic': widget.member.clinicId,
      'p_product': d['product'],
      'p_price': Money.parse(d['price']).decimal,
      'p_operation': op,
    },
  );
  Future<void> grant() => entry(
    'Permitir entrega de fármacos ordinarios',
    [
      RxField(
        'recipient',
        'Auxiliar o recepción',
        type: 'select',
        required: true,
        options: {
          for (final s in (widget.dashboard['staff'] as List).cast<Map>().where(
            (s) => ['auxiliar', 'recepcion'].contains(s['role']),
          ))
            s['id'] as String: '${s['label'] ?? s['id']} · ${s['role']}',
        },
      ),
      const RxField(
        'until',
        'Vigencia UTC (vacío: hasta revocación)',
        type: 'instant',
      ),
      const RxField('reason', 'Motivo / alcance de confianza', required: true),
    ],
    'inv_delivery_grant',
    (d, op) => {
      'p_clinic': widget.member.clinicId,
      'p_recipient': d['recipient'],
      'p_until': d['until'] == '' ? null : d['until'],
      'p_reason': d['reason'],
      'p_operation': op,
    },
  );
  Future<void> prepare(Map<String, dynamic> r) => entry(
    'Preparar cargo de aplicación registrada',
    [
      const RxField(
        'review',
        'Revisé la aplicación y la tarifa. El cobro no valida el acto clínico.',
        type: 'checkbox',
        required: true,
      ),
    ],
    'inv_application_prepare',
    (d, op) {
      if (d['review'] != true) {
        throw const FormatException('Confirma la revisión.');
      }
      return {'p_record': r['id'], 'p_operation': op};
    },
  );
  Future<void> revoke(Map<String, dynamic> g) => entry(
    'Revocar permiso de entrega',
    [const RxField('reason', 'Motivo', required: true)],
    'inv_delivery_revoke',
    (d, op) => {'p_id': g['id'], 'p_reason': d['reason'], 'p_operation': op},
  );
  Future<void> deliver() async {
    if (!canDispense) {
      throw StateError('verified_dispensing_permission_required');
    }
    final items = await widget.repository.read('inv_delivery_items', {
      'p_clinic': widget.member.clinicId,
    });
    if (!mounted) return;
    final prescriptions = <Map>[
      if (!dispensingKnown)
        ...(widget.dashboard['prescription_items'] as List? ?? []).cast<Map>(),
      ...(items as List).cast<Map>(),
    ];
    final unique = {
      for (final r in prescriptions)
        r['id'] as String:
            '${r['folio'] ?? 'Ordinaria'} · ${r['prescription_id']}',
    };
    await entry(
      'Registrar entrega física (cobro separado)',
      [
        RxField(
          'lot',
          'Producto y lote exactos',
          type: 'select',
          required: true,
          options: {
            for (final p
                in (widget.dashboard['products'] as List).cast<Map>().where(
                  (p) => p['m8_kind'] == 'farmaco' && p['m8_enabled'] == true,
                ))
              for (final l in (p['lots'] as List).cast<Map>())
                l['id'] as String:
                    '${p['nombre']} · ${l['lote']} · ${p['stock_unit']}',
          },
        ),
        RxField(
          'rx',
          'Medicamento de receta emitida',
          type: 'select',
          required: true,
          options: unique,
        ),
        const RxField(
          'quantity',
          'Cantidad física de stock (no dosis)',
          type: 'quantity',
          required: true,
        ),
      ],
      'inv_delivery_prepare',
      (d, op) => {
        'p_lot': d['lot'],
        'p_rx': d['rx'],
        'p_quantity': d['quantity'],
        'p_operation': op,
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Entregas y aplicaciones')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dispensingKnown)
            const Text(
              'La entrega de medicamentos sujetos a receta requiere MVZ habilitado y permiso vigente. Las delegaciones antiguas no conceden ese permiso.',
            ),
          const Text(
            'Una receta puede tener varias aplicaciones. Cada administración se registra en el expediente, descuenta su volumen del frasco y genera su propio cargo. Cobrar no equivale a prescribir, administrar ni dispensar.',
          ),
          if (error != null) Text(error!),
          TextButton(onPressed: load, child: const Text('Actualizar')),
          if (canManage)
            TextButton(
              onPressed: tariff,
              child: const Text('Configurar precio por aplicación'),
            ),
          if (!dispensingKnown && widget.dashboard['professional'] == true)
            TextButton(
              onPressed: grant,
              child: const Text('Delegar entrega ordinaria'),
            ),
          if (canDispense)
            TextButton(
              onPressed: () async {
                try {
                  await deliver();
                } catch (e) {
                  if (mounted) setState(() => error = inventoryError(e));
                }
              },
              child: const Text('Registrar entrega física'),
            ),
          for (final g in rows('grants'))
            ListTile(
              title: Text('Entrega ordinaria · ${g['recipient_id']}'),
              subtitle: Text(
                g['revoked'] == true
                    ? 'Revocado'
                    : g['valid_until']?.toString() ?? 'Hasta revocación',
              ),
              trailing:
                  g['responsible_id'] == widget.member.userId &&
                      g['revoked'] != true
                  ? TextButton(
                      onPressed: () => revoke(g),
                      child: const Text('Revocar'),
                    )
                  : null,
            ),
          const Divider(),
          const Text('Aplicaciones registradas (sin vender el frasco)'),
          for (final r in rows('applications'))
            ListTile(
              title: Text('${r['name']} · ${r['quantity']} ${r['unit']}'),
              subtitle: Text(
                '${r['observed_at']} · misma receta ${r['prescription_id']}',
              ),
              trailing: TextButton(
                onPressed: canPrepareCharge ? () => prepare(r) : null,
                child: const Text('Preparar cargo'),
              ),
            ),
          const Text(
            'Los cargos preparados se cobran desde Nueva venta. Recepción puede cobrar también los actos reservados ya registrados, sin recibir permiso para realizarlos.',
          ),
          for (final ch in rows('charges'))
            ListTile(
              title: Text('${ch['name']} · ${displayMoney(ch['price'])}'),
              subtitle: Text(
                '${ch['paid'] == true ? 'Cobrado' : 'Pendiente de cobro'} · ${ch['reference']['patient_name'] ?? ''}${ch['cost_pending'] == true ? ' · costo pendiente' : ''}',
              ),
            ),
          for (final dt in rows('deliveries'))
            ListTile(
              title: Text('${dt['name']} · ${displayMoney(dt['price'])}'),
              subtitle: Text(
                dt['paid'] == true
                    ? 'Cobrado'
                    : 'Entregado · pendiente de cobro',
              ),
            ),
        ],
      ),
    ),
  );
}
