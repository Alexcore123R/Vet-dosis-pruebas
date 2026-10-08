# M4 — Pacientes y expedientes

Implementación Flutter con dominio, repositorio Supabase y ViewModel por módulo. Acceso desde **Pacientes** en el menú. No requiere datos farmacológicos. No incluye pacientes ni contactos reales o de demostración en producción.

## Flujos implementados

- Alta de paciente: nombre, especie, raza, sexo y nacimiento opcional. Tutor nuevo, existente de la misma clínica o pendiente. Paciente y tutor nuevo se crean en una única transacción.
- Búsqueda por nombre/especie y consulta de contactos según permisos.
- Historial cronológico con usuario autenticado y hora del servidor de creación. Entradas clínicas de solo anexado: no se sobrescriben ni borran desde el cliente. Una aclaración se registra en una entrada nueva.
- SOAP: motivo, Subjetivo, Objetivo, Valoración y Plan. La plantilla presenta indicaciones de captura y la especie del paciente; no incluye hallazgos, diagnósticos, protocolos ni cifras clínicas precargadas. Los apartados pueden quedar vacíos si no se han documentado; guardar exige al menos uno y revisión expresa.
- Peso positivo en kg con coma o punto decimal; fechas válidas. Curva por fecha y lista de valores. El dibujo usa números aproximados para representar la escala, no para calcular dosis. Varias mediciones del mismo día se muestran por orden de registro.
- Alergias: sustancia/producto, reacción observada o referida y notas. No se infiere ausencia de alergias si no hay entradas, ni se clasifican automáticamente como diagnósticos confirmados.
- Vacunas y desparasitación: producto, lote opcional, fecha de aplicación y próxima fecha indicada por el usuario. No se inventan esquemas ni intervalos. WhatsApp abre un mensaje prellenado cuando existe un contacto internacional válido; el usuario decide enviarlo. No hay envíos automáticos ni API contratada.
- Consentimiento: procedimiento, texto proporcionado por la clínica, tutor firmante, aceptación y trazo en pantalla. Guarda el texto exacto y coordenadas normalizadas de la firma, con usuario/hora del servidor. Rechaza firmas vacías o un simple punto. Cambiar el texto, procedimiento, fecha o nombre del firmante invalida la aceptación y la firma anteriores. No hay plantillas legales inventadas ni certificación de firma electrónica avanzada. PDF y vínculo con receta se integrarán en M6.
- Dictado en español hacia el apartado SOAP elegido, usando `speech_to_text` y el servicio de voz del dispositivo/navegador. Puede requerir Internet y procesamiento del proveedor de voz. Se activa al pulsar Dictar, con permisos de micrófono/reconocimiento configurados en Android/iOS. El texto permanece como borrador hasta la revisión y guardado; no se generan diagnósticos ni planes con IA.

## Permisos

| Información o acción | Admin / MVZ | Auxiliar | Recepción | Estilista |
|---|---|---|---|---|
| Datos generales del paciente | Consultar y alta | Consultar | Consultar y alta | Consultar |
| Contactos de propietarios | Consultar y alta | Sin acceso | Consultar y alta | Sin acceso |
| SOAP | Consultar y anexar | Consultar | Sin acceso | Sin acceso |
| Peso, alergias, prevención | Consultar y anexar | Consultar y anexar | Sin acceso | Sin acceso |
| Texto y firma de consentimientos | Consultar y anexar | Sin acceso | Sin acceso | Sin acceso |

Supabase impone estas reglas mediante RLS y RPCs, además de los controles de interfaz. Roles vienen del login. Relaciones paciente/tutor y evento/paciente incorporan el identificador de clínica para impedir vínculos cruzados.

Los formularios privados se cierran al cambiar sesión, clínica o rol. Lecturas fallidas y pantallas cerradas no conservan ni restauran datos anteriores con respuestas tardías. Los contactos y expedientes se mantienen en memoria mientras se usan; **no se persisten en la base local ni en preferencias**. M4 requiere conexión. Cifrado, caché clínica segura y adaptadores offline son trabajo pendiente; la cola M2 no recibe datos de este módulo aún.

## Migración y auditoría

`supabase/adaptations/existing_patients_m4.sql`: ejecutar una vez después de M2. M3 es independiente. Añade `vet_owners`, `vet_patients`, `vet_patient_events` y comprobantes privados de idempotencia. No modifica las seis tablas anteriores.

Operaciones de alta/registro usan identificador aleatorio de 48 caracteres hexadecimales. El servidor asocia usuario, clínica, identificador y contenido, con bloqueo transaccional: repetir la misma operación devuelve el registro original; reutilizarla con otro contenido se rechaza. La bitácora guarda identificadores y tipo de operación, sin copiar contacto, notas o firmas a un registro menos restringido.

Los formularios mantienen el identificador al reintentar el mismo contenido. Si se modifica el contenido se crea una operación nueva: tras una respuesta de red incierta, actualizar la lista y verificar el registro antes de cambiarlo y volver a guardar. No hay reintentos automáticos ni escritura offline.

La migración está **preparada y probada localmente, pendiente de aplicar en el proyecto remoto**. Puede aplicarse al final junto con M3 antes de probar cuentas reales. No se han creado pacientes, tutores ni expedientes en el Supabase del usuario.

## Verificación y pendientes

`flutter analyze`, `flutter test` y compilación web configurada. Pruebas de fechas, pesos, consentimiento, permisos del cliente, eliminación de datos tras fallos/cierre, dictado simulado con revisión obligatoria, pantalla móvil y cierre de formularios al salir de sesión.

`bash supabase/tests/run.sh patients`: PostgreSQL 17 aislado, migraciones M2–M4 y pruebas de RLS, aislamiento, autor/hora, firma, permisos de escritura, auditoría y reintentos sin duplicación.

Quedan las pruebas de voz real y firma en dispositivos, compilación nativa Android/iOS y conexión a las tablas remotas después de aplicar la migración. No se ha probado un micrófono real ni enviado WhatsApp. Edición con historial de cambios de datos generales/contactos, integración del perfil con M3, avisos automáticos mediante API contratada y caché clínica cifrada se tratarán en las siguientes iteraciones.
