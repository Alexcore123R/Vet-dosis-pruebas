# Agenda y Planeación financiera: segunda etapa

## Continuidad con Copilot

Se consultaron las ramas y el PR #2 antes de editar. `design/app-wide` apunta al
commit `c451b30`, anterior a la navegación implementada en `acf6241`; no contiene
cambios visuales adicionales. La conversación compartida confirma la creación de
esa rama y el plan Agenda → Pacientes → Cálculos. Se continúa en
`design/ui-kit-home-agenda`, sin sobrescribir la rama creada por Copilot.

## Agenda

- Extiende el tema de Inicio a Agenda, manteniendo la fuente local/de sistema.
  `withValues` es compatible con Flutter 3.47.6; no se sustituye por API obsoleta.
- Resumen de citas del día y registros cargados, calculado exclusivamente sobre
  las filas recibidas y autorizadas. No representa el total global del servidor.
- Filtros horizontales por estados reales: agendada, en atención, lista, entregada
  y cancelada. Se combinan con el selector de fecha existente sin escrituras.
- Tarjetas con fecha/hora locales legibles y estado escrito. Se declara el uso del
  horario del dispositivo; no se simula una conversión a la zona de la clínica.
- Conserva expedientes vinculados, reprogramación y transiciones existentes, junto
  con las comprobaciones de `patient.read` y `appointment.manage`.
- Encabezado autenticado ajustable al tamaño de texto y logo que se reduce al
  ancho disponible, atendiendo los dos comentarios de revisión del PR #2.

Pendiente: vistas semanal/mensual completas, recordatorios e integración externa.
El calendario actual sigue siendo el selector de fecha existente.

## Planeación financiera

Ruta: Más → Administración y finanzas → Planeación financiera.

Primera herramienta operativa: simulador mensual en MXN para clínica o unidad
productiva. No es todavía un gestor de proyectos/presupuestos guardados. Sus siete
importes se capturan manualmente, sin valores didácticos precargados:

1. Ingresos estimados del mes.
2. Costos fijos del mes, sin depreciación.
3. Costos variables del mes, sin depreciación.
4. Depreciación mensual.
5. Inversión inicial en activos, sin fondo operativo ni reserva.
6. Fondos disponibles para el proyecto.
7. Reserva explícita para imprevistos.

Todos son obligatorios; 0 es válido. Admite coma o punto decimal, hasta dos
posiciones, sin separadores de miles, negativos ni importes no finitos. Se
trabaja en centavos enteros para resultados y fondos; divisiones de escenarios
se calculan con decimales. Límite por importe: 1000000000 MXN.

- **Resultado estimado:** ingresos − costos fijos − costos variables − depreciación.
- **Saldo operativo estimado de efectivo:** ingresos − costos fijos − costos variables.
- **Fondos adicionales:** máximo entre 0 e inversión + un mes de costos en efectivo
  + reserva − fondos disponibles. Los cobros previstos no son fondos disponibles.
- **Ingresos de equilibrio:** (fijos + depreciación) / (1 − variables / ingresos),
  solo con ingresos y margen de contribución positivos.
- **Recuperación simple:** inversión / saldo operativo positivo; inversión cero
  se informa expresamente en lugar de ofrecer una promesa de recuperación.

Se explican las fórmulas y los supuestos de precios/mezcla constantes y meses
iguales con cobros/pagos dentro del mes. Son escenarios antes de impuestos,
financiación, deuda y variaciones de capital de trabajo: no utilidad neta final.
No se incluye la reserva como gasto ni se duplica el fondo operativo.

Base conceptual: `porcinos-y-planeacion-desde-pdf-20261018.md`; el ejemplo del
PDF solo se utiliza en una prueba aritmética (pérdida de 10000), nunca como datos
reales de la clínica.

### Alcance de acceso y datos

El destino nuevo exige administrador y, cuando existe contrato de módulos,
acceso al módulo financiero `sales` existente. También se comprueba al entrar
por ruta directa. No se conceden permisos ni se modifican contratos remotos.
La app sin sesión conserva el modo de herramientas locales que ya utiliza.

Los importes viven únicamente en la pantalla: al abandonarla, cambiar de
usuario/espacio o perder el acceso se destruye el formulario. Editar un importe
retira resultados anteriores hasta recalcular. La interfaz informa que no se
guarda. Sin almacenamiento local, RPC, movimientos de Caja ni lecturas financieras.

Pendiente: proyectos y rubros guardados, periodos anuales/ciclos, escenarios
comparables, exportación y presupuesto contra real. Los registros porcinos y los
otros módulos conservan el alcance de la primera etapa.

## Verificación y entrega

Flutter 3.47.6: análisis sin incidencias; suite completa de **397 pruebas aprobada**
(`flutter test --timeout 5m --concurrency 2`). Cuatro renders de revisión aprobados.

- Pruebas de aritmética, validación de moneda, pérdida/margen cero, depreciación,
  fondos, permisos, rutas directas y destrucción del formulario.
- Pruebas de filtros combinados y conservación de captura/expedientes de Agenda.
- Pantallas estrechas (320 px) y texto al 200%; Agenda clara y oscura, incluyendo
  encabezados autenticados.
- Previews con datos ficticios en `review/agenda-pilot-20261018/` y
  `review/financial-planning-20261018/`. No son capturas de un dispositivo.

Pendiente compilar el APK de esta rama y realizar la revisión en Android. El APK
anterior sigue sin contener las nuevas pantallas.
