# Responsables y cierre de beta — 17 de octubre de 2026

Este resumen sustituye listas históricas para ordenar el cierre. Las pruebas de
GitHub son aisladas y no acreditan un despliegue completo en Supabase.

## Responsables

- **5.6 sol — Storage y Edge Functions:** buckets privados, fotos, avatares,
  adjuntos, rutas y autorización de funciones PDF, IA y suscripciones. Audita,
  corrige y prueba su área; entrega cambios y evidencia a la integración.
- **6.1 sol — integración y cierre de beta:** coherencia entre módulos, orden de
  migraciones, revisión de entregas, workflows y coordinación de pruebas reales.

La asignación corresponde a agentes de desarrollo; no crea permisos en la app.
Despliegues y cambios de secretos mantienen su alcance de autorización propio.

## Pendientes prioritarios

1. Terminar revisión transversal de Storage/Edge y de plataforma/MFA y offline.
2. Consolidar el orden de migraciones y verificar el estado del servidor de
   pruebas antes de aplicar el conjunto coordinado.
3. Probar con Auth real dos cuentas/dos clínicas: lectura, captura, revocación,
   vencimiento beta, exportación, archivos y PDF.
4. Revisar al primer MVZ con evidencia externa y comprobar las versiones
   publicadas de términos y privacidad que realmente acepta la app.
5. Generar el APK candidato y probar en Android: alarmas con la app cerrada,
   confirmación de aplicaciones, cámara, archivos y compartir/imprimir PDF.
6. Ensayar beta con datos ficticios y comparación de cálculos. Incorporar las
   tablas aportadas con fuente y estado, sin declararlas verificadas por defecto.

## Trabajo posterior

Recuperación completa en un espacio de prueba independiente y transferencias;
Drive; OCR; WhatsApp automático; voz/escalación hospitalaria; ampliaciones
clínicas y avícolas; suscripciones/cobros y publicación Play. Hay componentes
preparados: estos flujos completos no se consideran concluidos.

## Última verificación

Monitor de constantes y restauración: PostgreSQL/Flutter aprobados.
Corte de permisos: 24/24 trabajos aprobados en ejecución 39027345542.
Los candidatos recientes no fueron desplegados ni incluidos en un APK durante
la revisión de workflows.
