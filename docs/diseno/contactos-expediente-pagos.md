# Contactos, expediente y estado de cobro

Continuación del PR #7 sobre feature/historia-carnet-20261020. Código preparado y probado; no hay despliegue de Supabase ni APK de distribución generado.

## Contactos del tutor

La fuente única es vet_owners: nombre, teléfono principal, alternativo del mismo tutor, correo, dirección y contacto adicional con relación/autorización. La ficha del paciente y la consulta desde Agenda utilizan ese mismo tutor; no se copian teléfonos a cada cita. Los contactos de hospitalización se abren desde la estancia.

Los cambios usan versión esperada, bloqueo del tutor y de la clínica, permisos patient.read + patient.write vigentes y recibos idempotentes. Se conserva revisión privada de valores previos/nuevos y auditoría sin datos de contacto. Una edición concurrente no se sobrescribe. Retirar autorización oculta las acciones del contacto adicional sin borrar la historia.

La lectura conserva además el límite actual de roles admin/MVZ/recepción para contactos; no se usa el rol como sustituto del permiso explícito. En Agenda se requiere appointment.read y, para el contacto, patient.read y ese límite de roles. Los auxiliares no adquieren acceso a contactos por esta entrega. Los cambios de esa política deben revisarse como un corte independiente.

Llamar abre el marcador, WhatsApp prepara un texto que el usuario puede enviar, mapas abre la dirección bajo acción expresa. No hay envío ni llamada automática. WhatsApp exige prefijo internacional explícito; no se deduce el país. Números con comandos o caracteres no telefónicos no producen enlaces.

Android ofrece abrir la agenda del dispositivo o prellenar un contacto con nombre y teléfono principal, después de confirmación. La app de contactos decide el guardado final; puede sincronizar esa copia según la configuración del dispositivo. No se leen contactos del teléfono, no se solicita READ_CONTACTS/WRITE_CONTACTS y no se informa que el contacto quedó guardado por solo abrir el formulario. El puente usa un canal nativo y se compila en CI como debug no distribuible.

## Bitácora de contacto

Entradas anexas por paciente y tutor: persona/número, medio, resultado, fecha observada, observaciones de comunicación, autor y hora del servidor. Es captura humana, no evidencia de que el sistema haya enviado o logrado contacto. Los reintentos idénticos devuelven la misma entrada. No se infiere abandono a partir de deuda o falta de respuesta; tampoco se modifica el estado del paciente. Las aclaraciones se registran como nuevas entradas.

Si cambia la cuenta/clínica o falla una nueva comprobación se retiran datos anteriores. Una respuesta tardía no restaura contactos ni cobros después de cerrar la pantalla. Los formularios no se guardan en preferencias o archivos locales; la copia a la agenda del teléfono solo ocurre por decisión explícita del usuario.

## Organización del expediente

Las entradas se ordenan por fecha clínica, con fecha de registro e ID para desempatar. Se puede invertir el orden, filtrar por tipo y buscar/agrupar consultas por motivo sin distinguir tildes o mayúsculas. Fechas preventivas desconocidas/aproximadas se ordenan por su registro, sin inventar una aplicación exacta. El carnet y las historias estructuradas comparten ese criterio.

No se consolidan diagnósticos por similitud textual ni se cambian documentos históricos. La búsqueda de motivo no equivale a búsqueda en todos los PDFs/estudios externos; los enlaces existentes con Casos clínicos se conservan.

## Pago de la cita

La tarjeta muestra:
- Sin cargo registrado: no hay actos de servicio vinculados; no se presume deuda.
- Pendiente de pago: hay cargos y no hay líneas de venta activas vinculadas.
- Pagado: las ventas activas cubren los cargos vinculados.
- Abonado / restante: solo parte del conjunto de servicios de la cita está cobrada.
- Importes pendientes de revisión: el contrato o los importes no concuerdan.

La suma procede de clinic_service_acts y de inventory_sale_lines con su service_act_id, dentro de la misma clínica y excluyendo ventas anuladas. No se usan referencias bancarias, que son observacionales y duplicarían dinero ya registrado en POS. La respuesta requiere sales.read + inventory.read; sin ellos no se muestran importes ni se asume falta de pago. El estado clínico y la entrega son independientes del pago.

Importante: el POS actual cobra cada acto completo. La etiqueta parcial puede describir una cita con varios actos, algunos cobrados y otros pendientes. Esta entrega NO añade recepción de anticipos ni abonos a un único acto. Eso requiere un flujo contable integrado con turnos, reversos y comisiones; no simularlo con referencias bancarias o campos manuales en Agenda.

## Despliegue y pendientes que deben recordarse

- Aplicar solo patient_contacts_appointment_links_v1.sql después de revisar las dependencias reales del proyecto de pruebas. Requiere beta cerrada y política explícita aún dormida; no reejecutar 01–08, abrir admisiones ni conceder permisos por defecto.
- El enlace no inventa un tutor para un paciente sin tutor: completar esa vinculación administrativa sigue pendiente. El alta existente captura teléfono/dirección principales; los datos adicionales se editan después sobre el tutor registrado.
- Revisar lectura de nuevos campos en formatos futuros y sus permisos. Los PDF y las instantáneas ya firmadas no se modifican; esta entrega no agrega contacto automáticamente a PDFs antiguos.
- Extender respaldo/restauración a la nueva bitácora y revisiones privadas antes de afirmar cobertura integral. El mecanismo actual que serializa vet_owners puede incluir columnas nuevas, pero eso no acredita restauración completa.
- Pendientes de la etapa anterior: adjuntos del carnet, exportación/compartir, selección estructurada de componentes, planes preventivos sin evento anterior, verificación real en teléfono. La versión visible se incorporó después en la etapa de atención/ingreso/entrega.
- Agenda sigue pendiente de las observaciones específicas de la usuaria; esta entrega solo enlaza contacto y resumen financiero.

## Evidencia

Pruebas Flutter de teléfonos/URI, autorización retirada, orden clínico y motivo, importes exactos y estados, privacidad tras fallos/respuestas tardías, confirmación de exportación de contacto y diseño a 320 px/texto 200% en claro y oscuro. Fixture PostgreSQL 17 del nuevo patch: versiones, reintentos, enlace actualizado de Agenda, aislamiento, ventas anuladas y datos ocultos al perder permisos. Los helpers de permisos del fixture son sintéticos: no demuestra el corte RLS global ni la instalación remota. La compilación Android valida el puente; la prueba con la app Contactos de Honor queda para el teléfono.
