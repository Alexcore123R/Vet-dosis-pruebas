# P0 — Auditoría del contrato de navegación y aislamiento

**Alcance:** comparar `public.app_module_workspace(uuid)` realmente instalado con la versión candidata 13O, sin cambiar definiciones, datos, políticas ni dar permisos.

- `module_contract_readonly.py` consulta exclusivamente el catálogo `pg_proc` sobre el proyecto de **pruebas** fijado en `identity_schema.py`, conserva hashes/privilegios y produce un diff del código SQL en un artefacto privado de Actions. No consulta clientes ni expedientes.
- Los cuerpos SQL de 13N y 13O pueden diferir legítimamente: 13O agrega Estadísticas y Respaldos. Una diferencia de hash requiere revisar el texto; no justifica restaurar la versión de una migración a ciegas.
- `module_navigation_two_clinics.sql` agrega dos identidades y clínicas **ficticias** en el PostgreSQL local aislado; comprueba que el rol visual admin no regala permisos, que la clínica A no lee B y viceversa y que el anónimo no ejecuta. También confirma flags de beta/permisos sin activar. No prueba Auth HTTP en la nube.
- **Requisitos posteriores:** prueba real con dos sesiones Auth aprobadas y dos clínicas de prueba, expiración/revocación durante operación, respaldo verificable y revisión de la política global; nunca usar un JWT de administración como si fuese la sesión de Johana.

**Puerta:** aprobar ambas verificaciones no equivale a habilitar beta o autorizar la entrega del APK; mantener `deploy_ready=false`, PR borrador y controles desactivados mientras se revisa el conjunto.

## Resultado de ejecución — 22 de octubre de 2026

La [ejecución 39731919441](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39731919441) falló en el intento inicial y el reintento **antes de asignar un runner a cualquiera de los dos trabajos**: ambos terminaron sin pasos y sin registros descargables. **No se ejecutó la comparación remota ni el ensayo sintético nuevo.** Esta falla de infraestructura no demuestra un defecto del código ni acredita que esté bien.

Evidencia vigente separada:
- El [preflight de solo lectura anterior](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39710969017) sí corrió y encontró definición distinta de `app_module_workspace`; política de permisos con `enforcement_enabled=false`, `migration_reviewed=false`; y beta con admisiones y enforcement desactivados.
- Las [ocho suites SQL y regresión Flutter previas](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39710122697) aprobaron, pero **no reemplazan** la comparación nueva de las dos clínicas ni una prueba HTTP autenticada.
- No ejecutar `13N` ni `13O` para corregir una diferencia de hash; primero revisar el diff SQL y los permisos reales.
- El paso P0 queda **abierto** hasta que vuelva a funcionar GitHub Actions y se pueda contrastar el reporte, o se ejecute el informe localmente con credenciales protegidas en el entorno autorizado.
