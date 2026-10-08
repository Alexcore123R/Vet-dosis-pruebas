# Revisión de la base existente

Fuente: CSV query_results_1791275276916.csv suministrado por el usuario.
Se revisaron exclusivamente metadatos. No se consultaron registros reales,
fuentes clínicas, cantidad actual de miembros ni configuración de Supabase Auth.

## Resultado

Se pueden conservar las seis tablas: clinics, clinic_members, Fármacos,
Fármacos personalizados, inventario y lotes_inventario. RLS activo en todas.
Las funciones de membresía/rol consultan auth.uid() y tienen search_path vacío.
El roster es visible a los miembros de su propia clínica.

El permiso UPDATE existente ya limita las columnas a clinic_members.role y
clinics.name. Por eso el diagnóstico no demuestra que el cliente pudiera cambiar
los identificadores de membresía; la inquietud basada solo en las capturas queda
resuelta por los permisos de columna.

Diferencias que corrige el borrador de adaptación M2:

- Restricción admin/editor/member → cinco roles veterinarios explícitos.
- Ninguna conversión automática de editor o member. Si existen, aborta la
  transacción antes de completar cambios y exige definir la correspondencia.
- Reutiliza clinic_members y created_by. No crea clinic_memberships paralela.
- Conserva el parámetro p_name del RPC create_clinic, refuerza confirmación de
  correo y search_path e incorpora auditoría.
- Añade invitaciones de un uso/correo confirmado y tablas de auditoría.
- Protege último admin en DELETE y UPDATE; prohíbe cambiar la identidad de membresía.
- Escrituras de miembros pasan por RPCs acotados; añade set_clinic_member_role.
  El código anterior que insertaba/eliminaba miembros directamente deberá adaptarse.
- Retira TRUNCATE, REFERENCES y TRIGGER de inventario/lotes para roles de cliente.
  RLS no controla TRUNCATE; no se comprobó que el cliente web lo pudiera invocar.

El borrador no modifica registros de catálogo/inventario, ni migra sus campos clínicos.
No es idempotente: no ejecutar dos veces ni junto con la migración inicial.
Antes de ejecutarlo realmente, confirmar estado actual de roles y conservar un
respaldo de la base existente. El usuario confirmó la ejecución de la adaptación. No se ejecutó desde el agente
ni se verificaron sus funciones con una sesión autenticada.

## Pendientes de módulos posteriores

- Catálogo general sin concentraciones/presentaciones ni estado de verificación.
  Personalizados sí tiene marca, concentración, unidad, presentación y laboratorio.
- No existe flujo de aprobación de dosis compartidas: políticas actuales permiten
  lectura de registros de clínica por todos los miembros. Resolver en M3 antes de uso clínico.
- Inventario tiene caducidad en texto, pero lotes_inventario ya tiene fecha DATE.
  Usar lotes como origen de caducidad; no convertir texto arbitrariamente.
- Lotes no vincula su clinic_id/user_id al ámbito del item_id mediante restricciones.
  Reforzar esa consistencia en M8.
- Las políticas de escritura de productos/dosis referencian editor. El borrador M2
  no concede automáticamente esas facultades a MVZ; definir permisos al implementar M3/M8.
- Offline, propietarios y fichas de personal todavía pendientes.

## Validación local

Fixture PostgreSQL 17 reconstruido con tablas, columnas, restricciones, funciones,
triggers, políticas y grants del diagnóstico, sin registros reales.
Pruebas de aislamiento, roles, invitaciones, auditoría y último admin; datos sintéticos
previos conservados. Siete pruebas Flutter, análisis y compilación web aprobados.
No sustituye una prueba real contra Supabase Auth/PostgREST.

```sh
bash supabase/tests/run.sh existing
```

La app usa la estructura existente de forma predeterminada. La clave publicable
y URL conectan el cliente, pero no aplican la adaptación SQL ni habilitan Google OAuth.
