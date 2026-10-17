# Integración de la primera beta conectada

## Alcance

La primera beta requiere conexión para expedientes y aplicaciones. Usa datos
ficticios y comparación de resultados. El motor offline genérico no se presenta
como captura clínica disponible. Las referencias conservan su fuente y estado.
Restauración real, transferencias, cobros activos y publicación Play quedan fuera.

## Inventario antes de aplicar

El workflow **Inspeccionar integración beta (solo lectura)** consulta únicamente
el proyecto `wtrelwtztkddfktrfdpb`. Genera un artefacto JSON con existencia de
objetos, políticas beta/permisos, hook REST y hashes de cuerpos de funciones clave.
Usa el secreto ya configurado en GitHub y no exporta cuentas ni registros clínicos.

`missing` significa que falta la función; `different_definition_requires_review`
significa que requiere comparación; `body_matches_candidate` solo acredita ese
cuerpo. Ningún resultado acredita RLS, grants, triggers o instalación integral.
Por eso el reporte conserva `deploy_ready=false`.

El orden explícito de 23 candidatos esenciales está en
`scripts/supabase/integration_preflight.py`. Incluye 13A–13P y 13W; excluye 13Q–13V
de recuperación. No es un instalador y no ejecuta ningún candidato.

## Paquete atómico preparado

`integration_bundle.py` genera un archivo SQL para revisión. No se conecta al
servidor. El modo predeterminado termina en ROLLBACK; `--commit` genera la variante
de aplicación explícita. Ambos usan el mismo orden y cuerpos de las 23 migraciones.
El workflow de ensayo solo los ejecuta contra PostgreSQL efímero con datos sintéticos.

El paquete detiene la operación si faltan dependencias, si las políticas no están
desactivadas o si detecta funciones nuevas/recibo de una aplicación anterior.
Incluye timeout de bloqueos y de sentencias. Comprueba los hashes de funciones
finales y los conteos de pacientes, tutores, medicación, concesiones y verificaciones.
Guarda un recibo privado con los archivos y hashes al confirmar la transacción;
no genera concesiones ni habilita profesionales o admisiones.

Las pruebas comprueban un error deliberado a mitad del paquete, ensayo con rollback,
instalación parcial, aplicación completa y rechazo de repetición. Esta evidencia
no sustituye revisar el esquema y datos reales ni disponer de respaldo previo.
El paquete no incorpora todavía la actualización de Edge Functions o la prueba
de sesiones reales; no debe usarse como aprobación de apertura de beta.

`integration_dependencies.py` consulta en el servidor la presencia de las mismas
relaciones/funciones exigidas por el paquete. Publica faltantes sin ejecutar DDL.

Antes de aplicarlos hay que comprobar las adaptaciones M2–M14, identidad 10,
fundación beta 09A/09B, permisos 11A y consentimientos/plataforma/privacidad
12A/12B/12C. La presencia de funciones con igual nombre no sustituye esa revisión.
Un esquema parcial se revisa antes de decidir qué falta; no se reejecuta una
migración con CREATE TABLE para intentar repararlo.

## Criterios para desplegar y generar APK

1. Respaldo del entorno de pruebas y lista de diferencias revisada. Beta cerrada,
   sin activar admisiones ni convertir puestos en concesiones profesionales.
2. Aplicación coordinada del esquema y Edge Functions con el cliente compatible.
   Registrar commit, orden y resultado de cada bloque; detenerse ante errores.
3. Verificar primer MVZ por el proceso externo aprobado; permisos concedidos de
   forma explícita para las cuentas de prueba. Cuenta de plataforma separada y MFA.
4. Comprobar HTTP con dos cuentas/dos clínicas y sesión anónima: RPC/tablas,
   Storage, PDF, permisos revocados y vencimiento. Las pruebas locales ya existentes
   no se contabilizan como estas comprobaciones remotas.
