# 2B-9: receta con firma de consulta y autorización individual

Candidato **13H2**, posterior a 13H1, 16-oct-2026. SQL y Flutter locales; sin despliegue, nuevo APK ni apertura de beta. Usa la atribución aprobada por la usuaria, sin pedir otra vez esa decisión.

## Comportamiento

1. Quien realizó la consulta firma su participación desde su sesión, con nombre y confirmación explícita. No se toma una firma del perfil del responsable ni se acepta un usuario firmante enviado por otra persona.
2. Quien captura selecciona una firma registrada para el contenido/revisión exactos y prepara el documento. Puede ser otra persona, con `prescription.prepare`, lectura de paciente/caso y nombre propio. No necesita declarar una cédula por transcribir.
3. La receta pasa a **`awaiting_authorization`**. El MVZ responsable habilitado, con `prescription.authorize`, revisa las indicaciones estructuradas y autoriza esa versión. Todavía no se emite.
4. Se congela el snapshot con atribución, autorización individual y referencia. El renderer genera el PDF; el registro de artefacto vuelve a comprobar autoridad, contenido y productos después de la espera/renderizado.
5. El responsable revisa y confirma ese PDF exacto. Se registran `issued_by` y hora del servidor. Repetir una confirmación autorizada no vuelve a emitir; una revocación impide reutilizar el recibo de emisión.

El preparador puede consultar el PDF autorizado, pero no emitir por ser preparador. En controlados, preparar/firmar/autorizar/emitir en este flujo corresponde al responsable habilitado con sus permisos; se conservan requisitos de clasificación, fuente vigente, formato verificado y folio capturado. Este bloque no migra la dispensación de inventario ni publica normas.

La firma es declaración atribuida a una cuenta; no demuestra automáticamente que haya efectuado el acto, ni concede permiso clínico para realizarlo. Las restricciones de actuaciones clínicas continúan separadas.

## Esquema y rutas

- Se reutilizan `prescriptions`, sus elementos, perfiles versionados y `private.rx_artifacts`; no se duplica una receta ni un libro de frascos.
- Nuevos metadatos: `consultation_attestation_id`, `prepared_by`, `prepare_grant_id`, `prepared_member_since`, `authorized_by`, `authorized_at`, `authorization_grant_id`, `authorization_reference_id`, `authorization_profile_version_id`, `issued_by`. Restricción de integridad para el conjunto; NULL en históricos, sin conversión de puestos ni firmas.
- `rx_create/save` adquieren clínica/ledger/caso antes de modificar la receta y usan permisos explícitos. Preparación ordinaria no implica autorización de emitir. Controlados no aceptan al preparador ajeno como responsable.
- Se evita reintroducir roles mediante el membrete, los perfiles propios o el historial de delegaciones. Un miembro con puesto visual «estilista» y concesión explícita puede preparar; declarar sus propios datos no le concede habilitación. Revocar una delegación propia exige pertenencia/propiedad, no conservar habilitación profesional.
- `rx_prepare_attributed` consume la atestación privada, fija nombre del preparador, perfil del responsable y snapshot. No permite seleccionar un perfil titular ajeno al responsable del caso. La firma seleccionada de otro miembro ya debe existir como declaración de esa persona.
- `rx_authorize_individual` exige responsabilidad del caso, permiso y habilitación vigentes, revisión exacta y confirmación no preseleccionada. Mantiene las comprobaciones existentes de productos y formato controlado verificados.
- La ruta antigua `rx_prepare` queda cerrada. `rx_finalize` no usa permisos ni habilitación heredados. `private.rx_professional` **no se sustituye globalmente**: sus otros consumidores (formatos/reportes, entre otros) siguen en el inventario de corte pendiente.
- `rx_prescription_permissions`: contrato versión 1, modo `individual`, acciones por receta/revisión. Flutter no deduce autorización desde el puesto; un contrato perdido/desconocido después de conocerlo bloquea acciones, sin volver al flujo antiguo. Se mantiene compatibilidad solo con el servidor anterior al corte que nunca anunció este contrato.
- Listado/detalle y permisos no devuelven vectores de firma. Se retira SELECT directo de `prescriptions.snapshot` al cliente; se conservan columnas necesarias y RLS. El RPC PDF autorizado sigue entregando al renderer el snapshot del servidor; no se acepta uno arbitrario desde Flutter.
- `rx_pdf_register` conserva acceso exclusivo de servicio. Su implementación antigua queda privada sin EXECUTE de cliente/servicio, detrás de una guarda que serializa con cambios de permisos y habilitación. No reutilizar un acceso de servicio como autorización del usuario en Edge.

