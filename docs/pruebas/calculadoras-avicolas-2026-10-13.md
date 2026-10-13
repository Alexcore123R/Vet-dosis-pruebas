# Prueba de calculadoras con datos cargados — 13 de octubre de 2026

Resultado: 58 pruebas aprobadas. Se agregaron 45 pruebas que leen directamente los CSV y JSON versionados; se ejecutaron además las 13 pruebas existentes de avicultura e incubación, incluidas comprobaciones de interfaz y modelo de presentación.

## Capacidad

Superficie de piso de 10 × 10 m; ambos extremos del rango de cada etapa:

| Etapa | Diseño (aves/m²) | Capacidad (aves) |
|---|---|---|
| Crianza | 12 / 15 | 1200 / 1500 |
| Desarrollo | 8 / 10 | 800 / 1000 |
| Postura | 6 / 8 | 600 / 800 |

Superficie independiente de jaula de 1000 cm²:

| Etapa | Diseño (cm²/ave) | Capacidad (aves) |
|---|---|---|
| Crianza | 250 / 350 | 4 / 2 |
| Desarrollo | 350 / 450 | 2 / 2 |
| Postura | 450 / 550 | 2 / 1 |

Se verifica el redondeo por superficie independiente: 1000 cm² a 300 cm²/ave da 3 aves por piso; dos pisos dan 6. No se suman sobrantes entre jaulas.

## Área y metros para 1000 aves

Con paso de redondeo elegido de 0,01 m² y 0,01 m:

| Etapa | Área de piso según ambos extremos (m²) | Bebedero (m) | Comedero (m) |
|---|---|---|---|
| Crianza | 83,34 / 66,67 | 15 | 30 |
| Desarrollo | 125 / 100 | 25 | 50 |
| Postura | 166,67 / 125 | 50 | 70 |

Las áreas de jaula para 1000 aves son respectivamente 25/35, 35/45 y 45/55 m². Son áreas útiles geométricas, sin incorporar pasillos ni otras superficies no especificadas.

## Equipo para 1000 aves

| Equipo | Aves/unidad: mínimo / máximo | Unidades resultantes |
|---|---|---|
| Minitolva | 100 / 100 | 10 / 10 |
| Vitrolero | 100 / 100 | 10 / 10 |
| Campana | 80 / 100 | 13 / 10 |
| Plato | 45 / 55 | 23 / 19 |
| Niple | 8 / 12 | 125 / 84 |
| Copita | 6 / 8 | 167 / 125 |
| Criadora | 1500 / 2500 | 1 / 1 |

Los casos prueban cada razón por separado; no afirman que todos esos equipos correspondan a una misma etapa. Se conserva la etapa original del archivo. El caso adicional de 1000 aves a 10 aves/niple da 100 niples; 1001 aves da 101.

## Incubación

Huevo inicial de 65 g y puntos exactos de la curva subida:

| Día | Pérdida de referencia (%) | Peso calculado (g) |
|---|---|---|
| 3 | 2,4 | 63,44 |
| 6 | 4,2 | 62,27 |
| 9 | 5,7 | 61,295 |
| 12 | 8,6 | 59,41 |
| 15 | 10,7 | 58,045 |
| 18 | 12,8 | 56,68 |

Peso observado de 58,5 g: pérdida de 10%, diferencia de −2,8 puntos porcentuales respecto al día 18. Para el día 4 no se inventa un punto ni se interpola. La comparación requiere confirmar que la muestra y el pesaje sean comparables.

Rendimiento manual de 70%: 65 × 0,70 = 45,5 g de pollito. El porcentaje es una elección explícita del usuario, sin valor universal predeterminado.

La dilución se comprobó con un producto ficticio: 10 mg/ml a 1 mg/ml, volumen final 1000 ml, requiere matemáticamente 100 ml de concentrado. Se valida volumen final, unidades y rechazo de concentración objetivo superior a la inicial. No es una receta de desinfección de huevos ni una validación de un producto comercial.

## Integridad y alcance

- Se conservan 12 parámetros de capacidad y 7 razones de equipo con fuente y estado sin_verificar.
- Los valores fuera de rango muestran una advertencia adicional.
- Tolva, temperatura por edad y presión de agua permanecen vacíos.
- Entradas inválidas borran resultados anteriores; no se presentan cifras antiguas como nuevas.
- Las pruebas locales comprueban aritmética, lectura de archivos, modelo de presentación e interfaz. No prueban este flujo en el teléfono ni su persistencia en Supabase.
- No se encontraron fallos en los casos ejecutados. Esto no valida las referencias para uso profesional ni cubre la fase 2 de lotes, medicación o retiro del huevo.

Comando ejecutado:

```sh
flutter test test/uploaded_poultry_data_test.dart test/aviculture_test.dart test/incubation_test.dart
```
