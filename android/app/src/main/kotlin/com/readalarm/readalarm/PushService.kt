package com.readalarm.readalarm

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Pushes from readalarm.net (high-priority data messages, server/src/Fcm.php).
 * Android starts ReadAlarm just for this even when it was closed, and the
 * alarm rings natively ([AlarmEngine.ringFromPush]) without waiting for
 * Flutter. Replaces firebase_messaging's own service (AndroidManifest.xml);
 * the app sends its push token to the server each time it starts.
 */
class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        AlarmEngine.log(this, "Push received: ${message.data["type"]} for ${message.data["alarm_id"]}")
        AlarmEngine.ringFromPush(this, message.data)
    }

    override fun onNewToken(token: String) {
        AlarmEngine.log(this, "New push token: sent to the server when ReadAlarm next opens")
    }
}
