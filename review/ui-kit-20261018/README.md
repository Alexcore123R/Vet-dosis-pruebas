# Vistas del piloto visual

Renderizadas por pruebas Flutter a 390×844, sin Supabase ni datos reales.
Inicio usa la pantalla real sin sesión clínica; Agenda usa OperationsScreen en
un Scaffold de previsualización con permiso de lectura, sin edición ni citas.
La barra de Agenda de estas imágenes es del contenedor de previsualización.
No son capturas de un dispositivo Android ni acreditan funciones remotas.

- `inicio-light.png` y `inicio-dark.png`: buscador, selector actual y accesos.
- `agenda-light.png` y `agenda-dark.png`: calendario y estado sin registros.

Las pruebas cargan DejaVu Sans local bajo el nombre de fuente de prueba Roboto
para generar vistas legibles, y los Material Icons del bundle. La aplicación
conserva su fuente de sistema; no se ha añadido Plus Jakarta Sans.

Reproducir:

```
flutter test test/previews/capture_ui_kit.dart
```

Los estados con actividad real, múltiples clínicas y las interacciones de Android
siguen pendientes de revisión en teléfono. El launcher conserva su icono anterior:
el JPG aportado se guarda como original de referencia para preparar sus variantes.
