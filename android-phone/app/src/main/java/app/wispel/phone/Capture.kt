package app.wispel.phone

import android.app.Notification
import android.content.Context
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import androidx.core.app.NotificationCompat
import androidx.work.*
import java.util.UUID

class Capture : NotificationListenerService() {
    override fun onNotificationPosted(s: StatusBarNotification) {
        val relay = Relay(this)
        if (
            relay.role != "send" ||
                s.packageName == packageName ||
                s.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0
        )
            return
        val base =
            when (s.packageName) {
                getSystemService(TelecomManager::class.java)?.defaultDialerPackage -> "call"
                Telephony.Sms.getDefaultSmsPackage(this) -> "sms"
                "com.kakao.talk" -> "kakao"
                "com.Slack" -> "slack"
                relay.prefs.getString("mailPackage", "com.mailplug.aeolos2") -> "mail"
                else -> return
            }
        val extras = s.notification.extras
        val kind =
            if (base == "call" && s.notification.category == Notification.CATEGORY_MISSED_CALL)
                "missedCall"
            else
                Rules.classify(
                    base,
                    listOf(
                            Notification.EXTRA_TITLE,
                            Notification.EXTRA_TEXT,
                            Notification.EXTRA_BIG_TEXT,
                        )
                        .mapNotNull { extras.getCharSequence(it)?.toString() },
                )
        if (!relay.prefs.getBoolean("allow." + kind, true)) return
        // Android can repost the same conversation after a call or a ranking change.
        val n = s.notification
        if (
            n.category in
                setOf(
                    Notification.CATEGORY_SERVICE,
                    Notification.CATEGORY_PROGRESS,
                    Notification.CATEGORY_TRANSPORT,
                )
        )
            return
        val message =
            NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(n)
                ?.messages
                ?.lastOrNull()
        if (
            base == "sms" &&
                message == null &&
                n.category != Notification.CATEGORY_MESSAGE &&
                (n.flags and
                    (Notification.FLAG_FOREGROUND_SERVICE or Notification.FLAG_ONGOING_EVENT) !=
                    0 || extras.getCharSequence(Notification.EXTRA_TEXT).isNullOrBlank())
        )
            return
        // The OS can replace MessagingStyle timestamps while redacting the same SMS on every
        // repost.
        val timestamp =
            n.`when`.takeIf { it > 0 && it <= s.postTime + 300_000 }
                ?: message?.timestamp?.takeIf { it > 0 && it <= s.postTime + 300_000 }
                ?: s.postTime
        if (
            !Rules.valid(timestamp, System.currentTimeMillis()) ||
                timestamp < relay.prefs.getLong("pairedAt", 0L)
        )
            return
        val salt =
            relay.prefs.getString("eventSalt", null)
                ?: UUID.randomUUID().toString().also {
                    relay.prefs.edit().putString("eventSalt", it).commit()
                }
        val discriminator =
            if (message == null && base !in setOf("call", "sms"))
                extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
            else ""
        val eid =
            UUID.nameUUIDFromBytes(
                    (salt + "|" + s.key + "|" + timestamp + "|" + kind + "|" + discriminator)
                        .toByteArray()
                )
                .toString()
        Events.get(this).add(relay.id, kind, timestamp, eid)
        DeliveryWorker.schedule(this)
    }
}

class DeliveryWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result =
        try {
            Events.get(applicationContext).flush(Relay(applicationContext))
            Result.success()
        } catch (e: NetworkError) {
            if (e.status in listOf(401, 403, 409)) Result.failure() else Result.retry()
        } catch (e: Exception) {
            Result.retry()
        }

    companion object {
        fun schedule(c: Context) {
            val job =
                OneTimeWorkRequestBuilder<DeliveryWorker>()
                    .setConstraints(
                        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
                    )
                    .build()
            WorkManager.getInstance(c)
                .enqueueUniqueWork("send-events", ExistingWorkPolicy.APPEND_OR_REPLACE, job)
        }
    }
}
