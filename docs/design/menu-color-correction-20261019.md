# Colores compartidos y accesos del menú

La revisión en teléfono detectó que Más y el menú lateral conservaban la paleta verde anterior. El tema estaba limitado a Inicio, Agenda y Pacientes; además, copiar solo algunos colores dejaba contenedores Material derivados de la paleta anterior.

El shell ahora comparte el tema en todas sus secciones. El esquema completo se genera desde violeta, con acentos turquesa y superficies claras u oscuras; el lateral, barra inferior y encabezado usan superficies explícitas. Esta corrección extiende colores y superficies compartidas, sin completar todavía el rediseño particular de cada módulo. Las preferencias almacenadas no se reescriben.

Se retiraron los accesos directos Inicio y Cálculos del lateral porque ya están en la barra inferior. El selector de área y las secciones agrupadas permanecen.

Validación: 19 pruebas de navegación, tema, interfaz móvil y preferencias aprobadas, incluyendo menú abierto desde Inicio, Más y Cálculos. La corrección requiere un APK posterior al build 214530299 para verse en el teléfono.
