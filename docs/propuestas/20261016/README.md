# Propuestas posteriores al cierre de permisos

Recibidas el 16-oct-2026. La usuaria pidió retomarlas **después de estas rondas**, sin cambiar el orden actual. No implementadas ni importadas por este archivo.

## Mejoras propuestas

- Fluidoterapia: procedimiento visible, déficit/mantenimiento/pérdidas, bomba y goteo según factor del equipo, tipo de solución y programación de avisos.
- Suplementos, bolos, sedación, reversores y emergencias: evaluar referencias, concentraciones, especie, vía y contexto antes de diseñar cálculos. No precargar las cantidades sugeridas ni inferir pautas.
- Receta: membrete, historial, PDF/impresión, texto y preparación de WhatsApp; redondeo de tabletas explícito, preservando cálculo exacto y concentración.
- Constantes: referencias por especie/edad/contexto, PA y PAM estimada, TLLC, mucosas y observaciones opcionales. No concluir «estable/normal» por cuatro campos ni completar valores no medidos. Alertas diferenciadas de diagnóstico.
- Vademécum: marcas, fuentes/estados por especie, precauciones y enlace a cálculo. Las instrucciones de duración no se copian automáticamente entre productos o casos.
- Hospitalización: temporizadores, horas elegidas, filtros/contador y alertas ligadas al paciente; conservar confirmación dentro de la app e idempotencia ya acordadas.
- IA: contexto mínimo del paciente seleccionado con acceso autorizado, sugerencias y proveedor/modelo realmente disponible; no cambiar a Claude por suposición ni enviar datos sin revisar el alcance. Aviso profesional no sustituye permisos.
- Finanzas: cotizaciones, notas de venta, pagos parciales/saldos, ingresos y desglose; no llamar utilidad neta al ingreso/margen. IVA configurable con fundamento y distinguir nota de venta de factura fiscal.
- Laboratorio/imagen: resultados y archivos asociados al paciente/consulta, con permisos y límites de almacenamiento.
- Perfil y respaldo: identidad reutilizable y recuperación comprobable; no usar JSON sin protección ni mezclar expedientes de clínica con respaldo personal. Drive sigue sujeto al alcance y diseño aprobado.
- Paciente activo visible y peso con fecha/fuente: evitar usar silenciosamente un peso antiguo o de otro paciente. Metrónomo y sonidos no se presentan como verificación de la infusión real.

## Referencias SQL recibidas

Se guardan como `.sql.txt` fuera de adaptaciones y semillas ejecutables, sin alterar el original. No se ejecutaron, no constituyen el esquema actual de la app y no verifican datos clínicos.

- [1-seed_referencias_externas.sql.txt](1-seed_referencias_externas.sql.txt) — SHA-256 `ba105f4a488717350ac323d7e293c4256df0f59999ae9e9b91497735ffa009e2`
- [2-schema.sql.txt](2-schema.sql.txt) — SHA-256 `05d36c20e1d33962a38064a58add0b42f3dee391f72838c1d906f908a3109e90`
- [3-seed.sql.txt](3-seed.sql.txt) — SHA-256 `bc8ddd25be406da962aae1b3912b78d9ef3533bbf37ee08bfbff91f5a18893ce`

Hallazgos: el esquema usa estados `confirmado/por_confirmar` y un valor predeterminado confirmado en heredabilidades; eso no se convierte en verificación de la app. La actualización externa promueve rangos y reemplaza una fórmula; requiere revisión de fuente, unidad, validez y trazabilidad, no ejecución directa. Los lotes se aíslan por `user_id`, mientras la app distingue espacio personal y clínica con permisos; habrá que adaptar el modelo. Revisar límites inclusivos/exclusivos y evitar evaluar expresiones SQL/texto arbitrarias en el cliente. Cualquier dato admitido entra **sin verificar**, conservando la fuente y la marca original como procedencia, no como autoridad.
