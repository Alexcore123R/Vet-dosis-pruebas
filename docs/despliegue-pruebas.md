# Despliegue de pruebas: PDF

Proyecto fijo: wtrelwtztkddfktrfdpb. La base anterior no es el destino.

Las etapas SQL se ejecutan manualmente en Supabase; el flujo de GitHub no las vuelve a ejecutar.
El flujo `Desplegar PDF en Supabase de pruebas` es manual y despliega únicamente `forms-pdf`, incluyendo fuente Unicode y licencia declaradas en config.toml. No activa proveedores de IA ni cobros.

1. En https://supabase.com/dashboard/account/tokens crear un token personal para este trabajo. Elegir vencimiento si la pantalla lo ofrece. No pegarlo en chat.
2. En GitHub, repositorio privado Vet-dosis-pruebas: Settings → Secrets and variables → Actions → New repository secret.
3. Nombre exacto: SUPABASE_ACCESS_TOKEN. Pegar el token como valor y guardar.
4. Avisar que el secreto está listo; se puede ejecutar el flujo desde Actions o mediante GitHub CLI.
5. Tras ejecución, comprobar acceso no autenticado rechazado y pruebas autenticadas con usuarios autorizados. Un despliegue exitoso por sí solo no valida el flujo de firma/PDF.

El token personal puede permitir administración de varios proyectos de la cuenta; guardarlo solo como secreto y revocarlo al terminar o al retirar acceso al repositorio. No usar service_role como sustituto del token de gestión. Las variables estándar del servidor de Supabase las suministra la plataforma, nunca Flutter.
