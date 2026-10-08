import 'package:flutter/material.dart';

const productTools = <(String, String, String)>[
  (
    'Cálculos y dosis',
    'Peso, especie y presentación; cálculos separados de la interfaz.',
    'Cálculo rápido',
  ),
  (
    'Pacientes y expedientes',
    'Historia clínica, peso y seguimiento del paciente.',
    'Pacientes',
  ),
  (
    'Hospitalización',
    'Tratamientos, responsables y avisos programados.',
    'Hospitalización',
  ),
  (
    'Formatos y recetas',
    'Plantillas por clínica, firma y PDF para revisión.',
    'Formatos',
  ),
  (
    'Inventario y caja',
    'Lotes, caducidades, ventas y pagos manuales.',
    'Inventario',
  ),
  (
    'Agenda y equipo',
    'Citas, estética, servicios y organización por permisos.',
    'Agenda',
  ),
  (
    'Asistente IA',
    'Ayuda de uso incluida por temas; chat con proveedor propio, historial y contexto optativos.',
    'Asistente IA',
  ),
  (
    'Respaldo y reportes',
    'Exportación operacional y estadísticas por permisos.',
    'Estadísticas y respaldo',
  ),
];

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, this.onNavigate});
  final void Function(String)? onNavigate;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('VetDosis Pro', style: Theme.of(context).textTheme.headlineLarge),
      const Text('Tu trabajo veterinario, organizado en un mismo espacio.'),
      const SizedBox(height: 16),
      const Text(
        'Para México, en Android, iPhone y navegador. Trabaja de forma individual o con tu clínica, con acceso según el rol de cada integrante.',
      ),
      for (final tool in productTools)
        Card(
          child: ListTile(
            title: Text(tool.$1),
            subtitle: Text(tool.$2),
            trailing: onNavigate == null
                ? null
                : const Icon(Icons.chevron_right),
            onTap: onNavigate == null ? null : () => onNavigate!(tool.$3),
          ),
        ),
      Text('Planes y costos', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Propuesta de lanzamiento · MXN · cobros aún desactivados'),
      const Card(
        child: ListTile(
          title: Text('Gratis · \$0'),
          subtitle: Text(
            'Espacio personal · 50 pacientes · 250 MiB · 5 intentos IA/día',
          ),
        ),
      ),
      const Card(
        child: ListTile(
          title: Text('Individual · \$199/mes o \$1,990/año'),
          subtitle: Text(
            'Espacio propio · 5,000 pacientes · 2 GiB · 200 intentos IA/día. Ventas y cierre de caja manual sin conectar una pasarela.',
          ),
        ),
      ),
      const Card(
        child: ListTile(
          title: Text('Clínica · \$799/mes o \$7,990/año'),
          subtitle: Text(
            'Todos sus integrantes · 50,000 pacientes · 10 GiB · 1,000 intentos IA/día compartidos.',
          ),
        ),
      ),
      const Text(
        'Beta y regalos: beneficios temporales. El consumo de IA con clave propia depende del proveedor. La ayuda incluida tiene cupo separado y necesita activación. El anual equivale a diez mensualidades. Límites y precios sujetos a revisión antes de publicar.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Estado de lanzamiento: implementación local en pruebas. Conexión y pruebas reales de Supabase, dispositivos y servicios externos pendientes. El catálogo clínico necesita referencias verificadas; las respuestas de IA requieren revisión profesional. OCR, dictado y automatización de WhatsApp/Drive siguen pendientes.',
      ),
      if (onNavigate != null)
        FilledButton(
          onPressed: () => onNavigate!('Planes'),
          child: const Text('Ver mi plan y pagos'),
        ),
    ],
  );
}
