# VetDosis Pro — Guía integrada de diseño visual y organización v2

**Fecha:** 18 de octubre de 2026  
**Estado:** propuesta integral de diseño y navegación, NO implementación funcional.  
**Alcance:** consolidar las referencias HTML de Stitch y las propuestas trabajadas en la conversación para un futuro desarrollo Flutter/Android. Ninguna sección futura se debe mostrar como funcional sin comprobarla.

## 1. Decisión editorial: una aplicación, no cinco estilos

**Fuente visual predominante:** `ui_kit_neum_rfico_flat_botones_round_full.html` (componentes híbridos de neumorfismo sutil y bordes definidos; botones totalmente redondeados). **Complementos:** `ui_kit_tokens_neum_rficos_oficiales (1).html` (acentos pastel y estados), `dashboard_resumen_cl_nico_soft_neumorphism (1).html` (jerarquía de Inicio), `02._agenda_y_citas_cl_nicas_luminous_neumorphic.html` (calendario y tarjetas de cita). `vetdosis_pro_logo.html` es un SVG codificado en Base64, no un archivo HTML de UI navegable. El **icono de aplicación aprobado en la conversación** es una referencia de marca distinta del logotipo horizontal; conservarlo y obtener su recurso original antes de incorporarlo.

Se integran las ideas que discutimos, no todo elemento accidental de cada maqueta. En particular, se descartan las barras de estado iOS falsas, títulos ficticios de profesión, datos clínicos sin validar, acciones simuladas presentadas como reales y cambios independientes de paleta por pantalla.

## 2. Lenguaje visual congelado

| Token Flutter propuesto | Hex | Propósito |
|---|---|---|
| `canvas` | `#F1F4F8` | Fondo general gris perla azulado |
| `surface` | `#F7F9FC` | Tarjetas y paneles |
| `raised` | `#FFFFFF` | Controles elevados |
| `recessed` | `#EDF2F7` | Campos e interiores |
| `shadow` | `#DDE4EE` | Sombra suave de relieve |
| `ink` | `#0B1C30` | Texto principal |
| `inkSecondary` | `#64748B` | Texto secundario |
| `turquoise` | `#28D7D1` | Marca y selección contextual |
| `cyan` | `#49DFF0` | Iluminación/acento |
| `mint` | `#61E2D0` | Acento positivo/ambiental, NO única señal semántica |
| `lavender` | `#C8B5F6` | Superficies de acento suaves |
| `lilac` | `#AE92F3` | Acento secundario |
| `violet` | `#7D7AF2` | Diferenciación de módulos |
| `purpleAction` | `#7C4DFF` | Acciones destacadas y selección fuerte |
| `purpleDeep` | `#632CE5` | Gradiente restringido |
| `pink` | `#FF4FB3` | Rosa luminoso de marca, acentos y microdetalles |

**Tipografía:** Plus Jakarta Sans (con licencia/recurso local en Flutter), con alternativa sans del sistema. Títulos legibles, cuerpo ~14–16sp, ayudas 12–14sp cuando sea posible; los textos de 8–10 px de Stitch no se trasladan literalmente a pantallas operativas. **Interacción:** objetivos táctiles >= 48dp, foco/selección visibles, navegación accesible, contraste verificable y tamaños adaptables. El color nunca es la única codificación de estados clínicos o financieros. Alertas críticas, errores y peligros usan tokens semánticos dedicados, no rosa decorativo por defecto.

**Profundidad visual:** relieve neumórfico ligero únicamente en tarjetas principales, selector, campos y acciones; no apilar tres niveles de sombra. Superficies preferentemente claras, bordes finos y radios consistentes: tarjetas grandes 24dp, tarjetas menores 16–20dp, controles 14–18dp, botón primario de píldora. Gradientes violeta→turquesa solo en acciones principales y ciertos detalles de marca, nunca como fondo dominante de listas clínicas densas. Sin verde esmeralda oscuro como fondo de la aplicación.

**Iconografía:** coherente, de trazo redondeado y peso uniforme. El icono de app aprobado (huella + pulso) como identidad; preparar variante simplificada para notificaciones y tamaños reducidos. No usar dibujos SVG de muestra como si todos fueran iconos definitivos.

