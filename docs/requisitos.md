# Alcance consolidado

Fuente: instrucciones del usuario y dos partes del chat previo. Ante conflictos,
prevalecen las instrucciones explícitas del usuario. Las afirmaciones de compilación
y verificación del chat anterior no constituyen evidencia de este proyecto.

## Plataformas y arquitectura

Android, iOS y web para computadora. Flutter, MVVM, un directorio por módulo,
repositorios e inyección por constructor. Supabase multiclínica y multiusuario,
caché local offline multiplataforma (sustituye Room). Interfaz en español,
neumorfismo, cinco temas, claro/oscuro y menú lateral oculto.

## Orden de implementación

1. M1: cuatro ramas en cabecera y menú; Home, cálculo, escáner, receta,
   hospitalización; temas y ajustes.
2. M2: correo/Google, invitaciones a clínica, membresías y roles desde servidor,
   RLS por clínica y rol, auditoría, sincronización offline.
3. M3: catálogo JSON versionado, búsqueda por principio activo y marca MX,
   mg/kg → mg → ml por presentación, redondeo, límites, contraindicaciones,
   doble confirmación; dosis personales y aprobación del admin al compartir.
4. M4: pacientes, propietarios, alergias, SOAP, peso, vacunas, desparasitación,
   recordatorios, consentimiento firmado y transcripción de voz revisable.
5. M5: jaulas, paciente × hora, administración con autor y hora, alarmas,
   snooze y escalamiento. Evaluar restricciones de cada plataforma antes de
   prometer sonido con aplicación cerrada.
6. M6: PDF membretado y firma, historial, enlace wa.me, libro de control,
   folio oficial capturado por usuario, CSV/Excel.
7. M7: sedación por etapas, constantes, fluidos, CRI/goteo, pediatría/geriatría,
   peso metabólico y producción por lote/cabeza/agua/alimento, retiros por producto.
8. M8: lotes, caducidad 30/60 días, stock/reorden, cámara, códigos, POS,
   cortes, comisiones y pedidos redactados con IA con envío aprobado.
9. M9: citas, estética y estados, servicios, comisiones fijas/porcentaje,
   desempeño, pendientes asignados, mensajería, distribuidores y ficha personal.
10. M10: QR firmado cada 45 s, hora servidor, ubicación al escanear,
    entrada/salida, correcciones admin con motivo, reportes y privacidad.
11. M11: ventas, citas por especie, bajo stock, exportación completa y Drive;
    WhatsApp Business para agendar al final si la API está contratada.

## Reglas transversales

- Roles: admin, MVZ, auxiliar, recepción, estilista. Nunca seleccionables como identidad.
- Ficha médica del personal: solo propio usuario y admin, con consentimiento.
- Propietarios y otros datos sensibles: permisos definidos en servidor, no solo UI.
- Dosis, contraindicaciones, normativa y retiros: JSON versionado con fuente
  y estado verificada/sin verificar; dato faltante vacío y marcado.
- Cálculos puros separados de UI y con pruebas de casos conocidos.
- No usar ml/gr × peso como fórmula universal; definir unidades y concentración
  para cada tipo de cálculo antes de implementar.
- OCR/IA proponen datos para revisión, nunca verifican automáticamente un medicamento.
- IA de apoyo clínico, recomendaciones comerciales/análisis de mercado y SMS
  son solicitudes adicionales del chat: proveedor, costo y alcance por definir.
- No inventar folios ni afirmar cumplimiento COFEPRIS/SENASICA sin fuentes revisadas.
- La firma capturada y un PDF no prueban por sí solos validez legal.
- OAuth Google para login y autorización Drive son permisos distintos.

## Estado real

M1: proyectos Android/iOS/web generados, análisis aprobado, prueba de navegación
y apariencia móvil aprobada, compilación web realizada. Pendiente de revisión
en dispositivos reales y compilación nativa Android/iOS. Revisión visual local
en Chromium realizada; capturas en review/. No hay URL externa de vista previa.
M2: base de acceso, clínicas, invitaciones, roles y auditoría escrita y probada
localmente. Conexión real configurada, confirmación de correo verificada, caché
de acceso y base de cola offline integradas. Pruebas de cuenta real diferidas
por petición del usuario; gestión completa de miembros y adaptadores por módulo pendientes;
ver docs/supabase.md. M6–M14: implementaciones locales con instalación/integraciones pendientes; ver los documentos por módulo. No hay datos clínicos ni datos reales
de clínica cargados.

M3 implementado en código: motor exacto, catálogo importable, búsqueda, alertas, doble confirmación y captura/revisión de dosis personales. Migración M3 preparada y probada localmente, pendiente de aplicar; catálogo clínico real y pruebas con cuentas al final. Ver `docs/m3-dosis.md`.

M4 implementado como primera versión de expedientes: alta y consulta, SOAP, pesos, alergias, prevención, consentimientos y dictado revisable. Migración preparada y probada localmente, sin datos sensibles en caché; pruebas de voz/dispositivos y acceso remoto pendientes al final. Ver `docs/m4-expedientes.md`.

M5 implementado en primera versión: fichas/tabla, horarios explícitos, confirmación con usuario/hora del servidor, avisos nativos configurados, posposición y escalamiento local. Migración local probada, incluida concurrencia; pendiente aplicación remota y pruebas de notificaciones en dispositivos. Web requiere hoja abierta. Ver `docs/m5-hospitalizacion.md`.

## M-FORMATOS — fases aprobadas

Pasante = auxiliar, sin rol nuevo. Fase 1 implementada localmente: plantillas/versiones, borradores/asignación, firma propia y PDF del servidor conservado por hash; identificación del firmante solo número. Fuente legal sin verificar, revisión por clínica. Membrete/logo editable y congelado en documentos firmados. [Alcance real](m-formatos-fase1.md). Fase 2 (historia/quirúrgica) y M6 (recetas/medicación/control) implementados localmente con el alcance y límites de sus documentos; instalación real pendiente. Eutanasia: motivo, concepto previo, método, disposición y costo en consentimiento; constatación de muerte se anexa después.

Estado actualizado en la [revisión completa](revision-plataforma-2026-10-08.md): fuentes clínicas e integraciones reales siguen pendientes. IA de ayuda incluida con Gemini/GLM preparada, solo temas públicos, sin credenciales configuradas.
