# VetDosis Pro

Base Flutter para Android, iPhone y web (incluido navegador de computadora).
M1 contiene navegación por ramas, menú oculto, accesos a módulos pendientes
y cinco paletas con modos claro, oscuro y sistema. Apariencia persistida localmente.

## Preparación

Requiere Flutter estable compatible con Dart >=3.10 (Flutter >=3.38.1). Desde esta carpeta:

```sh
flutter pub get
flutter analyze
flutter run -d chrome
```

Los proyectos Android, iOS y web ya están incluidos; no es necesario ejecutar create de nuevo.
Para compilar iOS se necesita macOS con Xcode. Incluye la base de acceso con Supabase; requiere conectar un proyecto real.
Ver [configuración y estado de M2](docs/supabase.md).
Verificación en Flutter 3.47.6 / Dart 3.13.5: análisis sin errores y 150 pruebas
de núcleo, acceso, dosis, expedientes, hospitalización, recetas, cálculos e inventario/caja aprobadas. Compilación web generada en
`build/web`. Revisión visual local en Chromium: inicio a 390 × 844 y 1440 × 1000,
menú, ajustes y paletas claro/oscuro; sin errores JavaScript observados.
Capturas en `review/`. Pendiente de compilación Android/iOS y prueba en dispositivos reales.

## Arquitectura

`lib/modules/core` separa presentación (ViewModel) y datos (repositorio de ajustes).
`lib/core/app.dart` compone la aplicación y la UI del núcleo. Inyección por constructor.
Los próximos módulos se añadirán a `lib/modules/` con lógica de dominio independiente.
Room se sustituyó por Sembast/IndexedDB para la base local multiplataforma de M2.
Los expedientes de M4 requieren conexión; no se guardan datos de pacientes ni contactos en preferencias o en la caché sin cifrado.

El catálogo clínico está vacío deliberadamente. Nunca tomar ejemplos de Gemini
como fuentes verificadas de dosis, protocolos o normativa.

Las capturas en review/ corresponden al núcleo M1 previo al acceso.
Sin configuración Supabase, la versión actual muestra conexión pendiente.
La compilación local configurada ya muestra acceso por correo. Confirm email activo
y verificado en Supabase; registro/confirmación con cuenta real todavía pendiente.

Base existente revisada y adaptación local: [informe](docs/base-existente.md).
La app usa clinic_members y p_name de forma predeterminada. Para una instalación
nueva con clinic_memberships, usar SUPABASE_EXISTING_SCHEMA=false.

Acceso offline limitado y motor de cola: [estado y límites](docs/offline.md).

## M3 — Dosis

Calculadora con catálogo JSON importable, búsqueda por marca, aritmética exacta, controles de rango/redondeo, contraindicaciones y doble confirmación. Dosis personales separadas con captura y revisión admin. No hay datos clínicos precargados. [Detalles y pendientes](docs/m3-dosis.md).

Migración para la base existente: `supabase/adaptations/existing_doses_m3.sql` (una vez después de M2; aún no aplicada al proyecto remoto). Pruebas de permisos: `bash supabase/tests/run.sh doses`.

## M4 — Pacientes y expedientes

Alta de pacientes/tutores, permisos por clínica y rol, SOAP revisable con dictado por apartado, pesos y curva, alergias, vacunas/desparasitación, mensajes de recordatorio preparados por el usuario y consentimientos con firma. [Estado y límites](docs/m4-expedientes.md).

Migración: `supabase/adaptations/existing_patients_m4.sql` (una vez después de M2; pendiente de aplicar remotamente). Pruebas SQL: `bash supabase/tests/run.sh patients`.

## M5 — Hospitalización

Fichas por jaula y hoja paciente × hora, prescripción de horarios por MVZ/admin, confirmación con usuario/hora del servidor, posposición, avisos de retraso y altas que conservan lo administrado. [Plataformas, límites y estado](docs/m5-hospitalizacion.md).

