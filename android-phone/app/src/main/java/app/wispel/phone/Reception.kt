package app.wispel.phone

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.*
import org.json.JSONObject

class Reception : Service() {
    private lateinit var relay: Relay
    private val loop = Executors.newSingleThreadExecutor()
    @Volatile private var running = false
    @Volatile private var socket: WebSocket? = null

    override fun onBind(intent: Intent?): IBinder? = null

    private fun state(value: String) {
        relay.prefs.edit().putString("state", value).apply()
    }

    override fun onCreate() {
        super.onCreate()
        relay = Relay(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") relay.prefs.edit().putBoolean("enabled", false).apply()
        if (relay.role != "receive" || !relay.prefs.getBoolean("enabled", false)) {
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel("connection", "직접 연결 상태", NotificationManager.IMPORTANCE_LOW)
        )
        val stop =
            PendingIntent.getService(
                this,
                1,
                Intent(this, Reception::class.java).setAction("stop"),
                PendingIntent.FLAG_IMMUTABLE,
            )
        val notification =
            Notification.Builder(this, "connection")
                .setSmallIcon(R.drawable.note)
                .setContentTitle("위스펠 직접 수신")
                .setContentText("집 서버에서 알림을 받는 중")
                .setLocalOnly(true)
                .setOngoing(true)
                .addAction(Notification.Action.Builder(null, "중지", stop).build())
                .build()
        startForeground(1, notification)
        if (!running) {
            running = true
            loop.execute { connect() }
        }
        return START_STICKY
    }

    private fun connect() {
        var delay = 1L
        while (running && relay.role == "receive") {
            val ended = CountDownLatch(1)
            try {
                state("연결 중")
                socket =
                    relay
                        .transport()
                        .newWebSocket(
                            relay.request("/v1/stream").build(),
                            object : WebSocketListener() {
                                override fun onOpen(ws: WebSocket, response: Response) {
                                    state("연결됨")
                                    delay = 1
                                }

                                override fun onMessage(ws: WebSocket, text: String) {
                                    try {
                                        process(JSONObject(text))
                                    } catch (e: Exception) {
                                        ws.cancel()
                                    }
                                }

                                override fun onFailure(
                                    ws: WebSocket,
                                    t: Throwable,
                                    response: Response?,
                                ) {
                                    if (response?.code == 401) {
                                        state("연결 해제됨")
                                        running = false
                                        stopSelf()
                                    }
                                    ended.countDown()
                                }

                                override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                                    ended.countDown()
                                }

                                override fun onClosing(ws: WebSocket, code: Int, reason: String) {
                                    ws.close(code, null)
                                }
                            },
                        )
                while (running && !ended.await(1, TimeUnit.SECONDS)) {}
                if (running) {
                    state("재연결 대기")
                    Thread.sleep(delay * 1000)
                    delay = (delay * 2).coerceAtMost(30)
                }
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                if (!running) return
                state("연결 확인 필요")
                try {
                    Thread.sleep(3000)
                } catch (e: InterruptedException) {
                    return
                }
            }
        }
    }

    private fun process(n: JSONObject) {
        if (!running || relay.role != "receive") return
        val kind = n.getString("kind")
        val source = n.getString("sourceId")
        val now = System.currentTimeMillis()
        val at = n.getLong("occurredAt")
        require(Rules.labels.containsKey(kind))
        val prefs = relay.prefs
        val events = Events.get(this)
        val allowed =
            prefs.getLong("pause", 0) <= now &&
                prefs.getBoolean("allow." + kind, true) &&
                prefs.getBoolean("allow." + source + "." + kind, true)
        val enabled = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        val show = allowed && enabled && Rules.valid(at, now)
        if (events.remember(relay.id, n, prefs.getBoolean("history", true), show)) {
            if (show)
                postNotice(
                    n,
                    events
                        .tiles(relay.id)
                        .firstOrNull { it.source == source && it.kind == kind }
                        ?.count ?: 1,
                    prefs.getBoolean("watch." + kind, true),
                )
        }
        events.done(relay.id, n)
        relay.api(
            "/v1/ack",
            "POST",
            json("sourceId" to source, "eventId" to n.getString("eventId")),
        )
        prefs.edit().putLong("updated", now).apply()
    }

    override fun onDestroy() {
        running = false
        socket?.cancel()
        loop.shutdownNow()
        if (relay.prefs.getString("state", "") != "연결 해제됨") state("수신 중지")
        super.onDestroy()
    }
}

internal fun Context.postNotice(n: JSONObject, count: Int, showOnWatch: Boolean) {
    val kind = n.getString("kind")
    val at = n.getLong("occurredAt")
    val label = Rules.labels.getValue(kind)
    val delayed = Rules.quiet(at, System.currentTimeMillis())
    val channel = if (delayed) "delayed" else "kind." + kind
    val manager = getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
        NotificationChannel(
                channel,
                if (delayed) "지연된 알림" else label,
                if (delayed) NotificationManager.IMPORTANCE_LOW
                else NotificationManager.IMPORTANCE_DEFAULT,
            )
            .apply {
                setSound(null, null)
                enableVibration(false)
            }
    )
    val open =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, Home::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
    val notification =
        Notification.Builder(this, channel)
            .setSmallIcon(R.drawable.note)
            .setContentTitle(label)
            .setContentText(n.getString("sourceName") + if (count > 1) " · " + count + "건" else "")
            .setShowWhen(true)
            .setWhen(at)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setLocalOnly(!showOnWatch)
            .setNumber(count)
            .build()
    manager.notify(n.getString("sourceId") + "." + kind, 2, notification)
}
