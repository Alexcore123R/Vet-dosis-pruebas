# VetDosis Pro — traspaso operativo a otro modelo de Codex
Fecha de corte: **22 de octubre de 2026 (México)**. Documento de continuidad: **no sustituye una inspección del repositorio, de los PR ni del estado remoto actual**.

## 1. Encargo del agente entrante

Eres el siguiente agente técnico que continuará el desarrollo de **VetDosis Pro**. Codex ES el programador del proyecto: puede editar la app, escribir y corregir código Flutter, pruebas y documentos, crear commits y PR, ejecutar validaciones y preparar APK de pruebas. Los cambios ordinarios de código se hacen en una rama de trabajo. Un despliegue remoto o una publicación del repositorio se revisa aparte. No reinicies el desarrollo, no sustituyas los criterios del proyecto por supuestos y **no pidas a la propietaria que repita el contexto ya documentado**. Lee este traspaso, revisa el estado actual de GitHub, verifica cada diferencia y comienza con el primer bloqueo abierto.

**Objetivo actual:** cerrar una **beta clínica funcional** para que Johana (MVZ titulada, con experiencia clínica) y colegas evalúen módulos, documentos y referencias veterinarias **primero con pacientes y cuentas ficticios**. El criterio de aceptación es completar el flujo Paciente/Tutor → Agenda → Consulta/Nota → Receta/PDF → Caja/Entrega, además de Hospitalización, sin duplicados, filtraciones entre clínicas ni pérdidas de persistencia. La usuaria confirmó que los **APK recientes sí se instalan**; no volver a tratar la instalación como bloqueo vigente sin nueva evidencia.

## 2. Acceso al código y punto de partida

- Repositorio **privado** (22-oct-2026): **https://github.com/Alexcore123R/Vet-dosis-pruebas**
- Rama principal de trabajo de la app: `feature/historia-carnet-20261020`; último commit observado: `01948555b85a` — «Connect reviewed weekly productivity plans to task batches».
- `main` está muy detrás de esa rama; **NO continuar la beta partiendo de `main`** ni fusionar ciegamente la cadena de PR de diseño.
- Pasos en Codex: conectar/autorizAR la cuenta de GitHub que tiene acceso al repositorio privado; abrir/seleccionar este repositorio, comprobar rama y ejecutar `git status -sb`. Si se usa terminal con autenticación autorizada:

```bash
git clone https://github.com/Alexcore123R/Vet-dosis-pruebas.git
cd Vet-dosis-pruebas
git fetch origin
git switch feature/historia-carnet-20261020
git status -sb
```

- Si ya existe una copia de trabajo o cambios sin guardar, **no hacer clone encima, reset --hard, clean -fd ni checkout destructivo**. Trabajar sobre una rama nueva derivada del HEAD actual, sin pisar modificaciones de otros agentes.
- No hay `AGENTS.md` en la raíz según la inspección de este corte. Leer primero `README.md`, `docs/integracion-beta-pruebas.md`, `docs/equipo-y-cierre-beta.md`, `docs/apk-pruebas.md` y los traspasos de los PR #11/#12/#13.
- Flutter/Dart con Supabase/PostgreSQL; clientes Android, iOS y web. Referencia de CI reciente: Flutter **3.47.6**, Java **17**, PostgreSQL **17** para pruebas SQL aisladas. Comandos: `flutter pub get`, `flutter analyze`, `flutter test`; scripts `supabase/tests/run_*.sh` ejecutan PostgreSQL Docker en entorno aislado. Ajustar según instrucciones de cada workflow.

## 3. Qué ya existe y qué NO debe darse por terminado

Código en módulos Pacientes/Expedientes, Agenda, Consulta, Hospitalización, Recetas, Formatos/PDF, Caja/Inventario, contactos, productividad, promociones/IA, ajustes de equipo y permisos; la presencia de una pantalla o una RPC **no prueba** despliegue remoto ni un recorrido real. El teléfono sí instala APK nuevos, pero no se acreditó todo el flujo conectado de punta a punta.