`prepared_at` de la fila es el acto de preparación; `snapshot.prepared_at` es el momento posterior en que se congela el documento autorizado para PDF. `authorized_at` y `issued_at` representan actos distintos; no se afirma que preparar equivalga a emitir.

## Corrección antes de emitir

Preparador con permiso vigente o responsable con autorización pueden devolver un documento pendiente a borrador, con motivo. Se retira el artefacto **no emitido**, se anulan metadatos de firma/autorización de la versión pendiente y se incrementa la revisión. La atestación original permanece inmutable en su historial y deja de servir para la nueva revisión. Se auditan motivo, referencia de autorización y hash anterior.

Una receta emitida y su PDF no se devuelven a borrador ni se reescriben. Las correcciones de documentos emitidos necesitan un flujo anexo posterior; este botón no lo simula.

## Pruebas

- PostgreSQL con dependencias reales aisladas: firma obligatoria; preparador sin perfil/cédula profesional; autorización por otra persona responsable; sin permiso para emitir por preparar; hash/revisión exactos; PDF solo desde servicio; no exposición en listado/detalle; corrección con nueva firma; revocación antes de guardar artefacto o repetir emisión; inmutabilidad y anon.
- Concurrencia: dos confirmaciones emiten una vez; revocar primero impide confirmar después de esperar el bloqueo.
- Integración real de representación: el harness extrae el snapshot generado por PostgreSQL y lo pasa al renderer, extrae texto del PDF y compara la imagen con la firma capturada. Los bytes `%PDF-SYNTHETIC...` del fixture de registro sirven para probar la frontera SQL, no se presentan como un PDF renderizado válido; la comprobación posterior genera un PDF real por separado.
- Flutter: acciones sujetas a revisión actual; pérdida/versión desconocida del contrato; firma y casilla explícitas; doble toque bloqueado; selección de atestación sin firma prestada; revisión de indicaciones antes de autorizar. Pantallas probadas en tamaño de teléfono.

Ejecutar `bash supabase/tests/run_prescription_individual.sh` (Docker, Node 22, dependencias de `supabase/` y `pdftotext`) y `flutter test`. Workflow manual: `test-permission-cutover.yml`, trabajo `prescription-individual`, sin secretos de servicio ni despliegue.

Resultado local: **290 pruebas Flutter satisfactorias**, análisis sin incidencias, PostgreSQL y carreras satisfactorios; el snapshot real generado por la base también produjo un PDF con la firma y atribución esperadas. No equivale a prueba HTTP/Edge ni a prueba en teléfono físico.

## Pendiente para el corte integral

- Autorización permanente tipada, por alcance y destinatario, con vencimiento/revocación. **Continúa desactivada:** `rx_delegate` no crea delegaciones antiguas y la UI nueva no ofrece compartir firma/dispensación. Las delegaciones previas se muestran como histórico sin facultad nueva. Ampliar el alcance a toda la clínica no se infiere de un caso NULL.
- Migrar dispensación de inventario/ventas, reportes, formatos, Storage, restantes Edge/agregados y navegación. La fuente clínica/normativa y su verificación no se inventan ni se sustituyen por estos tests.
- Hasta migrar los permisos de reportes, Flutter nuevo no consulta ni habilita las rutas heredadas de reportes por puesto. El servidor de esos otros módulos todavía requiere su corte; ocultarlos no sustituye esa migración.
- Aislamiento HTTP real con dos cuentas/clínicas, vencimiento beta, MFA, Storage/Edge y revisión de acceso de las exportaciones. Las pruebas locales no acreditan eso.
- Revisión y aplicación coordinada; versión mínima del APK para el nuevo estado/contrato. No desplegar este candidato de forma aislada ni activar admisiones por estos resultados.
