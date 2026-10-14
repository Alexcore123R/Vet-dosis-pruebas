# Beta y permisos v1.1 — ajustes aprobados, implementación por etapas

14 de octubre de 2026. Complementa y prevalece sobre v1 donde difiere. No acredita despliegue remoto ni apertura de beta.

## Decisiones incorporadas

1. Antes de abrir la beta: A1 instalador/firma; candado beta; nuevo modelo de permisos. Después de abrir: transferencias, restauración y catálogo global de controlados. Hasta tener este último, conservar restricciones actuales y no habilitar emisión/controlados sin fuentes verificadas.
2. Agregar `procedure.perform`, `drug.administer` y `vial.draw`, con alcance por tipo de procedimiento. Concesión por persona y clínica, caducidad, revocación, otorgante y motivo. Habilitación y facultades reservadas se comprueban aparte: estos permisos no convierten al destinatario en MVZ. Cada aplicación/toma registra el procedimiento y concesión utilizados; si falta alcance o hay revocación, el servidor rechaza. Verificar también el frasco/producto, lote y clínica de la aplicación. No derivar permisos de una etiqueta de puesto.
3. Administración mínima de plataforma en pantalla móvil separada: aprobar/revocar correos, crear/revocar invitaciones y consultar inscripciones. Cuenta distinta a la cuenta de clínica; matrícula inicial de administradora por operación privilegiada fuera de la app. El servidor exige JWT `aal2`, cuenta habilitada y ausencia de membresía clínica para cada RPC. No basta ocultar botones ni haber inscrito un factor sin completar el desafío MFA. Sin crear excepciones de MFA para el arranque; la matrícula de identidad y el enrolamiento del factor se preparan por canal administrativo seguro.
4. Pérdida del patrocinador: registrar evento con hora de servidor, iniciar gracia de 14 días, avisar y permitir regularizar responsable/patrocinador autorizado. No reiniciar la gracia al refrescar, cambiar de dispositivo o reiterar el mismo evento. La gracia no renueva 60 días individuales, no conserva permisos revocados del patrocinador y no elude caducidad del build. Al final, solo consulta/exportación para quienes mantengan acceso. Un nuevo patrocinador requiere aceptación y beneficio vigente; registrar cierre del evento de gracia con auditoría.
5. Retención: la usuaria eligió **conservar por ahora y definir el borrado después**. NO programar borrado a 30 días, ni borrar cuentas, expedientes, evidencia o archivos al vencer beta. Mantener aviso de expiración y exportación. La política de privacidad debe decir que vencer acceso no implica eliminación automática; plazo definitivo, revisión legal, costos y procedimiento de solicitud de eliminación quedan pendientes. No prometer retención perpetua ni un mínimo normativo sin verificar.
6. Evidencia profesional mínima: revisor identificable, fecha de servidor, hash y referencia. Asegurar que el hash corresponde al objeto/registro revisado; un hash aislado sin referencia no demuestra validación de cédula. Evidencia privada, acceso acotado, revocaciones anexadas, historial inmutable. No copiar documentación a PDFs ni exportaciones personales. Primer MVZ revisado fuera de la app por administradora de plataforma; no autoverificación.
7. Receta con autorización permanente: guardar quién preparó y cuándo, autorización previa del titular con tipo/alcance/vigencia, y quién emitió y cuándo. PDF indica ese acto real, no afirma revisión individual si no ocurrió. Preparar usando datos versionados del MVZ no permite suplantar firma ni emitir por una mera etiqueta. Antes de emisión, revalidar habilitación, consentimiento de uso, alcance y revocación; conservar snapshot y hash. El flujo integrado preparar con datos del MVZ → PDF → emisión necesita prueba específica y no se da por probado solo por existir delegaciones.
8. Play App Signing para distribución por Play. La llave de carga es distinta de la llave de firma de aplicación gestionada por Play. Para APK beta fuera de Play definir firma propia estable del canal; no asumir que APK firmado con llave de carga actualiza una instalación firmada por Play. Copia cifrada y contraseñas fuera del repo y chat, por canal privado a la propietaria. La cuenta Play/configuración y entrega de respaldo aún están pendientes; no se generaron llaves en este paso.
9. Pruebas adicionales obligatorias: anon, escritura/lectura directa, Storage, Edge Functions, autoverificación, normalización de correo, concurrencia y bordes exactos de vencimiento/gracia/build. Aprobar un correo no equivale a verificar una cédula ni a conceder facultades clínicas.
10. Caducidad del build: 90 días desde publicación registrada por servidor. Prohibir refrescar su released_at para rejuvenecer el mismo build; publicación nueva tiene versión nueva y auditoría. Mínima versión por canal. El cliente declara versión para compatibilidad, no prueba criptográfica; autorización real permanece en servidor. Tras vencer, actualización y solo consulta/exportación autorizada.
11. Restauración futura: staging con TTL de 14 días y máximo un staging vivo por espacio. Índice único parcial por espacio y estado vivo, cuotas y reclamación transaccional. Limpiar solo staging expirado, nunca origen o destino activo. Fecha expiración inmutable desde creación; vista previa no activa pacientes, tratamientos, alarmas ni autoridad. Debe resolverse presupuesto físico antes de habilitarlo. No se implementa en primera etapa.

