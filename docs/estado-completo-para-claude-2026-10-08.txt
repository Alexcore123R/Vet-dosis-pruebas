# VetDosis Pro — actualización completa para Claude

Fecha de corte: 8 de octubre de 2026. Proyecto local: `/workspace/vetdosis_pro`.

Claude: este documento reúne el estado actual del proyecto, las decisiones acordadas, las funciones implementadas y los pendientes. Úsalo como actualización de referencia. Los informes anteriores de Gemini y algunos documentos históricos describen etapas anteriores; no prueban que sus funciones estuvieran operativas ni que las integraciones actuales estén desplegadas. Esta actualización distingue código existente, verificación local y servicios activados.

## 1. Estado general y significado de “implementado”

La aplicación actual está desarrollada en **Flutter/Dart**, con proyectos para Android, iOS y web. En computadora se plantea uso por navegador; no hay una aplicación de escritorio nativa independiente terminada. La compilación web de producción pasa. Compilación nativa, permisos, exportación y funcionamiento real en Android/iPhone siguen pendientes de las pruebas finales.

Hay implementación local de M1–M14, además de M-FORMATOS, con distintos alcances y pendientes detallados abajo. **Esto no significa que todos los requisitos estén completos ni que el producto esté listo para producción.**

- **Implementado localmente:** existe código, pantallas, lógica o adaptación SQL en el proyecto.
- **Probado localmente:** se verificó con pruebas automatizadas o datos sintéticos; no equivale a prueba en la clínica o Supabase remoto.
- **Preparado para integrar:** existe el flujo, pero faltan despliegue, configuración, credenciales, revisión de datos o prueba con el proveedor.
- **Pendiente:** todavía requiere desarrollo o integración. Se especifica cuál.

El proyecto Supabase existente fue considerado y su esquema inicial revisado. Se prepararon adaptaciones aditivas que reutilizan sus tablas. **No se ha acreditado la instalación remota completa de estas adaptaciones ni el despliegue de las Edge Functions.** No se hicieron cobros reales ni se cargaron pacientes o firmas reales para probar estas funciones.

Arquitectura: MVVM por módulos, repositorios, inyección por constructores y lógica de cálculo pura separada de la interfaz. Se sustituyó la propuesta Android/Room por **Sembast en plataformas nativas e IndexedDB en web** para la infraestructura de caché/sincronización; SharedPreferences guarda preferencias visuales. No existe aún caché clínica offline completa.

No hay repositorio Git inicializado ni publicación en GitHub acreditada en esta copia. Hosting, dominio, tiendas y publicación siguen pendientes.

## 2. Decisiones que deben conservarse

- App veterinaria para México, interfaz en español y navegación por ramas clínicas.
- Datos clínicos y regulatorios no se inventan. Referencias versionadas con fuente y estado `verificada/sin verificar`; datos faltantes permanecen vacíos.
- Una fuente o aprobación administrativa no reemplaza la revisión clínica/regulatoria.
- Roles vienen de Supabase y se comprueban en servidor; no hay selector para convertirse en admin o MVZ.
- Roles: admin, MVZ, auxiliar, recepción y estilista. **Pasante se trata como auxiliar**, sin otro rol.
- Ser admin, pagar un plan o registrar una cédula no habilita automáticamente como MVZ.
- Cada clínica queda aislada por permisos RLS/RPC. Propietarios, firmas, documentos y datos médicos del personal tienen restricciones adicionales.
- Firmas y documentos emitidos conservan versiones, autores y hora del servidor. Las correcciones clínicas se anexan; no borran el original.
- Los folios oficiales los captura el usuario autorizado. La app no inventa folios SENASICA/COFEPRIS ni declara validez oficial por sí misma.
- WhatsApp manual usa enlaces prellenados; no hay envíos externos automáticos. Pedidos a proveedores requieren aprobación explícita.
- Cobrar un tratamiento es distinto de emitir su receta, dispensar físicamente el producto, registrar su aplicación y validar un medicamento controlado.

## 3. M1 — núcleo, interfaz, navegación y ajustes

**Implementado:**

- Ramas en cabecera y menú lateral oculto: Pequeñas especies; Exóticos/Silvestres; Grandes especies/Producción; Gestión clínica.
- Home con accesos rápidos a cálculo, escáner, receta y hospitalización, filtrados por permisos.
- Cinco paletas: verde clínico, azul océano, índigo, ámbar y obsidiana. Modos claro, oscuro y sistema, con persistencia local.
- Estilo neumorphism ajustado para contraste y lectura. Menús, etiquetas largas y controles revisados en tamaños de teléfono y computadora.
- Ajustes por cuenta/clínica, perfil/firma, formatos/membrete/logo, notificaciones, inventario, IA/privacidad, planes/pagos, respaldos y ayuda.
- Clínica o espacio personal actual visible. Volver desde módulos conduce a Home.
- Aviso de inicio guiado, sin desplazar los accesos clínicos principales.
- Protección de cambios sin guardar en varios formularios: continuar editando o descartar; guardar bloquea salida; un error conserva la captura.

**Límites:** las ramas organizan herramientas, no deducen automáticamente especie o parámetros clínicos. El escáner actual identifica códigos de barras de inventario; no interpreta etiquetas de medicamentos. Falta extender la protección de cambios a todos los editores, recuperar borradores tras cerrar el proceso y completar navegación web con URLs/historial/enlaces profundos.

