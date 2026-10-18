import 'package:flutter/material.dart';
import '../../aviculture/presentation/aviculture_screen.dart';
import '../../incubation/presentation/incubation_screen.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../core/domain/module_access.dart';
import '../../core/domain/navigation_access.dart';

const productionSpecies = <String, List<String>>{
  'Bovinos': [
    'Leche',
    'Carne y engorda',
    'Doble propósito',
    'Atención individual',
  ],
  'Ovinos / caprinos': ['Ovinos', 'Caprinos'],
  'Aves': ['Postura', 'Engorda', 'Reproducción e incubación'],
  'Peces': ['Tilapia'],
  'Abejas': ['Apiarios y colmenas'],
  'Porcinos': [
    'Reproducción y gestación',
    'Maternidad y destete',
    'Crecimiento y engorda',
  ],
  'Equinos': ['Atención individual', 'Reproducción y crianza'],
};

const plannedProductionAreas = <String, List<String>>{
  'Bovinos': [
    'Animales y hatos/lotes',
    'Reproducción y alimentación',
    'Indicadores por unidad',
  ],
  'Ovinos / caprinos': [
    'Animales y rebaños',
    'Carne, leche y fibra según actividad',
    'Reproducción y alimentación',
  ],
  'Aves': [
    'Parvadas, casetas y ciclos',
    'Registros productivos',
    'Alimentación y seguimiento',
  ],
  'Peces': [
    'Lotes y unidades de cultivo',
    'Calidad del agua y alimentación',
    'Biomasa y ciclos',
  ],
  'Abejas': [
    'Apiarios y colmenas',
    'Revisiones y sanidad',
    'Cosechas y seguimiento',
  ],
  'Porcinos': [
    'Reproductores y servicios',
    'Camadas y alimentación',
    'Engorda e indicadores',
  ],
  'Equinos': ['Atención y seguimiento individual', 'Reproducción y crianza'],
};

/// Catalog and existing local tools only. No farm records or operating limits
/// are created by selecting a species/activity.
class ProductionMenu extends StatefulWidget {
  const ProductionMenu({
    super.key,
    required this.onNavigate,
    this.member,
    this.access,
  });
  final ValueChanged<String> onNavigate;
  final ClinicMembership? member;
  final ModuleAccess? access;
  @override
  State<ProductionMenu> createState() => _ProductionMenuState();
}

class _ProductionMenuState extends State<ProductionMenu> {
  String? species, activity;
  bool allowed(String page) =>
      navigationAllowed(page, widget.member, widget.access);
  Future<void> open(Widget screen) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Producción y grandes especies',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      if (species == null) ...[
        const Text(
          'Elige una especie o grupo. La clínica y tus permisos se conservan.',
        ),
        const SizedBox(height: 12),
        for (final entry in productionSpecies.entries)
          ListTile(
            title: Text(entry.key),
            subtitle: Text(
              entry.key == 'Aves'
                  ? 'Herramientas de capacidad e incubación disponibles según acceso'
                  : 'Organización de actividades · registros específicos en preparación',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              species = entry.key;
              activity = null;
            }),
          ),
      ] else ...[
        TextButton.icon(
          onPressed: () => setState(() {
            species = null;
            activity = null;
          }),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver a especies'),
        ),
        Text(species!, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in productionSpecies[species]!)
              ChoiceChip(
                label: Text(name),
                selected: activity == name,
                onSelected: (_) => setState(() => activity = name),
              ),
          ],
        ),
        if (species == 'Aves' && activity != null) ...[
          const SizedBox(height: 16),
          if (allowed('Cálculos clínicos') && activity == 'Postura')
            OutlinedButton.icon(
              icon: const Icon(Icons.agriculture_outlined),
              label: const Text('Capacidad e instalaciones avícolas'),
              onPressed: () => open(const AvicultureScreen()),
            ),
          if (allowed('Cálculos clínicos') &&
              activity == 'Reproducción e incubación')
            OutlinedButton.icon(
              icon: const Icon(Icons.egg_outlined),
              label: const Text('Abrir herramientas de incubación'),
              onPressed: () => open(const IncubationScreen()),
            ),
          if (!allowed('Cálculos clínicos'))
            const Text(
              'Las calculadoras no están habilitadas para tu acceso actual.',
            ),
          if (activity == 'Engorda')
            const Text(
              'Las herramientas específicas de engorda están en preparación. Las tablas actuales de postura no se aplican automáticamente a engorda.',
            ),
          if (activity != 'Engorda')
            const Text(
              'Las herramientas conservan sus referencias y avisos de datos sin verificar.',
            ),
        ],
        const SizedBox(height: 20),
        Text(
          'Apartados previstos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Estos registros específicos están en preparación; aún no permiten guardar datos de unidades o lotes.',
        ),
        for (final name in plannedProductionAreas[species]!)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(name),
            subtitle: const Text('En preparación'),
          ),
        const SizedBox(height: 16),
        Text(
          'Herramientas del espacio',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Abren los registros actuales de tu espacio; todavía no aplican un filtro por la especie seleccionada.',
        ),
        for (final (label, page) in [
          ('Pacientes individuales', 'Pacientes'),
          ('Agenda del espacio', 'Agenda'),
          ('Inventario del espacio', 'Inventario'),
        ])
          if (allowed(page))
            TextButton(
              onPressed: () => widget.onNavigate(page),
              child: Text(label),
            ),
      ],
    ],
  );
}