## 3. Estructura de navegación — tres ejes separados

### Eje A: cuenta y espacio de trabajo

1. Inicio de sesión / perfil de cuenta.
2. Selector de **espacio de trabajo**: personal o clínica/sucursal a la que pertenece el usuario.
3. Dentro del espacio: mostrar datos, equipos, pacientes, almacenes y finanzas que correspondan a ese espacio.
4. Permisos de operación independientes de **autorización profesional clínica**; administrador de la plataforma no equivale a director ni profesional autorizado de una clínica.

### Eje B: ámbito veterinario

El selector visual de Inicio («Pequeñas especies», «Exóticos», «Producción/Grandes especies») configura contenido y módulos **contextuales**, no cambia por sí mismo la titularidad de los datos ni otorga permisos. En producción abrir selector secundario por unidad/especie: aves de engorda, aves de postura, porcinos, bovinos y peces; extensible a otros sistemas. Permitir registros individuales, por lote, parvada, hato, estanque o grupo según el ámbito.

### Eje C: destinos funcionales

**Navegación inferior móvil recomendada (máximo cinco):** `Inicio` · `Agenda` · `Pacientes/Registros` · `Cálculos` · `Más`. En el área de producción, «Pacientes/Registros» puede rotularse «Unidades» sin perder la ruta lógica. **Vademécum**: acceso claro desde Cálculos y Más; puede ser acceso rápido configurable, pero no sexta pestaña obligatoria. **Ajustes**: dentro de perfil/Más, no una sexta pestaña. Los accesos a Chat IA y Escáner no deben tapar datos ni permanecer flotando simultáneamente sobre todas las pantallas: mostrarlos contextualizados en barra de acciones o un único acceso expandible cuando corresponda.

**Más** organiza áreas transversales con búsqueda y categorías en lugar de una cuadrícula infinita: Clínica y atención; Farmacia y suministros; Administración y finanzas; Equipo y comunicación; Reportes; IA y automatización; Cuenta y configuración. Visibilidad y acciones por permiso; si algo existe pero no está implementado, marcar «Próximamente» o dejarlo fuera de beta.

## 4. Pantallas maestras y organización de contenido

### 00. Entrada, cuentas y espacios

- Acceso y recuperación, verificación de sesión, invitaciones a clínicas, selección de espacio activo.
- Perfil personal y, **separadamente**, credenciales y habilitación profesional verificable. Mostrar «Dra./Dr.» únicamente cuando corresponda, no por defecto como en maqueta de Stitch.
- Estados: sin clínica, una clínica, múltiples clínicas, acceso restringido/suspendido, carga, error, offline.

### 01. Inicio / resumen del espacio

Orden visual adaptado del Dashboard:
1. Encabezado compacto: avatar, nombre, espacio activo seleccionable, notificaciones y acceso a perfil.
2. Selector de ámbito en tres tarjetas neumórficas; producción ofrece selector secundario de especie/unidad.
3. **Resumen del espacio**: periodo seleccionable y cuatro KPI contextuales como máximo por bloque; permitir expandir; gráfico semanal con escalas y etiquetas claras. Los KPI cambian por área y permisos. Datos reales o señalizados DEMO.
4. **Acciones prioritarias**: siguiente cita, alerta pendiente, tarea clínica, acceso reciente. Priorizar lo urgente, no publicidad.
5. **Módulos frecuentes** configurables: 3–6 accesos más usados; el resto vive en Más.
6. IA como acceso de asistencia no intrusivo; evitar promesas de precisión médica.

El Dashboard HTML incluye números de ejemplo; jamás trasladar «32 consultas», «2 UCI», etc. como datos reales. Indicadores financieros no visibles a roles sin acceso.

### 02. Agenda y citas

- Encabezado reutilizable, título, selector día/semana/mes, franja semanal, cambio de fecha, filtros: todas/en sala/confirmadas/pendientes y estados adicionales pertinentes.
- Tarjeta de cita: hora, paciente o unidad, especie, tutor/responsable, motivo/resumen, profesional asignado, estado textual, acciones rápidas pertinentes; clic abre detalle con historia y edición según permisos.
- Acción fija accesible «Nueva cita» sin cubrir lista; tratamiento de superposiciones, cancelaciones, reprogramación y zona horaria.
- Estados vacíos, sin red, fecha sin citas, acceso denegado.
- Respetar los flujos existentes de calendario/citas si ya funcionan; migrar exclusivamente su presentación sin borrar lógica.

