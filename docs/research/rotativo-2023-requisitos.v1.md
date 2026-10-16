# Requisitos derivados del rotativo — referencia v1

Registro: 16-oct-2026. Fuente inmediata: texto de Claude compartido por la propietaria en esta conversación, titulado «VetDosis Pro - Requisitos de flujo del portafolio de rotativo (v1)». Fuente descrita por ese texto: portafolio de una rotación en una clínica pequeña de Zapopan, agosto–noviembre de 2023. No se consultó el portafolio original en esta revisión.

**Estado de la fuente: sin verificar.** Una experiencia de un sitio en 2023 sirve para formular hipótesis de flujo, no para establecer prácticas universales, normativa vigente o protocolos. Los estados de implementación del texto recibido eran estimaciones con corte al 8-oct-2026; no se adoptan como estado actual del proyecto.

Este archivo es documentación de investigación, no un catálogo clínico ni un archivo cargado por la app. No incorpora fármacos, dosis, intervalos o reglas de retiro a los cálculos. Las prioridades propuestas quedan por validar con testers y no cambian el orden aprobado de seguridad/permisos.

## Hipótesis y contraste con el código

«Existe» en esta tabla significa que se encontró código, no que el flujo esté validado con una clínica real, desplegado en el APK actual o migrado a los permisos nuevos.

| ID / prioridad recibida | Necesidad propuesta | Evidencia y límite actual |
| --- | --- | --- |
| R01 alta | Avisos de tratamiento, incidentes y escalación fuera de horario | Hay planificación de avisos nativos, anticipación, vencimiento y escalación **local**. No se acredita aviso remoto a otro profesional ni alarmas con app cerrada probadas en el teléfono de la tester. Ver `lib/modules/hospital/application/hospital_alerts.dart`, `native_alarm_backend.dart` y `domain/hospital_models.dart`. |
| R02 alta | Hoja diaria derivada de órdenes vigentes y peso fechado | Existe hoja por horas, órdenes/tareas y registros de peso. No se encontró una hoja diaria consolidada que exija peso actualizado o revise recálculos por cambio de peso. Producto/concentración se manejan en el módulo de prescripción; no equivale a integración completa con esa hoja. Ver hospitalización y `lib/modules/prescribing/presentation/prescribing_screen.dart`. |
| R03 alta | Ingreso con consentimiento, asignación de jaula e identificación numérica | La asignación de jaula existe en `hospital_forms.dart`. Formatos, firmas y PDF tienen implementación; no se declara completo ni integrado el consentimiento específico de admisión descrito en el portafolio. No trasladar automáticamente cláusulas de deslinde sin revisión. |
| R04 alta | Frascos, saldo, aplicación exacta y validación profesional | Existen `rx_vial_open/close/adjust`, `rx_medication_report` y `rx_medication_review`, además de sus pantallas. Ya no corresponde marcarlos solo «diseñados». Su autorización nueva, integración completa y pruebas Auth reales siguen pendientes. |
| R05 alta | Captura rápida y utilizable con manos ocupadas | Existe dictado de notas mediante `lib/modules/patients/application/voice_dictation.dart`. «Más rápido que papel» debe medirse por tarea con testers; no es un criterio ya satisfecho por tener voz/autollenado. Nunca autollenar hallazgos normales, dosis, frecuencia, vía ni firmas. |
| R06 media | Calendario preventivo y preguntas previas configurables | Existen eventos preventivos, próxima fecha y preparación manual de recordatorio. No se acredita calendario por producto/clínica ni checklist previo completo. El intervalo citado en la fuente no es un valor predeterminado. |
| R07 media | Pruebas y muestras con resultado, interpretación y foto | No se identificó un flujo específico completo para prueba rápida/coprológico en esta revisión. La interpretación debe quedar como captura profesional, no inferirse de bandas o imagen sin validación. |
| R08 media | Identificación de aislamiento y limpieza al alta | No se identificó una bandera estructurada de aislamiento de paciente/jaula con cierre de limpieza trazable. Registrar como candidato, no como funcionalidad existente. |
| R09 media | Seguimiento de catéter/equipo | No se identificó un seguimiento específico de dispositivos. Las tareas programadas existentes no demuestran ese flujo ni un calendario validado. Los intervalos citados no se cargan como reglas. |
| R10 media | Consulta enfocada ampliable | Hay SOAP y documentos/mediciones clínicas estructurados. No se acredita un flujo completo de examen rápido por motivo. Campos sin captura no significan que sean normales ni que se haya examinado al paciente. |
| R11 media | Promociones, tarifas variables y nota de venta | Existen servicios, precios, caja, ventas y documentos/exportaciones. No se acreditan promociones programables o tarifas estructuradas por talla/pelaje. El corte de permisos financieros continúa pendiente. |
| R12 media | Alimentación dentro de la hoja hospitalaria | No se identificó una hoja estructurada de alimentación con porciones/horarios. No derivar dieta o porciones automáticamente de especie, edad, vómito o diagnóstico. |
| R13 baja | Disposición del cuerpo y residuos | Hay campos de disposición y costo en eutanasia y registro de constatación/corrección en `lib/modules/forms/clinical/death_screen.dart`. No solo un diseño. No se encontró un módulo de residuos. Revisión normativa y permisos de ese flujo siguen pendientes. |
| R14 baja | Plantillas de pendientes/checklists de turno | Existen tareas y mensajes de clínica en operaciones. No se acreditan plantillas recurrentes por turno ni evidencia estructurada de todos los pasos. |
| R15 baja | Cuidados al alta y material compartible | Se abre WhatsApp con texto preparado para recordatorios (`patients_screen.dart`); la persona decide enviarlo. No acredita automatización, WhatsApp Business, entrega confirmada ni biblioteca de infografías integrada. |

