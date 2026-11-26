import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'alarm_scheduler.dart';
import 'backend_service.dart';
import 'billing_service.dart';
import 'book_importer.dart';
import 'permission_service.dart';
import 'playback_service.dart';
import 'push_service.dart';
import 'speech.dart';
import 'storage.dart';

/// Everything the app talks to outside Dart. Tests pass fakes.
class AppServices {
  const AppServices({
    required this.storage,
    required this.speech,
    required this.alarms,
    required this.permissions,
    required this.playback,
    required this.importer,
    required this.billing,
    this.deviceBrand = '',
    this.backend = const NoBackend(),
    this.push = const NoPush(),
  });

  final AppStorage storage;
  final SpeechEngine speech;
  final AlarmScheduler alarms;
  final PermissionService permissions;
  final PlaybackService playback;
  final BookImporter importer;
  final BillingService billing;

  /// Phone manufacturer, lower case, e.g. 'samsung' ('' if unknown).
  final String deviceBrand;

  /// ReadAlarm's server at readalarm.net, which gets every alarm and
  /// sends a push when one is due; and the push itself.
  final BackendService backend;
  final PushService push;

  static Future<AppServices> device() async {
    var brand = '';
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        brand = (await DeviceInfoPlugin().androidInfo).manufacturer;
      } catch (_) {}
    }
    return AppServices(
      storage: await FileAppStorage.open(),
      speech: TtsSpeechEngine(),
      // Android: the native alarm engine (alarm clocks that ring before
      // Flutter starts). iPhone: notifications.
      alarms: defaultTargetPlatform == TargetPlatform.android
          ? NativeAlarmScheduler()
          : NotificationAlarmScheduler(),
      permissions: AndroidPermissionService(),
      playback: ForegroundPlaybackService(),
      importer: DeviceBookImporter(),
      billing: PlayBillingService(),
      deviceBrand: brand.toLowerCase(),
      backend: await HttpBackend.open(),
      push: FirebasePushService(),
    );
  }
}
