import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Keys of the permissions the alarm needs, as shown in onboarding and in
/// Settings → Alarm health. 'autoStart' has no Android API; the app tracks
/// the user's confirmation itself.
const permissionKeys = ['notifications', 'exactAlarm', 'battery', 'autoStart'];

abstract class PermissionService {
  /// Current status of every key except 'autoStart'.
  Future<Map<String, bool>> status();

  /// Asks for [key]. Some requests open a system settings page; call
  /// [status] again when the app resumes.
  Future<void> request(String key);

  Future<void> openAppSettings();
}

class AndroidPermissionService implements PermissionService {
  @override
  Future<Map<String, bool>> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return {'notifications': true, 'exactAlarm': true, 'battery': true};
    }
    return {
      'notifications': await Permission.notification.isGranted,
      'exactAlarm': await Permission.scheduleExactAlarm.isGranted,
      'battery': await Permission.ignoreBatteryOptimizations.isGranted,
    };
  }

  @override
  Future<void> request(String key) async {
    switch (key) {
      case 'notifications':
        await Permission.notification.request();
      case 'exactAlarm':
        if (!await Permission.scheduleExactAlarm.isGranted) {
          await Permission.scheduleExactAlarm.request();
        }
        // Android 14+: showing the alarm over the lock screen.
        await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestFullScreenIntentPermission();
      case 'battery':
        await Permission.ignoreBatteryOptimizations.request();
    }
  }

  @override
  Future<void> openAppSettings() => openAppSettingsPage();
}

/// permission_handler's top-level function, renamed to avoid the clash with
/// [PermissionService.openAppSettings].
Future<bool> openAppSettingsPage() => openAppSettings();
