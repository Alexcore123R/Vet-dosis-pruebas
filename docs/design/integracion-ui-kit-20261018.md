# Integración del UI Kit — Inicio y Agenda

## Inventario previo

- Proyecto: Dart >=3.10.0 <4.0.0, Flutter >=3.38.1; CI y revisión local con
  Flutter 3.47.6 / Dart 3.13.5. No se actualizan dependencias.
- `lib/core/app.dart` construye Material 3, localización es-MX, cinco paletas,
  preferencias claro/oscuro y estilo Neu. También contiene navegación y controles
  de acceso; deben conservarse.
- `WorkspacePanel` ya implementa tarjetas con relieve en Neu y Material estándar
  en las demás paletas. Se conserva su API para evitar migraciones de pantallas.
- Inicio usa DashboardViewModel y fuentes reales con permisos, estados vacíos,
  errores, resumen de caja, preferencias de alertas y accesos filtrados.
- Agenda es una sección de OperationsScreen; conserva capturas, validación de
  tiempos, selección del paciente, reprogramación, estados y permisos existentes.
- ZIP de GPT-6: tema, seis componentes, encabezado y navegación demostrativa.
  No contiene backend. La demo y example/main.dart no se incorporan al arranque.

## Adaptación y alcance por archivo

1. `lib/vet_ui/` y exportación: importar componentes, adaptar botones a Material
   para foco/teclado/estados deshabilitados y colores al tema anfitrión. El texto
   secundario y estados deben seguir siendo legibles en oscuro.
2. `test/vet_ui_test.dart`: validar 320 px, texto 200%, claro/oscuro y acciones
   deshabilitadas antes de aplicar componentes a las pantallas.
3. `lib/core/app.dart`: reutilizar tokens solo en Neu y conservar el resto de
   paletas, oscuridad, localización, navegación y autorización.
4. `lib/core/widgets/workspace_panel.dart`: reutilizar VetCard en Neu con la
   interfaz actual, sin cambiar las fuentes de datos de sus consumidores.
5. Inicio: accesos compactos con callbacks y filtros actuales; identidad de marca
   local, sin inventar saludo, puesto, cifras ni notificaciones.
6. Agenda: encabezado, acción, calendario y tarjetas de citas usando componentes;
   conservar formularios y flujo de operaciones. Estado vacío explícito.
7. Validar análisis completo y todas las pruebas después de integrar. Mantener
   pendiente inspección visual en teléfono Android y aprobación visual.

La petición de la usuaria autoriza esta integración visual. La guía adjunta pide
esperar aprobación antes de editar pantallas: esta autorización ya está expresada
por la usuaria en su solicitud de integrar Inicio y Agenda tras comprobar el kit.
No se modifica Supabase, RPC, permisos, firmas clínicas ni caducidad de beta.

## Recursos de marca

Se conservan el PNG con transparencia (250×120), el SVG decodificado del archivo
llamado HTML y el JPG original del icono (1280×1280). No se ejecuta HTML ni se
introducen CDN, fuentes externas o dependencias SVG. El PNG sirve como logo local;
el JPG queda como referencia de launcher, cuyo tratamiento adaptativo se revisará
por separado. No se sustituye el logo de cada clínica por la marca de la app.

## Navegación

La barra inferior del ZIP es una referencia de cinco destinos, no un router. Esta
ronda conserva la navegación existente y su filtrado. El selector de práctica del
ZIP solo contiene tres ámbitos, mientras el proyecto tiene además gestión; no
reemplaza al selector existente ni cambia los permisos al elegir otra rama.

## Validación realizada

- Antes de editar Inicio y Agenda: análisis sin incidencias y 36 pruebas aprobadas
  (kit, dashboard, navegación, agenda y Neu).
- La primera integración detectó que VetCard ocultaba la tinta de ListTile.
  Se corrigió añadiendo Material dentro de la superficie y se añadió interacción
  con ListTile a la regresión del kit; no se desactivó la comprobación de Flutter.
- Resultado final: `flutter analyze` sin incidencias y `flutter test --timeout 5m`
  con **373 pruebas aprobadas**.
- 17 comprobaciones adicionales de capturas, navegación móvil y agenda, y dos
  pruebas de tarjeta/botones en claro/oscuro aprobadas después de los ajustes.
- Tamaño 320 px y texto 200% cubiertos por pruebas de kit y agenda.
- Cuatro vistas en `review/ui-kit-20261018/`; su README explica los datos vacíos,
  el contenedor de Agenda y la fuente de previsualización. No son Android real.
- Flutter 3.47.6 / Dart 3.13.5 verificados localmente. Sin cambios de dependencias
  ni pubspec.lock; pubspec.yaml solo declara el directorio de marca.

El piloto aplica colorido nuevo al estilo Neu; otras paletas y sus preferencias
se mantienen. Inicio usa el logo PNG como marca de aplicación y conserva la
identidad de clínica. No se activan demo, navegación de cinco destinos, nuevos
indicadores, calendarios semana/día, avisos sin fuente o funciones futuras de la
guía. El calendario real existente conserva sus filtros y validaciones.

## Pendientes y entrega

Rama `design/ui-kit-home-agenda`, preparada para revisión del piloto antes de
combinar con main. El APK 39124259241 corresponde al código anterior, no a este
diseño. Faltan revisión en Android y APK de esta rama; tampoco se cambió el icono
de launcher ni se incorporaron los cuatro HTML de Stitch citados en las guías,
que no llegaron en este lote. Las guías se conservan como propuestas, no como
lista de funciones terminadas.
