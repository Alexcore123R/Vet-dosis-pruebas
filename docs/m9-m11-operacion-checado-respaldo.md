# M9–M11: entrega local

Estos módulos amplían el proyecto existente; no están instalados en Supabase remoto. Las migraciones nuevas se aplican una vez, después de las anteriores y con respaldo previo en la revisión final.

## M9 · Operación

`existing_operations_m9.sql` añade servicios, citas, tareas, mensajes, distribuidores, fichas médicas y servicios realizados. Todas las tablas tienen RLS y ningún cliente puede escribir directamente. Las RPC comprueban membresía y rol en servidor. No hay selector de rol.

El admin edita precio y comisión (porcentaje o bono fijo). Registrar un servicio conserva nombre, versión, precio, regla y comisión como un acto inmutable. Editar el catálogo no cambia actos anteriores. Recepción cobra el acto con caja M8; no vuelve a administrar, dispensar ni descontar medicamento. El servidor bloquea doble cobro y conserva la comisión en el corte; el reverso sigue siendo un evento separado. Cualquier permiso para actos clínicos sigue dependiendo de M6, no del catálogo de servicios ni de la agenda.

La agenda tiene calendario, inicio/fin en hora local convertida a UTC, profesional, especie y consulta/estética. El servidor serializa reservas por profesional para impedir solapamientos. Estados: agendado → en atención → listo → entregado; cancelación antes de listo. Estilista accede a sus citas; recepción tiene la agenda operativa sin acceso al expediente completo. Vinculación al paciente y reprogramación están pendientes.

Pendientes se asignan a persona o todos; solo destinatario, creador o admin pueden completar los personales. Mensajes tienen categoría, autor y hora del servidor, se conservan sin edición. No introducir datos sensibles en el chat compartido. Distribuidores tienen contacto manual por llamada, SMS o WhatsApp; no hay envío automático.

La ficha médica requiere consentimiento del propio usuario; solo él puede capturar o retirar su ficha. Solo él y admin de esa clínica pueden consultarla. Se registra la acción sin copiar su contenido al audit log. No aparece en el dashboard general ni en el respaldo de otros empleados.

## M10 · Checado

`existing_attendance_m10.sql` crea configuración, consentimiento, eventos y correcciones. El QR contiene clínica, admin, bloque de 45 segundos y firma HMAC-SHA256; su secreto reside en schema privado, nunca en la app ni en un respaldo exportado. El servidor comprueba firma, clínica, vigencia, admin vigente, membresía y consentimiento a la versión actual del aviso.

La app pide ubicación solo después de leer el QR y usa una consulta puntual, sin monitoreo en segundo plano. El servidor valida coordenadas, precisión y distancia (Haversine) contra radio configurable. Conserva distancia/precisión, no coordenadas del empleado. La hora oficial es del servidor. Una operación reintentada no duplica evento; dos intentos nuevos bajo el mismo QR se bloquean. Las entradas/salidas alternan con bloqueo por miembro para evitar carreras.

Solo admin anexa corrección de hora, con motivo y bitácora; el original permanece inmutable. Reportes CSV/PDF conservan hora original y efectiva. No son cálculo de nómina. Configurar el aviso otra vez invalida consentimientos antiguos; puede retirarse consentimiento.

La app descarta el QR al pasar a segundo plano y oculta el vencido; usa el intervalo recibido del servidor para renovar. El dispositivo requiere pruebas reales. GPS puede ser suplantado y no se presenta como prueba infalible de presencia.

## M11 · Estadísticas y exportación

`existing_statistics_m11.sql` ofrece exclusivamente al admin ventas de 12 meses, citas no canceladas del mes por especie y bajo stock. Usa zona horaria de M8. Las devoluciones restan en el mes en que ocurren; no se etiqueta el total de ventas como utilidad neta. Las barras tienen descripción accesible y las negativas se destacan.

Exportación operacional JSON: una función de lectura `STABLE` genera el snapshot bajo una sola vista coherente de PostgreSQL. La función pública verifica admin y registra que se exportó. Se conserva el texto JSON original del servidor dentro de un contenedor `snapshot_json`, evitando perder precisión de cantidades al pasar por números flotantes. Incluye registros relacionados, revocaciones, recetas/reportes/formatos y PDF congelados en bytes hex; catálogos locales originales se adjuntan con hash. Se descargan las fotos privadas vinculadas, sin enlaces temporales dentro del respaldo. Si falla una foto, no se genera un archivo que aparenta estar completo. Límite local: 50 MB.

SHA-256 verifica snapshot, fotos y catálogos; además los PDF históricos deben coincidir con su hash congelado. Se puede verificar un archivo guardado sin restaurarlo. CSV exporta tablas para Excel y servicios/comisiones. Los CSV son informes, no sustituyen el archivo JSON ni mantienen su precisión arbitraria para todos los lectores.

No se incluyen credenciales, tokens de invitación, secretos de QR, firmas reutilizables privadas ni fichas médicas ajenas. El archivo contiene pacientes/propietarios y PDF firmados: antes de exportar la pantalla pide reconocer su acceso restringido. El archivo no está cifrado; su almacenamiento seguro, Drive, automatización y restauración son trabajo explícitamente pendiente. No se afirma que esta exportación equivalga a un respaldo integral del servidor o que su hash autentique al emisor.

## Comprobaciones

Pruebas SQL aisladas verifican permisos por rol/clínica, consentimiento y privacidad del personal, citas solapadas, inmutabilidad, reintentos, comisión histórica, cobro por recepción, QR vencido/falsificado, ubicación fuera del radio y precisión insuficiente, correcciones reservadas al admin y exclusiones del respaldo. Pruebas Flutter verifican pantallas, limpieza de datos al perder acceso e integridad de archivos/fotos. Verificaciones locales no sustituyen instalación y pruebas en cuentas/dispositivos reales.
