# Portafolio de rotativo: propuestas para VetDosis Pro

Revisión: 16 de octubre de 2026. Fuente: PDF original de 103 páginas aportado por la propietaria. Se revisaron su estructura, secciones de flujo y casos, bibliografía pertinente y las tablas de páginas 40 y 60 mediante imagen. No es una validación integral de cada afirmación, tratamiento o norma. Las páginas citadas son las del PDF y coinciden con las impresas en estas secciones.

## Resultado de la revisión

El documento sí sirve para orientar captura, referencias y recorridos de prueba. Su experiencia de una clínica en 2023 no fija protocolos universales. Separar lo observado en esa clínica, las recomendaciones de la estudiante, los datos de cada paciente y los valores bibliográficos. Las dosis administradas de un caso no equivalen a una pauta utilizable para otros pacientes.

No se copia el original al repositorio: contiene identificadores, datos de contacto e imágenes. Este paquete no incluye esos datos ni fotografías. Los casos se describen aquí solo por flujo; los futuros escenarios de prueba usarán identidades y circunstancias sintéticas, sin reproducción de expedientes.

## Estado actual en las cuatro categorías acordadas

| Categoría | Evidencia y límites |
|---|---|
| Implementado y probado | Captura flexible 13D: ingreso sin jaula y cambios auditados, 268 pruebas Flutter satisfactorias y cuatro trabajos SQL de CI en ejecución 38877608215. Es un candidato, no una función disponible en el APK instalado. La base previa de servicios ya tiene comisión por porcentaje/bono, un realizador y vínculo con caja; esta revisión confirma el código, sin repetir pruebas ni certificar el despliegue de ese módulo. |
| Preparado local | Candidatos 13A–13D para el corte de permisos. En esta revisión: 16 referencias de constantes transcritas de p.60, cuatro discrepancias y propuestas de evolución. Son archivos versionados de investigación; no se importaron al catálogo de la app. |
| Aplicado en remoto y probado | La base beta/permisos 11A y los bloques legales anteriores constan en el seguimiento previo; permanecen sin activar el corte de permisos. Esta revisión del portafolio no despliega ni acredita ninguna funcionalidad remota nueva. |
| Pendiente | Completar permisos de hospitalización/aplicación/frascos, revisión profesional de referencias, biblioteca de consulta, consulta enfocada completa, cotización variable, varios participantes y liquidación de comisiones. Pruebas con cuentas reales y teléfono según el bloque correspondiente. |

## Propuestas apoyadas en páginas concretas

| Propuesta | Evidencia del portafolio | Implementación propuesta |
|---|---|---|
| Consulta enfocada ampliable | p.24 describe profundidad según motivo; p.33–38, 39–44 y 45–53 muestran tres historias organizadas por caso; p.58–62 contienen recomendaciones y formatos. | Motivo, nota breve y hallazgos capturados; desplegar anamnesis, exploración, problemas, pruebas y seguimiento según se necesiten. Ningún hallazgo normal preseleccionado; guardar sin completar todos los apartados. Una firma/cálculo conserva sus requisitos propios. |
| Referencias fisiológicas consultables | p.60, cuadro 12; bibliografía candidata en p.90. | Ficha de referencia con especie, unidades, contexto, fuente/página, versión y estado. Consulta separada del registro de una medición. No activar clasificación normal/anormal con estas filas sin revisión. |
| Hoja hospitalaria orientada al trabajo | p.17 y 26–30: hoja, medicación y tareas de hospital. | Vista por día de órdenes vigentes y aplicaciones reales. Peso/temperatura/seguimientos elegidos según el caso, sin exigirlos a diario por defecto. Un cambio de peso no modifica silenciosamente órdenes. Jaula opcional y cambios ya preparados en 13D. |
| Pruebas y seguimiento | p.19 y 24–26, pruebas rápidas y muestras; p.35–36 y 50–51, resultados complementarios. | Registro ligado a consulta/paciente con tipo, fecha, resultado, autor e interpretación registrada por la persona; adjunto opcional con permisos. No inferir automáticamente diagnóstico de una foto o bandas. |
| Aislamiento y limpieza | p.26 y 29, manejo de pacientes sospechosos/áreas. | Estado de aislamiento y tareas de limpieza trazables; no copiar listados de enfermedades como clasificación vigente. |
| Estética: valoración y cotización | p.17–18: valoración por estado del pelaje, raza/tamaño, servicio y petición del cliente. | Valoración breve opcional, precio base, extras y descuento desglosados, importe acordado y revisión si cambia el alcance. El extra de baño medicado viene de la conversación actual; su producto/uso clínico sigue el flujo autorizado separado del cobro. |
| Personal y comisiones por servicio | Necesidad aportada por la propietaria en la conversación; no se atribuye al PDF una política de comisiones que no establece. | Conservar quién realizó y quién registró; admitir varios participantes en una fase posterior. Comisión porcentual o fija por clínica/persona/servicio, sin valor por defecto. La cirugía requiere además el acto clínico autorizado; el cobro no prueba ni habilita el acto. |
| Promociones comerciales | p.24 cita descuentos de días concretos. | Promociones configurables, sin precargar los días o porcentajes de esa clínica. El 30 % de esta página es descuento al cliente, no comisión al trabajador. |
| Alimentación, pendientes y cuidados | Hospitalización p.26–30; nutrición p.63–80; materiales p.81–83. | Tareas y hoja de alimentación elegidas por el equipo. Nutrición como revisión bibliográfica futura; no convertir todas las fórmulas o recomendaciones del documento en calculadoras activas. |

