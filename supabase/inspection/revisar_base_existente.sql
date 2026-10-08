-- Solo lectura. Devuelve metadatos, no filas de las tablas de la aplicación.
-- Ejecutar en SQL Editor de Supabase y copiar el resultado de diagnostico.
WITH tablas AS (
  SELECT c.oid, n.nspname AS esquema, c.relname AS tabla,
         c.relrowsecurity AS rls_activo, c.relforcerowsecurity AS rls_forzado
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
), funciones_objetivo AS (
  SELECT DISTINCT t.tgfoid AS oid
  FROM pg_catalog.pg_trigger t
  JOIN tablas tb ON tb.oid = t.tgrelid
  WHERE NOT t.tgisinternal
  UNION
  SELECT p.oid
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'private')
    AND p.proname IN (
      'is_clinic_member', 'has_clinic_role',
      'prevent_last_clinic_admin_removal',
      'create_clinic', 'create_clinic_invitation',
      'accept_clinic_invitation', 'revoke_clinic_invitation'
    )
), secciones AS (
  SELECT 'tablas' AS seccion, jsonb_build_object(
    'esquema', esquema, 'tabla', tabla,
    'rls_activo', rls_activo, 'rls_forzado', rls_forzado
  ) AS detalle FROM tablas
  UNION ALL
  SELECT 'columnas', jsonb_build_object(
    'tabla', tb.tabla, 'columna', a.attname, 'posicion', a.attnum,
    'tipo', pg_catalog.format_type(a.atttypid, a.atttypmod),
    'obligatoria', a.attnotnull,
    'valor_predeterminado', pg_catalog.pg_get_expr(d.adbin, d.adrelid),
    'identidad', a.attidentity, 'generada', a.attgenerated
  ) FROM tablas tb
  JOIN pg_catalog.pg_attribute a ON a.attrelid = tb.oid
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped
  UNION ALL
  SELECT 'restricciones', jsonb_build_object(
    'tabla', tb.tabla, 'nombre', c.conname,
    'definicion', pg_catalog.pg_get_constraintdef(c.oid, true)
  ) FROM pg_catalog.pg_constraint c JOIN tablas tb ON tb.oid = c.conrelid
  UNION ALL
  SELECT 'indices', jsonb_build_object(
    'tabla', tb.tabla, 'definicion', pg_catalog.pg_get_indexdef(i.indexrelid)
  ) FROM pg_catalog.pg_index i JOIN tablas tb ON tb.oid = i.indrelid
  UNION ALL
  SELECT 'politicas', jsonb_build_object(
    'tabla', tablename, 'nombre', policyname, 'modo', permissive,
    'roles', roles, 'operacion', cmd, 'using', qual, 'with_check', with_check
  ) FROM pg_catalog.pg_policies WHERE schemaname = 'public'
  UNION ALL
  SELECT 'triggers', jsonb_build_object(
    'tabla', tb.tabla, 'nombre', t.tgname, 'estado', t.tgenabled,
    'definicion', pg_catalog.pg_get_triggerdef(t.oid, true)
  ) FROM pg_catalog.pg_trigger t JOIN tablas tb ON tb.oid = t.tgrelid
  WHERE NOT t.tgisinternal
  UNION ALL
  SELECT 'funciones', jsonb_build_object(
    'esquema', n.nspname, 'nombre', p.proname,
    'argumentos', pg_catalog.pg_get_function_identity_arguments(p.oid),
    'security_definer', p.prosecdef, 'configuracion', p.proconfig,
    'propietario', pg_catalog.pg_get_userbyid(p.proowner),
    'acl', p.proacl::text,
    'definicion', pg_catalog.pg_get_functiondef(p.oid)
  ) FROM funciones_objetivo f
  JOIN pg_catalog.pg_proc p ON p.oid = f.oid
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prokind = 'f'
  UNION ALL
  SELECT 'permisos_tablas', jsonb_build_object(
    'tabla', table_name, 'rol', grantee, 'permiso', privilege_type,
    'puede_otorgar', is_grantable
  ) FROM information_schema.table_privileges WHERE table_schema = 'public'
  UNION ALL
  SELECT 'permisos_columnas', jsonb_build_object(
    'tabla', table_name, 'columna', column_name,
    'rol', grantee, 'permiso', privilege_type
  ) FROM information_schema.column_privileges cp
  WHERE cp.table_schema = 'public' AND NOT EXISTS (
    SELECT 1 FROM information_schema.table_privileges tp
    WHERE tp.table_schema = cp.table_schema AND tp.table_name = cp.table_name
      AND tp.grantee = cp.grantee AND tp.privilege_type = cp.privilege_type
  )
)
SELECT jsonb_pretty(jsonb_object_agg(seccion, elementos)) AS diagnostico
FROM (
  SELECT seccion, jsonb_agg(detalle ORDER BY detalle::text) AS elementos
  FROM secciones GROUP BY seccion
) agrupado;
