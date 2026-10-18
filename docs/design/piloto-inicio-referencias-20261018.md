# Piloto de Inicio y recursos del icono

La usuaria autorizó probar el diseño de las imágenes en una sección. Se amplía el
PR #2 en Inicio; Agenda conserva la adaptación anterior de la rama. No se modifica
Supabase, RPC, permisos, datos clínicos, firma ni identificador del paquete.

## Presentación

- Tema turquesa legible y relieve suave limitados a Inicio mediante Theme;
  las preferencias y paletas de las demás pantallas permanecen intactas.
- Tres tarjetas de práctica y acceso separado a Gestión clínica; usan el mismo
  CoreViewModel.selectBranch y no modifican el espacio ni los permisos.
- Buscador e identidad real de la clínica conservados. No se añade un nombre,
  título profesional, saludo personalizado ni contador de notificaciones ficticio.
- Indicadores de pacientes consultados, citas por venir, hospital y tareas visibles.
  Se calculan a partir del modelo existente. Sin lectura disponible: «—»;
  sin permiso de resumen: se omite. Tareas del equipo no se muestran en personal.
- Gráfico de siete días de calendario en zona de la clínica/teléfono: cuenta las
  citas no canceladas presentes en la respuesta, con números y semántica accesible.
  La etiqueta advierte «Citas consultadas»; no se presenta como consultas hechas.
- Módulos principales en cuadrícula con adaptación a 320 px y texto 200%; otros
  accesos quedan como botones secundarios. Estadísticas detalladas se expanden
  sin anteponerse al resumen. El filtro de navegación anterior sigue aplicándose.
- En celular los indicadores se distribuyen en dos columnas para evitar palabras
  partidas. En pantallas más anchas caben cuatro; texto grande se apila.

## Iconos aportados

Ambos originales son RGBA 1024×1024 con transparencia real. Se conserva el primero
como alternativa y se utiliza el segundo, continuación de la marca anterior.
No se redibuja ni se modifica el PNG. Android escala el recurso drawable-nodpi:

- API 24–25: bitmap de launcher con filtrado y límites dados por el sistema.
- API 26+: adaptive-icon con fondo perla e inset del 18% para conservar el arte
  dentro del área segura; roundIcon usa el mismo recurso y la máscara del sistema.
- El icono de notificaciones no se sustituye por la imagen de launcher.

Se verificaron los recursos con AAPT2 9.4.1-15978811 y android.jar API 36:
`aapt2 compile --dir android/app/src/main/res`, seguido de `aapt2 link` con manifiesto
mínimo de prueba minSdk 24 / targetSdk 36. Compilación y enlazado aprobados;
`dump resources` confirma variantes anydpi y anydpi-v26. Esto es una comprobación
de recursos, no una compilación completa del APK firmado.

## Evidencia

- Análisis sin incidencias.
- 32 pruebas de piloto/dashboard/navegación/apariencia aprobadas inicialmente.
- Batería completa: 378 pruebas aprobadas.
- Regresiones del piloto y cuatro renders repetidos tras ajustar textos y anchos.
- Vistas y límites del fixture en `review/home-pilot-20261018/README.md`.

El PR sigue como borrador para revisar el piloto. Falta empaquetarlo y comprobarlo
con Android real. El APK 39124259241 carece de estos cambios; no se desplegó backend.
