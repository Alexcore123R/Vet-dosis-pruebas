# Propuesta 12C: aviso de privacidad vinculado a los términos

Estado: esquema aprobado expresamente por la usuaria y aplicado en el proyecto de pruebas el 16 de octubre de 2026. Borradores vinculados por versión y SHA-256, sin publicación de documentos ni apertura de admisiones.

Aplicación: [ejecución 38862986989](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38862986989), commit `de49511`. El operador confirmó `beta_closed=true` y `exact_unpublished_binding=true`. No creó aceptaciones ni renovó inscripciones.

Comprobación posterior: [ejecución 38863156552](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38863156552), commit `3309e9e`, acción `inspect`. Esquema completo reconocido y tres pruebas HTTP anónimas satisfactorias: RPC de aceptación, RPC de inscripción y lectura del historial denegados por permisos. Se usa exclusivamente la clave pública de cliente mediante secretos del servicio; no se registran credenciales ni respuestas privadas.

Pendientes actuales: comprobar aceptación/autorización con cuentas reales y documentos de prueba publicados de forma controlada, generar el APK actualizado y resolver los demás bloqueos de permisos antes de abrir la beta. La publicación de los documentos legales de la usuaria no fue autorizada ni realizada en este paso.

## Estado de partida anterior a la aprobación

- Implementado y probado: términos congelados por versión/hash, historial inmutable, validación en servidor, rechazo de versiones obsoletas y conservación del plazo original de la beta.
- Preparado local: pantalla con ambos textos y controles separados; migración 12C; operador de importación de borradores; pruebas de base de datos y Flutter.
- Aplicado en remoto y probado: 12A/12B y borrador de términos v1 revisado, verificado en ejecución 38842849820. La beta permanece cerrada.
- Pendiente: aprobación de 12C, aplicación remota y comprobación HTTP con cuentas reales; futura publicación de textos y distribución del APK, después de los demás requisitos de beta.

## Decisiones de esquema para revisión

| Entidad | Cambio propuesto | Protección |
| --- | --- | --- |
| `private.beta_privacy_notices` | Texto, versión, SHA-256, estado y fecha de publicación | Sin acceso directo de clientes; hash comprobado; publicación inmutable |
| `private.beta_terms` | `privacy_version` referencia una versión concreta del aviso | Un término publicado no puede cambiar de aviso; publicación requiere aviso publicado |
| `public.terms_acceptances` | `privacy_version` y `privacy_hash` | Se escriben junto con la aceptación de términos, con autor y hora de servidor existentes; historial inmutable y visible solo para su dueño |

Las filas históricas mantienen NULL en los campos nuevos. No se interpreta una aceptación anterior como lectura del aviso. Solo se registran ambas referencias tras la confirmación explícita de la persona. La lectura del aviso no se presenta como consentimiento universal para finalidades opcionales.

Las versiones de términos y aviso son independientes. Si cambia el aviso, se publica una nueva versión de términos vinculada a ese nuevo aviso: nunca se redirige una versión ya publicada. El estado de aceptación pendiente se deriva de la nueva versión de términos.

## Flujo y compatibilidad

1. El servidor devuelve los términos y el aviso publicado vinculado, cada uno con texto, versión y hash.
2. La pantalla muestra ambos textos. La persona marca aceptación de términos y confirmación de lectura del aviso por separado; ninguna casilla está preseleccionada.
3. La confirmación envía ambas versiones y hashes. El servidor verifica la última versión de términos y su vínculo exacto antes de guardar la constancia en una sola transacción.
4. Un cambio de versión/hash de cualquiera de los documentos elimina ambas selecciones en pantalla.
5. Un cliente antiguo que omite el aviso es rechazado si la versión de términos exige aviso. No se otorga aceptación tácita ni se amplía la beta. Los documentos históricos sin vínculo conservan su compatibilidad.
6. Se mantiene consulta/exportación ante vencimiento o términos pendientes. Una persona ya inscrita puede confirmar textos nuevos sin renovar la prueba.

Los RPC mantienen los nombres `beta_accept_terms` y `beta_enroll`; añaden parámetros opcionales para versión/hash del aviso. Se reemplazan las firmas anteriores sin dejar sobrecargas ambiguas, y se recarga el esquema de PostgREST. La app omite parámetros nuevos cuando el servidor todavía devuelve documentos históricos sin aviso, por lo que el cambio local no requiere activar 12C inmediatamente.

## Fases y riesgos

1. Revisión de esta propuesta y migración: riesgo de registrar una lectura inexistente, mitigado con campos históricos nulos y comprobación exacta.
2. Aplicación en pruebas, con admisiones y enforcement cerrados, e importación atómica de ambos borradores: riesgo de estado parcial, mitigado con transacción, detección de instalación incompleta y verificación de hashes.
3. Comprobaciones HTTP y actualización del APK: riesgo de clientes antiguos, mitigado con rechazo del aviso omitido y aviso de actualización; no abrir beta durante este paso.
4. Publicación posterior de ambos textos en una transacción y revisión del resto de bloqueos de beta. No forma parte del operador de preparación.

La migración añade campos y reemplaza funciones dentro de una transacción. Tras publicarse documentos o registrarse constancias, las correcciones son versiones nuevas; no se borran constancias para retroceder.

## Evidencia local

Resultado de esta revisión: `flutter analyze --no-pub` sin observaciones; 261 pruebas Flutter satisfactorias (13 del flujo beta); 32 pruebas Python del operador satisfactorias; suite PostgreSQL aislada, incluida la extensión 12C y la importación de ambos borradores reales, satisfactoria. No son pruebas HTTP del servidor remoto. No se generó ni distribuyó un APK en este paso.

- SQL aislado: rechazo de aviso omitido o hash incorrecto; texto servido correcto; confirmaciones repetidas sin duplicados; aislamiento de constancias; bloqueo de anon y edición del historial; conservación de beta vencida; inscripción revertida si falta el aviso; importación de las dos copias reales como borradores sin aceptaciones.
- Flutter: texto y versión visibles, confirmación de lectura obligatoria, envío de versión/hash exactos, reinicio de ambas casillas al cambiar solo el aviso, junto con casos anteriores de términos y vencimiento.
- Operador: origen y huellas exactas, inspección de solo lectura, rechazo de falta de confirmación, beta abierta o esquema parcial. No publica ni abre beta.

Archivos: `supabase/proposed/12C_privacy_binding.sql`, `scripts/supabase/privacy_schema.py`, `supabase/tests/privacy_binding.sql`, `test/beta_boundary_test.dart`.

El flujo manual `.github/workflows/prepare-test-privacy.yml` queda preparado para inspección o aplicación posterior a la aprobación. Su acción predeterminada es `inspect`; `prepare` exige `PREPARAR_AVISO_SIN_PUBLICAR`. No se ejecutó contra el servidor durante esta revisión. El operador anterior de términos reconoce también la firma ampliada para no interpretar 12C como una instalación parcial.