5. Confirmar texto/versión/hash de términos y privacidad publicados. Aceptar una
   actualización no renueva la beta; al vencer se conserva lectura/exportación.
6. Generar APK beta firmado conectado al proyecto de pruebas; comprobar versión,
   instalación y prueba en teléfono antes de invitar a otra persona.

## Prueba de aceptación de la app

- Cuenta A crea tutor, paciente y cita ficticios; cuenta B de otra clínica no los ve.
- Una persona con lectura carece de botones de escritura y tampoco puede escribir
  llamando directamente al servidor. Un puesto MVZ no sustituye habilitación.
- Guardar consulta focalizada sin exigir SOAP completo, temperatura, peso ni jaula.
- Preparación de receta, autorización y PDF reflejan a las personas reales y el
  acto de autorización; cada quien aporta su propia firma.
- Hospitalización confirma paciente, fármaco, mg/ml y vía; doble confirmación no
  duplica administración ni extracción. Posponer/no aplicada conservan su significado.
- En Android probar alarma con app cerrada y teléfono bloqueado, y confirmar dentro
  de la app desbloqueada. Comprobar batería, permisos, reinicio y dosis vencida.
- Comprobar cámara, adjuntos, compartir/imprimir PDF, exportación XLSX y rechazo de
  archivos de clínica ajena. Una URL firmada emitida conserva su TTL: no atribuirle
  revocación instantánea de permisos.
- Cortar conexión: explicar la indisponibilidad del registro clínico y recuperar
  acceso al reconectar sin mostrar datos de otra sesión.

La apertura de beta se evalúa después de registrar resultados, fallos y límites
del APK concreto. Esta preparación no abre automáticamente acceso.

## Inspección real del 17 de octubre de 2026

[Ejecución 39029114022](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029114022)
aprobada, sobre el commit de integración `e31dad7`. Las 36 pruebas Python de
herramientas administrativas pasaron antes de consultar el catálogo remoto.

- Identidad, membresías y las bases de política beta/permisos están presentes.
- Admisiones y enforcement beta están en false; permisos mantiene
  enforcement_enabled=false y migration_reviewed=false.
- El hook REST apunta a `public.beta_request_guard`.
- Diez funciones clave del candidato están ausentes. `clinic_statistics` existe,
  pero su cuerpo difiere del candidato. No se presume que esto describa todos los
  objetos de cada migración.
- No existen las tablas de constantes estructuradas ni staging de restauración.
- Solo se hicieron SELECT de catálogo y políticas; no se cambiaron datos,
  permisos, admisiones o definiciones.

El bloque 13X de Storage clínico, publicado en paralelo desde otra conversación,
se conservó al integrar Git. 5.6 sol corrigió un residuo SQL posterior a COMMIT y
amplió las pruebas. [Storage 39029205418 aprobado](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39029205418).
Permanece como candidato adicional fuera del manifiesto inicial; su aprobación
aislada no acredita instalación remota ni un flujo de adjuntos en la interfaz.

## Ensayo y dependencias del paquete atómico

- Las 42 pruebas Python de herramientas administrativas aprobaron.
- [Inspección remota 39030003970](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39030003970):
  todas las relaciones/funciones exigidas están presentes (`missing=[]`). Esto no
  acredita todavía compatibilidad de definiciones y datos.
- [Ensayo aislado 39030086535](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39030086535):
  aplicación de 23 candidatos, error deliberado y rollback, rechazo de instalación
  parcial/repetida, conteos conservados y hashes finales aprobados.
- La primera ejecución del ensayo falló porque el runner no incluía ripgrep;
  el script usa ahora grep para comprobar sus logs de error esperados.

El artefacto `beta-integration-review-only` contiene SQL de ensayo, SQL candidato
de aplicación y manifiesto de archivos/hashes. No contiene datos exportados ni
credenciales. No se ejecutó el SQL candidato en Supabase remoto.
Faltan el respaldo previo verificado, el ensayo sobre el esquema real y la
coordinación con cliente/Edge y cuentas de prueba antes de aplicar y abrir beta.