## Decisiones de flujo propuestas para validar

1. **Hoja diaria como vista de órdenes vigentes:** identificar fecha, zona horaria, orden/versión y autor. No duplicar órdenes al cambiar de día. Conservar la historia de cambios y lo realmente aplicado.
2. **Peso fechado y recálculo revisable:** señalar peso ausente o antiguo; permitir capturarlo. Un peso o una concentración nuevos pueden producir una propuesta de cálculo, pero no cambian dosis, ml, vía, horarios ni tareas de una orden vigente hasta la revisión y autorización que correspondan. No confundir resultado de calculadora con prescripción.
3. **Escalación remota explícita:** antes de implementarla, definir destinatario de turno, aceptación del relevo, plazo elegido, canal autorizado, reintentos y estados de entrega/lectura/confirmación. Un aviso local vencido no equivale a que otro profesional fue avisado. No registrar «Aplicado» desde una notificación ni por recibir/leer un aviso.
4. **Admisión/alta sin duplicar identidades:** reutilizar datos autorizados; separar firma del tutor, preparador y autorización profesional. Jaula e identificación no sustituyen consentimiento. No copiar textos de exención de responsabilidad del sitio observado.
5. **Pruebas, dispositivos, aislamiento y alimentación:** candidatos de flujo estructurado con autor/fecha/estado. Las frecuencias y criterios clínicos quedan pendientes de fuente y revisión; no se rellenan por defecto.
6. **Comparación con el papel:** medir tiempo, toques, correcciones y campos omitidos en la misma tarea; separar primera utilización de uso habitual. No prometer una mejora temporal sin medirla ni eliminar controles de confirmación para alcanzar esa meta.

## Caso de recorrido ficticio propuesto

Se conserva como hipótesis de prueba el caso de perro de **7 kg** con vómito y diarrea, resultado positivo de parvovirus capturado por la persona y recorrido de admisión → aislamiento/jaula → hoja hospitalaria → seguimiento de peso/catéter → alta/cuidados → limpieza. El peso y el resultado son datos inventados del escenario, no tablas clínicas.

El escenario completo todavía no es ejecutable con todas sus funciones en la app. No escribir dosis, tratamientos, concentraciones, dieta, horarios ni duración clínica para rellenar los huecos. Separar los pasos disponibles de los que están por diseñar. Las pruebas de calculadoras en paralelo no intervienen en la atención real y usan valores sin identificadores de terceros, conforme al alcance acordado y los términos de beta.

## Preguntas para la tester

- ¿Hay guardia nocturna o responsable local/remoto por turno y cómo recibe los avisos?
- ¿Qué partes de la hoja de hospitalización consumen tiempo o producen correcciones?
- ¿Qué se captura realmente, quién lo registra y quién autoriza cada orden?
- ¿Cómo documentan frascos, tomas, pendientes de validación y discrepancias?
- ¿Usan aislamiento, revisión de dispositivos y alimentación con hoja propia?
- ¿Qué tareas registrarían en menos pasos sin perder trazabilidad?
- ¿Qué tarifas/promociones y canales de comunicación usan realmente?

Se recaban respuestas voluntarias sin expedientes, identificaciones ni capturas con datos personales de terceros. Las observaciones sobre costo no bastan para fijar precios: validar disposición de pago y costo real del servicio por separado.

## Relación con el trabajo autorizado

Este registro orienta el bloque pendiente de hospitalización/aplicaciones/frascos. No sustituye las aprobaciones de permisos 2A, 13A, 13B y 13C ni autoriza abrir beta, desplegar funciones, enviar mensajes a terceros o implementar las quince propuestas a la vez. El siguiente trabajo técnico sigue siendo separar `hospital.schedule`, `drug.administer`, `vial.draw`, `medication.report` y `medication.validate`, conservando al ejecutante y la validación profesional como actos distintos.
