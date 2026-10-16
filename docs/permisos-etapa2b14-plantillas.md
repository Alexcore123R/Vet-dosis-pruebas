# 2B-14: plantillas, aprobación de contenido y membrete

Candidato local **13J2**, después de 13J1, 16-oct-2026. Primera parte del corte de formatos, no cierre integral de documentos/consentimientos. No desplegar aisladamente ni abrir beta.

## Estado

- **Implementado y probado:** reportes 13J1 y bloques previos tienen evidencia aislada.
- **Preparado local:** SQL/Flutter para consultar/editar/aprobar plantillas y membrete con permisos por persona; validación de este candidato al final.
- **Aplicado en remoto y probado:** nada de este candidato está aplicado a Supabase. CI usa una base aislada, no despliega.
- **Pendiente:** preparación/atestación y autorización de documentos, firma propia de quien realizó, firma del tutor no delegada, artefactos congelados, demás dependencias y pruebas reales antes del despliegue coordinado/APK.

## Capacidades explícitas

| Permiso | Alcance |
|---|---|
| `form.template.read` | Plantillas de la clínica, bases compartidas de referencia, historial y membrete de formatos. No documentos de pacientes. |
| `form.template.edit` | Con lectura, crear una copia o una nueva versión de una plantilla de la clínica; no depende del puesto ni de quién creó la plantilla. |
| `form.template.approve` | Con lectura y edición, aprobar esa versión con habilitación profesional vigente y perfil contrastado. No verifica datos clínicos ni firma un consentimiento. |
| `form.branding.manage` | Con lectura, guardar una nueva versión del membrete. No permite editar/aprobar plantillas ni emitir recetas. |

Ningún permiso se concede automáticamente; no se convierte un puesto/cédula capturada en habilitación. `form.prepare` y `form.authorize` siguen reservados para el futuro corte de documentos, no se reutilizan como autoridad de plantilla.

La aprobación conserva `source_status='sin verificar'`. Bitácora registra actor/fecha, concesiones de edición/aprobación, motivo, versión y perfil del revisor. Editar genera una versión nueva: una aprobación anterior no se arrastra silenciosamente. Campos y cláusulas bloqueados conservan su protección. No se alteran los formularios base ni se vuelven obligatorios peso, temperatura o una anamnesis completa.

Se serializa por clínica/libro e identidad del actor; se reevalúa permiso con hora real tras esperas/validación. Las versiones esperadas detectan edición simultánea. El reintento exige permiso actual antes de devolver el recibo. No se sobrescriben versiones ni se borran documentos.

## Interfaz y compatibilidad

Contrato estricto `schema_version=1`, `mode=templates_only`, con capacidades booleanas coherentes. Con contrato nuevo, el puesto no habilita editor/aprobación/membrete. Una capacidad perdida, respuesta incompatible o error elimina esquemas/capacidades anteriores; no vuelve a permisos por puesto.

La navegación a Formatos está disponible para consultar autoridad del servidor, también para alguien cuyo puesto visual sea estilista/recepción. Eso no concede acceso a datos. El editor deshabilita la casilla de aprobación si solo hay edición.

Este contrato es **solo de plantillas**: Flutter no consulta documentos ni muestra creación de consentimientos por su permiso. Las rutas SQL antiguas de documentos todavía requieren el siguiente corte; por eso no se despliega ni se declara cerrado Formatos. No se añade una vía de firma compartida. Las pantallas clínicas independientes conservan sus propias comprobaciones.

Las políticas RLS sustituyen puestos por `form.template.read` para plantillas/versiones/configuración. Una base compartida es visible solo si el usuario tiene lectura en algún espacio actual; una copia privada exige lectura en su clínica concreta. El endpoint de vista previa exige lectura actual de la clínica y valida esquema/membrete antes del renderer existente. La aprobación no certifica validez normativa.

## Recomendaciones recibidas

Se conservaron para después de estas rondas en [propuestas del 16-oct-2026](propuestas/20261016/README.md). Los SQL originales están como `.sql.txt`, con hash y fuera de migraciones/assets. No se ejecutaron ni se importaron sus estados `confirmado`, rangos, fórmulas o recomendaciones clínicas. Sus lotes por usuario deberán adaptarse al aislamiento por espacio/clínica antes de cualquier integración.

## Fases y riesgos

1. Este bloque: gobierno de plantillas/membrete, sin dar autoridad para documentos.
2. Documentos: separar preparador/realizador/MVZ, capturar firmas reales, autorización y PDF exacto. Conservar datos opcionales de revisión enfocada y registrar quién hizo cada acto; nunca tomar la firma de otro perfil.
3. Cerrar las otras dependencias y probar Auth/Storage/Edge reales con dos clínicas antes del despliegue conjunto. Los permisos de plantilla no sustituyen permisos de tratamiento, acceso a expedientes o respaldo.

No hay una decisión nueva pendiente para esta separación de capacidades operativas. No se amplían habilitaciones clínicas ni se implementan aún las mejoras pospuestas por la usuaria.

## Validación

- PostgreSQL aislado: puesto sin acceso implícito, edición por persona, aprobación profesional separada, fuente aún sin verificar, campos bloqueados, motivo, versionado, reintento revocado, acceso de terceros/anon/tablas y membrete independiente.
- Concurrencia: una edición por versión esperada, revocación durante espera y aprobación que vence mientras espera el bloqueo; sin persistir una versión aprobada vencida.
- Flutter: permisos sobre puesto, no leer documentos desde plantilla, contrato perdido/malformado, fallo/revocación de lectura y aprobación deshabilitada.

Suite completa local: **319 pruebas Flutter correctas**; `flutter analyze --no-pub` sin incidencias. SQL y concurrencia correctos. Evidencia de GitHub pendiente de ejecución sobre el commit de código.