### 03. Pacientes / unidades productivas

- Búsqueda por nombre, tutor, identificación y especie; filtros; lista con jerarquía clínica clara.
- Ficha individual: identificación, tutor, alertas, peso e historial; pestañas historia, vacunas, tratamientos, hospitalización, documentos y movimientos.
- Producción: registros por lote/parvada/hato/estanque, ciclos, indicadores y responsables; no forzar expediente individual donde no corresponda.
- Acción «Nuevo paciente» o «Nueva unidad» contextual.

### 04. Calculadoras clínicas

- Selector de especie, paciente/peso, principio activo o producto, presentación/concentración, indicación y pauta **solo cuando estén verificadas**.
- Resultado con desarrollo visible de fórmula, unidades, redondeo declarado, límites y validaciones; distinguir cálculo matemático de recomendación terapéutica.
- Caso de ejemplo DEMO y suspensión del resultado clínico si faltan datos/validación; nunca inventar dosis.
- Guardar resultado y asociarlo a expediente solo cuando esté permitido y autorizado.

### 05. Vademécum y escáner de medicamentos

- **Buscar primero por marca comercial**, además de principio activo, laboratorio y filtros por especie/vía. No confundir marca con producto-presentación.
- Producto comercial → presentaciones y concentraciones → ficha por formulación → indicaciones, pautas etiquetadas por especie, contraindicaciones, referencias y fecha/estado de revisión.
- Catálogo importado de PLM y lotes previos: distinguir los datos ya inventariados de las dosis pendientes; no mostrar la ficha como completa si no lo está.
- Cámara/escáner OCR/código de barras/IA: extracción asistida a **borrador** con fuente adjunta y revisión; no habilitar dosificación por extraer una etiqueta.
- Vínculos a calculadora, inventario y recetas manteniendo el identificador exacto de la formulación.

### 06. Hospitalización y tratamientos

- Vista de ocupación por pacientes y áreas, turnos, prioridades y tareas con hora límite.
- Ficha: órdenes autorizadas, dosis/administración, quién preparó/administró, horario, respuesta, incidencias, consumo de inventario y alertas.
- Estados inequívocos: pendiente / en preparación / administrado / omitido / suspendido; registro auditable, nunca sobrescribir historial silenciosamente.
- Acceso rápido para turno y modo de alta legibilidad; notificaciones verificadas con app en primer plano y cerrada.

### 07. Recetas, consentimientos y PDF

- Listado, borrador, revisión, firma/autorización profesional aplicable, emisión PDF y archivo adjunto.
- Nunca presentar firma o autorización como válida por el mero rol administrativo.
- Separar preparación de autorización y entrega; trazabilidad de revisiones.

### 08. Laboratorio / pruebas y adjuntos

- Solicitudes, toma de muestra, resultados y referencias, adjuntos de imagen/PDF, vínculo al paciente o lote.
- Estados pendiente/resultados recibidos/interpretados; permisos por clínica y protección de archivos.

### 09. Inventario, farmacia y compras

- Existencias por presentación/lote/caducidad/almacén; entradas, transferencias, bajas, alertas y trazabilidad.
- Movimientos derivados de venta o administración vinculados a documento origen; evitar doble descuento.
- Controlados: segregación de permisos, registros y cumplimiento normativo según aplique y tras verificación jurídica/profesional.

### 10. Ventas y caja

- Apertura y cierre de caja, venta de productos/servicios, pagos, descuentos, devoluciones y arqueo; diferencia entre ingreso cobrado y factura emitida.
- El cobro puede consumir inventario y relacionarse con atención, pero no autoriza actos clínicos.
- Informes de ventas sujetos a permisos financieros.

### 11. Administración → Finanzas