## Esquema adicional propuesto respecto a v1

- `private.platform_admins`: identidad de administradora separada, habilitada por bootstrap privilegiado. No migrar administradores de clínica a esta tabla.
- `private.beta_policy`: admisiones cerradas por defecto; 60/7/14/90 días como política aprobada. La apertura exige completar puerta de servidor y permisos, no solo cambiar una bandera.
- Correo aprobado/invitaciones e inscripciones privadas; endpoints devuelven solo proyecciones autorizadas. Invitación guarda hash de token; el token original se muestra una vez en administración y no se registra en bitácora ni analítica.
- Términos versionados con texto/hash publicado; aceptar versión exacta antes de primera inscripción. Invitación atómica ligada a correo verificado de Auth; inscripción única por usuario. No eliminar puntos ni etiquetas + de proveedores de correo.
- `beta_sponsor_events`: una pérdida activa por concesión de espacio, fecha de gracia fija y trazabilidad de reemplazo. Debe integrarse con la concesión y membresía, no solo con el estado de una pantalla.
- `professional_verifications`: revisor, fecha, hash y referencia obligatorios; vínculo a identidad/licencia y versión del perfil. Evidencia opcional de archivo en objeto privado referenciado, nunca con URL pública permanente.
- Catálogo de permisos incluye tres códigos nuevos y las concesiones por tipo de procedimiento. No se almacenan dosis/protocolos implícitos dentro de permisos.

## Orden y entregables

### Etapa 0: cimientos locales, sin activar admisiones

`supabase/proposed/09A_beta_foundation.sql`: tablas privadas mínimas, normalización de correo, RPC administrativos con cuenta separada y MFA, revocación, auditoría y función privada de evaluación de fechas. Admisiones desactivadas, sin inscribir usuarios, crear términos ficticios, migrar permisos ni eliminar datos. El archivo está en proposed: no pertenece todavía a deployment ni se aplica automáticamente.

Prueba local: `bash supabase/tests/run_beta_foundation.sh`, PostgreSQL aislado con cuentas sintéticas. Cubre MFA, admin separado, permisos de tablas, anon, normalización, tokens no expuestos en listados, revocaciones y fechas. No constituye prueba real de Supabase Auth, TOTP, Storage o Edge Functions.

### Etapa 1: A1 y puerta beta completa

Estabilizar ID/firma/versiones y proyecto embebido. Completar panel móvil de plataforma y MFA, inscripción/reintentos concurrentes, términos reales aprobados, beneficio por espacio, gracia de patrocinador y política de publicación. Integrar guardas en cada ruta de escritura (RPC, escrituras directas, Storage y Edge Functions); no abrir admisiones con rutas antiguas sin cubrir. Auditar exportaciones permitidas tras vencimiento y excluir credenciales/evidencia. Configuración remota con cuenta real y 2FA requiere trabajo explícito, no darla por realizada con tests locales.

### Etapa 2: permisos antes de apertura

Migrar solo etiquetas/administración; no promover roles heredados a habilitación. Revisar verificaciones previas con evidencia mínima. Añadir tres facultades por procedimiento y guardas a aplicaciones/tomas. Revocar atajos antiguos basados en roles en todos los endpoints relevantes. Probar preparación/emisión con datos del MVZ, autorización permanente y acto real en PDF, además de aislamiento y revocación concurrente.

### Etapa 3: apertura controlada

Pruebas reales con dos cuentas/dos clínicas, administrador de plataforma independiente con MFA y teléfono real; prueba de actualización del APK. Usuarios de prueba aprobados y admisión de 60 días; panel de estado y avisos siete días antes. No habilitar funciones clínicas pendientes de referencias/aprobación profesional.

### Después de abrir

Transferencias elegidas, restauración aislada 14 días/un staging, catálogo global de controlados con adiciones locales, XLSX real y reportes no oficiales hasta validar formato vigente. No activar controlados por ausencia de clasificación global verificada. No usar prototipos como fuente clínica.

## Estado explícito al cerrar este bloque

- Actualizado el documento de diseño con los cambios aprobados y conservación sin borrado automático.
- Preparada y probada una primera base SQL local. No se aplicó al proyecto remoto.
- No existe todavía candado completo de beta en servidor ni pantalla móvil de administración de plataforma.
- No se migraron roles/habilitaciones/permisos; no se abrió beta ni se crearon cuentas/llaves reales.
- Retención definitiva pendiente; no es un bloqueo para continuar las partes no destructivas autorizadas.