## Comparación ampliada del catálogo remoto (17 octubre)

[Inspección 39061277899](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39061277899)
aprobada. Las 45 pruebas Python pasaron. No se ejecutó DDL remoto ni se consultaron
filas de pacientes, tutores, cuentas o credenciales.

Se compararon columnas, tipos y nulabilidad de 33 relaciones, sus indicadores RLS,
y los cuerpos por hash/indicadores security-definer de cuatro funciones prerrequisito.
No hubo diferencias de columnas en las 32 relaciones de aplicación incluidas ni
diferencias en esas cuatro funciones. Esto no cubre todo el esquema.

Diferencias observadas y conservadas como revisión explícita:

- `storage.objects`: `name` y `metadata` admiten NULL en remoto; el simulador las
  declaraba NOT NULL. Hay once columnas adicionales gestionadas por Storage.
- `private.rx_artifacts`, `private.form_artifacts` y
  `private.professional_profile_versions`: RLS está activado en remoto, mientras
  que el esquema local base lo deja desactivado. No se propone desactivarlo remoto.

`run_integration_bundle.sh --observed-catalog-rehearsal` reproduce solo estas
diferencias de nulabilidad/RLS en PostgreSQL efímero antes del ensayo atómico.
El ensayo local aprobó aplicación de los 23 candidatos, rollback ante error,
rechazo de instalación parcial/repetida, conteos sin cambios y hashes finales.
[Ensayo CI 39061388108](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39061388108)
aprobado también: ejecutó la base original y la variante con diferencias observadas.
Las columnas adicionales de Storage no se recrean: este ensayo no consume sus
valores y no equivale a restaurar el esquema completo del servicio.

Sigue pendiente revisar constraints, políticas completas, grants y triggers,
disponer de respaldo verificable y probar las sesiones reales. Los informes
conservan `deploy_ready=false`. La migración adicional 13Y de renovación IA sigue
fuera del paquete de 23 candidatos y necesita despliegue coordinado con Edge/cliente.

## Revisión de seguridad y recuperación (17 octubre)

[Inspección 39061840288](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39061840288)
aprobada; las 50 pruebas Python pasaron en la ampliación. Se inspeccionaron además
hashes de constraints, políticas y triggers, privilegios efectivos de tabla para
anon/authenticated/service_role y metadatos de las 266 funciones de la base local.
No se exportaron cuerpos de funciones remotas ni registros de aplicación.

La API de respaldos respondió con `backups=[]`, `pitr_enabled=false` y
`walg_enabled=true`. Esta última bandera no acredita un punto recuperable:
no se ha verificado restauración ni se conoce una copia externa. No se descargó
ningún respaldo y no se activaron servicios de pago.

La comparación ampliada reporta 208 diferencias de metadatos, no 208 fallos:

- 164 funciones difieren. En 152 solo cambia EXECUTE para service_role. Otras
  diferencias incluyen EXECUTE para anon; requieren considerar el cuerpo y sus
  controles, sin inferir exposición clínica solo por ese permiso.
- Los cuerpos de `has_clinic_role` e `is_clinic_member` coinciden por hash con
  `deployment/02_pruebas_dosis_pacientes.sql`, y `ai_prepare` con
  `deployment/07B_pruebas.sql`. El simulador parte de adaptaciones distintas.
- `support_attachment_reserve` coincide con `deployment/07D_pruebas.sql`.
  `support_attachment_finish` coincide exactamente con la versión histórica de
  ese archivo en `a9743f57dc84`: verifica acceso y existencia del objeto, pero aún
  no incorpora la comprobación actual de MIME/tamaño contra la reserva. Preparar
  un reemplazo puntual revisado; no reejecutar toda la creación M14.
- En `clinic_members` ya no están las cuatro políticas heredadas de la fixture
  (lectura de roster y escrituras de administradores); queda `vd_memberships_read`.
  No restaurar esas políticas antiguas automáticamente para igualar el simulador.
