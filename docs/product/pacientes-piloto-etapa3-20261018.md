# Pacientes y expedientes: piloto por módulo

Continuación de `agenda-y-planeacion-etapa2-20261018.md`. Se revisaron las ramas
remotas antes de comenzar: `design/app-wide` sigue en `c451b30`, sin cambios de
Pacientes. Este bloque se entrega en `design/patients-pilot`, basado en
`design/ui-kit-home-agenda` (`91005f7`), para revisar solo este módulo.

## Comportamiento

- Pacientes comparte el tema de Inicio y Agenda, conservando modo claro/oscuro y
  las preferencias de apariencia fuera de los módulos migrados.
- Lista con tarjetas, selección identificable y ficha separada visualmente:
  identidad, tutor cuando está autorizado, acciones clínicas e historial.
- Búsqueda local por nombre/especie sin distinguir mayúsculas ni acentos vocálicos.
  Se conserva la distinción entre n y ñ. No busca contactos privados de tutores.
- Filtros horizontales obtenidos de las especies de los registros cargados;
  no añade un catálogo de especies ficticias ni consulta otro espacio.
- Búsqueda y especie se combinan, con número de coincidencias sobre registros
  cargados, estado vacío y acción para limpiar ambos filtros. No se presenta este
  número como el total global del servidor.
- Nuevo paciente organiza los campos en Datos del paciente y Tutor y contacto,
  usa teclados de teléfono/correo y admite selectores en ancho reducido.
- Nuevo paciente y Agregar entrada conservan el tema al abrir una ruta. La ficha
  abierta desde Agenda recibe el mismo tema de Pacientes.

## Lógica conservada

No se cambian repositorios, RPC, modelos clínicos, firmas, validación de campos,
políticas de acceso, propiedad de datos ni configuración de Supabase.

Los roles conservan sus restricciones: auxiliar no consulta contactos ni crea
pacientes; recepción no obtiene historial clínico; consultas SOAP y
consentimientos conservan los permisos médicos existentes. Se mantiene el acceso
a casos clínicos y la preparación manual de recordatorios ya disponible.

El guardado conserva operación idempotente, datos del formulario tras un error,
bloqueo durante la solicitud y cierre de formularios al cambiar de sesión. Los
colores y tarjetas no representan autorización nueva. Las alergias y pesos solo
se muestran si existen entradas autorizadas; no se añade un estado «estable» ni
alarmas clínicas inferidas.

## Verificación

Flutter 3.47.6: análisis sin incidencias, suite completa de **402 pruebas aprobada**
(`flutter test --timeout 5m --concurrency 2`) y cuatro renders aprobados.

- Búsqueda sin acentos, combinación de filtros y limpieza sin escrituras.
- Registro con tutor nuevo, fallo simulado, conservación de campos, reintento con
  la misma operación y recarga de la lista tras el éxito.
- Privacidad de contactos e historial y revocación/cambio de sesión existentes.
- Listado, ficha y formulario a 320 px con texto al 200%; claro y oscuro.
- Cuatro renders reproducibles en `review/patients-pilot-20261018/`.

Son pruebas locales con repositorios simulados. No equivalen a una creación real
en Supabase ni a una prueba física en Android. Pendiente generar el APK de la rama
y comprobar en el teléfono búsqueda, creación y expediente con la cuenta real.