## 4. M2 — autenticación, clínicas, equipo y permisos

**Implementado:**

- Registro e inicio de sesión con correo/contraseña, confirmación y cierre de sesión; flujo Google OAuth preparado.
- Sesión y rol obtenidos de Supabase; múltiples clínicas y selección de clínica activa.
- Creación de clínica e invitaciones vinculadas al correo confirmado, con código de un uso, caducidad de siete días y revocación.
- Administración del equipo: correo identificable, cambio de rol, confirmación de eliminación e invitaciones pendientes/aceptadas/revocadas/vencidas.
- Protección del último administrador y bitácora de operaciones.
- Recuperación de contraseña con respuesta neutral; nueva contraseña y confirmación desde sesión de recuperación, mínimo ocho caracteres. Cancelar termina esa sesión.
- Espacio personal independiente, sin compartirlo como equipo de clínica.
- Limpieza de pantallas/resultados privados al cambiar sesión, clínica o permisos.
- Conservación de historia al retirar un miembro: sus citas, actuaciones, tareas, registros médicos y checados anteriores no desaparecen. Nuevas asignaciones exigen membresía activa.
- Habilitación profesional reservada a operaciones privilegiadas del servidor; el cliente no se concede esta condición.

**Pendiente:** configuración/pruebas reales de OAuth, correo/SMTP y enlaces de recuperación; administración operativa de verificación profesional; eliminación de cuenta, reautenticación, cambio de correo y políticas completas de retención.

### Alcance offline real

Existe caché de membresías y motor persistente de sincronización, particionado por usuario/clínica, con idempotencia, reintentos, espera progresiva y conflictos de permisos/versiones. El acceso temporal usa una sesión válida y membresías cacheadas de menos de 24 horas; un retroceso del reloj invalida la caché. Solo errores de transporte permiten usarla; errores de permisos o datos fallan de forma cerrada. Se actualiza periódicamente en primer plano y se limpia al salir.

**No están registrados los adaptadores productivos para sincronizar expedientes, inventario o finanzas.** No hay caché clínica sensible cifrada, resolución completa de conflictos ni revocación instantánea sin conexión. Los registros clínicos/financieros requieren internet. Los cálculos y referencias locales de M3/M7 sí pueden funcionar sin traer expedientes.

## 5. M3 — motor de dosis

**Implementado:**

- Importación local de JSON versionado, hasta 2 MB; validación de estructura y conservación del catálogo anterior si falla. Reemplazo con confirmación.
- Búsqueda por fármaco y nombres comerciales suministrados, especie y presentación.
- Conversión exacta `mg/kg × kg → mg → ml` usando concentración `mg/ml`, con aritmética racional basada en BigInt.
- Graduación de jeringa explícita, redondeo por incrementos, comprobación del rango resultante y alertas de dosis bajo mínimo/sobre máximo.
- Contraindicaciones registradas por especie, raza y condición; coincidencia textual sin inferir diagnósticos o sinónimos.
- Doble confirmación que se invalida al editar los datos.
- Bloqueo de confirmación cuando faltan o no están verificadas las referencias requeridas.
- Dosis personales separadas y etiquetadas; estados propio/pendiente/aprobado/rechazado para compartir. Validación estricta y control de valores extremos frente a una base conocida. Nunca sobrescriben la base general.

**Límites:** el catálogo general local se mantiene vacío hasta recibir datos revisados. Los 27 registros vistos en la tabla Supabase inicial no se importaron ni se declararon clínicamente verificados. El motor actual trabaja con mg/kg y mg/ml; no convierte implícitamente porcentajes, tabletas u otras unidades. Aprobar una dosis compartida no verifica su contenido médico. Falta conectar el resultado confirmado automáticamente con recetas/aplicaciones y publicar/versionar de forma central los JSON.

## 6. M4 — pacientes y expedientes

**Implementado:**

- Pacientes con nombre, especie, raza, sexo y fecha de nacimiento; búsqueda por nombre/especie.
- Propietario nuevo, existente o pendiente de identificar; creación atómica y pertenencia a la misma clínica.
- Restricción de contactos del propietario a roles autorizados; auxiliares no reciben acceso general a estos datos.
- Cronología anexa con autor y hora del servidor; captura SOAP manual.
- Dictado mediante `speech_to_text` a la sección SOAP elegida, con revisión del texto. No es generación clínica automática por IA.
- Peso con valores exactos y curva visual; alergias; vacunas/desparasitación con producto, lote y fechas aportados por el usuario.
- Recordatorios manuales al propietario por WhatsApp; no se inventan calendarios vacunales.
- Captura básica de consentimiento y trazos de firma, con rechazo de firma vacía y anulación de aceptación al editar. Los documentos versionados/PDF se gestionan en M-FORMATOS.
- Acceso a casos clínicos vinculados desde el paciente.

**Pendiente:** edición general de paciente/propietario con historia; recordatorios automáticos; pruebas reales de voz; caché clínica offline. No se certifica identidad del firmante a partir del trazo.

## 7. M-FORMATOS — consentimientos, hojas clínicas y documentos

### Plantillas y constructor

