import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../inventory/domain/inventory_models.dart';
import '../domain/operations_repository.dart';

class CommissionPanel extends StatefulWidget {
  const CommissionPanel({super.key, required this.repository, required this.member});
  final CommissionRepository repository;
  final ClinicMembership member;
  @override
  State<CommissionPanel> createState() => _CommissionPanelState();
}

class _CommissionPanelState extends State<CommissionPanel> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  String cadence = 'semanal';
  DateTime? payOn;
  bool get admin => widget.member.role == ClinicRole.admin;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { busy = true; error = null; data = null; });
    try {
      final next = await widget.repository.commissionAccount(widget.member.clinicId);
      if (mounted) setState(() => data = next);
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo consultar el periodo de comisiones. Revisa la conexión y la migración 14E.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveSchedule() async {
    final chosen = payOn;
    if (chosen == null) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.repository.saveCommissionSchedule(widget.member.clinicId, cadence, chosen);
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo guardar el calendario de pagos.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> payPeriod() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar pago de comisiones'),
        content: const Text('Se cerrará el periodo y quedará registrada una liquidación por colaborador. Confirma solo después de realizar el pago.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar pago')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.repository.payCommissionPeriod(widget.member.clinicId);
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo registrar el pago. Comprueba que llegó el día elegido y actualiza.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = data?['schedule'] is Map ? Map<String, dynamic>.from(data!['schedule'] as Map) : null;
    final accrued = (data?['accrued'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final payments = (data?['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Mis comisiones', style: Theme.of(context).textTheme.titleLarge),
        const Text('Acumulado por servicios cobrados. Los pagos anteriores conservan su historial.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (schedule != null) Text('Periodo actual desde ${schedule['period_start']} · próximo pago ${schedule['next_pay_on']} · ${schedule['cadence']}'),
        if (data != null && schedule == null) const Text('El administrador aún no ha configurado un periodo de pago.'),
        for (final row in accrued)
          ListTile(title: Text(admin ? '${row['professional_name']}' : 'Saldo actual'), subtitle: Text(Money.parse('${row['amount']}', signed: true).display)),
        if (data != null && accrued.isEmpty) const Text('Sin comisiones acumuladas en este periodo.'),
        if (admin) ...[
          const Divider(),
          const Text('Calendario de pagos · solo administración'),
          DropdownButtonFormField<String>(
            initialValue: cadence,
            decoration: const InputDecoration(labelText: 'Frecuencia'),
            items: const [
              DropdownMenuItem(value: 'diario', child: Text('Diario')),
              DropdownMenuItem(value: 'semanal', child: Text('Semanal')),
              DropdownMenuItem(value: 'quincenal', child: Text('Cada 15 días')),
              DropdownMenuItem(value: 'mensual', child: Text('Mensual')),
            ],
            onChanged: busy ? null : (value) { if (value != null) setState(() => cadence = value); },
          ),
          TextButton.icon(
            onPressed: busy ? null : () async {
              final date = await showDatePicker(context: context, initialDate: payOn ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (date != null && mounted) setState(() => payOn = date);
            },
            icon: const Icon(Icons.event),
            label: Text(payOn == null ? 'Elegir próximo día de pago' : '${payOn!.day}/${payOn!.month}/${payOn!.year}'),
          ),
          FilledButton(onPressed: busy || payOn == null ? null : saveSchedule, child: const Text('Guardar calendario')),
          if (schedule != null) OutlinedButton(onPressed: busy ? null : payPeriod, child: const Text('Registrar pago y abrir siguiente periodo')),
        ],
        const Divider(),
        const Text('Liquidaciones registradas'),
        for (final row in payments.take(12))
          ListTile(title: Text(Money.parse('${row['amount']}').display), subtitle: Text('${row['scheduled_on']} · ${admin ? row['professional_name'] : 'Pago registrado'}')),
      ]),
    ));
  }
}
