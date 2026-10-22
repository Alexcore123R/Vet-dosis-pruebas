import 'dart:convert';
import 'package:flutter/material.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/inventory_repository.dart';

class InventoryInsightsScreen extends StatefulWidget {
  const InventoryInsightsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.ai,
  });
  final InventoryRepository repository;
  final ClinicMembership member;
  final AiRepository? ai;
  @override
  State<InventoryInsightsScreen> createState() =>
      _InventoryInsightsScreenState();
}

class _InventoryInsightsScreenState extends State<InventoryInsightsScreen> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> rows(String key) => (data?[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final result = await widget.repository.read('inv_ai_insights', {
        'p_clinic': widget.member.clinicId,
      });
      if (mounted) {
        setState(() => data = Map<String, dynamic>.from(result as Map));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo consultar el análisis. Revisa acceso a inventario y SQL 14M.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> suggest() async {
    if (widget.ai == null || data == null) return;
    final evidence = <String, dynamic>{
      'fecha': data!['today'],
      'zona': data!['timezone'],
      'periodo_actual': [data!['current_from'], data!['current_to']],
      'periodo_anterior': [data!['previous_from'], data!['previous_to']],
      'existencias_bajas': rows('products')
          .where((p) => p['low_stock'] == true || p['reorder'] == true)
          .take(20)
          .toList(),
      'lotes_que_caducan_en_90_dias': rows(
        'lots',
      ).where((l) => l['expired'] != true).take(20).toList(),
      'lotes_vencidos_no_disponibles': rows(
        'lots',
      ).where((l) => l['expired'] == true).take(10).toList(),
      'ventas_disponibles': data!['sales_allowed'],
      'ventas_netas_por_movimientos': rows('sales').take(20).toList(),
    };
    final draft = await requestAiDraft(
      context,
      repository: widget.ai!,
      member: widget.member,
      title: 'Compras y ofertas con datos reales',
      prompt:
          'Propón un plan operativo de compras u ofertas a partir de este extracto limitado de datos reales: ${jsonEncode(evidence)}. '
          'Las ventas se comparan en dos periodos de 30 días de calendario, incluyendo hoy. Son netas por fecha de venta y devolución; pueden ser negativas. '
          'Cita el producto, las cantidades o fechas registradas que apoyan cada propuesta. No supongas datos fuera del extracto. '
          'Separa reposición por faltantes, revisión de lotes próximos a caducar y ofertas opcionales para revisión del administrador. '
          'Los lotes vencidos no están disponibles y nunca deben ofrecerse. No propongas uso clínico de fármacos. '
          'No inventes márgenes, descuentos, precios, demanda ni plazos de proveedores. Si faltan datos para cantidades de compra, pide verificarlos. '
          'Un aumento o caída de ventas es una observación del periodo, no una predicción. Si no hay permiso o historial de ventas, indícalo y no infieras tendencias. '
          'Devuelve un borrador editable con acciones priorizadas y los datos que el administrador debe verificar antes de decidir.',
    );
    if (mounted && draft != null) {
      await reviewAiDraft(context, 'Revisar plan de compras y ofertas', draft);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Existencias, caducidades y ventas'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (data != null) ...[
          Text('Datos al ${data!['today']} · ${data!['timezone']}'),
          if (widget.ai != null)
            FilledButton.icon(
              onPressed: busy ? null : suggest,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Proponer compras u ofertas con IA'),
            ),
          const Text(
            'Las sugerencias se revisan antes de registrar un pedido, cambiar un precio o crear una promoción.',
          ),
          ExpansionTile(
            initiallyExpanded: true,
            title: const Text('Existencias bajas y reposición'),
            children: [
              if (!rows(
                'products',
              ).any((p) => p['low_stock'] == true || p['reorder'] == true))
                const ListTile(
                  title: Text('Sin productos bajo los umbrales registrados.'),
                ),
              for (final p in rows(
                'products',
              ).where((p) => p['low_stock'] == true || p['reorder'] == true))
                ListTile(
                  title: Text('${p['name']}'),
                  subtitle: Text(
                    'Disponible: ${p['available']} ${p['unit']} · Mínimo: ${p['minimum']} · Reorden: ${p['reorder_point']}',
                  ),
                ),
            ],
          ),
          ExpansionTile(
            title: const Text('Lotes próximos a caducar (90 días)'),
            children: [
              if (!rows('lots').any((l) => l['expired'] != true))
                const ListTile(
                  title: Text(
                    'Sin lotes próximos a caducar en este intervalo.',
                  ),
                ),
              for (final l in rows('lots').where((l) => l['expired'] != true))
                ListTile(
                  title: Text('${l['name']} · lote ${l['lot']}'),
                  subtitle: Text(
                    'Caduca ${l['expiry']} · ${l['days']} días · ${l['quantity']} ${l['unit']}',
                  ),
                ),
            ],
          ),
          ExpansionTile(
            title: const Text('Lotes vencidos — fuera del stock disponible'),
            children: [
              for (final l in rows('lots').where((l) => l['expired'] == true))
                ListTile(
                  title: Text('${l['name']} · lote ${l['lot']}'),
                  subtitle: Text(
                    'Caducidad: ${l['expiry']} · ${l['quantity']} ${l['unit']}',
                  ),
                ),
            ],
          ),
          ExpansionTile(
            title: const Text('Patrones de venta: comparación de 30 días'),
            children: [
              if (data!['sales_allowed'] != true)
                const ListTile(
                  title: Text('Se requiere sales.read para consultar ventas.'),
                )
              else ...[
                ListTile(
                  title: Text(
                    'Actual: ${data!['current_from']} a ${data!['current_to']}',
                  ),
                  subtitle: Text(
                    'Anterior: ${data!['previous_from']} a ${data!['previous_to']}\nVentas netas por fecha de movimiento; incluyen devoluciones.',
                  ),
                ),
                if (rows('sales').isEmpty)
                  const ListTile(
                    title: Text(
                      'Sin movimientos de productos en estos dos periodos.',
                    ),
                  ),
                for (final s in rows('sales'))
                  ListTile(
                    title: Text('${s['name']}'),
                    subtitle: Text(
                      'Cantidad neta (${s['unit']}): ${s['current_quantity']} / anterior ${s['previous_quantity']}\nImporte neto: ${s['current_amount']} / anterior ${s['previous_amount']}',
                    ),
                  ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}
