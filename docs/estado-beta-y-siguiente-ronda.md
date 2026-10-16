# Estado de la beta y siguiente ronda

Revisión del 16-oct-2026, después de 13L. Este resumen distingue código probado de despliegue; no autoriza abrir la beta.

## Dónde estamos

| Categoría | Evidencia y alcance |
|---|---|
| Implementado y probado | Los candidatos hasta 13L incluyen permisos por persona/procedimiento, recetas con autorías separadas, hospitalización, inventario/caja, formatos y registro de casos sin PDF. La última ronda documenta 339 pruebas Flutter y 19 trabajos de CI correctos. Esto no acredita todo el corte. |
| Preparado local / repositorio | Las migraciones candidatas, pantallas y pruebas de esas rondas están preparadas. El registro de casos no exige SOAP, peso, temperatura ni un PDF. |
| Aplicado en remoto y probado | Estas rondas no se han aplicado a Supabase. GitHub ejecutó pruebas aisladas; no equivale a despliegue. Consultar los documentos de la etapa 2A para la base desplegada anteriormente. |
| Pendiente | Constatación de muerte, dependencias transversales, validación integrada y despliegue coordinado en pruebas, pruebas reales de dos clínicas/Auth/Storage/Edge y alarmas en Android. |

## Orden de cierre

1. **Constatación de muerte:** sustituir autoridad por puesto por permisos actuales, habilitación vigente e identidad real; capturar resultado y hora expresamente; conservar consentimiento y PDF originales. Riesgo: confundir el consentimiento con la realización o constatación del acto.
2. **Dependencias transversales:** revisar navegación, agregados del dashboard, exportación/respaldos, archivos y rutas de servicio, identidad de plataforma y sincronización. Riesgo: que una ruta secundaria mantenga acceso por el modelo anterior o exponga otra clínica.
3. **Integración en el entorno de prueba:** revisar el orden completo de migraciones, aplicar el conjunto y validar con Auth real. Incluir revocación, vencimiento, usuarios sin sesión, dos cuentas y dos clínicas. Riesgo: que las pruebas aisladas no reproduzcan las políticas y configuración del servidor.
4. **APK y prueba de teléfono:** comprobar permisos efectivos, captura flexible, documentos y alarmas con la app cerrada. Después evaluar apertura de beta con datos ficticios y comparación de resultados, conforme a lo acordado.

Las nuevas propuestas de fluidoterapia, anestesia, referencias fisiológicas, comisiones y demás ampliaciones mantienen su lugar posterior a estas rondas. Las referencias se incorporarán con fuente y estado; no se deducen valores clínicos de ejemplos.

## Inspección de la siguiente ruta

- `lib/modules/forms/clinical/death_screen.dart` usa todavía `ClinicRole.mvz` junto con el responsable del documento para mostrar captura. Inicializa resultado `no_confirmada` y hora actual.
- La última definición encontrada de `clinical_death_add` está en `supabase/adaptations/existing_prescribing_m6.sql`. Conserva una alternativa por rol visual y no tiene sustitución en los candidatos 13A–13L.
- La lectura `clinical_death_list` comprueba consentimiento firmado de eutanasia y `private.form_readable`; falta revisar conjuntamente acceso directo a tabla, contrato de interfaz y escritura.
- Los registros ya son anexos, con referencia de corrección y operación idempotente. Preservar esas propiedades y volver a comprobar autoridad antes de aceptar reintentos.

## Criterios para la implementación siguiente

- La cuenta que constata debe ser la identidad real registrada; no tomar la firma del perfil del responsable ni atribuirle automáticamente el acto.
- Mantener por ahora el alcance actual del responsable del consentimiento, pero exigir habilitación y permiso explícito actual. No ampliar a otros profesionales sin una decisión concreta de esquema.
- Definir el vínculo al tipo de procedimiento y guardar evidencia de la concesión utilizada. No convertir puestos ni asignaciones históricas en permisos.
- Contrato del servidor para lectura y captura; sin alternativa por rol después de reconocerlo. Limpiar capacidades al cambiar identidad/clínica o perder acceso.
- Resultado, fecha/hora, método y hallazgos se capturan explícitamente; disposición, costo y notas posteriores continúan opcionales. No precargar método ni datos clínicos.
- Correcciones anexas con motivo; misma clínica, paciente y consentimiento. Conservar los bytes del PDF firmado y no cerrar automáticamente hospitalización.
- Pruebas de identidad, habilitación, permiso/procedimiento, revocación y vencimiento durante espera, reintentos concurrentes, otra clínica, usuario anónimo y ausencia de valores clínicos preseleccionados.

No hay una nueva decisión de la usuaria necesaria para esta revisión. La migración y el contrato de constatación siguen **pendientes de implementación**; este documento no los presenta como completados.

## Continuación 13M

La implementación local de constatación se describe en [la ronda 13M](permisos-etapa2b19-constatacion.md). Los hallazgos anteriores documentan el punto de partida; la nueva pantalla y migración sustituyen esa ruta en el candidato, aún sin desplegar.