- Cinco bases originales de consentimiento: general, quirúrgico/anestésico, eutanasia, alta anticipada e ingreso hospitalario.
- Bases clínicas de historia, hoja quirúrgica/anestésica y valoración prequirúrgica.
- Copias por clínica: nunca modifican la base; conservan versión de origen y marca de modificación.
- Cada cambio o restauración crea versión con fecha, autor, motivo y estado; no sobrescribe la anterior.
- Constructor con texto, decimal, fecha, casilla, selección única/múltiple, tabla repetible y cláusulas propias; identificaciones y vínculos a paciente/propietario/casos se gestionan de forma estructurada.
- Definiciones protegidas de paciente, propietario, MVZ/cédula, firmante/número, firmas, privacidad y revocación. Los campos específicos de eutanasia son obligatorios.
- Membrete, logo PNG/JPG hasta 250 KB, costos, preguntas y cláusulas propias configurables. Información preoperatoria y docencia editable por la clínica para revisión médica.
- Sin cláusula “irrevocable”. Aviso de referencia y responsabilidad del contenido final por la clínica.
- Base administrada por servidor; falta consola global completa y catálogo ampliado. Las bases originales están **sin verificar**.

Los PDF adjuntos del usuario se usan como guía de estructura; no se copió decoración ni texto de terceros. No existe aún un constructor completo de cualquier documento oficial arbitrario: las columnas oficiales requieren formato/fuente verificados y protección propia.

### Aprobación, firmas y PDF exacto

Se distinguen aprobación de plantilla clínica y aceptación del tutor. Una copia pendiente de revisión se guarda, pero no se usa para crear un consentimiento final. El documento pasa por borrador, preparación, listo para revisión y firmado.

**El PDF final se genera en la Edge Function `forms-pdf`.** El servidor congela versión, contenido, campos, membrete y firmas; genera el archivo; registra sus bytes/hash SHA-256. Flutter verifica el hash y muestra ese archivo completo. El MVZ confirma que tutor y MVZ revisaron los bytes presentados. Finalizar exige la misma revisión/hash y **conserva exactamente ese PDF, sin volver a renderizarlo ni añadir sellos posteriores**. La aceptación final tiene hora del servidor separada.

Editar antes de finalizar invalida firmas/PDF/revisión. Una vez firmado, plantilla, contenido, firmas y PDF histórico no cambian al editar las plantillas. Los artefactos privados se guardan actualmente en Postgres, con máximo de 2 MB por PDF; no son enlaces públicos. No se presenta esta protección como almacenamiento WORM certificado.

Solo se guarda nombre y número de identificación del firmante, **no fotografía de INE/DNI**. La firma es un artefacto aparte. No hay biometría ni certificación de firma electrónica avanzada.

Admin configura plantillas/membrete; MVZ responsable prepara/finaliza. Auxiliar llena borradores asignados, sin finalizar ni obtener acceso general a firmas/propietarios. Los documentos clínicos tienen permisos específicos por caso; recepción/estilista no tienen acceso a consentimientos clínicos.

### Historia, cirugía y eutanasia

- Hoja con cirujano, anestesista y MVZ responsable separados; una persona puede ocupar varios puestos sin fusionarlos.
- SOAP y peso inicial del documento clínico se incorporan atómicamente a eventos del paciente al finalizar; reintentos no duplican.
- Observaciones, unidades, hora observada, quien realizó/capturó y hora del servidor quedan estructurados. Peso posterior alimenta la curva.
- ASA y EKG se registran por el profesional; no se interpretan automáticamente.
- Autorizaciones por persona/procedimiento, vencimiento y revocación; un auxiliar reporta actos propios, conservando responsables diferenciados.
- Correcciones anexas con motivo. Actuaciones posteriores no modifican el PDF firmado.
- Medicación se enlaza al registro único de M6, sin una base farmacológica paralela.
- Eutanasia recoge motivo clínico, concepto previo del MVZ, método propuesto, procedimiento/información, disposición y costo acordados. **Constatación de muerte es posterior**, con resultado, método/hallazgos, hora y responsable; admite corrección anexa. No se declara la muerte antes de consentir ni se alteran acuerdos originales.

**Pendiente:** instalación remota, revisión clínica/jurídica de contenido, pruebas reales de firma/impresión, editor universal de campos vinculados y catálogo de todos los formatos oficiales verificados.

## 8. M5 — hospitalización

- Ingreso por paciente/jaula, sin duplicar paciente activo ni ocupar dos veces una jaula activa.
- Tabla paciente × hora, fecha seleccionable, minutos exactos y varios tratamientos/revisiones.
- Programación revisada por roles autorizados; confirmación de aplicación con quien/cuando del servidor, sin anticiparse al horario.
- Control de versiones, reintentos y concurrencia para no duplicar administraciones.
- Snooze de 5/10/15/30 minutos, hasta tres veces, con motivo y horario original preservado; escalamiento visual/local.
- Alta con motivo cancela pendientes conservando historia.
- Receta emitida vinculada a horarios capturados expresamente y aplicación única de M6; no se interpreta el intervalo por conjetura.
- Notificaciones locales nativas preparadas, texto genérico sin paciente/fármaco en pantalla bloqueada; hasta 60 próximas notificaciones. Abrir exige sesión/rol antes de mostrar hospitalización.

