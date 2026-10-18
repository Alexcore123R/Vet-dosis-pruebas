# Inicio — piloto de las referencias visuales

Vistas renderizadas por Flutter a 390×1400 (lámina larga para revisar la sección,
no captura de un teléfono Android). Todas las cuentas, clínicas, pacientes y
actividades son ficticias y el encabezado las identifica como DEMO.

- `inicio-demo-light.png`, `inicio-demo-dark.png`: actividad sintética recibida
  por los repositorios de prueba; números calculados por DashboardViewModel.
- `inicio-empty-light.png`, `inicio-empty-dark.png`: mismas rutas con listas
  vacías consultadas; sus ceros representan el fixture vacío, no datos reales.

Se usan los widgets reales de Inicio, con Auth/Operations/Patients/Hospital
sustituidos por fixtures de pruebas. La tipografía de las láminas es DejaVu Sans
local cargada bajo el nombre de Roboto; Android conserva su fuente del sistema.

Reproducir: `flutter test test/previews/capture_home_pilot.dart`.

El selector de práctica, buscador y cuadrícula conservan los callbacks existentes.
Gestión clínica sigue accesible. El gráfico cuenta citas no canceladas recibidas
por la app dentro de los últimos siete días de calendario; no representa consultas
realizadas ni acredita que la respuesta contenga toda la actividad de la clínica.
Los indicadores ausentes se muestran como «—», y se ocultan los no autorizados.

Pendiente: comprobar el piloto, el icono y la navegación en un APK/dispositivo real.
No se ha combinado esta rama con main ni reemplazado el APK anterior.
