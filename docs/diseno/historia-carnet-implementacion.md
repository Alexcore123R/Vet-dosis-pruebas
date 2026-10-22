# Historia clínica y carnet — primera integración

Base: design/production-tools, ec615ae. Rama separada; no despliegue remoto.

Pacientes añade captura de historia clínica estructurada con antecedentes, alimentación, entorno, reproducción, anamnesis, exploración, constantes con unidades, problemas, estudios y seguimiento. Reutiliza el evento SOAP con record_type=clinical_history, sin introducir un tipo de evento ilegible para clientes anteriores. Los campos estructurados se conservan en el payload y el resumen SOAP permite lectura básica en versiones anteriores. No genera el PDF firmado de Formatos ni sustituye sus plantillas.

El carnet utiliza los eventos preventive existentes, sin copiar filas. Añade coberturas o tipo de desparasitación, producto/marca opcional, procedencia explícita, persona que aplica o refiere, referencia documental y profesional que indicó la próxima fecha. La evidencia es una referencia de texto: la carga de imágenes sigue pendiente. Las aplicaciones de clínica requieren fecha exacta y aplicador declarado; el servidor conserva quién capturó. El nombre declarado no acredita una habilitación profesional.

Las fechas externas desconocidas o aproximadas conservan la fecha de registro en el campo date legado y se muestran expresamente como desconocidas/aproximadas mediante date_precision; ningún consumidor debe tratar ese campo como aplicación exacta sin revisar la precisión. El producto desconocido se representa como No especificado para compatibilidad con la RPC actual. Una próxima fecha debe ser posterior o igual a la fecha legada, y tener profesional indicado. Los consumidores heredados, PDF, estadísticas y recordatorios requieren revisión antes de despliegue para respetar la precisión; no se afirma compatibilidad clínica completa con clientes antiguos.

El calendario lista próximas fechas indicadas, sin crear citas ni esquemas automáticos. Las etiquetas triple/séxtuple no expanden coberturas automáticamente. La selección estructurada de componentes y la planificación de vacunas sin evento previo quedan pendientes; no se importa el calendario de 2023 como recomendación universal.

Seguridad: no modifica RLS, funciones de autorización ni grants. La adaptación patient_history_booklet_v1.sql añade validación antes de insertar; no reabre rutas cerradas por el candidato 13C. No aplicar scripts 01–08 ni desplegar SQL automáticamente. Revisar contratos remotos y consumidores antes de activar. Los registros previos conservan origen no especificado. Reintentos reutilizan el identificador existente; cambio de contenido genera una operación nueva.

Pendientes de enlace: documentos clínicos y PDF firmados de Formatos, creación de citas, adjuntos privados, inventario/lotes/caja, recetas y actuaciones profesionales, exportación del carnet, correcciones estructuradas y versión visible de app. Evitar recapturar alergias, pesos y prevención existentes.

Referencias aportadas: formatos de historia general/canina/felina y rotativo AIRR, calendarios páginas 21–22. Se conserva solo su utilidad estructural, sin datos personales, membretes, firmas, dosis ni costos. Las tablas farmacológicas, bienestar, nutrición y operación quedan como material para revisar después; el catálogo Qwen sigue separado y deshabilitado para cálculo.

Validación: se incluyen pruebas de dominio para procedencia, fechas desconocidas, idempotencia de normalización, próxima fecha e historia estructurada; workflow independiente ejecuta análisis y suite Flutter. Sin Flutter ni Android SDK local; no afirmar aprobación hasta ver Actions. La validación SQL y pruebas en teléfono siguen pendientes.