**Límites:** Android puede requerir permiso de alarma exacta y usar alternativa aproximada; iOS depende del sistema. Falta probar app cerrada, reinicio, ahorro de batería y modos de concentración en dispositivos. En web se vigila mientras la hoja está abierta, no con navegador cerrado. No se llama automáticamente a otro integrante. Un aviso ya programado en otro dispositivo puede permanecer hasta refrescar: falta sincronización/push remota. Cambio de jaula y vista completa de altas históricas pendientes.

## 9. M6 — perfiles profesionales, recetas, medicación y controlados

### Perfiles y recetas

- Perfil versionado con nombre, cédula, datos profesionales y firma propia. Datos declarados quedan sin verificar hasta habilitación independiente del servidor.
- Permisos separados y revocables para compartir datos profesionales y firma, preparar/emitir recetas ordinarias y dispensar productos ordinarios.
- Permite compartir datos del dueño/MVZ bajo autorización y distinguir quien emite, firma propia y responsable real. Compartir firma no habilita actos restringidos.
- Receta con paciente/propietario, responsable/emisor, producto/presentación, cantidad/dosis, vía, intervalo, duración y cuidados capturados.
- Folio oficial manual, PDF congelado/revisado con hash, impresión/compartir y texto manual por WhatsApp. `wa.me` no adjunta automáticamente el PDF.

### Registro único y frascos

- Aplicación con producto, cantidad/unidad, lote, paciente, procedimiento, quien aplicó, quien reportó, hora observada y hora del servidor.
- Auxiliares reportan; una entrada controlada queda pendiente de validación. Solo MVZ responsable habilitado valida o corrige con motivo mediante anexos.
- Frasco: producto/lote, volumen inicial, fecha de apertura, estado y saldo exacto.
- Cada toma descuenta una sola vez; validar después no vuelve a descontar. Correcciones/pérdidas/devoluciones se registran como movimientos anexos.
- Cierre físico compara saldo; discrepancia requiere nota del MVZ. Aplicaciones incompatibles con frasco cerrado/saldo disponible se conservan como incidencia, no se pierden silenciosamente.
- La referencia de dosis calculada permanece “no disponible” hasta completar el enlace M3; no se inventa.
- Reportes periódicos congelados con entradas validadas; pendientes/incidencias marcan incompleto. PDF/hash y CSV; emisión oficial exige clasificación/formato regulatorios verificados.

Un auxiliar **no prepara ni emite recetas controladas, no valida controlados y no genera/firma reportes oficiales**, aunque tenga autorización permanente o firma compartida. Falta completar resolución de ciertas incidencias de frascos cerrados y revisar formatos/regulación reales. No hay catálogo regulatorio verificado precargado.

## 10. M7 — cálculos clínicos y producción

Lógica pura con entradas explícitas, precisión y pruebas conocidas:

- Fluidoterapia: mantenimiento aportado, déficit por deshidratación, pérdidas del periodo, volumen total, ml/h y gotas/min.
- CRI: mcg/kg/min, peso, potencia mg/ml, mezcla final y flujo; mg/h, mg y ml de producto, diluyente, concentración, duración y goteo.
- Producción por cabeza y lote homogéneo con peso explícito.
- Agua: mg de activo/L y potencia mg/g; no supone equivalencias ambiguas de ppm.
- Alimento: mg/kg de alimento y toneladas métricas para cantidad de producto.
- Protocolos por etapas con referencias verificadas a especie y presentación; no inventa combinaciones/reversores.
- Constantes con rangos verificados y alertas; no diagnostica.
- Peso metabólico según exponente de referencia, sin presentarlo como ajuste universal de dosis entre especies.
- Ajustes pediátricos/geriátricos solo con factores específicos verificados, sin porcentajes universales.
- Retiro por producto/presentación/especie/vía/destino y fuente; desconocido nunca equivale a cero.

Las referencias clínicas están vacías hasta revisión. Falta editor/importador completo de referencias M7 y conexión automática de resultados verificados con recetas/registros. No hay liberación automática de carne/leche para comercialización.

## 11. M8 — inventario, ventas y caja

### Inventario

- Adaptación del inventario/lotes existentes; producto, presentación, unidad, costos/precios MXN, stock mínimo, reorden, proveedor y código de barras.
- Lotes con caducidad tipo fecha, costo y movimientos inmutables. Transacciones/idempotencia/versiones previenen doble descuento y venta concurrente de la última unidad.
- Stock disponible excluye caducados y fechas farmacológicas no verificadas; alertas 30/60 días considerando fecha de clínica.
- Datos heredados preservados y pendientes de revisión/adopción; no se convierten fechas o existencias por suposición.
- Código de barras por cámara/manual y foto privada del producto; Storage con permisos por clínica.
- Pedidos con borrador, revisión de versión y aprobación del encargado; copia/contacto manual al proveedor.

### POS, tratamientos repetidos y cierre

