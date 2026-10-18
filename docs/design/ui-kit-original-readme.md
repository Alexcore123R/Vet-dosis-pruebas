# VetDosis Pro — UI Flutter, entrega para integración 6.1

**Estado:** componentes Dart de referencia funcionales como widgets. **No se han compilado** en este entorno (Flutter/Dart no instalados). No se integraron al repositorio remoto ni se cambió ningún dato/Supabase. Requiere revisión con el SDK y versión Flutter del proyecto.

## Contenido

- `lib/vet_ui/vet_theme.dart`: paleta y tema Flutter Material 3.
- `lib/vet_ui/vet_components.dart`: `VetCard`, `VetActionButton`, `VetStatusBadge`, `VetModuleTile`, `VetPracticeSelector`, `VetKpiCard`.
- `lib/vet_ui/vet_shell.dart`: `VetBottomNav` (5 destinos) y `VetWorkspaceHeader`.
- `lib/vet_ui.dart`: exportaciones.
- `lib/demo/vet_visual_demo.dart`: pantalla demostrativa con datos **NO REALES**.
- `example/main.dart`: arranque de referencia de la demostración (no reemplazar el `main.dart` del proyecto).

## Integración en el repo existente

1. Trabajar en rama independiente, auditar tema, router, navegación y widgets existentes; NO sobrescribirlos a ciegas.
2. Copiar `lib/vet_ui/` y `lib/vet_ui.dart` al `lib/` del proyecto; opcionalmente copiar `lib/demo/vet_visual_demo.dart`.
3. Fusionar `VetTheme.light()` con el tema actual sin anular localización ni rutas.
4. Conectar callbacks a rutas/permisos **existentes**. Los callbacks demostrativos de la galería no son acciones de producción.
5. Respetar roles, permisos, espacios y habilitaciones profesionales existentes. El selector de práctica no concede permisos ni cambia la propiedad de los datos.
6. Ejecutar `dart format lib/vet_ui lib/vet_ui.dart lib/demo/vet_visual_demo.dart` y `flutter analyze` / `flutter test` dentro del repo.
7. Integrar Inicio y después Agenda conservando su lógica ya funcional. Comparar UI Android y hacer pruebas de regresión.

## Aclaraciones

- Los tonos oficiales provienen de los HTML de Stitch. Se usan aquí `Color` constantes, sin CSS, Tailwind ni dependencias CDN.
- La fuente Plus Jakarta Sans requiere incorporarla legalmente en el proyecto y configurar `pubspec.yaml` si se desea idéntica a Stitch. El kit usa fuente sistema como fallback.
- El logo horizontal HTML trae SVG codificado como Base64; este paquete **no lo incrusta**, ni inventa un icono oficial nuevo. Añadir recursos aprobados al repo.
- El selector de producción ofrece por ahora solo el ámbito general; los subtipos productivos requieren navegación contextual según permisos y datos.
- La navegación de prueba muestra cinco destinos y no es un router. El proyecto anfitrión debe aportar sus rutas y su estado.
- No usar números ficticios de dashboard, dosis farmacológicas, títulos profesionales o estados médicos en la interfaz real.
- Alerta: `.withValues(alpha: ...)` requiere una versión relativamente reciente de Flutter. Si la versión del repo es anterior, reemplazar por `.withOpacity(...)` o adaptar el código.
