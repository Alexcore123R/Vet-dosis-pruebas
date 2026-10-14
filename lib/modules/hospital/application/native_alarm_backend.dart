import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../domain/hospital_models.dart';
import 'hospital_alerts.dart';

class NativeAlarmBackend implements AlarmBackend {
  NativeAlarmBackend({this.onOpen});
  void Function()? onOpen;
  final plugin = FlutterLocalNotificationsPlugin();
  bool exact = false;
  @override
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  @override
  String get timingNotice => !supported
      ? 'Web: los avisos requieren la hoja abierta.'
      : defaultTargetPlatform == TargetPlatform.android && !exact
      ? 'Android puede retrasar avisos: falta permiso de alarmas exactas.'
      : 'Sonido y entrega sujetos a permisos, batería y ajustes del dispositivo.';
  @override
  Future<void> initialize() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_vetdosis'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onOpen?.call(),
    );
    exact =
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) onOpen?.call();
  }

  @override
  Future<String> requestPermission() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      if (await android.requestNotificationsPermission() != true) {
        return 'Permiso de notificaciones denegado.';
      }
      exact = await android.canScheduleExactNotifications() ?? false;
      if (!exact) exact = await android.requestExactAlarmsPermission() ?? false;
      return exact
          ? 'Activados: avisos Android con alarma exacta.'
          : 'Activados: Android puede retrasar los avisos; falta permiso de alarma exacta.';
    }
    final granted =
        await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true) ??
        false;
    return granted
        ? 'Activados: notificaciones locales de iPhone.'
        : 'Permiso de notificaciones denegado.';
  }

  @override
  Future<void> schedule(int id, AlarmJob job) async {
    if (!supported) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      exact =
          await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.canScheduleExactNotifications() ??
          false;
    }
    final prefs = await SharedPreferences.getInstance();
    final sound = prefs.getBool('hospital.alert.sound.v2') ?? true;
    final vibration = prefs.getBool('hospital.alert.vibration.v2') ?? true;
    await plugin.zonedSchedule(
      id: id,
      title: job.advance
          ? 'Hospitalización · Próximo horario'
          : job.escalated
          ? 'Hospitalización · Revisión prioritaria'
          : 'Hospitalización · Revisa la hoja',
      body:
          'Abre la app y comprueba el estado actual antes de administrar. Este aviso no confirma una dosis.',
      scheduledDate: tz.TZDateTime.from(
        job.at.isAfter(DateTime.now())
            ? job.at
            : DateTime.now().add(const Duration(seconds: 2)),
        tz.UTC,
      ),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'hospital_v2_s${sound ? 1 : 0}_v${vibration ? 1 : 0}',
          'Hospitalización',
          channelDescription: 'Avisos de tratamientos y revisiones pendientes',
          importance: Importance.max,
          priority: Priority.high,
          playSound: sound,
          enableVibration: vibration,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: sound),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (supported) await plugin.cancel(id: id);
  }
}