- POS para roles de cobro autorizados, turnos propios, fondo inicial, ingresos/gastos/retiros con motivo y cierre congelado.
- Efectivo, transferencia y tarjeta como métodos registrados; ventas, reversos, costos, comisiones y margen sobre datos capturados.
- Servicio con precio/comisión congelados. No se denomina utilidad neta certificada a un cálculo sin todos los gastos/impuestos.
- Producto farmacológico exige receta y clasificación/presentación verificadas cuando corresponde.
- Dispensación cuantificada/restringida solo por MVZ habilitado; entrega ordinaria de auxiliar/recepción bajo permisos aplicables.
- **Una receta puede respaldar varias aplicaciones de un tratamiento:** cada aplicación tiene su registro/cargo propio. Cobrar no vuelve a descontar el frasco ni exige emitir una nueva receta para cada puesta.
- La entrega física descuenta inventario una vez; aplicación descuenta volumen del frasco. El cobro se vincula al acto/entrega, sin confundir ml administrados con venta de todo el envase.
- Auxiliar/recepción pueden cobrar un acto controlado ya autorizado/registrado; esto no los convierte en dispensadores o validadores de controlados.
- Reverso de ticket completo y exportación CSV con neutralización de fórmulas.

**Pendiente:** devoluciones parciales y devolución física separada, ajustes contables por correcciones clínicas/costos tardíos, pagos divididos/anticipos/cuentas por cobrar completas, adopción de inventario heredado sin clínica, XLSX, OCR de etiquetas, redacción IA de pedidos y análisis automático del mercado. Escanear una foto no extrae automáticamente una concentración.

## 12. Cobros de clientes y referencias bancarias

Existe registro manual de transacciones externas con banco/plataforma libre, referencia, fecha, monto, dirección ingreso/egreso y, opcionalmente, últimos cuatro dígitos. No se guardan PAN completo, CVV ni claves bancarias.

Se registran pendientes de revisión; admin concilia con motivo, comisión/neto y hora del servidor. Se controlan referencias duplicadas y vínculo con venta de la misma clínica, método/importe/cajero compatibles. Conciliar no duplica ingreso ni movimiento de stock y **no verifica automáticamente con el banco**. Los egresos externos aún no se enlazan por completo al libro de caja.

Esto permite registrar operaciones de cualquier banco, PayPal, Stripe o terminal por nombre/referencia. **No significa conexión API universal ni cobro integrado con esas plataformas.** No hay aún un adaptador activo de pagos de clientes por banco/Stripe/PayPal.

Los pagos de la suscripción a VetDosis son otro sistema, explicado en M13; no deben mezclarse con el dinero de los clientes de una clínica.

## 13. M9 — operación de clínica

- Agenda de consulta/estética con profesional, hora UTC y visualización local, estados y protección de solapamientos.
- Paciente existente por búsqueda de nombre en la misma clínica (hasta 50 resultados); servidor toma nombre/especie del expediente. Selección no expone contactos o notas; estilista no busca expedientes.
- Opción cita manual sin crear paciente. Desde cita vinculada se abre paciente respetando permisos.
- Reprogramación/cancelación con motivo, versión y bitácora; conserva fechas/autor originales.
- Nombre visible propio por clínica, para asignaciones, agenda, mensajes, comisiones y checado; UUID como respaldo. Es alias declarado, no identidad profesional verificada. No se extendió aún a todas las vistas clínicas.
- Catálogo de servicios editable por admin, porcentaje o bono fijo, registro por profesional, desempeño y CSV.
- Tablón de tareas asignadas/“todos”, prioridad, estado y filtros.
- Mensajería interna por categoría con autor/hora; no hay push/Realtime completo.
- Distribuidores con contacto manual por llamada, SMS o WhatsApp.
- Ficha médica del personal, con consentimiento y acceso propio/admin; retiro de consentimiento. No se comparte con el resto del equipo.

## 14. M10 — checado

- QR del admin firmado HMAC, cambia cada 45 segundos, secreto solo del servidor.
- Validación de clínica/membresía/admin activo/vigencia y hora del servidor.
- Ubicación solicitada solo al escanear; radio/precisión comprobados. Guarda distancia/precisión, no historial de coordenadas del empleado.
- Entrada/salida alternadas, reintentos idempotentes y prevención de duplicados del mismo intervalo.
- Consentimiento/aviso versionados; cambios relevantes invalidan consentimiento anterior; opción de retirarlo.
- Corrección admin con motivo y registro anexo; CSV/PDF con nombres e identificadores.
- QR se descarta al expirar o pasar a segundo plano.

**Pendiente:** pruebas reales de cámara/GPS, revisión de privacidad, incidencias de eventos omitidos y flujo de domicilio/configuración. No es un módulo completo de nómina ni prueba infalible frente a ubicación falsificada.

## 15. M11 — estadísticas, exportación y respaldo protegido

- Panel admin: ventas mensuales de 12 meses con reversos, citas por especie y bajo stock disponible; gráficas legibles. Venta no equivale a ganancia.
- Exportación operativa coherente JSON/CSV con registros clínicos/operativos, documentos históricos congelados, fotos/artefactos y verificaciones de hash.
- Incluye chats propios permitidos, no chats privados de compañeros; excluye contraseñas, claves API/servicio, secretos QR, tokens de invitación, firmas privadas reutilizables y fichas médicas ajenas.
- Es respaldo operativo autorizado, **no volcado completo del servidor**.
- Respaldo cifrado predeterminado `.vetbackup`, contraseña de mínimo 12 caracteres y confirmación. No se almacena ni se envía esa contraseña.
- AES-256-GCM; salt/nonce aleatorios; PBKDF2-HMAC-SHA256 de 600.000 iteraciones. Detecta contraseña incorrecta o manipulación.
- JSON sin cifrar es opción explícita; CSV no está cifrado.
- Límites actuales: archivo completo sin cifrar hasta 50 MiB y contenedor cifrado hasta 72 MiB. Falta fragmentación para conjuntos mayores.
- Revisión de archivo JSON/cifrado: descifra, comprueba clínica, estructura, hashes, PDF/rutas, duplicados y mezcla de clínicas. Muestra fecha/tablas y permite exportar resumen sin datos clínicos.

