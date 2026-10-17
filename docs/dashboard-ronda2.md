# Dashboard — revisión con 12 capturas

Estado: implementación local con repositorios existentes; sin migraciones. Colores de la usuaria: naranja quitar/reemplazar, verde conservar, azul incorporar. Las cifras clínicas y financieras de los prototipos no se importaron.

## Distribución y alcance

1. Estadísticas al inicio, solo con permiso administrativo actual. Ventas mensuales netas de reversos, sin llamarlas utilidad neta.
2. Accesos compactos con iconos y tema Neu: inventario, estadísticas, recetas, formatos, pacientes, agenda, hospitalización, ambos cálculos y escáner. Se eliminan las cinco tarjetas grandes de accesos; IA y soporte siguen como flotantes.
3. Alertas y recordatorios dinámicos: dosis pendientes cuyo horario llegó, próximas dentro de la anticipación elegida y stock bajo. Configuración desplegable en dashboard y en Ajustes. Avisos visuales de stock bajo activables; no son notificaciones automáticas de inventario con app cerrada.
4. Próximas cuatro citas agendadas del día, usando zona de clínica si inventario/estadísticas la devuelve; si falta, se indica día/horas del teléfono. Las citas recientes se conservan con su estado.
5. Inventario: búsqueda por nombre/código dentro de lo consultado, existencias disponibles agrupadas por unidad, artículos activos y alertas. Valores a costo por lotes utilizables y valor a precio de venta capturado; margen potencial antes de comisiones/gastos. Estos resúmenes financieros se muestran solo al admin con el esquema actual. No mezclar frascos/tabletas en un total de unidades. No incluir lotes caducados como disponibles.
6. Caja: turno propio abierto/cerrado, apertura con fondo capturado mediante RPC existente y operación idempotente, bloqueo de doble apertura de formulario, acceso a venta/corte/cierre y tres cortes cerrados visibles según permisos existentes. Fondo en blanco al abrir, no un importe asumido. No se cierra caja ni se registra venta al tocar una tarjeta de resumen.
7. Ventas de hoy (admin): importes del servidor por efectivo, tarjeta y transferencia, ventas menos reversos, margen tras costos/comisiones y resultado con gastos capturados. Fecha del servidor. Número de ventas y ticket promedio permanecen explícitamente no disponibles: la consulta actual no los entrega; no inferirlos a partir de líneas ni de un historial limitado.
8. Próximas dosis se conserva; se eliminan las tarjetas de conteo simple de pacientes y hospitalización. El acceso a sus pantallas permanece.
9. Equipo y avisos para clínicas compartidas: cuatro pendientes visibles no completados y cuatro mensajes recientes, autor/fecha/categoría, acceso a crear mensajes y gestionar pendientes mediante pantallas/RPC existentes. El espacio personal no publica notas a un equipo inexistente.

## Avisos de dispositivo

Preferencias persistidas por dispositivo: sonido, vibración, stock visual y anticipación 0/5/10/15/30 min. Cero conserva el comportamiento previo sin anticipación; no se selecciona 15 min por copiar el prototipo. El plan agrega un aviso temprano distinto del aviso al horario y de la escalación; respeta posposición y excluye tareas terminadas. IDs estables y huellas invalidan programas cuando cambian preferencias. Dashboard reprograma con las tareas cargadas de su espacio; desde Ajustes se debe abrir hospitalización para revisar el plan completo.

Android usa canales separados para combinaciones de sonido/vibración, respetando las restricciones de canales del sistema. iOS respeta solicitud de sonido, pero no garantiza controlar vibración independientemente. Web mantiene avisos visuales; no garantiza avisos tras cerrar navegador. El usuario todavía debe activar avisos y permisos en Hospitalización. No hay acción de aplicar en notificación, ni administración automática.

Pendiente: verificar con teléfono real alarmas con app cerrada, sonido/vibración, batería, permisos y anticipación. La programación simulada no acredita entrega física. El soporte del dispositivo y sus ajustes prevalecen.

## Notas, pendientes y futuras votaciones

Se reutilizan clinic_messages y clinic_tasks con sus filtros del servidor y bitácora existentes. Esta versión no implementa fijar mensajes, vencimientos de avisos ni confirmación de lectura; requerirían revisión del esquema. Los mensajes no deben contener datos sensibles de pacientes o personal.

Propuesta para votaciones, todavía sin migración: polls(clinic_id,id,question,created_by,opens_at,closes_at,state); poll_options(clinic_id,poll_id,id,label,position); poll_votes(clinic_id,poll_id,voter_id,option_id,server_at), claves compuestas de clínica y unicidad(poll_id,voter_id). Participación de miembros activos, cierre comprobado en servidor, opción válida del mismo sondeo, auditoría, prohibición de votar como otro usuario. Decidir visibilidad nominativa/anónima y posibilidad de cambiar voto antes de implementar. Nunca usar votación como autorización clínica. Integrar su autorización con el esquema nuevo pendiente de revisión, no recrear roles clínicos.

## Validación

Pruebas de dashboard, fecha de clínica, cálculos de inventario, notas/pendientes, turnos propios, planificación de anticipación y persistencia; navegación móvil, texto grande, claro/oscuro; regresión de hospitalización e inventario. Análisis estático y compilación según los resultados del turno. La instalación y prueba de datos reales de esta revisión quedan pendientes del APK actualizado.

## Cierre adicional — 17 de octubre

El cliente muestra ahora `sale_count` y `average_ticket` si el servidor los entrega.
La actualización candidata `14A_dashboard_sales_metrics.sql` añade ambos campos a
la función privada de totales existente, sin cambiar sus permisos ni movimientos.
Son ventas completas del periodo, excluyendo las revertidas antes de su cierre;
el promedio usa sus importes originales, no el neto de caja dividido entre líneas.
Un periodo sin ventas devuelve cero y promedio nulo. Los totales de caja siguen
incluyendo los reversos según la fecha del movimiento. Esta candidata está fuera
del paquete de permisos de 23 archivos y todavía no está aplicada en remoto.

Si falla la consulta del contrato de módulos, aparece un aviso con Reintentar;
los módulos permanecen bloqueados hasta obtener un contrato válido. No confundir
este error de carga con una respuesta válida que deniega permisos a la persona.

Pendientes de cierre operativo: aplicar y validar permisos en el servidor de
prueba, desplegar las métricas tras revisar su candidata, y comprobar en teléfono
el escáner/cámara, identidad, navegación y alarmas. Las votaciones aún requieren
definir privacidad y cambio de voto; no se incluyen como función terminada.

Validación del cierre: [39080528142](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39080528142)
aprobó PostgreSQL aislado, análisis Flutter completo sin incidencias y 25 pruebas
de dashboard, navegación/permisos, identidad y tema Neu. El APK anterior todavía
no contiene este cierre adicional; requiere recompilación después de la integración.

Actualización remota: 14A y contrato de módulos inicial instalados y verificados en
[39081043942](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39081043942).
La cuenta necesita concesiones explícitas para mostrar cada módulo. No se crearon
permisos por inferirlos del puesto; las pruebas con cuentas reales siguen pendientes.
