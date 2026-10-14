import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/domain/navigation_access.dart';
import 'dashboard_view_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.model,
    required this.onNavigate,
    this.offline = false,
    this.statisticsOnly = false,
  });
  final DashboardViewModel model;
  final ValueChanged<String> onNavigate;
  final bool offline, statisticsOnly;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardViewModel model = widget.model;
  Timer? timer;
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
    model.dispose();
    super.dispose();
  }

  String time(DateTime date) {
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget panel(String title, String page, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Abrir $title',
                onPressed: () => widget.onNavigate(page),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          ...children,
        ],
      ),
    ),
  );
  Widget unavailable(String name, bool loaded, Widget content) =>
      model.errors[name] != null
      ? Text(model.errors[name]!)
      : loaded
      ? content
      : const Text('Resumen no disponible.');
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final m = model;
      final stats = m.statistics;
      final statsPanel = panel('Estadísticas', 'Estadísticas', [
        unavailable(
          'Estadísticas',
          stats != null,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ventas mensuales netas de devoluciones · MXN'),
              const Text('Estos importes no representan utilidad neta.'),
              for (final row
                  in m
                      .rows(stats, 'sales')
                      .reversed
                      .take(widget.statisticsOnly ? 12 : 3))
                ListTile(
                  title: Text('${row['month']}'),
                  trailing: Text('\$${row['amount']}'),
                ),
              if (widget.statisticsOnly) ...[
                const Divider(),
                const Text('Citas no canceladas del mes por especie'),
                for (final row in m.rows(stats, 'species'))
                  ListTile(
                    title: Text('${row['species']}'),
                    trailing: Text('${row['count']}'),
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
          if (m.updated != null)
            Text(
              'Última consulta: ${time(m.updated!)} · Actualiza para ver cambios.',
            ),
          if (m.busy) const LinearProgressIndicator(),
          if (!widget.statisticsOnly) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in <(String, IconData, String)>[
                  ('Inventario', Icons.inventory_2_outlined, 'Inventario'),
                  ('Estadísticas', Icons.bar_chart, 'Estadísticas'),
                  ('Recetas', Icons.description_outlined, 'Receta'),
                  ('Formatos', Icons.folder_outlined, 'Formatos'),
                  ('Pacientes', Icons.pets, 'Pacientes'),
                  ('Agenda', Icons.calendar_month, 'Agenda'),
                  (
                    'Hospitalización',
                    Icons.local_hospital_outlined,
                    'Hospitalización',
                  ),
                  (
                    'Cálculo rápido',
                    Icons.calculate_outlined,
                    'Cálculo rápido',
                  ),
                ])
                  if (navigationAllowed(action.$3, m.member))
                    ActionChip(
                      avatar: Icon(action.$2),
                      label: Text(action.$1),
                      onPressed: () => widget.onNavigate(action.$3),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            panel(
              'Alertas',
              navigationAllowed('Hospitalización', m.member)
                  ? 'Hospitalización'
                  : 'Agenda',
              [
                if (navigationAllowed('Hospitalización', m.member))
                  unavailable(
                    'Hospitalización',
                    m.ward != null,
                    Text(
                      '${m.overdue.length} dosis pendientes cuyo horario ya llegó.',
                    ),
                  ),
                if (navigationAllowed('Inventario', m.member))
                  unavailable(
                    'Inventario',
                    m.stock != null,
                    Text(
                      '${m.lowStock.length} productos con stock disponible bajo o igual al mínimo.',
                    ),
                  ),
                for (final p in m.lowStock.take(3))
                  ListTile(
                    title: Text('${p['nombre']}'),
                    subtitle: Text(
                      'Disponible: ${p['available_stock']} · mínimo: ${p['stock_minimo']}',
                    ),
                    onTap: () => widget.onNavigate('Inventario'),
                  ),
              ],
            ),
            if (m.member?.role.name != 'estilista')
              panel('Pacientes', 'Pacientes', [
                unavailable(
                  'Pacientes',
                  m.patientCount != null,
                  Text('${m.patientCount} pacientes registrados.'),
                ),
              ]),
            if (navigationAllowed('Inventario', m.member))
              panel('Inventario', 'Inventario', [
                unavailable(
                  'Inventario',
                  m.stock != null,
                  Text(
                    '${m.products.length} productos activos · ${m.lowStock.length} por revisar.',
                  ),
                ),
              ]),
            panel('Próximas citas', 'Agenda', [
              unavailable(
                'Agenda',
                m.agenda != null,
                Column(
                  children: [
                    if (m.upcoming.isEmpty)
                      const Text(
                        'No hay citas futuras agendadas en los datos consultados.',
                      ),
                    for (final a in m.upcoming.take(5))
                      ListTile(
                        title: Text('${a['patient_name']}'),
                        subtitle: Text('${time(m.starts(a)!)} · ${a['kind']}'),
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
                        subtitle: Text('${time(m.starts(a)!)} · ${a['state']}'),
                        onTap: () => widget.onNavigate('Agenda'),
                      ),
                  ],
                ),
              ),
            ]),
            if (navigationAllowed('Hospitalización', m.member)) ...[
              panel('Hospitalización', 'Hospitalización', [
                unavailable(
                  'Hospitalización',
                  m.ward != null,
                  Text('${m.ward?.stays.length} pacientes hospitalizados.'),
                ),
              ]),
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
            ],
          ],
          if (navigationAllowed('Estadísticas', m.member)) statsPanel,
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