Migración: `supabase/adaptations/existing_hospital_m5.sql` (después de M2 y M4, pendiente de aplicar remotamente). Pruebas locales: `bash supabase/tests/run.sh hospital`, incluida confirmación concurrente desde dos conexiones. Notificaciones nativas configuradas; pruebas reales con app cerrada pendientes en dispositivos. Web: avisos con la hoja abierta.

## M-FORMATOS — fase 1

Plantillas originales versionadas por clínica, constructor, aprobación clínica, membrete/logo, borradores y firmas propias de tutor/MVZ. PDF generado en servidor y finalización de los mismos bytes revisados mediante SHA-256. Identificación del firmante: solo número, sin foto. [Estado, fases y límites](docs/m-formatos-fase1.md).

Adaptación `supabase/adaptations/existing_forms_phase1.sql` después de M2/M4 y función `forms-pdf`, pendientes de instalación remota. Pruebas SQL: `bash supabase/tests/run.sh forms`; generador: `npm ci --prefix supabase` y `npm --prefix supabase run test:renderer`. Pasante equivale a auxiliar. Recetas/delegaciones/control farmacológico pendientes en fase 3/M6.

## M-FORMATOS — fase 2

Historia clínica conectada con SOAP/peso, hoja quirúrgica con responsables separados, mediciones/actuaciones y permisos por procedimiento, correcciones anexas y constatación posterior a eutanasia. Conserva la versión y PDF originales firmados. [Uso, esquema y límites](docs/m-formatos-fase2.md).

Adaptación aditiva `supabase/adaptations/existing_forms_phase2.sql` después de M2/M4/fase 1, y actualización de `forms-pdf`, pendientes en Supabase remoto. Pruebas: `bash supabase/tests/run.sh clinical`.

## M6 — Recetas y registro de medicación

Perfiles versionados, firma propia o compartida con permisos revocables, recetas con PDF revisado, aplicaciones pendientes de validación, frascos y reportes congelados con CSV. Conectado con casos clínicos y hospitalización. Los actos reservados requieren habilitación profesional de servidor; catálogo regulatorio vacío hasta contar con fuentes. [Estado, instalación y límites](docs/m6-recetas-control.md).

Adaptación local: `supabase/adaptations/existing_prescribing_m6.sql`; pendiente de aplicar remotamente. Pruebas: `bash supabase/tests/run.sh prescribing`.

## M7 — Cálculos clínicos

Fluidoterapia, CRI, producción por lote/agua/alimento y motor de referencias para protocolos, constantes, metabolismo, ajustes y retiros. Parámetros capturados por MVZ, sin cifras clínicas precargadas. [Alcance y pruebas](docs/m7-calculos.md). No requiere una nueva migración Supabase.

[Pendientes para la revisión final](docs/pendientes-revision-final.md), incluidos datos, instalación remota, dispositivos e integraciones.

## M8 — Inventario y ventas

Productos/lotes existentes, caducidades y reorden, stock con movimientos auditables, POS con permisos de dispensación M6, corte inmutable y CSV, cámara para códigos/fotos privadas y pedidos con aprobación. [Alcance, instalación y límites](docs/m8-inventario-ventas.md). Adaptaciones locales `existing_inventory_m8.sql` y `existing_inventory_photos_m8.sql`; aún sin instalación remota. Pruebas SQL: `bash supabase/tests/run.sh inventory`.

Ajuste M8: entrega clínica y cobro separados, permisos revocables para recepción/auxiliar en ordinarios y cargos por cada aplicación de una receta. Adaptación adicional `existing_inventory_workflow_m8.sql`, aún sin instalación remota; conserva los permisos reservados de controlados.


## M9–M11 — Operación, checado y exportación

Agenda/calendario y estética, servicios con comisión congelada y cobro por recepción, tareas, mensajes, distribuidores y ficha médica consentida. QR firmado de 45 s, ubicación puntual, hora del servidor, correcciones anexas y asistencia CSV/PDF. Estadísticas y respaldo operacional JSON con PDF históricos, fotos, catálogos y verificación de hashes; tablas CSV. [Alcance y límites](docs/m9-m11-operacion-checado-respaldo.md).