**La revisión NO restaura ni importa datos.** No existe aún restauración completa con dependencias, correspondencia de usuarios, conflictos y rollback. Tampoco respaldo automático en Drive. Una copia operativa no reemplaza respaldo de infraestructura. Hash/cifrado no certifican autoría del documento.

## 16. M12 — IA configurable y chats

- Proveedores preparados: OpenAI, Gemini, Anthropic y Z.AI/GLM.
- Conexión por API key personal o de clínica, cifrada en servidor y no devuelta a Flutter.
- Selector de modelos: listado limitado; Z.AI usa catálogo documentado, sin asegurar disponibilidad por cuenta.
- Historial por usuario. Privado por defecto; admin no puede leer chats privados ajenos.
- Controles independientes de visibilidad (privada/clínica con audiencia por roles) y uso en contexto (ninguno/personal/clínica).
- Continuidad del chat actual y contexto reciente acotado según permiso. No se incluye automáticamente todo el historial ni expedientes.
- Consentimiento explícito de proveedor/modelo. Si se revoca acceso al contexto durante una petición, se descarta la respuesta; no se puede retirar contenido ya enviado al proveedor.
- Gateway autenticado con destinos fijos, límites, solicitudes idempotentes y cuotas; fallos también consumen intento y borrar chats no reinicia cuota.
- Respuestas etiquetadas como IA sin verificar, sin ejecutar recetas o acciones clínicas.

**Pendiente:** activación con claves/cuentas reales, rotación de secretos, pruebas reales de modelos, streaming/contexto ampliado. OCR, SOAP generativo, pedidos IA y análisis de mercado no están conectados.

### IA inicial incluida

Está preparado un soporte limitado con Gemini 2.5 Flash por defecto o GLM 4.5 Flash alternativo, con lista controlada de modelos. **Permanece desactivado hasta configurar clave del operador y revisar condiciones/costos.** No se promete API gratuita ilimitada.

Solo permite seis temas públicos prefijados de ayuda de la app: inicio, permisos, pagos, notificaciones, reportar problemas y privacidad. No recibe consultas clínicas libres, expedientes, chats personales o adjuntos. Tiene consentimiento, máximo inicial de cinco solicitudes diarias por usuario y 100 globales, separados de BYOK. Sin herramientas externas, búsqueda ni cambio automático a proveedor de pago. Esta restricción evita enviar información sensible a un servicio gratuito cuyos términos lo prohíban.

## 17. M13 — planes, costos y suscripción

**Propuesta implementada en catálogo/interfaz; precios no publicados ni cobros activados.** Moneda MXN.

| Plan | Mensual | Anual | Alcance propuesto |
|---|---:|---:|---|
| Gratis | $0 | $0 | Espacio personal limitado |
| Individual | $199 | $1.990 | Uso propio sin exigir que pague toda la clínica |
| Clínica | $799 | $7.990 | Todos los integrantes de una clínica |
| Beta/regalo | $0 temporal | Según concesión | Operador autorizado, con vencimiento |

El anual equivale a diez mensualidades. Son decisiones comerciales pendientes de aprobación final, impuestos/términos y revisión de costos.

| Límite propuesto | Gratis | Individual | Clínica |
|---|---:|---:|---:|
| Pacientes | 50 | 5.000 | 50.000 |
| Almacenamiento presupuestado | 250 MiB | 2 GiB | 10 GiB |
| Intentos IA BYOK diarios | 5 personales | 200 personales | 1.000 compartidos por equipo |

El almacenamiento usa presupuesto conservador de registros/PDF/fotos, no medición idéntica a la factura Supabase. BYOK requiere la clave del usuario/clínica y puede tener costo del proveedor; no son miles de consultas financiadas por VetDosis. La IA pública inicial tiene otra cuota.

El individual permite expediente propio, cálculo, recetas según habilitación, agenda, inventario y registro manual de cobros/caja por efectivo/transferencia/tarjeta. No obtiene datos financieros de otra clínica ni funciones de equipo/checado por pagar individualmente; no incluye integración con terminal bancaria. Un plan nunca concede autoridad clínica.

Existe pantalla de planes, ciclo mensual/anual, beneficios/límites, historial y registro de interés. Al vencer, conserva datos y vuelve al plan gratuito; bloquea nuevo crecimiento cuando excede cuota. Hay transición heredada propuesta de 90 días al adaptar clínicas existentes, no un pago confirmado.

Stripe: checkout y webhook firmado preparados; activa solo por evento válido pagado e idempotente del servidor. Volver desde el navegador no activa el plan. **No están activos ni probados con cobros reales.**

