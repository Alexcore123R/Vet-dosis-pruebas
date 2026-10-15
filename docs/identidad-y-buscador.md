# Identidad visual, buscador y exportaciones

## Estado

- Implementado y probado localmente: buscador por apartados tolerante a acentos; escáner flotante; avatar por cuenta; identidad clínica; cliente de sincronización; exportadores PDF y XLSX reales.
- Preparado localmente: `supabase/proposed/10_identity.sql`, prueba aislada `bash supabase/tests/run_identity.sh`. No modifica datos clínicos ni permisos de documentos.
- Aplicado en remoto el 15-oct-2026: esquema de identidad y generador PDF v2 en el proyecto de pruebas. Verificadas las rutas nuevas contra acceso anónimo (HTTP 401). No se ha probado todavía sincronización entre dos teléfonos con sesión real.
- Pendiente de prueba real: subir foto y comprobar sincronización con dos cuentas y dos teléfonos. La migración ya se aplicó; no repetirla ni usar la fixture de pruebas en Supabase.

## Esquema concreto para revisión

1. Tabla `account_identity`: propietario (auth.uid), icono 0–4, ruta opcional de foto, fecha de actualización. RLS de lectura del dueño; sin escrituras directas desde la app. RPC de lectura/escritura sin parámetro de propietario: el servidor siempre lo toma de la sesión.
2. Bucket privado `account-avatars`: PNG hasta 500000 bytes; una ruta permitida `auth.uid()/avatar.png`. Lectura, inserción, sustitución y borrado solo por el dueño; las clínicas no ven fotos personales de otros miembros. La app decodifica y recodifica las fotos. MIME/tamaño se limitan en Storage; la prueba PostgreSQL local solo valida las políticas, no sustituye una prueba de carga binaria en Storage real.
3. `clinic_identity_get(clinic_id)`: requiere membresía y devuelve solo id, nombre, membrete, logo y selección de incluir logo. Todos los puestos pueden consultar esa identidad. No amplía `form_branding`, edición de membretes, expedientes ni habilitación profesional.
4. No hay borrado por vencimiento beta. Elegir icono oculta la foto; el único objeto privado puede conservarse hasta reemplazarlo o borrarlo. No se borra durante un cambio a icono para evitar eliminar una carga simultánea de otro dispositivo.

La migración es aditiva y no depende del modelo de permisos beta propuesto. Requiere M2, Forms fase 1 y Storage ya existentes. Ejecutar solo este archivo nuevo, nunca repetir adaptaciones históricas. Para revertir la interfaz se puede volver al APK anterior; no borrar tabla/bucket como reversión automática.

## Comportamiento

- Foto/icono: lectura remota con copia local por usuario. Una selección local pendiente no se sobrescribe al reconectar. Reintento explícito. Una cuenta remota nueva no elimina la foto de la versión local anterior ni la sube sin acción del dueño.
- Sin servidor nuevo: el membrete antiguo sigue funcionando para sus roles actuales. El acceso para todo el personal requiere la migración. La foto se guarda localmente y se informa si no se pudo sincronizar.
- Perfil: administración abre el editor existente con vista previa obligatoria y versionado. Necesita una plantilla para la vista previa. Cambiar el texto del membrete no renombra la clínica; el nombre mostrado es el real de la membresía activa.
- Exportaciones nuevas PDF/XLSX: corte de caja, transacciones, tablas operacionales desde Respaldo y registro de control emitido. Se consulta el membrete autorizado al exportar; un fallo de acceso o conexión cancela la exportación. XLSX incluye imagen embebida, no un CSV renombrado. CSV mantiene su estructura de datos sin imágenes.
- Los datos se exportan como texto en XLSX para conservar folios, ceros iniciales y precisión; nunca como fórmulas ejecutables. Para cálculos posteriores el usuario debe convertir las columnas numéricas correspondientes.
- Tablas PDF anchas se dividen en bloques de seis columnas, conservando el orden de registros. Son exportaciones de consulta, no nuevos originales firmados.
- Registro de control: las exportaciones nuevas se rotulan «basado en Anexo 5, no oficial». No certifican que se haya implementado el formato normativo vigente ni completan columnas ausentes en el registro actual. No se cambian los PDF originales ni su firma/hash.
- El generador PDF v2 incluye el nombre canónico de la clínica del snapshot incluso si el membrete solo contiene contactos, y lo repite en cada página. La vista previa obtiene el nombre mediante la membresía autorizada. Requiere desplegar la Edge Function actualizada. Los PDF clínicos ya emitidos conservan sus bytes originales. Los respaldos JSON/cifrados conservan su esquema y verificación; no se les incrusta un membrete visual.

## Verificación

- Flutter: cambios de cuenta/clínica, datos locales dañados, navegación, recuperación remota sin subida automática, fallo y reintento de sincronización.
- PostgreSQL aislado: anon, RLS entre dueños, rutas ajenas/adicionales, acceso de recepción sin ampliar permisos clínicos, revocación de membresía y límites del bucket.
- XLSX: ZIP/OpenXML y relaciones de imagen; lectura independiente con openpyxl, incluyendo folios y fórmulas como texto.
- PDF: generación con fuente Unicode, nombre/membrete, logo y tablas anchas; texto extraído con pdftotext.
- Pendiente real: subida de foto desde el celular, dos dispositivos con la misma cuenta, otro usuario sin acceso al avatar, y dos clínicas con logos distintos en cada exportación.

## Prueba desde el celular (servidor ya activado)

1. La migración ya se aplicó mediante el flujo de GitHub, usando el secreto del servicio. No hace falta copiar SQL.
2. Para revisar el estado se puede ejecutar «Identidad en Supabase de pruebas» con acción `inspect`. La acción `apply` comprueba dependencias, se niega a sobrescribir un esquema parcial y no repite una migración completa existente.
3. Instalar el APK nuevo firmado. Abrir Mi cuenta y clínicas, elegir icono/foto y comprobar el mensaje de sincronización.
4. Entrar con la misma cuenta en otro dispositivo; comprobar la imagen. Con otra cuenta, comprobar que no se puede descargar el avatar ajeno.
5. En dos clínicas con logos diferentes, comprobar inicio, perfil y una exportación PDF/XLSX de cada una. Una cuenta de recepción puede ver el logo y no editar el membrete.
6. El generador de formatos se despliega por el flujo existente «Desplegar PDF en Supabase de pruebas». No necesita copiar secretos al chat.

La activación remota fue correcta. Las sesiones reales y la carga binaria de una foto desde el celular todavía requieren la prueba del dispositivo.

## Evidencia de esta entrega

- Migración aplicada y verificada: https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38765183079
- Despliegue PDF v2 correcto: https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38764680547
- APK con la nueva implementación: https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/38764737968 (su estado de compilación se consulta en GitHub).
- 240 pruebas de Flutter en la suite completa; comprobaciones dirigidas posteriores de identidad, exportación y formatos correctas. Análisis sin observaciones.
- 8 pruebas del generador de PDF; políticas SQL probadas localmente y de nuevo en el flujo remoto antes de aplicar; 6 pruebas de protecciones del despliegue.
- HTTP sin sesión contra `account_identity_get`, `account_identity_save` y `clinic_identity_get`: 401 en las tres rutas, después del despliegue.
- No se crean usuarios ni registros clínicos reales para estas comprobaciones. No se prueban como cumplidas las sesiones reales entre clínicas ni la transferencia binaria de fotos.