Jerarquía separada de Caja:
- **Resumen financiero:** ingresos reales, gastos reales, saldo y tendencias.
- **Planeación y presupuestos:** ingresos estimados, costos fijos, costos variables, presupuesto operativo, presupuesto general; comparar plan vs real.
- **Inversiones:** inversión inicial, activos/equipos, inversión total, capital de trabajo, seguimiento de inversiones.
- **Rentabilidad y escenarios:** margen bruto/neto, flujo de caja, punto de equilibrio, ROI e hipótesis conservadora/base/optimista.
- **Reportes:** periodos, clínica/sucursal/unidad productiva, exportaciones y versiones de presupuesto.

Marcar siempre **real / estimado / simulado**; no mezclar presupuesto con dinero existente. Moneda MXN configurable.

### 12. Equipo, permisos y operación

- Personal, puestos, turnos, tareas, membresías, permisos granulares, autorizaciones profesionales independientes, historial de cambios.
- Registro de asistencia con QR de vigencia corta y geocerca opcional; ambos son indicios operativos, NO prueba infalible de presencia. Corrección auditable y privacidad.
- Administración de plataforma totalmente separada de administración de una clínica.

### 13. Comunicaciones internas

- Tablón de avisos, notas, anuncios y acuses de lectura; encuestas/votaciones; chat de equipo y mensajes privados, adjuntos y notificaciones.
- Segmentación por espacio, equipo y rol; los mensajes no sustituyen una orden clínica autorizada.
- Moderación, acceso y retención según reglas de la clínica.

### 14. Producción animal

- Selector por sistema productivo. Registros epidemiológicos, tratamientos, inventarios, indicadores de productividad y costos por ciclo/unidad, trazabilidad, alertas y reportes.
- Submódulos iniciales previstos: aves de engorda, aves de postura, cerdos, bovinos y peces. Diseñar estructura reutilizable, pantallas específicas solo al definir requisitos verificables.

### 15. IA y ajustes

- Asistente: consulta y apoyo a redacción/organización, siempre distinguiendo sugerencias de decisiones profesionales.
- Configuración IA: proveedor, credenciales seguras, rotación/revocación, límites y privacidad; nunca exponer claves en UI/logs.
- Ajustes: apariencia claro/oscuro real, accesibilidad, notificaciones, idioma, cuenta/espacios, sesiones, privacidad, almacenamiento y respaldos.
- Permisos de Storage y Edge Functions deben validarse independientemente del diseño visual.

### 16. Estadísticas y reportes

- Vistas por ámbito clínico/producción, operacional, financiero; comparaciones por periodos y exportación donde autorizada.
- Gráficas accesibles con números y etiquetas, no solo colores.

## 5. Biblioteca de componentes Flutter

- `VetThemeTokens`, `VetTypography`, `VetElevation`, `VetSpacing`, `VetSemanticColors`.
- `VetWorkspaceHeader`, `VetPracticeSelector`, `VetProductionSubtypeSelector`, `VetBottomNav`, `VetMoreMenu`.
- `VetSurfaceCard`, `VetKpiCard`, `VetModuleTile`, `VetChartPanel`, `VetActivityTimeline`.
- `VetActionButton` (primary/secondary/neutral/destructive), `VetIconButton`, `VetFloatingAction` contextual.
- `VetInput`, `VetSearchField`, `VetStepper`, `VetSegmentedControl`, `VetFilterChip`, `VetStatusBadge`, `VetDateSelector`.
- `VetListItem`, `VetPatientCard`, `VetAppointmentCard`, `VetMedicationPresentationCard`, `VetTaskCard`.
- `VetEmpty`, `VetLoading`, `VetError`, `VetOffline`, `VetPermissionDenied`, `VetUnverifiedClinicalData`.

Cada componente con estados normal, pulsado, seleccionado, deshabilitado, cargando, error y enfoque de accesibilidad cuando aplique. No copiar Tailwind ni usar CDN dentro de Flutter; implementar nativamente.

## 6. Matriz de acceso visual y seguridad

- **Espacio:** ¿qué clínica o cuenta posee el dato?
- **Área:** ¿es pequeñas especies, exóticos o producción, y cuál subtipo?
- **Rol/permisos:** ¿puede ver, preparar, editar, publicar, administrar o exportar?
- **Habilitación profesional:** ¿está autorizado a prescribir/validar/firmar cuando corresponde?
- **Estado clínico:** ¿el dato farmacológico es importado, borrador, revisado o verificado?
- **Estado del módulo:** ¿implementado y probado, parcial, solo maqueta o futuro?

