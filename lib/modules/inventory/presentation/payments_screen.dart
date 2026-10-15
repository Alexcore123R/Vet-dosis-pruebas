import '../../identity/domain/identity_repository.dart';
import '../../exports/domain/branded_export.dart';
import '../../exports/presentation/branded_export_action.dart';
import 'payments_view_model.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../backup/domain/backup_archive.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/inventory_repository.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.identity,
  });
  final InventoryRepository repository;
  final ClinicMembership member;
  final IdentityRepository? identity;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final model = PaymentsViewModel(
    widget.repository,
    widget.member.clinicId,
  );
  String filter = 'todos';
  bool get busy => model.busy;
  String? get error => model.error;
  bool get admin => widget.member.role == ClinicRole.admin;
  List<Map<String, dynamic>> rows(String key) => model.rows(key);
  @override
  void initState() {
    super.initState();
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> load() => model.load();
  Future<void> report() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: 'Registrar transacción externa',
          fields: [
            const RxField(
              'direction',
              'Movimiento',
              type: 'select',
              options: {
                'ingreso': 'Cobro recibido',
                'egreso': 'Pago realizado',
              },
              required: true,
            ),
            const RxField(
              'method',
              'Medio',
              type: 'select',
              options: {
                'efectivo': 'Efectivo',
                'transferencia': 'Transferencia',
                'tarjeta': 'Tarjeta',
              },
              required: true,
            ),
            const RxField('amount', 'Importe bruto MXN', required: true),
            const RxField(
              'provider',
              'Banco, terminal o plataforma (efectivo: caja)',
              required: true,
            ),
            const RxField(
              'external_reference',
              'Referencia / ID de transacción (obligatoria salvo efectivo)',
            ),
            RxField(
              'sale_id',
              'Venta existente opcional (solo cobros)',
              type: 'select',
              options: {
                for (final s in rows(
                  'sales',
                ).where((s) => s['reversed'] != true))
                  s['id'] as String:
                      '${s['method']} · \$${s['total']} · ${s['id']}',
              },
            ),
            const RxField(
              'occurred_at',
              'Fecha y hora de la transacción',
              type: 'local_instant',
              required: true,
            ),
            const RxField(
              'card_last_four',
              'Últimos 4 dígitos de tarjeta, opcional. Nunca número completo ni CVV',
            ),
            const RxField('notes', 'Nota sin datos bancarios sensibles'),
          ],
          submit: (d, op) async {
            try {
              await widget.repository.write('pay_report', {
                'p_clinic': widget.member.clinicId,
                'p_data': d,
                'p_operation': op,
              });
            } catch (e) {
              throw FormatException(paymentError(e));
            }
          },
        ),
      ),
    );
    if (ok == true && mounted) await load();
  }

  Future<void> reconcile(Map<String, dynamic> t) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: 'Conciliar contra comprobante / estado de cuenta',
          fields: const [
            RxField(
              'decision',
              'Resultado',
              type: 'select',
              options: {
                'verificada': 'Verificada manualmente',
                'rechazada': 'Rechazada / referencia incorrecta',
              },
              required: true,
            ),
            RxField('fee', 'Comisión de la plataforma MXN', required: true),
            RxField(
              'reason',
              'Referencia de comprobación o motivo (mínimo 5 caracteres)',
              required: true,
            ),
          ],
          submit: (d, op) async {
            try {
              await widget.repository.write('pay_reconcile', {
                'p_id': t['id'],
                'p_decision': d['decision'],
                'p_fee': d['fee'],
                'p_reason': d['reason'],
                'p_operation': op,
              });
            } catch (e) {
              throw FormatException(paymentError(e));
            }
          },
        ),
      ),
    );
    if (ok == true && mounted) await load();
  }

  Future<void> export() async {
    try {
      await FilePicker.saveFile(
        fileName: 'transacciones.csv',
        bytes: Uint8List.fromList(
          utf8.encode('\uFEFF${BackupArchive.tableCsv(rows('transactions'))}'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No se pudo exportar.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Cobros y pagos')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          BrandedExportAction(
            repository: widget.identity,
            clinicId: widget.member.clinicId,
            clinicName: widget.member.clinicName,
            title: 'Transacciones · Reporte interno · No comprobante fiscal',
            fileName: 'transacciones',
            rows: () async =>
                csvRows(BackupArchive.tableCsv(rows('transactions'))),
          ),
          const Text(
            'Las ventas ya registran efectivo, tarjeta o transferencia. Aquí se añaden referencias externas sin duplicar venta, caja o inventario. Las referencias nuevas quedan pendientes de revisión; no confirman el pago por sí mismas.',
          ),
          const Text(
            'Cobrar desde esta app requiere una pasarela configurada y confirmación de servidor. Esa conexión sigue pendiente.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : report,
                child: const Text('Registrar transacción'),
              ),
              TextButton(
                onPressed: busy ? null : export,
                child: const Text('CSV'),
              ),
              IconButton(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          DropdownButton<String>(
            value: filter,
            items: [
              for (final m in ['todos', 'efectivo', 'transferencia', 'tarjeta'])
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (m) => setState(() => filter = m!),
          ),
          for (final t in rows(
            'transactions',
          ).where((t) => filter == 'todos' || t['method'] == filter))
            Card(
              child: ListTile(
                title: Text(
                  '${t['direction']} · ${t['method']} · \$${t['amount']} MXN',
                ),
                subtitle: Text(
                  '${t['provider']} · ${t['external_reference'] ?? 'sin referencia externa'}\n${t['state']} · ${t['occurred_at']}\n${t['net'] == null ? '' : 'Comisión \$${t['fee']} · neto \$${t['net']}'}${t['review_reason'] == null ? '' : '\n${t['review_reason']}'}',
                ),
                trailing: admin
                    ? IconButton(
                        icon: const Icon(Icons.fact_check_outlined),
                        onPressed: busy ? null : () => reconcile(t),
                      )
                    : null,
              ),
            ),
          const Divider(),
          const Text('Ventas registradas en caja'),
          for (final s in rows('sales'))
            ListTile(
              title: Text('${s['method']} · \$${s['total']} MXN'),
              subtitle: Text(
                '${s['created_at']} · ${s['id']}${s['reversed'] == true ? ' · con reverso' : ''}',
              ),
            ),
        ],
      ),
    ),
  );
}

String paymentError(Object error) {
  final t = error.toString();
  const messages = {
    'payment_external_unique':
        'Esa referencia ya está registrada para esta plataforma en la clínica.',
    'payment_sale_mismatch':
        'El importe o medio no coincide con la venta elegida.',
    'payment_allocation_exceeds_sale':
        'Las referencias verificadas excederían el total de esa venta.',
    'fee_exceeds_payment': 'La comisión supera el importe de la transacción.',
    'reversed_sale': 'La venta tiene un reverso; revisa su conciliación.',
    'own_sale_required': 'La venta no pertenece a tu caja o clínica.',
    'admin_required': 'Solo admin puede conciliar.',
    'unsupported_payment_fields':
        'El registro incluye campos bancarios no admitidos.',
  };
  for (final e in messages.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return 'No se pudo registrar. Revisa los campos, conexión y permisos.';
}