- Hay 25 diferencias de permisos de tabla. Las revisadas reflejan acceso del rol
  de servicio; Storage también otorga privilegios a anon y depende de sus políticas.
  Esto no acredita acceso HTTP de anon ni reemplaza probar RLS con sesiones reales.
- Storage añade sus propios triggers y constraints respecto de la fixture mínima.

Pendientes concretos antes de aplicar: disponer de copia recuperable y ensayar su
restauración; reproducir o revisar las diferencias restantes de ACL/políticas y
cuerpos desplegados; preparar la actualización puntual del finalizador de adjuntos;
coordinar 13Y y Edge; probar cuentas separadas y anon por HTTP. La inspección sigue
manteniendo `deploy_ready=false`, sin cambios remotos ni apertura de admisiones.

Actualización de recuperación: el [respaldo cifrado 39073667621](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39073667621)
ya creó la primera copia real de base y verificó descifrado/lectura del archivo.
Caduca en Actions el 24 de octubre: conservar copia externa. Véase
`respaldo-operativo-pruebas.md`. Sigue pendiente ensayar restauración completa del
archivo real y copiar binarios Storage; esto no abre beta ni autoriza migraciones.

Actualización posterior: [39077111210](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39077111210)
acreditó restauración del archivo real en un contenedor Supabase sin red y ensayo
de los 23 candidatos con rollback sobre esa copia. Storage reportó 3 buckets y
0 archivos. Véase `ensayo-restauracion-real.md` para los límites (datos clínicos
consultados vacíos, roles/propietarios no reproducidos como identidades operativas,
sin prueba HTTP/secretos/plataforma). No se aplicaron cambios al servidor activo.

## Contrato inicial instalado — 17 octubre, 23:58 UTC

Se superó el estado histórico de «sin aplicar» para el paquete inicial:

- [39080817606](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39080817606):
  respaldo real restaurado sin red; 23 candidatos y 13Y/14A/14B ensayados juntos,
  en una transacción terminada en ROLLBACK.
- [39080925135](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39080925135):
  ensayo del mismo conjunto en el proyecto fijo de pruebas con ROLLBACK;
  estado seleccionado de catálogo, conteos, políticas y hashes igual antes/después.
- [39081019769](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39081019769):
  ensayo específico del subconjunto de instalación (23 + 14A + 14B), ROLLBACK.
- [39081043942](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39081043942):
  **instalación confirmada** de los 23 candidatos iniciales y 14A/14B en una
  transacción. Contrato de módulos y recibo presentes; hashes de los dos parches
  comprobados dentro de la transacción. SQL SHA256
  `948b6e9fe103ba2fc63604ae9b36c29a38c4d0567b3eef32fa144b84eb81b0ae`.

Los conteos de pacientes, tutores, medicaciones, concesiones y verificaciones
profesionales se conservaron. Admisiones cerradas; enforcement de beta y permisos
sigue desactivado como exigían los guardas. No se creó autoridad por puesto ni se
habilitó profesionalmente a nadie. Los nuevos RPC revisados exigen sus concesiones
explícitas aun con la política global dormida; instalar el contrato no asegura
que el menú muestre módulos a una cuenta sin concesiones.

13Y **no se instaló**: su ensayo satisfactorio no equivale a despliegue. Debe
coordinarse con Edge. 13X y restauración de respaldos siguen fuera del paquete.
El arreglo de adjuntos valida MIME/tamaño; no recrea buckets ni políticas antiguas.

Faltan concesiones elegidas para la cuenta/clínica de prueba y pruebas HTTP con
sesiones reales de ambas clínicas, anon, Storage y Edge. Esta instalación de
esquema no acredita una beta clínica operativa. No repetir los workflows de
instalación/ensayo inicial sobre el estado instalado: rechazan aplicaciones
parciales o repetidas; las siguientes actualizaciones requieren candidatos aditivos.