Adaptaciones locales: `existing_operations_m9.sql`, `existing_attendance_m10.sql`, `existing_statistics_m11.sql`; pendientes de instalar después de M8 workflow (M11 también necesita M3). Drive, restauración ensayada y respaldo integral siguen pendientes. Pruebas SQL aisladas: `bash supabase/tests/run.sh remaining`.

## Cobros/pagos — referencias externas

Registro por clínica de efectivo, transferencia o tarjeta, banco/plataforma y referencia, sin volver a sumar ventas ni descontar stock. Conciliación manual del admin y comisión/neta separadas. Adaptación adicional `existing_payment_references.sql`. [Integración prevista y estado real](docs/cobros-pagos-integraciones.md): Stripe/PayPal y conexiones bancarias aún no están activadas.

## M12–M13 — IA y planes

Historial privado/compartido con contexto optativo por rol, conexiones de IA cifradas en servidor y selector de modelos; espacio individual, catálogo de planes, cuotas, beta/regalos y base de suscripción Stripe con webhook verificado. Implementación local, precios en borrador y cobros desactivados. [Costos y alcance](docs/planes-costos-m13.md), [IA y privacidad](docs/m12-ia-contexto.md).

Pruebas adicionales: `bash supabase/tests/run.sh ai_plans` y `node --test supabase/tests/ai_billing.test.mjs`. Las adaptaciones y Edge Functions aún no están instaladas en Supabase remoto.

## M14 — Soporte, pagos e inicio guiado

Página de producto/herramientas y precios, guía reabrible, historial de pagos de suscripción y reportes privados con adjuntos y conversación de soporte. IA opcional para preparar ayuda revisada, sin enviar archivos al proveedor. [Estado y configuración](docs/m14-soporte-inicio-producto.md). Adaptación local `existing_support_m14.sql`, posterior a M13 y con Storage; atención humana/contactos y servicios reales pendientes.

## Revisión de plataforma e IA inicial

[Informe, correcciones y prioridades](docs/revision-plataforma-2026-10-08.md). Mejoras de inicio/escáner, menús por rol, ajustes, legibilidad y reintentos. Ayuda incluida con Gemini por defecto y GLM alternativo, solo temas públicos sin datos clínicos ni texto libre; clave y cupos controlados en servidor, sin fallback de pago. [Configuración y fuentes oficiales](docs/ia-incluida.md). Adaptación adicional `existing_starter_ai_review.sql` y función `starter-ai`, todavía sin instalación remota ni claves reales.

## Beta y permisos: actualización 16-oct-2026

Administración de plataforma con cuenta separada y 2FA comprobada por la propietaria. Base de permisos explícitos y evidencia profesional aplicada **desactivada** al proyecto de pruebas, sin promoción de roles ni datos clínicos de ejemplo. Pantalla de gestión en «Mi cuenta y clínicas → Permisos y habilitación». [Alcance, evidencia y lo pendiente](docs/permisos-etapa2a.md).

Las ACL heredadas aún requieren sustitución por módulo; esta base no acredita la migración completa ni autoriza abrir la beta. El primer MVZ necesita revisión externa con evidencia real. Las admisiones y el candado global permanecen desactivados; no hay borrado automático por vencimiento.

Actualización de términos y plataforma: la pantalla usa la misma versión/hash del texto que registra `terms_acceptances`, con historial inmutable y aceptación de actualizaciones sin renovar los 60 días. Los documentos de Drive están importados como borradores, sin publicar. La plataforma dispone de consulta/revocación de habilitaciones globales con MFA, sin crear una inscripción clínica ni permitir la primera verificación desde la app. [Estado y pendientes de los textos](docs/terminos-versionados-y-plataforma.md).
