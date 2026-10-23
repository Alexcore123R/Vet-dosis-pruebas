# Identidad neu · menta y lavanda

La referencia aprobada es el collage del usuario y su acceso: superficies lisas,
luz blanca arriba a la izquierda, sombra gris difusa y campos suavemente hundidos.
Se conserva el logo original aportado, sin regenerarlo. Se usa el PNG con
transparencia `1000294086.png` de Drive (archivo
`1g0RR9DhDKK5GYLnZgMedDQgWt_FKeo2o`), preservando sus bytes originales. El nombre combina azul
noche y lavanda; el botón de acceso usa un degradado menta–lila con texto oscuro.

## Integración

- `neu_identity.dart` reúne colores, sombras, marca, botón y borde interior de
  campos. Los bordes de foco y error siguen visibles.
- El tema Neu es el predeterminado de instalaciones sin preferencias. Una
  elección previa de Clásico se conserva. Se puede seleccionar Neu en Ajustes.
- Inicio usa una cuadrícula adaptable de módulos. Los resúmenes conservan sus
  datos reales y sus estados de carga/error; no se añaden métricas ficticias.
- Pacientes, cálculo rápido y hospitalización comparten superficies neu.
  Hospitalización añade un encabezado teñido con el nombre y la jaula reales.
- El menú inferior ofrece Inicio, Cálculos cuando está autorizado, Pacientes
  cuando está autorizado y Más. Más abre el menú existente; los demás módulos
  siguen disponibles según permisos. Las pantallas de cálculos comparten selección.
- Acceso mantiene registro, Google cuando está configurado y recuperación cuando
  el repositorio la admite. La contraseña puede mostrarse u ocultarse.

No se cambian motores de cálculo, contratos de servidor, políticas de permisos ni
configuración de Supabase. Esta integración visual usa los contenidos disponibles
en la app; las maquetas no se convierten en datos clínicos.

## Revisión reproducible

```sh
flutter analyze
flutter test test/auth_test.dart test/neu_theme_test.dart \
  test/neu_access_navigation_test.dart test/platform_review_test.dart
flutter test --dart-define=CAPTURE_NEU=true test/neu_access_navigation_test.dart
flutter build web --release
```

Las capturas en `review/neu-20261023/` se generan desde los widgets Flutter con
un repositorio de autenticación de prueba, a 390 × 844. No son imágenes generadas
por IA ni una sesión real. La prueba de captura carga DejaVu para tener texto
legible en el ejecutor de pruebas. La recuperación no aparece en esas capturas
porque ese repositorio de prueba no ofrece dicha capacidad.

Las pruebas cubren validación de acceso, mostrar/ocultar contraseña, texto al
180 %, claro/oscuro, persistencia de preferencias y navegación según rol.
La revisión en un teléfono físico y con una cuenta real queda pendiente.

## Calculadoras: identidad por herramienta

Se aplica una superficie mate con tinte suave, sombras de luz/oscuridad y campos
hundidos en el estilo neu. Los botones usan esquinas de 16 px y nombres explícitos.
La identidad se mantiene al seleccionar otra herramienta:

- Dosis: menta.
- Fluidoterapia: cian.
- Infusión continua: lila.
- Cabeza/lote: índigo.
- Agua: turquesa.
- Alimento: malva.
- Ajuste pediátrico/geriátrico: morado con magenta.

El título y el icono acompañan siempre al color. El modo oscuro adapta el contraste;
el estilo estándar conserva sus campos convencionales. Se mantienen las fórmulas,
unidades, fuentes, validaciones e invalidación de resultados tras editar entradas.
Las herramientas de avicultura e incubación mantienen sus pantallas actuales.