Pendiente: portal/cancelación, reembolsos, prorrateo, fallos de pago, CFDI/términos, pruebas sandbox y configuración final. PayPal no tiene adaptador de suscripción. Consola completa de regalos pendiente.

Lealtad: propuesta desactivada de 1.000 puntos por 30 días; no acumula premios automáticamente ni existe programa comercial lanzado. Descuentos sobre suscripción pagada requieren integración con proveedor. El presupuesto operativo preliminar no sustituye cotizaciones reales ni cálculo de rentabilidad.

## 18. M14 — producto, inicio guiado y soporte

- Página interna de producto/herramientas/planes, accesible antes del login; no hay landing externa publicada.
- Guía de siete pasos, reabrible/postergable, progreso local por usuario/espacio. Completarla no acredita configuración ni crea pacientes.
- Historial de suscripción separado de pagos de clientes.
- Reportes privados por usuario: error, pregunta, pago y sugerencia; estados y conversación con autor/hora.
- Consentimiento para revisión humana; hasta 20 tickets/día, 200 mensajes, cinco adjuntos por reporte de hasta 5 MiB cada uno: JPEG, PNG, PDF o TXT.
- Adjuntos privados con enlaces temporales, sin sobrescribir archivos. No recopila diagnósticos del dispositivo automáticamente.
- IA opcional prepara título/descripción editable mediante BYOK con consentimiento; no manda el reporte, no añade archivos ni datos clínicos automáticamente. Reportar no depende de tener IA.
- Consola de operadores humanos preparada, con asignación global privilegiada y bitácora; admin de clínica no es operador de soporte.
- Contacto por correo/WhatsApp configurable, apertura manual de aplicación del usuario.

**Pendiente:** asignar operadores/contactos reales, horarios y atención; limpieza de cargas fallidas, cuotas globales de adjuntos, retención/análisis de seguridad y push. No se ofrece una disponibilidad humana o SLA real aún.

## 19. Resumen de permisos: evitar confundir clínica y caja

| Operación | Regla actual |
|---|---|
| Asignar roles/invitar integrantes | Admin de esa clínica, con controles del servidor |
| Editar plantillas | Admin o MVZ responsable según plantilla |
| Llenar borrador asignado | Auxiliar autorizado; no finaliza firmas |
| Preparar/emitir receta ordinaria | MVZ habilitado o delegación ordinaria explícita vigente, según caso |
| Preparar/emitir receta controlada | Solo MVZ habilitado responsable; no auxiliares |
| Reportar una aplicación propia | Persona autorizada, conservando quien aplicó y quien reportó |
| Validar/corregir controlados y emitir reporte oficial | Solo MVZ responsable habilitado |
| Dispensación física restringida/cuantificada | MVZ habilitado |
| Entrega ordinaria | Rol con permiso vigente, receta/clasificación/caso aplicables |
| Cobrar aplicación/servicio/venta autorizada | Roles POS, incluyendo recepción/auxiliar; cobro no concede autorización clínica |
| Leer chats privados | Su propietario; admin de clínica no tiene acceso automático |
| Leer ficha médica del personal | Propio usuario y admin, con consentimiento y restricciones |
| Acceder a otra clínica | Nunca por tener un plan o rol en la primera |

No basta ocultar botones: RLS, RPC y funciones comprueban identidad, clínica, rol, habilitación y versiones.

## 20. Archivos y componentes que existen

Módulos Flutter en `lib/modules/`: `core`, `auth`, `offline`, `doses`, `patients`, `forms`, `hospital`, `prescribing`, `calculations`, `inventory`, `operations`, `attendance`, `backup`, `ai`, `subscriptions`, `support`, `welcome`.

Funciones Supabase en `supabase/functions/`: `forms-pdf`, `ai-gateway`, `starter-ai`, `subscriptions-gateway`, `subscriptions-webhook`, más bibliotecas compartidas.

Adaptaciones en `supabase/adaptations/` para clínicas M2, dosis M3, pacientes M4, hospital M5, formatos fases 1/2, recetas M6, inventario/fotos/flujo M8, operación M9, asistencia M10, estadísticas M11, referencias de pagos, suscripciones M13, IA M12, cuotas/archivos/exportación, soporte M14, revisión IA inicial, gestión de equipo, extensión de citas y conservación de historia de membresías.

**No aplicar estas adaptaciones indiscriminadamente.** Tienen dependencias y su instalación debe cotejar el esquema remoto y respaldarlo. En particular, cuotas M13 preceden ciertas funciones M12; fotos dependen de Storage; las ampliaciones recientes de citas/historia dependen de tablas previas. No recrear las tablas iniciales para “empezar limpio”.

Documentación detallada en `docs/`: módulos, `avance-pendientes.md`, `pendientes-revision-final.md`, `revision-plataforma-2026-10-08.md`, `ia-incluida.md`, `respaldo-protegido-recuperacion.md` y referencias PDF en `docs/formatos-referencia/`. Algunas notas de fases anteriores dicen que M6 u otras conexiones eran futuras: este reporte y los avances posteriores actualizan esas notas históricas.

## 21. Verificación disponible y sus límites

