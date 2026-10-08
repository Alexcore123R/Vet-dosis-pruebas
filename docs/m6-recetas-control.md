# M6: recetas, perfiles y registro único de medicación

Implementación local para Flutter y Supabase. No se ha aplicado esta adaptación al proyecto remoto ni probado en cuentas o dispositivos reales.

## Perfiles y permisos

Cada usuario conserva versiones de su nombre, cédula, registro y firma. Los datos autodeclarados se identifican como sin verificar. Una habilitación profesional revisada en servidor, con referencia y vencimiento, es independiente del rol administrativo y de la cédula escrita. La operación privilegiada `rx_professional_authorize` no está disponible para el cliente ni para el admin de una clínica.

El titular concede o revoca por separado el uso de datos, firma, preparación y emisión ordinaria. Preparar o emitir como auxiliar exige también acceso y autorización vigente en el caso, y un producto clasificado con fuente verificada que permita ese flujo. Un permiso compartido jamás habilita recetas controladas, validaciones o reportes oficiales. Compartir firma es opcional; el PDF distingue al titular de los datos del usuario que emite con firma propia.

Las firmas e historial de perfiles permanecen en tablas privadas. Los documentos históricos conservan su versión y firma; revocar un permiso impide nuevos usos, pero no modifica un documento ya emitido. La preparación y la emisión comprueban permisos y versiones en servidor.

## Recetas y PDF

La receta contiene paciente, propietario, responsable del caso, emisor, presentación comercial exacta y cantidades, vía, intervalo, duración y cuidados capturados. No propone dosis. Los folios oficiales se ingresan manualmente; el ID interno no se presenta como folio oficial.

`forms-pdf` genera el PDF en servidor a partir de la instantánea preparada allí. Se guarda el archivo y su hash; la app verifica el hash y presenta ese mismo archivo antes de emitir. La finalización exige la revisión y hash exactos, con permisos aún vigentes. Cambios en borradores invalidan la revisión. Los archivos emitidos no se regeneran al cambiar el perfil o el membrete.

El PDF se comparte mediante las opciones del sistema. El enlace `wa.me` prepara el texto de las indicaciones para envío manual; no adjunta automáticamente un PDF ni usa la API de WhatsApp. En web, la disponibilidad del diálogo de compartir depende del navegador.

Los formatos clínicos de M-FORMATOS también pueden vincular un perfil autorizado. La vinculación conserva la versión y vuelve a verificar permisos antes de firmar. Las capturas manuales existentes siguen disponibles; no conceden habilitación profesional.

## Aplicaciones, frascos y hospitalización

La hoja clínica y anestésica usan el registro único de medicación, sin una segunda lista independiente. Cada aplicación conserva cantidad exacta, unidad, producto, lote, paciente, procedimiento, aplicador, usuario que reportó, momento observado y hora del servidor. Queda pendiente de revisión. Solo el MVZ habilitado responsable valida o solicita corrección; la corrección se agrega con motivo y mantiene el original.

Un frasco registra apertura, volumen inicial medido, lote, responsable, saldo y movimientos. La aplicación resta una sola vez, incluso ante reintentos. Validarla no vuelve a descontar. Las correcciones agregan la diferencia contable; merma, devolución y ajuste requieren cantidad exacta y motivo. El cierre conserva saldo esperado, saldo medido y diferencia; una discrepancia exige nota del MVZ. No se modifica el volumen inicial para cuadrar cuentas.

Una aplicación ya realizada que exceda el saldo o se reporte con el frasco cerrado se conserva como incidencia. No se valida silenciosamente ni entra en un reporte completo. La corrección en un frasco cerrado sigue marcada; aún no existe un flujo separado para resolver esa incidencia tras el cierre.

El responsable puede programar horas explícitas desde una receta emitida para una estancia activa. Las tareas vinculadas se confirman desde el registro único con cantidad/lote, no con el botón antiguo de administración. Al regresar, hospitalización actualiza las tareas y alarmas locales. No se interpreta automáticamente un intervalo textual para inventar horarios.

## Reportes y fuentes

Los reportes congelan periodo, corte, registros validados y pendientes. Un pendiente o incidencia los marca incompletos. Validaciones posteriores no alteran un reporte ya preparado o emitido. La exportación CSV incluye el estado, referencias y cantidades exactas; está preparada para abrir en Excel y neutraliza fórmulas introducidas como texto. No es un archivo XLSX.

El catálogo regulatorio de la app está vacío intencionalmente. Los productos y requisitos oficiales deben publicarse como versiones con fuentes verificadas mediante un flujo administrativo de servidor. Un producto sin clasificación verificada no se puede emitir con permisos ordinarios de auxiliar. La emisión controlada y los reportes oficiales se bloquean sin referencias suficientes y campos requeridos. Los datos sintéticos de las pruebas no se distribuyen como datos clínicos o normativos.

## Instalación y límites

Aplicar una sola vez `supabase/adaptations/existing_prescribing_m6.sql`, después de las adaptaciones M2, M4, M5 y ambas fases de M-FORMATOS; desplegar también la actualización de `forms-pdf`. Antes de aplicar remotamente, revisar el esquema real y su respaldo. No ejecutar esta adaptación nuevamente sobre una instalación ya adaptada.

Los perfiles, recetas, aplicaciones y reportes requieren conexión; no se guardan en preferencias ni en caché sin cifrado. La descarga de un PDF o CSV crea un archivo sensible bajo control del usuario.

Pendiente: referencias clínicas/regulatorias reales, vincular una dosis calculada verificada de M3 (se muestra no disponible), prueba integrada del descuento de envases/dispensación/POS ya implementados en [M8](m8-inventario-ventas.md), XLSX, instalación remota y pruebas reales de Android/iOS, notificaciones con app cerrada y cuentas distintas. M8 ya revisa el permiso de dispensación al registrar la venta; falta comprobarlo en el proyecto remoto.

## Comprobación local

- `flutter analyze` y `flutter test`: análisis limpio y 82 pruebas aprobadas.
- `bash supabase/tests/run.sh prescribing`: permisos, aislamiento por clínica, auxiliares sin actos reservados, revocación entre preparación y emisión, archivos inmutables, correcciones anexadas, reportes congelados y conexión con hospitalización/formularios. Incluye dos conexiones concurrentes sobre el mismo frasco y reintentos de ajustes sin duplicación.
- `node --test supabase/tests/forms_renderer.test.mjs`: 7 pruebas con PDF real, firmas, folio capturado, paginación, membrete/logo y reporte incompleto.
- La comprobación de tipos de la función utiliza `supabase/functions/forms-pdf/deno.json`. Compilación web configurada en `build/web`.
