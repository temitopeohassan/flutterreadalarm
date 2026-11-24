import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'alarm_scheduler.dart';
import 'backend_service.dart';
import 'event_log.dart';

/// The Firebase project that carries the server's pushes. Set at build
/// time with --dart-define (see server/README.md); without them push is
/// off and alarms ring only from the phone.
class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const androidAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// iPhones get pushes only with a paid Apple developer account (an APNs
  /// key in Firebase); apps installed with SideStore can't. Off unless
  /// built with --dart-define=READALARM_IOS_PUSH=true.
  static const iosPush = bool.fromEnvironment('READALARM_IOS_PUSH');

  static FirebaseOptions? get options {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final appId = ios ? iosAppId : androidAppId;
    if (ios && !iosPush) return null;
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        senderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }
}

abstract class PushService {
  /// Gets the phone's push token and gives it to [backend], now and
  /// whenever it changes; rings alarms that arrive by push.
  Future<void> start(BackendService backend, AlarmScheduler alarms);
}

class NoPush implements PushService {
  const NoPush();

  @override
  Future<void> start(BackendService backend, AlarmScheduler alarms) async {}
}

/// A push that arrived while ReadAlarm was closed or in the background:
/// Android starts it just for this. Rings the alarm unless it already rang.
@pragma('vm:entry-point')
Future<void> onBackgroundPush(RemoteMessage message) async {
  try {
    EventLog.instance = await EventLog.open();
  } catch (_) {}
  final options = PushConfig.options;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
  await ringFromPushInBackground(message.data);
}

class FirebasePushService implements PushService {
  @override
  Future<void> start(BackendService backend, AlarmScheduler alarms) async {
    final options = PushConfig.options;
    if (options == null) {
      logEvent('Push: off in this build');
      return;
    }
    try {
      final android = defaultTargetPlatform == TargetPlatform.android;
      if (android) {
        // Firebase already started natively from the build's resources
        // (android/app/build.gradle.kts); otherwise start it here.
        try {
          await Firebase.initializeApp();
        } catch (_) {
          await Firebase.initializeApp(options: options);
        }
      } else {
        await Firebase.initializeApp(options: options);
      }
      final messaging = FirebaseMessaging.instance;
      // iPhone asks; Android uses the notification permission from setup.
      await messaging.requestPermission(alert: true, sound: true, badge: true);
      if (!android) {
        // Android rings pushes natively (PushService.kt), even when
        // ReadAlarm is closed; iPhone through Flutter.
        FirebaseMessaging.onBackgroundMessage(onBackgroundPush);
        FirebaseMessaging.onMessage.listen((m) => alarms.ringFromPush(m.data));
      }
      // The classic registration token, which the server's send call
      // (FCM HTTP v1, message.token) takes. firebase_messaging 17 marks it
      // deprecated in favour of installation ids; it still works.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen(backend.setPushToken);
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      await backend.setPushToken(token);
      logEvent('Push: ready');
    } catch (e) {
      logEvent('Push: could not start: $e');
    }
  }
}
