# Primera etapa de secciones y navegación

Láminas Flutter a 390×1300, con cuenta y clínica sintéticas identificadas como DEMO.
No hay consultas a Supabase ni capturas de Android real. Fuente de previsualización:
DejaVu Sans local bajo nombre Roboto, igual que en los pilotos anteriores.

- `mas.png`: menú agrupado; Administración y finanzas abierta. Planeación financiera
  está identificada como «En preparación», sin callback ni formulario simulado.
- `produccion.png`: los siete grupos de especies y su estado.
- `aves.png`: Postura seleccionada, con enlace al módulo de instalaciones existente.

Reproducir: `flutter test test/previews/capture_section_navigation.dart`.
Las rutas de herramientas avícolas y sus restricciones se prueban en
`test/section_navigation_test.dart`. Los registros productivos específicos y la
planeación financiera aún no están implementados. La barra inferior se adapta a
los destinos disponibles para la cuenta; las vistas muestran el fixture administrador.
