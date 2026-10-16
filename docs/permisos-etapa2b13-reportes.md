# 2B-13: reportes del libro de controlados

Candidato local **13J1**, después de 13I2, 16-oct-2026. No desplegar por separado, activar beta ni generar APK con este cambio todavía.

## Estado

- **Implementado y probado:** inventario/caja 13I2 y los bloques anteriores tienen evidencia aislada documentada.
- **Preparado local:** SQL y Flutter para corte del libro de controlados, PDF, emisión y exportación con permisos por persona. Validación de este candidato al final del documento.
- **Aplicado en remoto y probado:** este candidato no está aplicado a Supabase. Las pruebas de GitHub usan PostgreSQL aislado, no el proyecto remoto.
- **Pendiente:** formatos/consentimientos y sus firmas, otros agregados/respaldos/identidad, pruebas reales Auth/Storage/Edge con dos clínicas, despliegue coordinado y APK.

## Alcance y autoridad

Reutiliza el libro existente: cada responsable consulta sus propias aplicaciones de controlados/cuantiﬁcados, con corte inmutable y pendientes visibles. No añade reportes generales de producción ni implementa todas las columnas del Anexo 5. No hay nuevas tablas, concesiones automáticas, conversiones de históricos, datos clínicos ni normas.

- Preparar requiere `report.prepare`, `clinical.read`, `patient.read` y habilitación profesional vigente con identidad contrastada. Este libro reservado a controlados sigue siendo del MVZ; preparar otros documentos ordinarios es otro flujo.
- Emitir requiere además `report.issue`; preparar no concede emitir. El servidor revalida identidad, perfil, concesión concreta de preparación y pertenencia antes de guardar el artefacto y antes de emitir. Una concesión nueva no resucita el borrador anterior.
- El perfil aporta **la firma propia** del MVZ responsable; no se delega su firma. La emisión registra actor, hora del servidor, concesión de emisión, hash del contenido y del PDF en bitácora. La doble confirmación produce un solo evento.
- El puesto `admin` no da acceso al libro ni a sus PDF. El acceso exige responsable original, habilitación vigente, lectura clínica y permiso vigente para preparar o emitir reportes.
- No se habilita formato oficial: el servidor rechaza `p_official=true`. PDF/CSV/XLSX se identifican como **«basado en Anexo 5, no oficial»**. No se generan folios ni se infieren plazos o columnas normativas. El formato vigente verificado se aborda aparte.

## Cortes, lectura y exportaciones

Solo entran aplicaciones cuya última revisión exacta al corte sea validada, sin incidencia, con referencia de permiso de validación y producto con fuente verificada no vencida al corte. Las revisiones históricas sin referencia del modelo nuevo siguen pendientes; no se convierten automáticamente en validaciones nuevas. Las correcciones posteriores no modifican el reporte original.

Las listas y respuestas de mutación omiten el snapshot con la firma. Las tablas solo permiten consultar `id/clinic_id` para la resolución de ámbito de Edge; no exponen directamente contenido o filas del reporte. PDF consulta la autoridad del usuario; el registro del artefacto es exclusivo del servicio y vuelve a comprobar la autoridad congelada después de renderizar.

Los originales emitidos conservan su firma y hash aunque el perfil cambie después, mientras exista autoridad actual de lectura. Un borrador sin atribución del nuevo modelo no se renderiza/emite: debe prepararse un corte nuevo. No se elimina ningún histórico.

Cada exportación de CSV o PDF/XLSX de consulta vuelve a consultar al servidor; no usa solamente las filas guardadas en pantalla. La respuesta de exportación omite los vectores de firma. El XLSX utiliza el generador OOXML real existente; el PDF firmado del corte se mantiene separado del PDF de consulta con membrete.

Flutter consume contrato `schema_version=1`, `mode=controlled_reference`, con capacidades booleanas estrictas. La pérdida del contrato conocido, versiones desconocidas o errores borran datos/capacidades anteriores. Compatibilidad con servidores anteriores solo mientras nunca anunciaron el contrato nuevo; no hay alternativa por puesto en las rutas SQL nuevas.

## Riesgos y fases restantes

1. Probar y guardar este candidato local de reportes, preservando la ruta de recetas individual/temporal existente.
2. Cerrar formatos: preparación/autorización por persona, firma real de quien realiza, firma del tutor no delegada y congelación de PDF. Revisar plantillas sin volver obligatoria toda la historia clínica.
3. Completar dependencias transversales y probar Auth/Storage/Edge reales antes del despliegue coordinado. Estas pruebas SQL no certifican alarmas Android ni publicación de beta.

No hay nuevas decisiones de esquema pendientes para este bloque conservador. Ampliar a reportes oficiales o generales requiere su especificación/fuente; no se presenta el libro actual como cumplimiento normativo completo.

## Validación local

- `bash supabase/tests/run_permission_reports.sh`: permisos distintos, actor sin habilitación, administrador sin acceso implícito, tablas/anon/servicio, revocación, perfil cambiado, históricos emitidos, pendientes y fuente, doble emisión y caducidad tras esperar un bloqueo.
- El renderer procesa un snapshot generado por SQL y `pdftotext` verifica la advertencia no oficial, una fila validada, dos pendientes y firma propia. Los bytes `%PDF-SYNTHETIC-*` usados en pruebas SQL son solo fixtures de frontera; esa comprobación no sustituye la del renderer real.
- Flutter: contrato estricto, separación preparar/emitir y exportación con nueva comprobación. Suite completa: **315 pruebas**, análisis sin incidencias.

Evidencia de GitHub pendiente de ejecución sobre el commit de código de este candidato.
