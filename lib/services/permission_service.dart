import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Opens the phone maker's auto-start setting, or the closest page found.
  Future<AutoStartPage> openAutoStartSettings();

  /// For support: the phone's model and the auto-start screens found on it.
  Future<String> autoStartReport();
}

/// Which page [PermissionService.openAutoStartSettings] opened.
enum AutoStartPage {
  /// The maker's auto-start list (e.g. Phone Master's on Tecno).
  autoStart,

  /// The maker's phone-manager app, at its home screen.
  phoneManager,

  /// Android's app info page for ReadAlarm (no maker screen found).
  appInfo,
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

  static const _autoStart = MethodChannel('readalarm/autostart');

  @override
  Future<AutoStartPage> openAutoStartSettings() async {
    try {
      switch (await _autoStart.invokeMethod<String>('open')) {
        case 'autostart':
          return AutoStartPage.autoStart;
        case 'manager':
          return AutoStartPage.phoneManager;
      }
    } catch (e) {
      debugPrint('Opening auto-start settings failed: $e');
    }
    await openAppSettingsPage();
    return AutoStartPage.appInfo;
  }

  @override
  Future<String> autoStartReport() async {
    try {
      return await _autoStart.invokeMethod<String>('report') ?? '';
    } catch (e) {
      return 'No report: $e';
    }
  }
}

/// permission_handler's top-level function, renamed to avoid the clash with
/// [PermissionService.openAppSettings].
Future<bool> openAppSettingsPage() => openAppSettings();
