import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'alarm_scheduler.dart';
import 'book_importer.dart';
import 'permission_service.dart';
import 'playback_service.dart';
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
    this.deviceBrand = '',
  });

  final AppStorage storage;
  final SpeechEngine speech;
  final AlarmScheduler alarms;
  final PermissionService permissions;
  final PlaybackService playback;
  final BookImporter importer;

  /// Phone manufacturer, lower case, e.g. 'samsung' ('' if unknown).
  final String deviceBrand;

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
      alarms: NotificationAlarmScheduler(),
      permissions: AndroidPermissionService(),
      playback: ForegroundPlaybackService(),
      importer: DeviceBookImporter(),
      deviceBrand: brand.toLowerCase(),
    );
  }
}