La auditoría clínica tuvo una ejecución **aprobada** con 8 suites SQL aisladas y **104 pruebas Flutter enfocadas**:
- https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39710122697
- Otra ejecución anterior del módulo principal: 463 tests Flutter aprobados https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39699054513 .
- **No confundir** con nuevas ejecuciones de Actions que terminaron sin runner y sin pasos: esos resultados no acreditan ni error de código ni éxito.

Inspección **solo lectura** del Supabase **de pruebas**, 22-oct, aprobada:
https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39710969017
Verificó presencia de dependencias básicas; encontró `private.beta_policy.admissions_enabled=false`, `private.beta_policy.enforcement_enabled=false`, `private.permission_policy.enforcement_enabled=false`, `private.permission_policy.migration_reviewed=false`. La función `public.app_module_workspace(uuid)` difiere del cuerpo candidato esperado; el reporte **NO significa** que falte toda la instalación. `deploy_ready=false`.

Proyecto Supabase **de pruebas** está fijado por `scripts/supabase/identity_schema.py`; **nunca** usar credenciales de administración en código, logs, PR, prompts o APK, ni ejecutar migraciones por el hecho de que exista un secreto de Actions. No hay autorización para desplegar, cambiar la política beta, habilitar admisiones, publicar datos clínicos o tocar producción.

## 4. PR abiertas: revisar antes de hacer cambios

- **PR #7** — núcleo de trabajo de Pacientes, historia, carnet, Agenda y múltiples módulos. Base `design/production-tools`, cabeza `feature/historia-carnet-20261020`. No fusionada:
  https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/7
- **PR #11** — protocolo de beta clínica, pruebas SQL/Flutter y checklist para Johana. Base `feature/historia-carnet-20261020`; las pruebas iniciales pasaron; ejecución posterior falló antes de runner. Documento: `docs/pruebas/auditoria-beta-clinica-20261021.md` en la rama `audit/clinical-beta-gate-20261021`.
  https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/11
- **PR #13** — **P0 activo**. Comparador SOLO LECTURA del cuerpo de `app_module_workspace` frente a 13N/13O y prueba con dos clínicas sintéticas, rama `audit/p0-module-contract-20261022`. `13O` añade Estadísticas/Respaldos a 13N. CI falló antes de asignar runner, por tanto **NO hay informe remoto nuevo verificado**.
  https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/13
- **PR #12** — previo a «Crear cuenta», diálogo de términos de uso y aviso de privacidad con dos casillas, versiones/hash publicados y bloqueo si no hay textos vigentes. Rama `feature/signup-legal-review-20261021`. **En borrador, no integrado ni desplegado**; los documentos legales de `docs/legal/` siguen como **borradores**, no publicar ni inventar aceptaciones. Los primeros ensayos detectaron fallos de Dart luego corregidos, y CI posterior no llegó a ejecutar runners: pruebas finales pendientes.
  https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/12
- **PR #10** — staging privado de fuentes y referencias veterinarias, rama independiente `feature/reference-staging-20261021`, base `main`. Las tablas bibliográficas **todavía no se han importado**. No correr el SQL bruto de Qwen: contiene `DROP TABLE ... CASCADE`.
  https://github.com/Alexcore123R/Vet-dosis-pruebas/pull/10
- También están pendientes PR #8/#9 para Agenda/CI, y una cadena de diseño #2→#3→#4→#7, con bases encadenadas. Verificar relaciones y revisiones, no hacer merge indiscriminado.

## 5. Próximos pasos concretos y orden

**P0 — compatibilidad y permisos remotos (primero):**
1. Inspeccionar definiciones reales, grants, políticas y hooks mediante consultas SELECT de catálogo en el entorno **de pruebas**, sin leer expedientes ni cambiar flags. Resolver el diff de `app_module_workspace`: `13N` vs `13O` vs cuerpo remoto; jamás aplicar una de esas migraciones a ciegas.
2. Revisar el estado del backup verificable, límites del esquema, contratos/RPC de cliente y protección RLS. La presencia de objetos no sustituye verificar políticas efectivas.
3. Comprobar con **dos sesiones reales de prueba** de Auth, dos clínicas aisladas y datos completamente ficticios: lectura/no lectura, crear y recuperar registros, revocar permisos, tiempos de expiración, anónimo, Edge/Storage/PDF. No reutilizar un JWT administrador como si fuera la sesión de Johana. No abrir la beta ni crear cuentas con datos reales para este ensayo.
4. Ejecutar de nuevo los jobs de PR #13 cuando haya runners disponibles; aislar fallos reales del código y fallos de infraestructura. Registrar SHA, ejecución y resultado.

