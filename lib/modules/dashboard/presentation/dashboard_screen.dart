import '../../../core/widgets/neu_header_card.dart';
import 'home_pilot.dart';
import '../../../vet_ui/vet_components.dart';
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
    this.homePilot = false,
    this.alerts,
  });
  final DashboardViewModel model;
  final ValueChanged<String> onNavigate;
  final bool offline, statisticsOnly, homePilot;
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

  List<(String, int)>? get activity {
    if (model.member == null ||
        !model.canSummarize('agenda') ||
        model.agenda == null) {
      return null;
    }
    final local = model.localTime(model.now());
    final today = DateTime.utc(local.year, local.month, local.day);
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      final count = model.rows(model.agenda, 'appointments').where((row) {
        final date = model.starts(row);
        if (date == null || row['state'] == 'cancelado') return false;
        return DateUtils.isSameDay(model.localTime(date), day);
      }).length;
      return (labels[day.weekday - 1], count);
    });
  }

  List<(String, String, IconData)> get summaryMetrics => [
    if (model.member != null && model.canSeePatients)
      ('Pacientes', model.patientCount?.toString() ?? '—', Icons.pets_outlined),
    if (model.member != null && model.canSummarize('agenda'))
      (
        'Citas por venir',
        model.agenda == null ? '—' : '${model.upcoming.length}',
        Icons.calendar_month_outlined,
      ),
    if (model.member != null && model.canSummarize('hospital'))
      (
        'En hospital',
        model.ward == null ? '—' : '${model.ward!.stays.length}',
        Icons.local_hospital_outlined,
      ),
    if (model.member != null &&
        !model.member!.isPersonal &&
        model.canSummarize('agenda'))
      (
        'Tareas visibles',
        model.agenda == null ? '—' : '${model.pendingTasks.length}',
        Icons.task_alt,
      ),
  ];

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
          if (widget.statisticsOnly &&
              navigationAllowed('Estadísticas', m.member, m.moduleAccess))
            statisticsPanel,
          if (widget.homePilot && !widget.statisticsOnly) ...[
            const SizedBox(height: 16),
            HomeSummary(metrics: summaryMetrics, activity: activity),
          ],
          if (!widget.homePilot &&
              !widget.statisticsOnly &&
              navigationAllowed('Estadísticas', m.member, m.moduleAccess))
            statisticsPanel,
          if (!widget.statisticsOnly) ...[
            const SizedBox(height: 16),
            if (widget.homePilot) ...[
              Text(
                'Módulos principales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              HomeModuleGrid(
                actions: [
                  for (final action in <(String, String)>[
                    ('Inventario', 'Inventario'),
                    ('Pacientes', 'Pacientes'),
                    ('Recetas', 'Receta'),
                    ('Agenda', 'Agenda'),
                    ('Cálculo rápido', 'Cálculo rápido'),
                    ('Hospital', 'Hospitalización'),
                  ])
                    if (navigationAllowed(action.$2, m.member, m.moduleAccess))
                      action,
                ],
                onNavigate: widget.onNavigate,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in <(String, String)>[
                    ('Formatos', 'Formatos'),
                    ('Estadísticas', 'Estadísticas'),
                    ('Cálculos clínicos', 'Cálculos clínicos'),
                    ('Escáner', 'Escanear producto'),
                  ])
                    if (navigationAllowed(action.$2, m.member, m.moduleAccess))
                      OutlinedButton.icon(
                        onPressed: () => widget.onNavigate(action.$2),
                        icon: Icon(sectionIcon(action.$2)),
                        label: Text(action.$1),
                      ),
                ],
              ),
              const SizedBox(height: 16),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                    if (navigationAllowed(action.$2, m.member, m.moduleAccess))
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width - 48,
                        ),
                        child: VetActionButton(
                          label: action.$1,
                          icon: sectionIcon(action.$2),
                          style: VetActionStyle.neutral,
                          onPressed: () => widget.onNavigate(action.$2),
                        ),
                      ),
                ],
              ),
            if (widget.homePilot &&
                navigationAllowed('Estadísticas', m.member, m.moduleAccess))
              ExpansionTile(
                title: const Text('Ver estadísticas'),
                children: [statisticsPanel],
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
            if (m.member != null && m.commissions != null)
              panel('Mis comisiones', 'Servicios', [
                Text(
                  'Saldo de servicios cobrados pendiente de liquidar: ${money(m.ownCommission?['amount'] ?? '0')}',
                ),
                if (m.commissions?['schedule'] is Map)
                  Text(
                    'Próximo pago: ${(m.commissions!['schedule'] as Map)['next_pay_on']}',
                  ),
                const Text(
                  'El porcentaje se configura por servicio. Solo cuentan ventas vigentes.',
                ),
              ]),
            if (m.member?.isPersonal == false && m.attendanceWeek != null)
              panel('Puntualidad y asistencia', 'Checado', [
                if (m.attendanceWeek!['week_summary'] is Map) ...[
                  Text(
                    'Semana desde ${(m.attendanceWeek!['week_summary'] as Map)['week_start']}',
                  ),
                  Text(
                    'Asistencias registradas: ${(m.attendanceWeek!['week_summary'] as Map)['attended']}',
                  ),
                  if ((m.attendanceWeek!['week_summary']
                          as Map)['configured'] ==
                      true)
                    Text(
                      'A tiempo: ${(m.attendanceWeek!['week_summary'] as Map)['on_time']} · Retrasos: ${(m.attendanceWeek!['week_summary'] as Map)['late']}',
                    )
                  else
                    const Text(
                      'La clínica aún no configuró un horario para medir retrasos.',
                    ),
                  const Text(
                    'Administración ve el total del equipo; cada integrante ve sus propios registros.',
                  ),
                ],
              ]),
            if (m.member?.isPersonal == false &&
                (m.agenda?['sections'] as Map?)?['tasks'] == true)
              panel('Tareas de hoy', 'Pendientes del equipo', [
                unavailable(
                  'Agenda',
                  m.agenda != null,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (m.todayTasks.isEmpty)
                        const Text('No hay tareas programadas para hoy.'),
                      for (final t in m.todayTasks.take(4))
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
                    ],
                  ),
                ),
              ]),
            if (m.member?.isPersonal == false &&
                (m.agenda?['sections'] as Map?)?['messages'] == true)
              panel('Anuncios y avisos', 'Anuncios y avisos', [
                unavailable(
                  'Agenda',
                  m.agenda != null,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (m.notices.isEmpty)
                        const Text('No hay avisos recientes.'),
                      for (final msg in m.notices)
                        ListTile(
                          title: Text('${msg['category']} · ${msg['body']}'),
                          subtitle: Text(
                            '${staffLabel('${msg['author_id']}', m.rows(m.agenda, 'people'))} · ${time(DateTime.parse(msg['created_at']))}',
                          ),
                        ),
                      TextButton(
                        onPressed: () => widget.onNavigate('Anuncios y avisos'),
                        child: const Text('Ver avisos'),
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
