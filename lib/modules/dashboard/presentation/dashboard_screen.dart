import '../../../core/widgets/neu_header_card.dart';
import '../../doses/domain/quantity.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../../core/domain/navigation_access.dart';
import '../../auth/domain/staff_labels.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../hospital/application/hospital_alerts.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import 'dashboard_view_model.dart';
import 'alert_preferences_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.model,
    required this.onNavigate,
    this.offline = false,
    this.statisticsOnly = false,
    this.alerts,
  });
  final DashboardViewModel model;
  final ValueChanged<String> onNavigate;
  final bool offline, statisticsOnly;
  final HospitalAlerts? alerts;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardViewModel model = widget.model;
  final search = TextEditingController();
  Timer? timer;
  bool openingCash = false;
  @override
  void initState() {
    super.initState();
    model.load(offline: widget.offline);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    model.dispose();
    super.dispose();
  }

  String time(DateTime date) {
    final d = model.localTime(date);
    return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color sectionColor(String page) => switch (page) {
    'Pacientes' || 'Hospitalización' => const Color(0xFF61C7BA),
    'Inventario' || 'Cálculo rápido' => const Color(0xFF51BAC6),
    'Estadísticas' || 'Caja' => const Color(0xFF879AE0),
    _ => const Color(0xFFAC8DD5),
  };

  Widget panel(String title, String page, List<Widget> children) =>
      NeuHeaderCard(
        title: title,
        icon: sectionIcon(page),
        color: sectionColor(page),
        trailing: IconButton(
          tooltip: 'Abrir $title',
          onPressed: () => widget.onNavigate(page),
          icon: const Icon(Icons.chevron_right),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
  Widget unavailable(String name, bool loaded, Widget content) =>
      model.errors[name] != null
      ? Text(model.errors[name]!)
      : loaded
      ? content
      : const Text('Resumen no disponible.');
  Widget metrics(List<(String, String)> values) => LayoutBuilder(
    builder: (context, c) {
      final cols =
          c.maxWidth >= 330 && MediaQuery.textScalerOf(context).scale(1) < 1.4
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final v in values)
            SizedBox(
              width: (c.maxWidth - 12 * (cols - 1)) / cols,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.$2, style: Theme.of(context).textTheme.titleLarge),
                    Text(v.$1),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  String money(dynamic value) {
    try {
      return Money.parse('$value', signed: true).display;
    } catch (_) {
      return 'No disponible';
    }
  }

  Future<void> openCash() async {
    if (widget.offline ||
        model.member == null ||
        model.inventory == null ||
        model.stock == null ||
        model.busy ||
        openingCash) {
      return;
    }
    setState(() => openingCash = true);
    try {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RxEntryScreen(
            title: 'Abrir turno de caja',
            fields: const [
              RxField(
                'opening',
                'Fondo inicial de efectivo MXN',
                required: true,
              ),
            ],
            submit: (data, op) async {
              try {
                await model.inventory!.write('inv_shift_open', {
                  'p_clinic': model.member!.clinicId,
                  'p_opening': Money.parse(data['opening']).decimal,
                  'p_operation': op,
                });
              } on FormatException {
                rethrow;
              } catch (_) {
                throw const FormatException(
                  'No se pudo abrir el turno. Actualiza y revisa conexión y permisos.',
                );
              }
            },
          ),
        ),
      );
      if (saved == true && mounted) await model.load(offline: widget.offline);
    } finally {
      if (mounted) setState(() => openingCash = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, ?widget.alerts]),
    builder: (context, _) {
      final m = model;
      final stats = m.statistics;
      final totals = m.dayTotals;
      final statisticsPanel = panel('Estadísticas', 'Estadísticas', [
        unavailable(
          'Estadísticas',
          stats != null,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ventas mensuales netas de devoluciones · MXN. No representan utilidad neta.',
              ),
              for (final s
                  in m
                      .rows(stats, 'sales')
                      .reversed
                      .take(widget.statisticsOnly ? 12 : 3))
                ListTile(
                  title: Text('${s['month']}'),
                  trailing: Text(money(s['amount'])),
                ),
              if (widget.statisticsOnly) ...[
                const Text('Citas no canceladas del mes por especie'),
                for (final s in m.rows(stats, 'species'))
                  ListTile(
                    title: Text('${s['species']}'),
                    trailing: Text('${s['count']}'),
                  ),
              ],
            ],
          ),
        ),
      ]);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.statisticsOnly
                      ? 'Estadísticas de la clínica'
                      : 'Resumen de tu espacio',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Actualizar resumen',
                onPressed: m.busy
                    ? null
                    : () => m.load(offline: widget.offline),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (widget.offline)
            const Text('Sin conexión: reconecta para consultar los resúmenes.'),
          if (m.member == null)
            const Text(
              'Conecta tu cuenta y elige una clínica para consultar sus datos.',
            ),
          if (m.member != null &&
              m.moduleAccess != null &&
              m.moduleAccess!.modules.values.every((enabled) => !enabled))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No tienes accesos habilitados a las áreas de este espacio. '
                'Revisa los permisos de tu cuenta con quien lo administra.',
              ),
            ),
          if (m.updated != null) Text('Última consulta: ${time(m.updated!)}'),
          if (m.busy) const LinearProgressIndicator(),
          if (navigationAllowed('Estadísticas', m.member, m.moduleAccess))
            statisticsPanel,
          if (!widget.statisticsOnly) ...[
            const SizedBox(height: 16),
            Text(
              'Módulos principales',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final columns = scale > 1.4
                    ? 1
                    : constraints.maxWidth >= 700
                    ? 4
                    : 2;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final action in <(String, String)>[
                      ('Inventario', 'Inventario'),
                      ('Estadísticas', 'Estadísticas'),
                      ('Recetas', 'Receta'),
                      ('Formatos', 'Formatos'),
                      ('Pacientes', 'Pacientes'),
                      ('Agenda', 'Agenda'),
                      ('Hospitalización', 'Hospitalización'),
                      ('Cálculo rápido', 'Cálculo rápido'),
                      ('Cálculos clínicos', 'Cálculos clínicos'),
                      ('Escáner', 'Escanear producto'),
                    ])
                      if (navigationAllowed(
                        action.$2,
                        m.member,
                        m.moduleAccess,
                      ))
                        SizedBox(
                          width: width,
                          child: WorkspacePanel(
                            child: InkWell(
                              onTap: () => widget.onNavigate(action.$2),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: sectionColor(
                                          action.$2,
                                        ).withValues(alpha: .20),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        sectionIcon(action.$2),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      action.$1,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
            panel(
              'Alertas y recordatorios',
              navigationAllowed('Hospitalización', m.member, m.moduleAccess)
                  ? 'Hospitalización'
                  : 'Agenda',
              [
                if (m.canSummarize('hospital'))
                  unavailable(
                    'Hospitalización',
                    m.ward != null,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${m.overdue.length} dosis pendientes cuyo horario ya llegó.',
                        ),
                        for (final t in m.overdue.take(3))
                          ListTile(
                            title: Text('${m.patient(t)} · ${t.label}'),
                            subtitle: Text(
                              'Horario: ${time(m.effectiveTime(t))}',
                            ),
                            onTap: () => widget.onNavigate('Hospitalización'),
                          ),
                      ],
                    ),
                  ),
                if (m.canSummarize('inventory') &&
                    widget.alerts?.stockWarnings != false)
                  unavailable(
                    'Inventario',
                    m.stock != null,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${m.lowStock.length} productos con stock disponible bajo o igual al mínimo.',
                        ),
                        for (final p in m.lowStock.take(3))
                          ListTile(
                            title: Text('${p['nombre']}'),
                            subtitle: Text(
                              'Disponible: ${p['available_stock']} · mínimo ${p['stock_minimo']}',
                            ),
                            onTap: () => widget.onNavigate('Inventario'),
                          ),
                      ],
                    ),
                  ),
                if (m.canSummarize('hospital') &&
                    (widget.alerts?.leadMinutes ?? 0) > 0)
                  for (final t
                      in m.nextDoses
                          .where(
                            (t) =>
                                m.effectiveTime(t).difference(m.now()) <=
                                Duration(minutes: widget.alerts!.leadMinutes),
                          )
                          .take(3))
                    ListTile(
                      title: Text(
                        'Próxima dosis · ${m.patient(t)} · ${t.label}',
                      ),
                      subtitle: Text(time(m.effectiveTime(t))),
                      onTap: () => widget.onNavigate('Hospitalización'),
                    ),
                if (navigationAllowed(
                  'Hospitalización',
                  m.member,
                  m.moduleAccess,
                ))
                  ExpansionTile(
                    title: const Text('Configurar avisos en este dispositivo'),
                    children: [
                      AlertPreferencesPanel(
                        alerts: widget.alerts,
                        onUpdated: () async {
                          final a = widget.alerts;
                          if (a?.scope != null && m.ward != null) {
                            await a!.reconcile(
                              '${m.member!.userId}:${m.member!.clinicId}:${m.member!.role.name}',
                              m.ward!.tasks,
                            );
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
            if (m.canSummarize('agenda')) ...[
              panel('Próximas citas de hoy', 'Agenda', [
                Text(
                  m.clinicTimezone == null
                      ? 'Día y horas del teléfono'
                      : 'Zona de la clínica: ${m.clinicTimezone}',
                ),
                unavailable(
                  'Agenda',
                  m.agenda != null,
                  Column(
                    children: [
                      if (m.todayAppointments.isEmpty)
                        const Text('No hay citas futuras agendadas para hoy.'),
                      for (final a in m.todayAppointments)
                        ListTile(
                          title: Text('${a['patient_name']}'),
                          subtitle: Text(
                            '${time(m.starts(a)!)} · ${a['kind']}',
                          ),
                          onTap: () => widget.onNavigate('Agenda'),
                        ),
                    ],
                  ),
                ),
              ]),
              panel('Citas recientes', 'Agenda', [
                unavailable(
                  'Agenda',
                  m.agenda != null,
                  Column(
                    children: [
                      if (m.recent.isEmpty)
                        const Text(
                          'No hay citas recientes en los datos consultados.',
                        ),
                      for (final a in m.recent.take(3))
                        ListTile(
                          title: Text('${a['patient_name']}'),
                          subtitle: Text(
                            '${time(m.starts(a)!)} · ${a['state']}',
                          ),
                          onTap: () => widget.onNavigate('Agenda'),
                        ),
                    ],
                  ),
                ),
              ]),
            ],
            if (m.canSummarize('inventory')) ...[
              panel('Inventario', 'Inventario', [
                unavailable(
                  'Inventario',
                  m.stock != null,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${m.products.length} artículos activos · ${m.lowStock.length} por revisar',
                      ),
                      if (m.canSeeClinicSales)
                        metrics([
                          (
                            'Valor a costo',
                            m.valueAtCost?.display ?? 'No disponible',
                          ),
                          (
                            'Valor a venta',
                            m.valueAtSale?.display ?? 'No disponible',
                          ),
                          (
                            'Margen potencial',
                            m.potentialMargin?.display ?? 'No disponible',
                          ),
                        ]),
                      const Text(
                        'Existencias disponibles por unidad; no incluye lotes caducados.',
                      ),
                      if (m.stockByUnit == null)
                        const Text('Existencias por unidad no disponibles.'),
                      for (final e
                          in (m.stockByUnit ?? <String, Quantity>{}).entries)
                        Text('${e.value.display()} ${e.key}'),
                      const Text(
                        'Margen potencial antes de comisiones y gastos; no es utilidad neta.',
                      ),
                      TextField(
                        controller: search,
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto por nombre o código',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (search.text.trim().isNotEmpty)
                        for (final p
                            in m.products
                                .where(
                                  (p) =>
                                      '${p['nombre']} ${p['codigo_barras'] ?? ''}'
                                          .toLowerCase()
                                          .contains(
                                            search.text.trim().toLowerCase(),
                                          ),
                                )
                                .take(5))
                          ListTile(
                            title: Text('${p['nombre']}'),
                            subtitle: Text(
                              'Disponible: ${p['available_stock']} ${p['stock_unit']}',
                            ),
                            onTap: () => widget.onNavigate('Inventario'),
                          ),
                    ],
                  ),
                ),
              ]),
              panel('Caja del turno', 'Caja', [
                unavailable(
                  'Inventario',
                  m.stock != null,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (m.ownShift == null) ...[
                        const Text(
                          'Tu caja está cerrada. Captura el fondo inicial al abrir.',
                        ),
                        FilledButton.icon(
                          onPressed: widget.offline || m.busy || openingCash
                              ? null
                              : openCash,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Abrir caja'),
                        ),
                      ] else ...[
                        Text(
                          'Tu caja está abierta · fondo inicial: ${money(m.ownShift!['opening_cash'])}',
                        ),
                        FilledButton(
                          onPressed: () => widget.onNavigate('Caja'),
                          child: const Text('Venta o revisión del turno'),
                        ),
                      ],
                      const Text('Últimos cortes visibles'),
                      if (m.recentCuts.isEmpty)
                        const Text(
                          'No hay cortes cerrados en los datos consultados.',
                        ),
                      for (final sh in m.recentCuts)
                        ListTile(
                          title: Text(
                            'Cierre: ${time(DateTime.parse(sh['closed_at']))}',
                          ),
                          subtitle: Text(
                            'Contado: ${money(sh['counted_cash'])}',
                          ),
                          onTap: () => widget.onNavigate('Caja'),
                        ),
                    ],
                  ),
                ),
              ]),
              if (m.canSeeClinicSales)
                panel('Ventas de hoy', 'Caja', [
                  unavailable(
                    'Inventario',
                    totals != null,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Día de la clínica: ${m.stock?['today'] ?? 'no disponible'}',
                        ),
                        metrics([
                          ('Ventas menos reversos', money(totals?['gross'])),
                          (
                            'Margen tras costos y comisiones',
                            money(totals?['margin']),
                          ),
                          (
                            'Resultado con gastos capturados',
                            money(totals?['recorded_net']),
                          ),
                        ]),
                        metrics([
                          (
                            'Ventas vigentes del día',
                            totals?['sale_count'] is int
                                ? '${totals!['sale_count']}'
                                : 'No disponible',
                          ),
                          (
                            'Ticket promedio de ventas vigentes',
                            totals?['average_ticket'] == null
                                ? 'No disponible'
                                : money(totals!['average_ticket']),
                          ),
                        ]),
                        for (final entry in [
                          ('Efectivo', 'cash'),
                          ('Tarjeta', 'card'),
                          ('Transferencia', 'transfer'),
                        ])
                          ListTile(
                            title: Text(entry.$1),
                            trailing: Text(money(totals?[entry.$2])),
                          ),
                        const Text(
                          'Importes netos de reversos. No acreditan que estén incluidos todos los gastos ni costos pendientes.',
                        ),
                      ],
                    ),
                  ),
                ]),
            ],
            if (m.canSummarize('hospital'))
              panel('Próximas dosis', 'Hospitalización', [
                unavailable(
                  'Hospitalización',
                  m.ward != null,
                  Column(
                    children: [
                      if (m.nextDoses.isEmpty)
                        const Text(
                          'No hay dosis futuras pendientes en los datos consultados.',
                        ),
                      for (final t in m.nextDoses.take(5))
                        ListTile(
                          title: Text('${m.patient(t)} · ${t.label}'),
                          subtitle: Text(time(m.effectiveTime(t))),
                          onTap: () => widget.onNavigate('Hospitalización'),
                        ),
                    ],
                  ),
                ),
              ]),
            if (m.member?.isPersonal == false)
              panel('Equipo y avisos', 'Equipo y avisos', [
                unavailable(
                  'Agenda',
                  m.agenda != null,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Pendientes del equipo'),
                      if (m.pendingTasks.isEmpty)
                        const Text('No hay pendientes visibles.'),
                      for (final t in m.pendingTasks.take(4))
                        ListTile(
                          title: Text('${t['title']} · ${t['priority']}'),
                          subtitle: Text(
                            t['assigned_to'] == null
                                ? 'Para el equipo'
                                : staffLabel(
                                    '${t['assigned_to']}',
                                    m.rows(m.agenda, 'people'),
                                  ),
                          ),
                          onTap: () =>
                              widget.onNavigate('Pendientes del equipo'),
                        ),
                      TextButton(
                        onPressed: () =>
                            widget.onNavigate('Pendientes del equipo'),
                        child: const Text('Crear o revisar pendientes'),
                      ),
                      const Text('Avisos recientes'),
                      if (m.messages.isEmpty)
                        const Text('No hay mensajes del equipo.'),
                      for (final msg in m.messages)
                        ListTile(
                          title: Text('${msg['category']} · ${msg['body']}'),
                          subtitle: Text(
                            '${staffLabel('${msg['author_id']}', m.rows(m.agenda, 'people'))} · ${time(DateTime.parse(msg['created_at']))}',
                          ),
                        ),
                      TextButton(
                        onPressed: () => widget.onNavigate('Equipo y avisos'),
                        child: const Text('Escribir aviso al equipo'),
                      ),
                    ],
                  ),
                ),
              ]),
          ],
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