**P1 — cierre funcional (después):**
5. Completar **abonos parciales sobre un único cargo** con saldos e idempotencia; confirmar que el esquema realmente admite el escenario. No presentar pagos repartidos en servicios como si fueran abonos correctos.
6. Completar **atención sin cita previa**, manteniendo caso clínico, historial, permisos y la vinculación opcional de Agenda.
7. Recorrer Paciente → Agenda → Consulta/Nota → Receta/autoría/PDF → Caja → Entrega → cierre/reapertura de app; probar hospitalización, duplicados, reintentos, restauración y aislamiento entre clínicas. Los PDF y las autorizaciones requieren actor profesional realmente habilitado.
8. **Recetas y Equipo:** la propietaria mencionó ajustes pendientes, aún sin lista detallada. Inspeccionar pantalla, repositorios y documentos existentes; proponer lista concreta y no inventar requisitos.
9. **Registro legal:** cerrar PR #12, revisar redacción legal, publicación verificable de versiones, confirmación explícita, casillas separadas y **recibo auditado posterior a email/alta beta**. Una casilla previa al alta no es automáticamente aceptación autenticada.
10. **Catálogo veterinario:** importar después los lotes/Qwen a una zona de revisión con especie, fuente, edición, página, unidad, método y estado. Johana y colegas revisarán las referencias; ninguna dosis no aprobada debe alimentar calculadora clínica.

## 6. Condiciones de seguridad, coordinación y estilo

- Priorizar **no perder datos**: antes de despliegues un backup reciente validado y verificación de destino; evitar `DROP TABLE ... CASCADE`, aplicar SQL de Qwen sin limpiar, sobreescrituras y cambios irreversibles. No revocar ni generar credenciales por iniciativa sin autorización.
- En la beta de Johana, **solo pacientes, tutores y clínicas ficticios** inicialmente. No guardar ni compartir JWT, API secretas, datos reales, cédulas, firmas, teléfonos/domicilios de personas o PDFs sensibles en logs, PR, fixtures y repositorios públicos.
- No confundir `admin` visual, etiqueta `MVZ` ni antigüedad profesional con habilitación y permiso vigente. Autoría, firma y aprobación deben reflejar la identidad real autorizada de cada operación.
- Distinguir «código preparado», «suite aislada aprobada», «aplicado a Supabase pruebas», «probado en Android con Auth real» y «aprobado para uso clínico». Nunca anunciar un paso como cerrado sin la prueba que le corresponde.
- La usuaria prefiere colaboración ejecutiva: si el trabajo se puede avanzar sin pedir aclaraciones, avanzar; presentar resultados, PR, tests y límites. Evitar preguntas repetidas.
- Otros modelos colaboran en Storage/Edge e integración; revisar cambios recientes antes de editar archivos compartidos. **PR pequeña por cambio; no fusionar ni desplegar sin revisión.**
- Si los límites de Codex impiden continuar, este documento permite el traspaso al siguiente modelo. Cambiar un repositorio de privado a público puede liberar minutos **estándar** de GitHub Actions, pero no elimina las cuotas del modelo Codex. **No cambiar visibilidad sin auditar secretos, historial, artefactos y documentos personales.**

## 7. Primer mensaje de trabajo sugerido

«Revisa la rama actual `feature/historia-carnet-20261020` y las PR #13, #11, #12. Comienza por el P0: diagnostica con solo lectura la diferencia de `app_module_workspace`, comprueba los permisos mediante pruebas sintéticas, recupera evidencias de Actions, y prepara una corrección mínima si encuentras un defecto verificable. No despliegues ni abras la beta. Reporta archivos/commits tocados, tests realmente ejecutados y siguientes bloqueos.»

**Fuentes de verdad:** código y definiciones efectivas actuales, resultados actuales de CI y catálogo remoto; este resumen es un mapa de acceso, no una certificación de estabilidad.

