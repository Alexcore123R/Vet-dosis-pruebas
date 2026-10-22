# P0 — Auditoría del contrato de navegación y aislamiento

**Alcance:** comparar `public.app_module_workspace(uuid)` realmente instalado con la versión candidata 13O, sin cambiar definiciones, datos, políticas ni dar permisos.

- `module_contract_readonly.py` consulta exclusivamente el catálogo `pg_proc` sobre el proyecto de **pruebas** fijado en `identity_schema.py`, conserva hashes/privilegios y produce un diff del código SQL en un artefacto privado de Actions. No consulta clientes ni expedientes.
- Los cuerpos SQL de 13N y 13O pueden diferir legítimamente: 13O agrega Estadísticas y Respaldos. Una diferencia de hash requiere revisar el texto; no justifica restaurar la versión de una migración a ciegas.
- `module_navigation_two_clinics.sql` agrega dos identidades y clínicas **ficticias** en el PostgreSQL local aislado; comprueba que el rol visual admin no regala permisos, que la clínica A no lee B y viceversa y que el anónimo no ejecuta. También confirma flags de beta/permisos sin activar. No prueba Auth HTTP en la nube.
- **Requisitos posteriores:** prueba real con dos sesiones Auth aprobadas y dos clínicas de prueba, expiración/revocación durante operación, respaldo verificable y revisión de la política global; nunca usar un JWT de administración como si fuese la sesión de Johana.

**Puerta:** aprobar ambas verificaciones no equivale a habilitar beta o autorizar la entrega del APK; mantener `deploy_ready=false`, PR borrador y controles desactivados mientras se revisa el conjunto.