## Datos extraídos y discrepancias

`constantes.p60.v1.csv`: 8 parámetros × 2 especies = **16 filas**, todas `sin_verificar` y `importar_en_app=false`. Incluye frecuencia respiratoria, cardiaca, relleno capilar, temperatura, presiones sistólica/media/diastólica y producción de orina. Edad y condiciones de medición se dejan vacías porque no se especifican en el cuadro. Se conserva el texto original y una normalización numérica de transcripción; no se inventan rangos por edad, tamaño o reposo.

El relleno capilar se expresa literalmente como `< 2`: no se transforma en intervalo inclusivo ni se le añade un mínimo. Los otros extremos no indican inclusividad explícita. La fórmula de presión media impresa queda documentada, no implementada.

`discrepancias.v1.csv`: p.40 presenta referencias felinas diferentes de p.60 para temperatura, frecuencia cardiaca y respiratoria. Además, el relleno capilar figura como `>3 seg.` frente a `< 2 s`. Se retienen como discrepancias; no se elige una versión correcta ni se corrigen datos silenciosamente. La p.40 repite la fila de pliegue cutáneo; no se convierte en dos mediciones diferentes.

La p.90 lista una referencia de Ateuves (2014), pero la entrada bibliográfica está mezclada con otra y el cuadro no la atribuye explícitamente. La relación y el documento externo siguen por comprobar. Todo dato conserva como fuente inmediata el portafolio, no una fuente primaria supuestamente verificada.

Tablas de fármacos, vacunas, nutrición y normativa: inventariadas como material candidato, **no importadas** en esta entrega. Concentraciones, presentaciones y contexto deben cotejarse antes de separar filas; no inferir concentración desde una cantidad en ml usada en un caso. El material normativo histórico no establece por sí solo la norma o el formato hoy vigente.

## Lo que ya existe de servicios y comisiones

Evidencia: `supabase/adaptations/existing_operations_m9.sql` y `lib/modules/operations/presentation/operations_screen.dart`.

- `clinic_services`: precio, porcentaje o bono fijo, valor de comisión y versión.
- `clinic_service_acts`: servicio, una persona realizadora, cita opcional y copia congelada del precio/regla/comisión. Los actos son inmutables.
- Caja vincula el acto al cobro; exportación CSV y resumen por persona.
- El campo histórico `professional_id` referencia un integrante; su nombre no acredita cédula ni habilitación.
- El estado actual `paid` significa que **el cliente pagó el servicio** mediante venta vigente; no que la clínica pagó la comisión al integrante. Debe aclararse en la UI antes de ofrecer una liquidación de comisiones.

