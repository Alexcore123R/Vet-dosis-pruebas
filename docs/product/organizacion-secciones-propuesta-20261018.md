# Organización de secciones — propuesta para revisar antes del diseño

Estado: propuesta de arquitectura de información; no cambia rutas, permisos ni
pantallas. La usuaria pidió revisar las propuestas de GPT-6 y ordenar las secciones
antes de continuar el diseño. El piloto del PR #2 sigue como borrador visual.

## Tres decisiones diferentes

1. Espacio: personal o una clínica a la que pertenece la cuenta. Determina de quién
   son los datos. Las sucursales requieren revisar el modelo real antes de
   presentarlas como una opción operativa nueva.
2. Área de trabajo: pequeñas especies, exóticos/silvestres o grandes especies y
   producción. Ordena las herramientas pertinentes; no concede permisos.
3. Función: consultar pacientes, calcular, administrar inventario, cobrar, etc.
   Su acceso depende de permisos y, cuando aplica, habilitación profesional.

Cambio propuesto: Gestión clínica deja de ser una cuarta área veterinaria en la
presentación y pasa a Administración. No se elimina su funcionalidad ni se cambia
su identificador interno sin revisar compatibilidad. Grandes especies también
incluye atención individual; producción añade unidades, grupos y ciclos cuando
estén implementados. No convertir todo expediente de un bovino/equino en un lote.

## Entradas principales

Encabezado: espacio activo y cambio de espacio, identidad real de usuario/clínica,
perfil y acceso a notificaciones cuando exista una fuente real de avisos.

Barra inferior propuesta: Inicio / Agenda / Pacientes / Cálculos / Más.
Pacientes podrá rotularse Registros o Unidades en contextos productivos cuando el
flujo correspondiente exista. Cada destino respeta la autorización; no se crea una
pestaña vacía para aparentar que un módulo futuro está disponible. La elección de
un área conserva la clínica y los permisos. Los borradores y cambios de espacio
mantienen las protecciones actuales frente a pérdida o cruce de datos.

Inicio resume, muestra prioridades y ofrece accesos frecuentes; no sustituye las
pantallas completas ni es la única forma de encontrarlas. Más es un menú agrupado
con búsqueda de destinos visibles, no otra copia del dashboard.

## Menú agrupado

| Grupo | Contenido propuesto |
|---|---|
| Atención y expedientes | Pacientes, consultas, hospitalización, vacunas/seguimiento, estudios y adjuntos, recetas y consentimientos |
| Medicamentos y herramientas | Vademécum, calculadoras, escáner de productos, inventario y compras, frascos/controlados |
| Administración y finanzas | Caja y ventas, catálogo de servicios/tarifas/comisiones, proveedores, costos, presupuestos, inversiones y escenarios |
| Equipo y comunicación | Integrantes, permisos/delegaciones, pendientes, avisos/mensajes y asistencia |
| Estadísticas y reportes | Acceso común con vistas clínicas, operativas, inventario y financieras según permiso; exportaciones contextuales |
| Asistente IA | Chat contextual y acceso a configuración del proveedor, credenciales, privacidad y límites para quien corresponda |
| Cuenta y ajustes | Perfil y espacios, logo/membrete, apariencia, seguridad, privacidad/términos, respaldos, plan, ayuda e inicio guiado |

Los accesos directos de la barra inferior y del menú abren las mismas rutas y
registros; no crean módulos ni datos duplicados. Un informe puede ofrecer un
atajo desde su módulo de origen sin convertirse en una segunda implementación.

Administración de plataforma es un portal aparte de la administración clínica,
con acceso de plataforma y 2FA. No mezclarla con los permisos del equipo clínico.

## Relaciones que deben quedar claras

- Consulta vive en el expediente. Agenda programa y cambia el estado de la cita;
  no obliga a completar una historia ni autoriza procedimientos por sí sola.
- Laboratorio/imagen/pruebas se vinculan al paciente y a la atención. Pueden tener
  una bandeja propia cuando el flujo lo justifique; no necesitan otra pestaña
  principal para capturar un resultado y un adjunto.
- Recetas y consentimientos comparten el grupo de atención, pero conservan flujos
  y autorizaciones diferentes. No fusionar sus estados de firma o aprobación.
- Vademécum describe el producto/formulación y sus referencias; inventario registra
  existencia, lotes y movimientos. Comparten enlaces, no son la misma entidad.
