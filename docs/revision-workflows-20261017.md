# Revisión de workflows, 17 de octubre de 2026

El fallo 39026525419 del monitor de constantes estaba en PostgreSQL:
`syntax error at or near "or"`, al aplicar `13W_clinical_vitals.sql`.
Después del primer `COMMIT` habían quedado dos copias parciales del cuerpo SQL.
Se retiraron esos fragmentos, conservando la migración completa que guarda el
snapshot de referencias. La prueba Flutter de aquella ejecución había aprobado.

Se revisaron las últimas ejecuciones de los 12 workflows, dentro de las 250
ejecuciones más recientes. Solo el monitor tenía su última ejecución fallida;
APK, firma, restauración, corte de permisos y preparación/despliegue tenían una
última ejecución exitosa. Los fallos antiguos permanecen en el historial.
No se relanzaron workflows de despliegue ni se generó un APK para esta revisión.

Al ejecutar el corte completo actual apareció otro fallo en `workspace-management`:
Docker rechazó `vetdosis-workspace-manage-$` (salida 125). El script tenía un dólar
literal en lugar de `$$` para el ID del proceso. Se corrigió el nombre y se probó
la cadena de administración por separado antes de repetir el corte completo.

La revisión también corrigió autorización por sección en estadísticas, rechazo
de NULL en restauración y aplicación restringida a destinos de prueba temporales.
Las migraciones son candidatos: requieren aplicación coordinada y no se publican
automáticamente en Supabase por ejecutar los tests.
