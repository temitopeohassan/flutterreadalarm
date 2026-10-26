import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'event_log.dart';

/// Keeps the app alive while a book is being read, so reading continues
/// with the screen locked, and shows lock-screen controls.
abstract class PlaybackService {
  Future<void> init(void Function(String command) onCommand);
  Future<void> show({
    required String title,
    required String text,
    required bool playing,
  });
  Future<void> hide();

  /// Why the background service isn't running while reading, or null if
  /// it is. Without it Android may stop reading once the screen locks.
  ValueListenable<String?> get problem;
}

/// Commands sent from the notification buttons.
const playbackToggle = 'toggle';
const playbackStop = 'stop';

@pragma('vm:entry-point')
void _startPlaybackTask() =>
    FlutterForegroundTask.setTaskHandler(_PlaybackTaskHandler());

/// Runs in the service's isolate and forwards button presses to the app.
class _PlaybackTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

class ForegroundPlaybackService implements PlaybackService {
  void Function(String command)? _onCommand;

  @override
  final ValueNotifier<String?> problem = ValueNotifier(null);

  @override
  Future<void> init(void Function(String command) onCommand) async {
    _onCommand = onCommand;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'reading_session',
        channelName: 'Reading session',
        channelDescription: 'Controls for the book being read aloud',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        stopWithTask: true,
      ),
    );
  }

  void _onData(Object data) {
    if (data is String) _onCommand?.call(data);
  }

  List<NotificationButton> _buttons(bool playing) => [
        NotificationButton(
            id: playbackToggle, text: playing ? 'Pause' : 'Resume'),
        const NotificationButton(id: playbackStop, text: 'Stop'),
      ];

  @override
  Future<void> show({
    required String title,
    required String text,
    required bool playing,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final ServiceRequestResult result;
      if (await FlutterForegroundTask.isRunningService) {
        result = await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
          notificationButtons: _buttons(playing),
        );
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: 4201,
          serviceTypes: [ForegroundServiceTypes.mediaPlayback],
          notificationTitle: title,
          notificationText: text,
          notificationIcon: const NotificationIcon(
              metaDataName: 'com.readalarm.readalarm.NOTIFICATION_ICON'),
          notificationButtons: _buttons(playing),
          callback: _startPlaybackTask,
        );
      }
      // Failures are returned, not thrown. Without the service (and its
      // wake lock) Android may pause reading once the screen locks.
      if (result case ServiceRequestFailure(:final error)) {
        debugPrint('Playback service failed to start: $error');
        logEvent('ERROR background reading service did not start: $error');
        problem.value = '$error';
      } else {
        problem.value = null;
      }
    } catch (e) {
      logEvent('ERROR background reading service unavailable: $e');
      problem.value = '$e';
      // Reading still works in the foreground without the service.
      debugPrint('Playback service unavailable: $e');
    }
  }

  @override
  Future<void> hide() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('Stopping playback service failed: $e');
    }
  }
}
