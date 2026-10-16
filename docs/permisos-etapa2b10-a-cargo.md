# 2B-10: dejar a cargo y retomar revisión

Candidato local **13H3**, posterior a 13H2, 16-oct-2026. No desplegar por separado, no abrir beta ni generar otro APK por este bloque. El permiso previo no equivale a afirmar que el MVZ revisó individualmente una receta. Tampoco acredita por sí mismo cumplimiento normativo: las fuentes y formatos clínicos conservan sus controles de verificación.

## Alcance implementado

- El MVZ responsable habilitado, con `prescription.authorize`, elige **un caso existente**, una persona con lectura y `prescription.prepare`, y vencimiento explícito. Puede crear otra autorización para otro caso; no existe caso NULL ni facultad para casos futuros/toda la clínica.
- La persona acepta desde su sesión. No hay selección automática de autorización, fecha límite o aceptación. El vencimiento debe ser futuro y estar dentro de la vigencia de los dos permisos operativos.
- Solo recetas ordinarias con productos/clasificación verificables por el flujo existente. Los controlados siguen exclusivamente en el flujo individual del responsable habilitado. No se crean permisos de procedimiento, aplicación, extracción ni dispensación al aceptar.
- Quien realizó la consulta registra su nombre y firma propia sobre el borrador exacto; quien prepara queda identificado. La persona a cargo selecciona la autorización aceptada y revisa/confirma el PDF para emitir con su propia identidad. Nunca se comparte la firma del MVZ.
- El PDF dice **autorización previa** y **«No consta revisión individual de este documento»**, con responsable, fecha, referencia, caso y vencimiento. La firma impresa sigue siendo la de quien realizó la consulta. La revisión posterior no sustituye este PDF ni reescribe el acto original.
- Cada primera emisión crea un aviso persistente para el MVZ que autorizó, con receta, persona, fecha de servidor y hashes exactos. Abrir el tablón/PDF no marca revisado: necesita confirmación explícita y permiso/habilitación vigentes del MVZ original. Una nota de revisión es opcional e inmutable; no corrige la receta emitida.
- **Retomar revisión** revoca todas las autorizaciones temporales de recetas ordinarias que ese MVZ ofreció en la clínica, incluidas las no aceptadas. No revoca las de otro MVZ ni modifica documentos emitidos. Los pendientes pueden volver a borrador con motivo, nueva revisión y nueva firma, para autorización individual.

Los avisos aparecen en el apartado **A cargo**, con indicador de pendientes en la pantalla de prescripción. Se actualizan cada 30 segundos mientras esa pantalla permanece abierta y no está en un formulario/PDF. **No es push, alarma de fondo ni aviso con la app cerrada.** La actualización fallida vacía el tablón y bloquea las acciones temporales hasta recuperar datos. Si cambia cuenta, clínica o paciente, se descarta el modelo anterior.

## Esquema

Se reutiliza `professional_delegations`; se añaden `document_type`, identificadores exactos de permiso del otorgante y preparador, fechas de pertenencia y versión del perfil responsable. Los registros antiguos siguen sin tipo y no adquieren facultades por migración.

`prescriptions.authorization_mode` distingue `standing`; los documentos H2 existentes conservan NULL y su atribución individual explícita, sin promocionar registros históricos. Se adapta la restricción de atribución: en autorización temporal, `authorized_by` es el MVZ que otorgó el permiso previo e `issued_by` es quien efectivamente emitió. Se conserva la consulta firmada, el preparador y todas sus referencias.

Nuevas tablas privadas, append-only, RLS sin acceso directo de cliente:

- `rx_standing_acceptances`: una aceptación por autorización.
- `rx_standing_events`: un aviso por receta efectivamente emitida, con hashes originales.
- `rx_standing_reviews`: una revisión posterior por aviso, con autor, fecha de servidor y nota.

Las tablas nuevas reciben las guardas de beta. Las rutas RPC comprueban pertenencia, lectura, caso, habilitación y permisos; las funciones previas trasladadas a `private` pierden EXECUTE de cliente. El RPC antiguo de delegación genérica sigue cerrado. Los avisos no incluyen vectores de firmas.

Una autorización deja de funcionar al vencer/revocarse, cambiar el responsable del caso, cambiar la versión del perfil o perder/renovar alguno de los permisos vinculados o la pertenencia. No se reactiva por volver a tener el mismo puesto ni por conceder un permiso nuevo. El servidor serializa con clínica/ledger/caso/identidades y vuelve a comprobar tiempo real tras esperar bloqueos.

Contrato de Flutter: `schema_version: 1`, `mode: individual_standing`, `standing_version: 1`. Se conserva H2 si es lo único que el servidor anunció; después de conocer H3, perderlo o recibir otra versión bloquea acciones. Ningún dato clínico ni referencia normativa nueva entra por este bloque.

## Validación y límites

Harness: `bash supabase/tests/run_prescription_standing.sh`, con PostgreSQL aislado, Node, dependencias de `supabase` y `pdftotext`. Reutiliza primero los fixtures/pruebas H2; todos los productos y estados verificados del harness son **ficticios para pruebas**, nunca datos de producción.

Comprueba aceptación, expiración elegida, autoría real sin elevar al preparador, controlados rechazados, acceso ajeno/anon y tablas privadas, cambio de perfil/permiso/pertenencia, revocación, retorno a borrador, revisión posterior sin alterar PDF, emisión/aviso únicos y vencimiento durante espera de bloqueo. Genera un PDF real a partir del snapshot de PostgreSQL y comprueba texto y firma. El fixture SQL de registro usa bytes sintéticos exclusivamente para probar esa frontera.

Flutter prueba contrato/desconocimiento/pérdida, selección explícita del permiso, aceptación, ausencia de valores predeterminados, motivo al retomar, tablón sin revisión automática y rechazo de un PDF distinto antes de confirmar revisión posterior.

Resultado local: **298 pruebas Flutter satisfactorias**, análisis sin incidencias, **15 pruebas del renderer** satisfactorias y harness PostgreSQL/PDF/concurrencia satisfactorio. Incluye una espera de bloqueo que atraviesa el vencimiento sin permitir emisión ni crear aviso.

Esto no acredita entrega push, prueba HTTP real de Edge Functions, aislamiento con dos clínicas en teléfono ni aplicación remota de las migraciones. Esas comprobaciones siguen pendientes del corte integral. Inventario/dispensación, reportes, formatos, Storage y rutas restantes aún deben cerrar su migración de permisos.

## Siguiente fase

Revisar el corte completo antes de aplicar al servidor y exigir una versión de APK compatible. La autorización para otros procedimientos o para toda la clínica necesita su alcance propio; no se deduce de esta autorización de recetas. Las notificaciones con app cerrada requieren un canal adicional, permisos y pruebas de entrega en dispositivo real. Por ahora los datos se conservan: este bloque no introduce borrado automático.
