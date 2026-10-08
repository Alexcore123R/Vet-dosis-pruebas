# M3: motor y catálogo de dosis

Implementación Flutter para Android, iOS y web. El motor es Dart puro; la pantalla usa un ViewModel y repositorios inyectados. El catálogo incluido está vacío. No se han descargado ni verificado las 27 filas de fármacos de Supabase.

## Cálculo y confirmación

- Peso kg × dosis mg/kg = masa mg; masa / concentración mg/ml = volumen ml.
- Aritmética racional con BigInt: no se comparan límites con punto flotante.
- La graduación de jeringa es obligatoria, sin valor clínico predeterminado. Redondeo al incremento más próximo; los empates suben. Si el volumen resultante sale del rango publicado o queda en cero, se bloquea la confirmación.
- Rango mínimo/máximo, vía, intervalo, fuente y concentración verificados son necesarios para confirmar. Datos incompletos permiten revisar el cálculo cuando la concentración existe, pero no confirmarlo.
- Alertas rojas para rango y contraindicaciones por especie, raza o condición. Las coincidencias son textuales, sin distinguir mayúsculas; no interpretan sinónimos ni diagnostican condiciones no ingresadas. Todas las reglas publicadas se muestran para revisión.
- Primera revisión mediante casilla y segunda confirmación en diálogo. Cambiar entradas, fármaco, especie o presentación invalida el resultado. Confirmar no registra una administración ni produce una receta.
- Acceso al cálculo de producción: roles admin/MVZ provenientes de Supabase. El administrador puede importar el catálogo local; no modifica automáticamente el catálogo remoto.

## Formato de catálogo

JSON `schema_version: 1`, `catalog_version` no vacío y `farmacos` como lista. Cada dosis tiene identificador independiente para admitir diferentes vías/indicaciones de un mismo fármaco y especie.

```json
{
  "schema_version": 1,
  "catalog_version": "0.1.0",
  "farmacos": [{
    "id": "identificador-por-definir",
    "farmaco": "Nombre pendiente",
    "especie": "Especie pendiente",
    "unidad_dosis": "mg/kg",
    "min": null,
    "max": null,
    "via": null,
    "intervalo": null,
    "estado": "sin verificar",
    "fuente": null,
    "presentaciones": [],
    "contraindicaciones": []
  }]
}
```

`presentaciones`: cada objeto exige `id`, `nombre_comercial`, `unidad_concentracion: "mg/ml"`, `concentracion` decimal o null, `estado` y `fuente`. `contraindicaciones`: `tipo` especie/raza/condicion, `valor`, `nota`, `estado` y `fuente`.

Valores numéricos: cadenas decimales para conservar exactitud (hasta 12 dígitos enteros y 9 decimales); no notación científica. Unidades distintas se rechazan en esta versión, requieren conversión explícita revisada. No se asume que un porcentaje, mg/comprimido o mcg/ml equivale a mg/ml.

Una entrada marcada `verificada` exige una referencia no vacía. Esa etiqueta es una declaración del responsable del archivo: la app valida estructura, no comprueba la exactitud médica de la fuente. Lista vacía de contraindicaciones no demuestra ausencia de riesgo.

Importación con selector de archivo JSON, hasta 2 MB, validación y confirmación de reemplazo antes de guardar. Catálogo en almacenamiento local persistente; importar un archivo inválido conserva el anterior. El archivo original debe conservarse en control de versiones para mantener su historial.

## Dosis personales

Nueva tabla separada `dose_personal_entries`: sin sobrescribir `Fármacos`. Captura de especie, rango, vía, intervalo, presentación y concentración; validación estricta. La comparación con una entrada general del mismo nombre/especie advierte y rechaza en el formulario valores de al menos 100 veces su máximo. Si falta una referencia general, no se inventa un tope. Nunca se considera esa comparación prueba clínica de seguridad.

Estados: personal (autor), pending (autor y admin), approved (miembros admin/MVZ de la clínica), rejected (autor y admin). Solo admin revisa; el RPC lo verifica en servidor. Revisiones se registran en bitácora. Aprobación para compartir y verificación de referencias son decisiones distintas. No hay actualizaciones directas: una corrección se captura como nueva entrada y necesita nueva aprobación.

`supabase/adaptations/existing_doses_m3.sql` está preparado para aplicar **una vez**, después de M2. No está aplicado en el proyecto remoto. Añade tabla, funciones y RLS, conserva el catálogo general y datos anteriores. Las dosis compartidas antiguas carecen de aprobación: limita su lectura al autor/admin y revoca su edición directa hasta migrarlas con revisión; conserva las filas. El formulario necesita conexión y esta migración. No hay sincronización offline de dosis personales ni reintento automático de su creación: una respuesta perdida debe revisarse actualizando la lista antes de volver a guardar.

## Verificación

Pruebas matemáticas con fármacos y especies ficticios, nunca distribuidos en producción: masa/volumen, decimales, extremos inclusivos, redondeo fuera de límites, cero/entradas inválidas, concentraciones ausentes, fuentes, reglas de contraindicación, búsqueda por marca y validación personal. Pruebas de estado de doble confirmación, persistencia/importación inválida e interfaz móvil.

PostgreSQL 17 aislado: `bash supabase/tests/run.sh doses` comprueba aislamiento de clínica, ocultación de pendientes, aprobación solo admin, imposibilidad de editar estado directamente, auditoría, bloqueo de recepción y preservación del catálogo.

Pendiente externo: importar y revisar datos clínicos reales con concentraciones y fuentes; aplicar la migración M3 y probar autenticación/creación/aprobación en el proyecto real al final. Android/iOS necesitan compilación y pruebas en dispositivos; una compilación web no las sustituye.