Una pantalla oculta por permiso no basta: Supabase/Edge deben denegar la operación no autorizada. Nunca asumir que el UI Kit acredita el funcionamiento real de esos controles.

## 7. Qué se conserva y qué cambia de Stitch

**Se conserva:** colores luminosos, huella/ritmo como identidad, tarjeta elevada suave, botón píldora, selector por práctica, resumen, filtros en chips, agenda semanal, patrones para formularios y estados, badges con texto.

**Se cambia:** valores ficticios por datos reales/DEMO; texto demasiado pequeño; seis pestañas inferiores por cinco; «Dra.» predeterminado por título verificado; botones decorativos por acciones reales; iconos inconsistentes por set de iconos; estado oscuro aparente por tema implementado; duplicados de cabecera y fondos; gradientes enormes por acentos moderados.

**No se impone:** que cada módulo tenga el mismo número de tarjetas. La plantilla global es común, pero la densidad, los formularios y datos cambian según el trabajo clínico o administrativo.

## 8. Secuencia de implementación coordinada (sin editar backend en esta fase)

1. Auditar tema, rutas, widgets y pantallas Flutter existentes. No dar por hecho que están pendientes todas las funciones.
2. Crear tokens + galería de componentes en rama aislada (o PR) sin modificar Supabase ni permisos.
3. Portar Inicio y Agenda con el mismo comportamiento previo; comparar capturas Android y comprobar regresión de citas/cuentas.
4. Incorporar Pacientes, Calculadoras y Vademécum por grupos; mantener compuertas clínicas por verificación.
5. Incorporar Hospitalización, Inventario, documentación y funciones compartidas; probar cruces de datos.
6. Añadir Administración/Finanzas, Equipo/Comunicaciones y Producción desde la navegación común, sin mostrar pantallas vacías como funcionales.
7. Pruebas automáticas durante desarrollo; revisión integral de la usuaria al final sobre APK de pruebas. No retrasar la verificación técnica de seguridad y dosis hasta esa prueba final.

**Responsabilidades de colaboración:** la persona define prioridades de uso y valida la experiencia; modelos implementan y documentan cambios; cada módulo debe tener pruebas independientes de quien lo creó. Sol 6.1 integra/cierra beta según el reparto descrito; cualquier rama de diseño debe coordinarse antes de combinarse con su trabajo. La guía NO acredita que 5.6, Astra ni Claude hayan aprobado este documento.

## 9. Criterios de aceptación

- Los mismos colores/radios/espaciados y tipografía en Inicio, Agenda y módulos.
- El selector de espacio no mezcla datos entre clínicas; el selector de área no cambia permisos.
- Ninguna acción operativa queda oculta bajo un icono decorativo sin etiqueta accesible.
- Modo claro legible bajo estrés y en teléfono de pantalla reducida; botones >=48dp.
- Cálculos y fichas sin verificar se señalan inequívocamente.
- No se presentan como funcionalidades listas los módulos que solo están especificados.
- No se rompen las acciones existentes de cuentas, calendario ni citas por el rediseño.

## 10. Material fuente de esta consolidación

Archivos aportados en este chat:
- `ui_kit_neum_rfico_flat_botones_round_full.html`
- `ui_kit_tokens_neum_rficos_oficiales (1).html`
- `dashboard_resumen_cl_nico_soft_neumorphism (1).html`
- `02._agenda_y_citas_cl_nicas_luminous_neumorphic.html`
- `vetdosis_pro_logo.html` (Base64 SVG)
- `VetDosis_Design_System_v1.md` (guía anterior)

**Nota de procedencia:** paletas, patrones de Dashboard y Agenda y componentes UI proceden de estos archivos; jerarquía de navegación, ámbitos de producción, finanzas, comunicaciones, protocolos clínicos y orden de integración consolidan propuestas de esta conversación. Las decisiones de cinco pestañas y limitación de profundidad visual son recomendaciones nuevas de integración, no algo que afirmen los archivos de Stitch.
