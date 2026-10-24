# Fluidoterapia y huellas de firma

Base funcional: f6af49b (`feature/manual-drive-export-receipt-20261023`). El nombre `vetdosis-pruebas-apks` corresponde al artefacto de Actions, no a una rama.

El panel calcula déficit, mantenimiento, pérdidas por periodo o día, caudal y goteo. La selección de paciente consulta el último peso registrado y pide confirmar vigencia. Cada cambio invalida el resultado y detiene el metrónomo; también se detiene al pasar a segundo plano. La revisión permite preparar instrucciones de hospitalización, sin guardar una orden automáticamente.

Las tasas, fórmula alométrica, límite de potasio y dosis de bolo requieren captura explícita; no se convierten valores de imágenes en recomendaciones universales. El potasio contabiliza solución base más suplemento. El bolo queda separado del plan; se bloquea su combinación con suplementación de KCl.

## Procedencia

Manual de protocolos de anestesia en perros, gatos y exóticos, Juan Salom Morell y Gaspar Soler Aracil, Multimédica, 2023. PDF aportado por el usuario: 17f-BPnXvwpEwg8FUGlky1zxPUEiW7WjK. Tabla 5.1, página impresa 56 / PDF 72: orientación breve sobre signos de deshidratación. Página impresa 58 / PDF 74: componentes del plan y goteo. Es un manual de contexto anestésico; no se trasladan automáticamente sus pautas a todos los pacientes. No se distribuye el PDF.

Se conservan los visores existentes de fisiología y laboratorio mediante `reference_review_list`. Las filas consultadas en Supabase están pendientes de revisión o contrastadas pendientes de MVZ; las composiciones de fluidos también indican NO CLÍNICO. No se modificó la base de datos ni se promovieron filas a valores aprobados.

## Firma

`check_keystore.py` exporta únicamente el certificado público DER a un temporal, calcula SHA-1 y SHA-256 y los muestra en logs/resumen de Actions. Conserva el bloqueo ante discrepancia de SHA-256. No imprime contraseñas ni material privado. Los workflows existentes de comprobación y APK ya invocan este script.