## Acceso al cambiar de modelo y coste de compilación

En Codex: seleccionar el nuevo modelo, abrir el entorno ya vinculado a GitHub y elegir este repositorio privado. Si no aparece, autorizarlo con la cuenta GitHub propietaria desde la conexión de GitHub de Codex. Trabajar desde `feature/historia-carnet-20261020`, en rama derivada; no empezar desde `main`. No hacen falta contraseñas ni claves pegadas en el chat: el acceso se concede mediante la aplicación conectada.

La referencia al proyecto Supabase de pruebas está en `scripts/supabase/identity_schema.py`; el procedimiento de construcción APK está en `docs/apk-pruebas.md`. El acceso GitHub del agente no habilita por sí mismo el despliegue del servidor. Mantener secretos en el servicio correspondiente, nunca en el código ni en los mensajes.

Para compilar gratuitamente: comprobar primero el consumo en GitHub Settings → Billing and licensing → Usage. Los repositorios públicos usan minutos gratuitos de runners estándar, pero publicar uno revela código e historial de Actions. Auditar antes de cambiar visibilidad; una copia pública preparada para compilación también haría visible el código incluido. El límite de uso del modelo Codex es independiente del coste de GitHub Actions.

## 9. Acceso a Supabase para Codex — configuración comprobada, sin claves en Git

**Destino exclusivo:** proyecto Supabase de pruebas `wtrelwtztkddfktrfdpb`. Dashboard: `https://supabase.com/dashboard/project/wtrelwtztkddfktrfdpb`. API cliente: `https://wtrelwtztkddfktrfdpb.supabase.co`. El identificador y la URL no son secretos; NO incluir accesos administrativos, contraseñas o tokens en archivos o chat.

**Configuración recomendada para la auditoría P0:** añadir el MCP oficial de Supabase, limitado al proyecto y solo lectura (no permitir modificaciones):

```sh
codex mcp add supabase-vetdosis-auditoria --url 'https://mcp.supabase.com/mcp?project_ref=wtrelwtztkddfktrfdpb&read_only=true&features=database,docs'
codex mcp login supabase-vetdosis-auditoria
codex mcp list
```

Los comandos anteriores son para Codex CLI o extensión con MCP soportado. En interfaces con configuración visual MCP, agregar como servidor HTTP la misma URL y realizar la autenticación OAuth desde la pantalla. La autenticación la completa la propietaria en el navegador o interfaz; **no compartir un PAT ni una contraseña**. Las herramientas no aparecen en todos los entornos web/cloud: comprobar desde el Codex que realmente se conectó.

**Si un cambio requiere SQL remoto o Edge Functions:** Codex SÍ implementa, corrige, crea SQL propuesto, y ensaya en PostgreSQL aislado; este MCP de auditoría no puede aplicar cambios. Para la fase de despliegue aprobada crear una conexión de escritura independiente, también limitada al mismo proyecto, con aprobación de cada operación y respaldo verificado. Nunca habilitar permisos de escritura en el MCP de auditoría ni conectar un proyecto de producción por comodidad.

**GitHub Actions:** el secreto `SUPABASE_ACCESS_TOKEN` existente se usa solo en Actions para los scripts administrativos. No se puede asumir que Codex tenga automáticamente acceso a ese secreto por tener el repositorio. El APK usa solamente la clave publicable definida en el flujo de compilación, no `service_role`.

**Guía oficial:** https://supabase.com/docs/guides/ai-tools/mcp y https://learn.chatgpt.com/docs/extend/mcp. Supabase recomienda precaución al conectar asistentes a bases con datos sensibles. Usar solamente datos ficticios durante la auditoría; no consultar ni exportar expedientes reales.

**Sobre el problema de compilación:** la propietaria confirmó que los minutos de GitHub Actions de su cuenta se agotaron. No hacer más suposiciones sobre el origen de los runs sin runner. Para compilar gratuitamente, examinar primero si es viable hacerlo localmente con Flutter o publicar una réplica saneada para ejecutores estándar. Hacer público un repo original expone su historial, código y parte de los registros de Actions; no cambiar su visibilidad automáticamente.
