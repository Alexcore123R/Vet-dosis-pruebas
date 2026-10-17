# Navegación y dashboard por capacidades actuales

Candidato local **13N**, posterior a 13M. Sin aplicar a Supabase, sin APK y sin apertura de beta.

## Estado y alcance

- **Implementado y probado previamente:** rutas funcionales hasta 13M, cada una con comprobación propia del servidor.
- **Preparado en esta ronda:** contrato transversal de entrada a pacientes, agenda, hospitalización, inventario, caja, recetas, formatos y clínica; filtrado de menú, buscador, accesos rápidos y consultas del dashboard.
- **Aplicado en remoto y probado:** nada de 13N. PostgreSQL aislado y Flutter no equivalen al proyecto Supabase de prueba.
- **Pendiente:** estadísticas y respaldos, Storage y Edge Functions, plataforma/MFA, cola offline y comprobaciones HTTP reales con dos clínicas.

No se introdujo una decisión nueva de esquema. Los puestos conservan su uso visual y no otorgan capacidades. Las secciones aún no revisadas mantienen su comportamiento anterior hasta tener un permiso definido; no se presentan como migradas por este bloque.

## Contrato del servidor

`app_module_workspace` exige sesión y membresía de la clínica. Devuelve versión 1, ocho booleanos de entrada —pacientes, agenda, hospitalización, inventario, ventas/caja, recetas, formatos y clínica— y cinco booleanos independientes para los resúmenes de pacientes, agenda, hospitalización, inventario y ventas. No devuelve filas, nombres, importes, conteos, datos clínicos ni evidencia privada.

Cada booleano se calcula desde concesiones actuales mediante `permission_effective`; considera pertenencia, vencimiento, revocación, procedimiento cuando corresponde y habilitación profesional declarada por el catálogo. No consulta el puesto visual y no crea concesiones. Un permiso de un área no abre otra: por ejemplo, inventario no habilita caja y pacientes no habilita expediente clínico. Gestionar un módulo tampoco inventa lectura de su resumen: `inventory.manage` permite entrar a su herramienta, mientras que el dashboard requiere `inventory.read`.

El contrato no llama al candado beta porque no devuelve datos de negocio y debe poder cargarse antes y después de aceptar términos. Las lecturas y escrituras reales conservan el candado beta en sus propias rutas. Esto evita que un rechazo inicial deje ocultos los módulos durante toda la sesión después de aceptar los términos.

## Interfaz y limpieza de estado

La aplicación carga el contrato para la cuenta y clínica activas. Mientras carga o si recibe una versión/forma desconocida, los ocho módulos revisados quedan ocultos. Al cambiar usuario, clínica o repositorio, elimina primero las capacidades anteriores; una respuesta tardía de la identidad previa no puede restaurarlas. El refresco periódico de la sesión también invalida primero el contrato y vuelve a consultarlo, para reflejar concesiones vencidas o revocadas sin reiniciar la aplicación.

El menú lateral, buscador, escáner flotante, ajustes relacionados, accesos rápidos y pantalla seleccionada consumen el mismo contrato. Si una pantalla quedó seleccionada y se pierde la capacidad, no construye ese módulo ni inicia su consulta.

El dashboard consulta agenda, inventario, hospitalización y pacientes solo si el módulo correspondiente está disponible. Las cifras de caja visibles en el dashboard usan la capacidad de ventas/caja; dejan de depender del puesto administrador. Los RPC de cada módulo siguen siendo la autoridad final y pueden devolver datos aún más limitados según la acción concreta.

Para compilaciones o pruebas sin repositorio de capacidades se conserva temporalmente el filtro visual anterior. La compilación conectada a Supabase siempre registra el repositorio nuevo y por ello falla cerrada para los módulos revisados. Esta compatibilidad deberá retirarse cuando el despliegue coordinado sea obligatorio para todos los canales.

## Riesgos y validación

El principal riesgo era conservar datos o accesos de la clínica anterior durante un cambio de identidad. El límite generacional del cargador y el estado denegado durante carga/error cubren ese caso. Otro riesgo era confundir visibilidad con autorización; por eso el contrato solo evita consultas innecesarias y cada RPC mantiene su comprobación.

`run_module_navigation_dashboard.sh` aplica toda la cadena en PostgreSQL aislado y prueba administrador visual sin permisos, concesión estrecha, revocación, otra clínica y anónimo. `module_navigation_dashboard_test.dart` prueba contrato estricto, independencia entre inventario/caja, ausencia de consultas ocultas y limpieza al cambiar identidad.

Este bloque no acredita Auth HTTP real, Storage, Edge Functions, restauración, exportación, alarmas en teléfono ni despliegue remoto.
