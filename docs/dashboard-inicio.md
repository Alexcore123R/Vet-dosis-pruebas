# Inicio y navegación — 14 de octubre de 2026

El inicio muestra accesos a inventario, estadísticas, recetas, formatos, pacientes, agenda, hospitalización y cálculo rápido según el rol. El menú agrupa Cálculo rápido y Cálculos clínicos dentro de Cálculos. Planes y Respaldo se abren desde Ajustes. Estadísticas dispone de una pantalla independiente; Respaldo mantiene sus exportaciones y revisión de archivos. IA y soporte tienen botones flotantes independientes: IA encima de soporte, esquina inferior derecha. El contenido reserva espacio inferior para esos botones.

El dashboard consulta los repositorios existentes del espacio activo: agenda, pacientes, hospitalización, inventario y estadísticas. No requiere migraciones ni nuevos permisos del servidor. Los permisos del menú filtran las consultas y accesos; la autorización sigue siendo responsabilidad del servidor. No carga estadísticas para roles distintos de admin, hospitalización para recepción/estilista ni inventario para estilista.

Las secciones cargan de forma independiente y muestran un error si fallan. Ausencia de cuenta, conexión o repositorio aparece como resumen no disponible, nunca como cero. Al actualizar se descartan resultados previos. Los datos se consultan al abrir el inicio y con Actualizar resumen; no hay suscripción en tiempo real. La hora de última consulta permite identificar antigüedad. Un reloj local revisa cada minuto la clasificación de horarios sin descargar nuevos registros.

Citas próximas: estado agendado, inicio futuro, orden ascendente, máximo cinco. Citas recientes: inicio pasado, orden descendente, máximo tres, con estado visible, incluidas cancelaciones. El alcance histórico es el que devuelve el repositorio de agenda (actualmente 90 días).

Dosis: solamente tareas de tipo medicacion en estado pendiente, asociadas a hospitalización. El horario efectivo respeta posposición posterior al horario original. Los avisos distinguen dosis cuyo horario ya llegó y próximas dosis; no administran ni modifican tratamientos. El resumen no incluye tratamientos externos a hospitalización. Stock bajo utiliza el stock disponible y la bandera low_stock calculados por el servidor; solo incluye productos activos.

Recetas y formatos son accesos a sus pantallas. No se agregaron contadores ficticios: sus repositorios actuales no exponen una consulta agregada para el inicio. Estadísticas conserva importes netos de devoluciones, sin llamarlos utilidad neta. Respaldo y planes conservan sus funcionalidades y restricciones anteriores.

Validación: nueve pruebas aprobadas en dashboard_test.dart, widget_test.dart y support_welcome_test.dart; análisis estático sin incidencias. Se verifica navegación móvil a cálculos, IA, soporte y ajustes, aislamiento por clínica, error parcial, modo sin conexión, filtrado de citas y tratamiento de dosis pospuestas/completadas. Las pruebas usan repositorios de prueba: la comprobación con una cuenta real y datos reales en el teléfono sigue pendiente.