No rehacer estas entidades. Ampliar su flujo y migrar sus permisos por separado: los accesos antiguos por rol no satisfacen el nuevo modelo aprobado. El candidato 13B deja los agregados no migrados cerrados; no reabrirlos automáticamente para mostrar comisiones.

## Fases propuestas y riesgos

1. **Ahora: preparar referencias y decisiones.** Archivos de investigación versionados, discrepancias y esta propuesta. Riesgo: confundir transcripción con validación; por eso no se cargan en calculadoras ni se marcan verificados. No cambian la base ni el APK.
2. **Mantener el bloque prioritario: terminar permisos clínicos.** Hospitalización, órdenes, administración, frascos y validación; después el corte coordinado con UI compatible. Riesgo: aplicar una migración aislada o conservar una ruta antigua que eluda permisos. No abrir beta por haber terminado un archivo.
3. **Consulta enfocada y referencias.** Captura opcional por caso, fuente visible y escenarios sintéticos de recorrido digestivo, herida cutánea y alteraciones hematológicas. Los tratamientos no se precargan desde los casos. Riesgo: que una plantilla rellene normales o convierta una observación histórica en recomendación.
4. **Servicios variables y comisiones.** Primero cotización base/extras y un realizador aprovechando M9; después participantes y liquidación. Riesgo: duplicar cobros, usar precio de catálogo nuevo para un acto antiguo, confundir cobro con pago al personal o no revertir correctamente una devolución.
5. **Seguimientos adicionales.** Pruebas, aislamiento, alimentación, dispositivos y pendientes según uso real de testers. Frecuencias elegidas por clínica/caso; sin valores clínicos universales derivados del portafolio.

## Decisiones de esquema para revisar antes de implementar

Estas son propuestas concretas, **no migraciones aprobadas ni aplicadas**:

- **Referencias:** entidad/versionado independiente de mediciones del paciente. Campos: parámetro/especie/contexto, literal, límites y operadores, unidad, fuente/página/hash, estado y revisión profesional. Un cambio produce versión nueva; no cambia mediciones, órdenes o interpretaciones anteriores. No aceptar un booleano `verificado` del cliente como autorización.
- **Cotización:** cabecera por clínica con paciente/cita opcionales, estado y versión; líneas de base, extras y descuentos, moneda e importes decimales; quién acordó el precio y cuándo. El importe final no se altera al cambiar el catálogo. Modificaciones aceptadas y cancelaciones trazables, no sobrescribir ventas.
- **Participantes y comisión:** extender el acto existente con participantes y copia de regla/base/importe por beneficiario. Mantener el realizador histórico y no convertirlo automáticamente en varios beneficiarios. Las reglas nuevas se aplican hacia adelante.
- **Liquidación:** registro separado del cobro al cliente, con pagos, ajustes inversos y saldo. Definir si la comisión se genera al terminar o al cobrar; si usa subtotal antes/después de descuentos, impuestos y extras; qué pasa con devoluciones y cómo se reparte entre participantes. Ninguna de esas decisiones la fija el portafolio. Propuesta inicial: mostrar explícitamente base elegida y no habilitar una regla incompleta.
- **Permisos financieros:** lectura propia/global, gestión de tarifas, realización de servicio, aprobación de ajustes y liquidación como capacidades distintas. Acceso a una comisión no concede lectura de toda la historia clínica ni habilitación para cirugía o medicación. Definir los códigos en el corte correspondiente, sin reutilizar etiquetas de puesto como autoridad.

No hacen falta decisiones nuevas para mantener campos clínicos opcionales: eso ya se acordó. Sí hay que revisar las bases y liquidación antes de programar comisiones variables. No se necesita resolverlas para continuar el bloque pendiente de permisos hospitalarios.

## Verificación de esta entrega

Revisión visual de p.40 y p.60; 16 filas únicas y cuatro discrepancias, fuente SHA-256 en `fuente.v1.json`, todos los registros sin verificar y sin carga en app. No se copian identificadores ni tratamientos de los casos en estos archivos. Solo documentación y datos de investigación: no se ejecutaron de nuevo las 268 pruebas de la app porque no cambió código ejecutable.
