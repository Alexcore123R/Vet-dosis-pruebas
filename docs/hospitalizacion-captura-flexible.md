# Captura flexible y ubicación hospitalaria — candidato 13D

Decisión de producto de la propietaria: no exigir historia completa, todas las constantes o peso diario para guardar una consulta o ingresar a hospitalización. Capturar lo realmente evaluado; vacío no significa normal ni realizado. Los requisitos corresponden a cada acción: cálculo por kg requiere peso, conversión a ml requiere concentración; eso no bloquea guardar otros datos del paciente.

Estado: SQL y UI candidatos, sin despliegue ni APK nuevo. No abre beta. Complementa la migración de permisos, no la termina.

## Comprobación del estado previo

- El ingreso existente solo pedía paciente y jaula: no exigía peso, temperatura ni anamnesis completa. Sí impedía dejar vacía la jaula en interfaz y servidor.
- La plantilla `clinical_history` de `assets/clinical/forms.clinical.v1.json` no marca mediciones como obligatorias. Los requisitos para preparar/firmar documentos no equivalen a exigir un examen completo en el ingreso. Un documento quirúrgico mantiene sus campos específicos; no se transforma en nota breve de consulta.
- Una medición individual exige su valor, unidad y autor/fecha porque ese es el acto que se registra. No obliga a registrar las demás constantes. No hay captura automática de hallazgos normales.

## Cambio preparado

- Ingreso sin jaula: se guarda NULL en servidor y se muestra «Sin asignar». No exige motivo, constantes ni hoja clínica completa.
- Cambio posterior de jaula o retirada de asignación: guarda versión, autor, fecha servidor, antes/después y motivo opcional en bitácora. No crea otra hospitalización, cambia paciente ni modifica órdenes o dosis.
- La ocupación exclusiva continúa para jaulas con nombre, incluyendo espacios externos y mayúsculas. Se permiten varias estancias sin asignación y se mantiene una estancia activa por paciente.
- Se conserva idempotencia: repetir una confirmación no duplica el ingreso ni el movimiento. Una versión antigua se rechaza; una jaula ocupada no se sobrescribe. Las constancias antiguas sin ubicación registrada no se muestran como si probaran que no había jaula.
- La interfaz solo permite omitir jaula y ofrece cambios/historial cuando el servidor anuncia esas capacidades. El servidor todavía no migrado conserva la validación previa; la app no ofrece un guardado que ese servidor rechazaría.

## Esquema y permisos

`13D_hospital_flexible_admission.sql` permite NULL en `hospital_stays.cage`; no reescribe las ubicaciones existentes. El índice único previo ya admite varios NULL.

Añade `hospital.manage` para ingreso y ubicación **administrativos**, sin convertirlo en prescripción ni habilitación profesional. El ingreso exige también `patient.read`; consultar estancias/tareas/historial exige `hospital.read`. Gestionar ubicación no concede lectura por sí mismo. No hay concesiones automáticas por rol ni datos clínicos nuevos. La UI usa los permisos anunciados para las acciones nuevas; al fallar una consulta conocida no recupera permisos antiguos.

La integración completa de navegación por permisos para puestos que antes no entraban al módulo sigue pendiente: no se presenta este candidato como migración completa de hospitalización. El acceso antiguo por roles se conserva únicamente en rutas todavía no migradas, no como alternativa al permiso nuevo del ingreso/ubicación.

Los movimientos se registran en la bitácora existente; `hospital_cage_history` devuelve solo esos eventos de la estancia/clínica autorizadas. No añade tabla de movimientos paralela ni altera registros previos.

## Límites antes de desplegar

Requiere corte coordinado, actualización del APK y revisión de compatibilidad: un APK antiguo no está preparado para leer una jaula NULL. Aún faltan prescripción hospitalaria, aplicación/posposición/no aplicación, alta clínica, administración/extracción/validación de medicamentos y su UI. Esas rutas antiguas no se presentan como protegidas por este bloque. No activar indicadores ni aplicar aisladamente.

La captura breve de consulta y las firmas de documentos deben conservar acciones diferenciadas. No se eliminan requisitos de una firma, orden o cálculo bajo el argumento de permitir campos opcionales. Nuevos seguimientos de peso, temperatura, alimentación o dispositivos se configurarán según la necesidad, sin intervalos clínicos por defecto.

## Validación

`bash supabase/tests/run_hospital_flexible_admission.sh`: dependencias reales de planes/agenda/permisos en PostgreSQL Docker aislado. Solo casos sintéticos. Cubre dos ingresos sin jaula y sin mediciones, lectura/gestión separadas, cambio sin motivo obligatorio, unicidad de ocupación, reintentos, conflicto de versión, liberación de jaula, historia con autor/hora, revocación ante reintento, aislamiento y anon. Resultado local: satisfactorio.

Flutter: cuatro pruebas nuevas de lectura de jaula NULL, ingreso mínimo, compatibilidad con servidor anterior y cambio sin jaula/motivo; pasan junto con las trece pruebas previas de hospitalización. Análisis sin observaciones. Suite completa Flutter: 268 pruebas satisfactorias. CI pendiente de registrar.
