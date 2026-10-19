# APK beta: Inicio, Agenda y Pacientes

Compilación iniciada el 18 de octubre y completada el 19 de octubre de 2026 (UTC).

- Rama de origen: `design/patients-pilot`.
- Commit compilado: `c99e45c4a652e2bc9a44aacf6a53d7a88ca46210`.
- [Ejecución satisfactoria 39177796598](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39177796598).
- [Descargar ZIP de instaladores](https://github.com/Alexcore123R/Vet-dosis-pruebas/actions/runs/39177796598/artifacts/12155082271).
- Artefacto: `vetdosis-pruebas-apks`; disponible hasta el 1 de noviembre de 2026 a las 23:59:58 UTC.
- Identificador: `io.github.alexcore123r.vetdosis.beta`; versionCode: `214530299`.

## Verificación

GitHub Actions completó el análisis sin incidencias y las 402 pruebas. Verificó ambos APK contra la firma persistente configurada, su identificador, versión y respaldo Android desactivado. La publicación beta quedó registrada con caducidad de 90 días, sin abrir admisiones. SHA-256 del ZIP registrado por Actions: `401e317e00f9bc648e5d2765b0fb13b408da8f7b74c624753a2a8344f7c09b91`.

La descarga local desde este entorno recibió HTTP 403 del almacenamiento de artefactos; no se realizó una segunda comprobación local de sus hashes. Las comprobaciones anteriores corresponden al flujo de CI. La revisión física de esta entrega en Android queda pendiente.

## Contenido e instalación

Incluye el piloto visual de Inicio, Agenda y Pacientes/expedientes, el icono de la app, navegación agrupada, menú de producción por especies y simulador financiero de sesión. Los registros productivos pendientes siguen identificados como tales. Esta entrega no concede permisos ni habilitación profesional.

Acceder a GitHub con una cuenta autorizada al repositorio, descargar y extraer el ZIP. Instalar `app-arm64-v8a-beta-release.apk` como actualización de la beta existente, sin desinstalar ni borrar datos. El instalador `app-armeabi-v7a-beta-release.apk` es la alternativa para dispositivos que no admitan arm64.

Revisar Inicio, Agenda y Pacientes en el teléfono; comprobar búsqueda, ficha y registro de un paciente ficticio, así como selección de espacio y acciones permitidas. El commit compilado indicado arriba sigue siendo la referencia aunque la rama reciba después documentación adicional.
