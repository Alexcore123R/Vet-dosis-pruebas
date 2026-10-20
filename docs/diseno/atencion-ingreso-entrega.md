# Atención del día, ingreso y entrega

Primera etapa del recorrido aprobado después de contactos e historia/carnet, en el PR #7. Implementada en código; requiere revisión de dependencias, SQL nuevo y validación en teléfono antes de desplegar. No constituye un APK nuevo instalado ni un cambio en el servidor.

## Qué incorpora

- Vista de atención del día en Agenda, con zona y límites diarios devueltos por el servidor (ajuste de horario estacional incluido). Incluye citas del día agendadas/entregadas y pendientes en atención/listas de días anteriores; excluye canceladas y citas futuras. Se puede quitar el filtro para consultar otras fechas. El calendario existente sigue mostrando horarios del dispositivo y se identifica así.
- Tarjeta con responsable, horario programado, estado, contacto y saldo ya vinculados. El registro de ingreso incorpora su hora efectiva del servidor, separada de la hora programada. Acceso directo al expediente para evolución.
- Ingreso: motivo, pertenencias (incluida declaración de ninguna), servicios autorizados, quién autorizó, persona autorizada para recoger y referencia/aceptación del presupuesto. No registra dinero, no crea cargos ni sustituye firma o consentimiento.
- Cierre de consulta: fecha clínica, indicaciones, tratamiento indicado por el MVZ y seguimiento. Se guarda como evento SOAP con subtipo care_discharge en el expediente; no se muestra el contenido clínico en la respuesta administrativa de Agenda. No crea una receta, dosis calculadas, órdenes hospitalarias o una cita de revisión automática.
- Servicio de estética listo: indicaciones y seguimiento operativos, sin crear un SOAP veterinario.
- Entrega: quién recogió, comprobación manual de autorización, indicaciones entregadas y pertenencias/incidencias. Si cambió la persona o falta un ingreso antiguo, exige referencia de cómo se comprobó su autorización. No certifica identidad automáticamente ni acredita pago.
- Ajustes muestra versión y número de compilación reales de la aplicación instalada; el texto se puede seleccionar/copiar. No usa el antiguo 0.1.0 fijo.

## Estados, autoridad y consistencia

Los pasos delegan las transiciones a ops_write existente en la misma transacción: agendado → en_atencion → listo → entregado. Se eliminan los atajos del menú de la app para esos cambios cuando está disponible el repositorio nuevo; cancelar/reprogramar conservan sus reglas existentes. La API histórica no se elimina ni se sustituye: otros clientes anteriores pueden seguir cambiando estados sin documentos. Eso debe considerarse al decidir cuándo hacer obligatorio este flujo en todos los clientes.

Citas antiguas en atención pueden completar el registro de ingreso. Citas antiguas listas pueden registrar las indicaciones antes de su entrega. Cada paso solo se registra una vez, es inmutable, tiene autor/hora de servidor y versión de cita esperada. Reintentos con el mismo contenido devuelven el mismo recibo y no duplican SOAP, documento o transición; contenido distinto con el mismo identificador se rechaza. Un fallo revierte todo.

Se requiere appointment.read y appointment.manage vigentes para escribir; patient.read si la cita está vinculada. Se conserva además el límite heredado de cita propia o roles administrativos/clínicos autorizados. El cierre de consulta exige paciente vinculado, rol admin/MVZ y patient.write además de los anteriores; el endpoint clínico existente conserva sus propias comprobaciones. El personal operativo no adquiere acceso al contenido clínico por consultar una tarjeta. No se otorgan permisos nuevos ni se activan políticas.

No se mezclan ingreso/entrega de cita con hospitalización: las estancias continúan usando su hoja, pendientes y revisión de alta existentes. Tampoco se bloquea una entrega por deuda. Ingreso/alta hospitalaria y casos sin cita no se generan desde estos documentos.

La app limpia Agenda, contacto, cobros y registros al salir del primer plano; vuelve a comprobar al regresar y descarta respuestas tardías. Los formularios comprueban que siguen perteneciendo a una tarjeta vigente. Cambiar clínica, cuenta o paciente de contexto reconstruye la pantalla.

## Instalación y pruebas

Preparar únicamente supabase/adaptations/appointment_care_v1.sql después de comprobar M4, M9, inventory_clinic_settings, permiso explícito, recibos y wrappers instalados. Exige beta cerrada y política explícita dormida. No reejecutar 01–08 ni sustituir wrappers sin revisar. La tabla nueva no permite lectura/escritura directa por authenticated: solo RPC autorizada.

Fixture PostgreSQL 17 aislado: transacciones de ingreso/cierre/entrega, versiones, reintentos, contradicción de recogida, datos clínicos fuera del snapshot operativo, cierre de estética frente a cierre médico, pérdida de permisos e inmutabilidad. Dependencias de permisos/eventos/ops son sintéticas; no acredita el corte RLS global ni los wrappers remotos.

Flutter: límites de día de clínica, pendientes anteriores, validación, respuesta tardía tras segundo plano, error de permisos, controles operativos sin cierre médico y diseño de tarjeta a 320 px/texto 200%. El workflow incorpora el fixture nuevo, suite/análisis y compilación Android.

## Siguientes etapas acordadas

1. Abonos individuales/anticipos integrados con caja, turnos, comprobantes, anulaciones y comisiones. El parcial actual sigue describiendo varios servicios, algunos cobrados.
2. Carnet: fotos/comprobantes, cobertura estructurada y próximas fechas confirmadas por profesional. El documento aportado permanece como referencia, sin importar automáticamente dosis o calendarios.
3. Resumen clínico de problemas activos/medicación vigente y estados resueltos. No inferir vigencia a partir de un SOAP viejo; requiere registro y cierre explícitos.
4. Extender respaldo/restauración a registros operativos de atención, bitácora y revisiones de contacto antes de afirmar cobertura integral. Las correcciones clínicas se documentan con nueva entrada; no se editan documentos cerrados ni se ofrecen falsas garantías de recuperación.
5. Completar el flujo equivalente sin cita, vinculación administrativa de paciente/tutor pendientes y cambios que la usuaria señale en Agenda. Probar contactos y recorrido en el Honor X6.

No prometer que estos pendientes ya están implementados. La versión real visible sí queda incorporada en esta etapa.
