# Secciones implementadas — primera etapa

Solicitud de la usuaria: ir implementando las secciones acordadas mientras se
revisan los materiales. Esta etapa incorpora navegación y conecta las funciones
existentes; no crea backend ni da por terminados módulos futuros.

## Implementado

- Catálogo común en `section_catalog.dart`: Atención y expedientes; Medicamentos y
  herramientas; Administración y finanzas; Equipo y comunicación; Estadísticas y
  reportes; Asistente IA; Cuenta y ajustes.
- Menú Más con buscador sin distinción de tildes, grupos expandibles y destinos
  filtrados con el acceso vigente. El menú lateral usa el mismo catálogo.
- Barra inferior: Inicio, Agenda, Pacientes, Cálculos y Más. Los destinos
  restringidos se omiten; el índice se recalcula al recibir/revocar accesos.
- Cálculos abre un menú de las dos rutas existentes, con los mismos filtros previos.
- Servicios y Proveedores abren OperationsScreen con las secciones existentes
  `services` y `suppliers`. Se sujetan al módulo de operaciones/agenda y a sus
  verificaciones de permisos y sección en el servidor. No se concede ningún permiso.
- Mi cuenta y clínicas reutiliza la misma ruta del avatar. Respaldo, equipo,
  asistencia, planes, soporte y demás entradas reutilizan sus destinos actuales.
- Gestión clínica deja de ser una opción de especie en el menú lateral: su acceso
  abre Más con Administración y finanzas desplegada. Su enum interno permanece
  por compatibilidad con las preferencias y selectores anteriores.
- Elegir Producción y grandes especies abre el submenú de Bovinos, Ovinos/caprinos,
  Aves, Peces, Abejas, Porcinos y Equinos; seleccionar una especie muestra actividades.
- Aves → Postura abre AvicultureScreen; Aves → Reproducción e incubación abre
  IncubationScreen. Se reutilizan pantallas completas y no se duplican las fuentes.
  Al volver de la herramienta se conserva la actividad seleccionada.

## Qué sigue en preparación

- Planeación financiera aparece como información no operativa dentro de su grupo,
  sin callback ni flujo de guardado. No usa precios, costos o datos del ejemplo PDF.
- Cada especie tiene una relación explícita de apartados productivos previstos.
  No se ofrecen formularios de lotes/unidades/ciclos que aún no existen.
- Engorda avícola no usa las tablas de postura como parámetros universales.
- Los enlaces de pacientes, agenda e inventario desde producción abren los datos
  actuales del espacio. Se informa que todavía no filtran por la especie elegida.
- Equinos, bovinos y otros animales pueden seguir registrándose individualmente
  en Pacientes; el submenú no crea ni convierte automáticamente esos registros.

## Navegación y límites

Los selectores conservan espacio y permisos; esta etapa no aplica filtros de
especie a repositorios ni cambia propiedad de datos. El botón «Volver a especies»
vuelve al catálogo local; el regreso de una calculadora usa Navigator y conserva
la selección. El regreso del apartado principal a Inicio conserva el comportamiento
actual de CoreShell. Los formularios existentes conservan sus rutas y protecciones.

No se modifica Supabase, firmas, permisos profesionales, contenido farmacológico,
contratos remotos ni datos de producción. Se añaden únicamente mapas de presentación
para Servicios/Proveedores al módulo ya existente; la RPC sigue autorizando las
operaciones. No se incorpora la administración de plataforma al menú de clínica.

## Verificación

- Flutter 3.47.6: análisis sin incidencias y suite completa de 387 pruebas aprobada.
- Nueve pruebas específicas de navegación y tres capturas reproducibles aprobadas.

- Se cubren búsquedas con destinos financieros no autorizados, planeación sin acción,
  catálogo por especie, avicultura/incubación reales, vuelta a actividad, restricciones
  de calculadoras, revocación de accesos de la barra y reutilización de Servicios.
- Prueba de las pantallas nuevas a 320 px con texto 200%.
- Las pruebas del selector Home se actualizan al nombre aprobado «Producción y
  grandes especies»; no se suavizan sus comprobaciones de permisos.
- Vistas reproducibles en `review/section-navigation-20261018/`.

Estado de entrega: código en el PR #2; pendiente APK de la rama y prueba real en
Android. No está incluido en el APK 39124259241 anterior.

## Continuación

La [segunda etapa](agenda-y-planeacion-etapa2-20261018.md) activa Planeación
financiera como simulador mensual sin persistencia y amplía el piloto de Agenda.
La etiqueta «En preparación» de la primera etapa es histórica para este destino.