- Escáner de productos se abre desde inventario/vademécum donde corresponda.
  El QR de asistencia conserva su flujo propio y su validación; no se confunden.
- Frascos/controlados se relacionan con inventario y atención, con registros y
  autorizaciones específicos. El catálogo global futuro no se da por instalado.
- Estética y cirugía usan agenda, expediente/actuación, servicios, cobro y comisión
  según el caso. Comparten un catálogo de servicios; no duplicar tarifas por pantalla.
- Caja registra movimientos reales. Planeación registra supuestos y presupuestos.
  Finanzas los compara, identificando siempre real/estimado/simulado. No llamar
  utilidad neta a las ventas o al margen sin contar los gastos correspondientes.
- Avisos/pendientes actuales no equivalen a un sistema completo de chats privados,
  adjuntos, encuestas y votaciones. Esas funciones son propuestas posteriores.
- Un recordatorio al tutor y una alarma de hospitalización tienen destinatarios y
  requisitos diferentes aunque compartan una bandeja de notificaciones.
- Perfil personal, identidad de clínica y habilitación profesional siguen separados.
  Configurar IA no otorga permisos clínicos ni modifica el proveedor para otro espacio.

## Contraste con el código actual

Inspección de entradas de `lib/core/app.dart`, `navigation_access.dart` y pantallas:

| Entrada actual | Ubicación conceptual propuesta |
|---|---|
| Inicio | Inicio |
| Agenda; pestañas de OperationsScreen | Agenda; servicios en Administración; pendientes/avisos en Equipo |
| Pacientes | Pacientes / Atención y expedientes |
| Hospitalización | Atención y expedientes |
| Receta; Formatos | Atención y expedientes, conservando sus flujos |
| Cálculo rápido; Cálculos clínicos | Cálculos / Medicamentos y herramientas |
| Inventario; Escanear producto | Medicamentos y herramientas |
| Caja | Administración y finanzas |
| Equipo e invitaciones; Permisos; Checado | Equipo y comunicación |
| Estadísticas; Respaldo | Reportes; Cuenta y ajustes, respectivamente |
| Asistente IA; Proveedores IA | Asistente IA y su configuración |
| Mi cuenta y clínicas; Ajustes; Ayuda; Planes | Cuenta y ajustes |
| Administración beta/profesional de plataforma | Portal de plataforma separado |

Una ruta/pantalla en código no acredita que toda su función esté probada en el
servidor o en teléfono. La revisión operativa y sus pendientes siguen en
`docs/revision-pruebas-telefono-20261018.md`. La guía visual v2 contiene requisitos
futuros, no un inventario de funcionalidades completadas.

## Orden de trabajo propuesto

1. Revisar nombres, grupos y relación entre espacio, área y función con este mapa.
2. Mapear cada destino a su ruta existente, permiso, estado de implementación y
   lugar de entrada; registrar faltantes sin agregarlos como botones simulados.
3. Ajustar navegación y comprobar acceso, cambio de clínica, regreso y borradores.
4. Retomar el piloto de Inicio sobre esa estructura y después Agenda.
5. Dejar finanzas avanzadas, mensajería completa y producción adicional para sus
   rondas funcionales; su ubicación puede quedar prevista desde ahora.

No se ha modificado la navegación con esta propuesta ni se ha aprobado el mapa
por la usuaria todavía. Este documento se añade al PR para revisión conceptual.

## Ampliación: menú por especie en producción

La usuaria propone una segunda selección de bovinos, ovinos/caprinos, aves
(postura/engorda), peces, abejas, porcinos y equinos. Se desarrolla en
[Menú por especie y actividad](produccion-menu-especies-propuesta-20261018.md),
con enlaces conceptuales a los módulos avícolas existentes y ubicación de sus
materiales de clase. Es una propuesta; no activa nuevos destinos ni referencias.

## Primera implementación autorizada

La usuaria pidió comenzar a implementar las secciones. La primera etapa conecta
el menú agrupado, la barra inferior, Servicios/Proveedores y el submenú productivo
con las herramientas avícolas existentes. Alcance, restricciones y pendientes en
[Implementación de secciones, etapa 1](secciones-implementacion-etapa1-20261018.md).
El mapa completo sigue distinguiendo funciones existentes de las futuras.
