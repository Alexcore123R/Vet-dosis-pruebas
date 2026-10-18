# VetDosis Pro — Design System v1 (propuesta de consolidación)

**Objetivo:** conservar las referencias de Stitch y transformar sus componentes a Flutter sin sustituir la funcionalidad existente. Este documento **no** afirma que las pantallas estén implementadas ni autoriza modificar Supabase o desplegar una beta.

## Jerarquía de fuentes
1. `ui_kit_neum_rfico_flat_botones_round_full.html`: componente base para tarjetas, controles, chips, botones y navegación.
2. `ui_kit_tokens_neum_rficos_oficiales (1).html`: paleta alternativa y reglas de neumorfismo; solo se incorporan los elementos no contradictorios con la base.
3. `dashboard_resumen_cl_nico_soft_neumorphism (1).html`: referencia de distribución del inicio, selector de práctica y tarjetas resumen.
4. `02._agenda_y_citas_cl_nicas_luminous_neumorphic.html`: distribución de agenda, filtros y tarjetas de citas.
5. `vetdosis_pro_logo.html`: contiene una cadena SVG codificada en Base64; tratarla como fuente vectorial, revisar antes de empaquetar.

## Tokens visuales
| Token | Valor | Uso |
|---|---|---|
| background | `#F1F4F8` | lienzo principal |
| surface | `#F7F9FC` | tarjetas |
| raised | `#FFFFFF` | controles elevados |
| shadowLight | `#DDE4EE` | relieve neumórfico |
| textPrimary | `#0B1C30` | títulos y texto sobre claros |
| textSecondary | `#64748B` | texto secundario, revisar contraste en tamaño pequeño |
| turquoise | `#28D7D1` | acción/selección, con texto oscuro cuando lo exija contraste |
| cyan | `#49DFF0` | acento |
| mint | `#61E2D0` | acento |
| lavender | `#C8B5F6` | acento suave |
| lilac | `#AE92F3` | acento |
| violet | `#7D7AF2` | acento |
| purple | `#7C4DFF` | selección y acciones secundarias |
| purpleDeep | `#632CE5` | gradientes puntuales |
| pink | `#FF4FB3` | acento de marca, **no** codificar peligros clínicos solo por estética |

**Restricciones:** nada de verde esmeralda oscuro como color global; no introducir paletas nuevas por pantalla. Tipografía de referencia: Plus Jakarta Sans con alternativas del sistema. Contraste WCAG AA y dianas táctiles >=48 dp deben verificarse por componente: los colores decorativos no necesariamente sirven como color de texto.

## Componentes base Flutter (crear con nombres consistentes)
- `VetSurfaceCard`: tarjeta clara de relieve suave con alternativa compacta.
- `VetActionButton`: primary gradient, secondary solid, neutral outline, destructive con color semántico.
- `VetIconTile`: acceso a módulo (icono + título + subtítulo opcional).
- `VetFilterChip` y `VetSegmentedControl`.
- `VetInput`: campo en relieve interno, con validación y teclado contextual.
- `VetBadge`: estado semántico con texto además del color.
- `VetPracticeSelector`: Pequeñas especies / Exóticos / Grandes especies–Producción.
- `VetWorkspaceHeader`: espacio activo, usuario y notificaciones; título profesional solo si habilitación verificada.
- `VetBottomNavigation`: definir destinos en función de jerarquía y pruebas de usabilidad; no fijar seis pestañas sin revisión.
- `VetEmptyState`, `VetLoadingState`, `VetErrorState`, `VetPermissionDenied`.

## Reglas de funcionamiento
- **Ámbito:** el selector de práctica cambia opciones especializadas; el espacio de trabajo determina de quién son los datos; los permisos autorizan acciones. No son el mismo filtro.
- **RLS y servidor:** ocultar botones no sustituye autorización en Supabase.
- **No inventar datos clínicos:** dosis, pautas, contraindicaciones, normas y estados de paciente deben provenir de datos verificados o ser DEMOSTRACIÓN claramente identificada.
- **Accesibilidad:** no usar color como única señal; valores y textos deben ser legibles, en especial en mini-tarjetas y gráficos.
- **Estados:** diseño para vacío, sin conexión, cargando, permiso denegado, error, acceso beta caducado.
- **Android:** eliminar barras de estado iOS simuladas; utilizar el sistema operativo real. Fuentes y SVG deben incorporarse como recursos locales/licenciados, sin CDN para tiempo de ejecución.

## Orden de integración seguro
1. Tomar captura/código del tema Flutter actual y comparar tokens; no sobrescribir `lib/core/app.dart` sin coordinación con 6.1.
2. Implementar tokens y componentes en una rama de diseño separada sin cambiar RPC, permisos o backend.
3. Crear una pantalla de catálogo de componentes (debug-only) con estados interactivos y prueba de tamaños distintos.
4. Migrar **Inicio** como piloto; comparar contra HTML de Dashboard y APK actual. Reusar el selector de práctica.
5. Migrar **Agenda** con pruebas de navegación, carga y estados; no sustituir la lógica existente de citas.
6. Después: pacientes, cálculos, hospitalización, vademécum y los módulos de administración.
7. Revisar Flutter analyze/tests, capturas en Android real y accesibilidad antes de integrar con main.

## Inventario de decisiones pendientes
- Confirmar la jerarquía exacta de la barra inferior y el menú contextual.
- Definir estados semánticos (éxito, advertencia y peligro) separados de la paleta de marca.
- Elegir cuáles gradientes y sombras se permiten en pantallas densas.
- Resolver variantes de pantalla oscura por separado; el conmutador visual del HTML no implica soporte real.
- Auditar módulos prometidos frente a funcionalidades Flutter y Supabase antes de rotularlos como activos.

## Nota de traspaso a 6.1 / Codex
> Usar estos HTML como referencias, NO pegar HTML ni Tailwind dentro de Flutter. Primero presentar inventario del tema actual y plan de cambios por archivos, y esperar aprobación antes de editar pantallas integradas. El trabajo de Storage/IA y controles beta queda fuera de este alcance visual.