- **150 casos Flutter distintos comprobados localmente** entre ejecución general y pruebas específicas. No se afirma una única ejecución final de 150: hubo 148 casos generales sin el caso criptográfico lento, verificación separada de ese caso y una prueba nueva específica de interfaz/permisos.
- Último análisis Flutter sin incidencias y compilación web de producción correcta.
- Suites SQL en PostgreSQL 17 aislado, datos sintéticos: roles, separación de clínicas, invariantes, idempotencia y concurrencia en módulos cubiertos. La última suite de IA/planes incluye extensiones de agenda/historia/equipo/soporte.
- Pruebas previas de servidor: 11 de IA/facturación y siete del renderizador PDF, además de chequeo de tipos Deno en funciones. No se presentan como ejecutadas de nuevo hoy.
- Revisión visual previa: 24 combinaciones de vistas/tamaños/temas y 44 capturas incluyendo desplazamientos/menús; revisión de contraste de cinco paletas en ambos modos y pruebas de ancho reducido/texto aumentado.
- Las capturas no cubren todos los flujos ni los últimos cambios con datos reales.

No se hicieron llamadas reales a proveedores IA, operaciones bancarias o cobros, ni pruebas con pacientes reales. Falta prueba integrada de Auth/DB/Edge Functions, permisos con múltiples cuentas, teléfonos, notificaciones cerradas, cámara, voz, GPS, PDF/compartir e integraciones contratadas. Pasar pruebas sintéticas no acredita validez normativa ni seguridad clínica de un catálogo.

## 22. Desarrollo que todavía falta

1. Caché clínica sensible cifrada, adaptadores offline reales, conflictos/revocación/retención y borradores recuperables.
2. Restauración completa de respaldo con dependencias/usuarios/conflictos/rollback, exportación fragmentada y Drive automático.
3. Devoluciones parciales/físicas, ajustes financieros por correcciones clínicas y costos tardíos; anticipos/pagos divididos/cuentas por cobrar completas.
4. Resolución completa de incidencias de frascos cerrados; adopción del inventario heredado sin clínica.
5. Conexiones de cobro a proveedores seleccionados; ciclo completo de suscripciones y consola de regalos/lealtad.
6. Verificación profesional operativa, eliminación/reautenticación de cuenta, edición de pacientes/propietarios con historia y nombres legibles en vistas clínicas restantes.
7. Enlace explícito de cálculos verificados a receta/aplicación; editor de referencias M7 y catálogo/formularios regulatorios verificados.
8. OCR de etiquetas, SOAP generativo revisado, pedidos IA y análisis de mercado, si se mantiene ese alcance.
9. URLs/navegación web completa, paginación general y protección de cambios en todos los editores.
10. Limpieza/cuotas/retención de adjuntos, push de soporte/mensajería y sincronización remota de avisos hospitalarios.
11. Incidencias de checado omitido, cambio de jaula, historial de altas y exportación XLSX.
12. Recordatorios automáticos y WhatsApp Business/SMS solo con contratación/configuración de sus APIs; actualmente son contactos manuales.

No todos estos pendientes deben bloquear un primer lanzamiento limitado; deben quedar visibles y acordarse su prioridad, sin presentarlos como ya terminados.

## 23. Datos, decisiones y activación final

El usuario dejó para el final sus datos/configuraciones. Esto requiere su información y también trabajo técnico posterior; no significa que tenga que realizar el despliegue solo.

- JSON y fuentes clínicas reales, revisión por MVZ; clasificación regulatoria de productos, formatos oficiales y tiempos de retiro comerciales.
- Membrete/logo, textos de privacidad/consentimiento, retención y revisión de documentos. La estructura original no acredita cumplimiento legal.
- Aprobar precios, cuotas, costos operativos, impuestos/CFDI, términos y alcance comercial.
- Cuentas/configuración de Google OAuth/correo; claves IA del operador o BYOK; Stripe sandbox/producción y PayPal si se elige; Drive/WhatsApp Business/SMS cuando aplique.
- Personas/contactos/horarios de soporte y proceso de verificación profesional.
- Revisar y respaldar Supabase existente; aplicar adaptaciones en orden; desplegar funciones, secretos privados y buckets; verificar permisos con cuentas reales.
- Hosting/dominio, repositorio GitHub u otro, branding, cuentas de tiendas, firma de aplicaciones y publicación.
- Pruebas reales de Android/iPhone/web y clínicas/usuarios autorizados, sin usar datos sensibles innecesarios en pruebas.

No incluir claves privadas en el chat ni en Flutter. Este reporte omite credenciales intencionalmente.

## 24. Instrucciones para continuar sin perder lo acordado

Inspeccionar primero código/esquema y documentación reciente. Conservar tablas, historia y permisos existentes. Distinguir versión base, aprobación clínica, habilitación profesional y aceptación de documento. Nunca regenerar el PDF aceptado como si fuera el mismo. Mantener idempotencia/concurrencia y probar restricciones del servidor, no solo botones. No inventar información clínica ni folios oficiales. No convertir permisos de cobro en autoridad para controlados. No abrir chats privados por rol admin. No afirmar offline completo, IA gratis ilimitada, bancos conectados, facturación activa o app nativa verificada hasta demostrarlo.

**Resultado actual:** base amplia implementada y verificada localmente, con pendientes funcionales explícitos y una etapa de configuración/despliegue/pruebas reales todavía por realizar.
