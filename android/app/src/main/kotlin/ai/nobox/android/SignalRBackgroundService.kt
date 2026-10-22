package ai.nobox.android

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.microsoft.signalr.HubConnection
import com.microsoft.signalr.HubConnectionBuilder
import com.microsoft.signalr.HubConnectionState
import io.reactivex.rxjava3.core.Single
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Foreground service yang menjaga koneksi SignalR tetap hidup saat aplikasi
 * berada di background.
 *
 * PENTING (ANR FIX):
 * Service.onStartCommand() dijalankan di MAIN THREAD Android — thread yang sama
 * dengan UI Flutter. Versi sebelumnya memanggil `start().blockingAwait()` dan
 * `Thread.sleep()` langsung di main thread sehingga UI freeze sampai puluhan
 * detik ("App isn't responding"). Semua operasi jaringan/blocking sekarang
 * dijalankan di worker thread.
 */
class SignalRBackgroundService : Service() {

    companion object {
        private const val TAG = "NOBOX_BG_SIGNALR"
        private const val CHANNEL_ID = "signalr_service_channel"
        private const val CHAT_CHANNEL_ID = "chat_notifications"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_START = "START_SIGNALR_SERVICE"
        private const val ACTION_STOP = "STOP_SIGNALR_SERVICE"
        private const val EXTRA_TOKEN = "EXTRA_JWT_TOKEN"
        private const val EXTRA_USERID = "EXTRA_USERID"
        private const val EXTRA_TENANTID = "EXTRA_TENANTID"

        const val EXTRA_ROOM_ID = "roomId"
        const val EXTRA_ROOM_NAME = "roomName"

        private const val PREFS_NAME = "nobox_bg_service"
        private const val KEY_TOKEN = "token"
        private const val KEY_USER_ID = "userId"
        private const val KEY_TENANT_ID = "tenantId"

        private const val CONNECT_TIMEOUT_SECONDS = 15L
        private const val STOP_TIMEOUT_SECONDS = 5L

        fun startService(context: Context, token: String, userId: String, tenantId: String) {
            val intent = Intent(context, SignalRBackgroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_USERID, userId)
                putExtra(EXTRA_TENANTID, tenantId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            // Gunakan stopService() (bukan startService dengan ACTION_STOP) agar
            // tidak terkena larangan start service dari background di Android 8+.
            context.stopService(Intent(context, SignalRBackgroundService::class.java))
        }
    }

    // Semua pekerjaan SignalR berjalan di worker thread tunggal.
    private val worker = Executors.newSingleThreadExecutor()

    @Volatile private var isServiceActive = false
    @Volatile private var isConnecting = false

    private var hubConnection: HubConnection? = null
    private var token: String? = null
    private var userId: String = "1"
    private var tenantId: String = ""
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        isServiceActive = true
        createNotificationChannels()
        acquireWakeLock()
    }

    override fun onDestroy() {
        isServiceActive = false
        releaseWakeLock()
        try {
            worker.execute { stopSignalRListener() }
        } catch (_: Exception) {
            // Executor sudah shut down — tidak ada yang perlu dilakukan.
        }
        worker.shutdown()
        Log.d(TAG, "Service destroyed")
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                token = intent.getStringExtra(EXTRA_TOKEN)
                userId = intent.getStringExtra(EXTRA_USERID) ?: "1"
                tenantId = intent.getStringExtra(EXTRA_TENANTID) ?: ""
                saveCredentials()

                // startForeground() WAJIB dipanggil cepat di main thread,
                // tetapi koneksi SignalR-nya dijalankan di worker thread.
                startForeground(NOTIFICATION_ID, createServiceNotification("Menghubungkan..."))
                worker.execute { startSignalRListener() }
            }

            ACTION_STOP -> {
                worker.execute { stopSignalRListener() }
                stopForeground(true)
                stopSelf()
            }

            else -> {
                // Service di-restart oleh OS (START_STICKY) dengan intent null.
                // Tetap panggil startForeground() agar tidak memicu error
                // "did not then call Service.startForeground()".
                restoreCredentials()
                if (token.isNullOrEmpty()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForeground(NOTIFICATION_ID, createServiceNotification("Menyambungkan ulang..."))
                worker.execute { startSignalRListener() }
            }
        }
        return START_STICKY
    }

    private fun saveCredentials() {
        try {
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString(KEY_TOKEN, token)
                .putString(KEY_USER_ID, userId)
                .putString(KEY_TENANT_ID, tenantId)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "saveCredentials failed: ${e.message}")
        }
    }

    private fun restoreCredentials() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            token = prefs.getString(KEY_TOKEN, null)
            userId = prefs.getString(KEY_USER_ID, "1") ?: "1"
            tenantId = prefs.getString(KEY_TENANT_ID, "") ?: ""
        } catch (e: Exception) {
            Log.w(TAG, "restoreCredentials failed: ${e.message}")
        }
    }

    /** Dijalankan di worker thread — jangan pernah dipanggil dari main thread. */
    private fun startSignalRListener() {
        if (!isServiceActive || isConnecting) return
        if (hubConnection?.connectionState == HubConnectionState.CONNECTED) {
            Log.d(TAG, "Already connected, skip.")
            return
        }

        isConnecting = true
        try {
            hubConnection = HubConnectionBuilder.create("https://id.nobox.ai/messagehub")
                .withAccessTokenProvider(Single.defer { Single.just(token ?: "") })
                .build()

            // Register handler with 4 arguments (Action4) since the backend sends up to 4 parameters.
            // Using multiple on() handlers for the same event crashes the Java SignalR client if argument counts mismatch.
            hubConnection?.on("TerimaPesan", { rawRoom: Any, rawMsg: Any, arg3: Any, arg4: Any ->
                Log.d(TAG, ">>> TerimaPesan (4 args)! room=$rawRoom")
                handleIncomingMessage(rawRoom.toString(), rawMsg.toString())
            }, Object::class.java, Object::class.java, Object::class.java, Object::class.java)

            // Retry mechanism dengan exponential backoff.
            val maxRetries = 3
            val retryDelays = longArrayOf(5000, 10000, 20000) // 5s, 10s, 20s

            for (attempt in 0..maxRetries) {
                if (!isServiceActive) return
                try {
                    Log.d(TAG, "Starting connection... (attempt ${attempt + 1}/${maxRetries + 1})")
                    // Timeout wajib ada: blockingAwait() tanpa timeout bisa
                    // menggantung selamanya saat jaringan buruk.
                    hubConnection?.start()
                        ?.timeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                        ?.blockingAwait()
                    Log.d(TAG, "CONNECTED! id=${hubConnection?.connectionId}")
                    updateServiceNotification("Tersambung / Aktif")

                    // Wajib Subscribe User agar backend mengirimkan event TerimaPesan
                    if (userId.isNotEmpty() && tenantId.isNotEmpty()) {
                        try {
                            hubConnection?.send("SubscribeUserAgent", userId, tenantId)
                            hubConnection?.send("SubscribeUserSpv", tenantId)
                            Log.d(TAG, "Subscribed user: userId=$userId, tenantId=$tenantId")
                        } catch (e: Exception) {
                            Log.e(TAG, "SubscribeUser failed: ${e.message}")
                        }
                    }

                    return // Berhasil, keluar dari loop
                } catch (e: Exception) {
                    Log.e(TAG, "Connection attempt ${attempt + 1} FAILED: ${e.message}")
                    if (attempt < maxRetries && isServiceActive) {
                        val delay = retryDelays[attempt]
                        Log.d(TAG, "Retrying in ${delay / 1000}s...")
                        updateServiceNotification("Retry ${attempt + 2}...")
                        // Aman: kita sedang di worker thread, bukan main thread.
                        Thread.sleep(delay)
                    } else {
                        Log.e(TAG, "All connection attempts failed!")
                        updateServiceNotification("Gagal: ${e.message?.take(40)}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Connection setup FAILED: ${e.message}")
            updateServiceNotification("Gagal: ${e.message?.take(40)}")
        } finally {
            isConnecting = false
        }
    }

    /** Dijalankan di worker thread. */
    private fun stopSignalRListener() {
        try {
            hubConnection?.stop()
                ?.timeout(STOP_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                ?.blockingAwait()
            Log.d(TAG, "SignalR stopped")
        } catch (e: Exception) {
            Log.w(TAG, "stopSignalRListener: ${e.message}")
        } finally {
            hubConnection = null
        }
    }

    private fun handleIncomingMessage(roomIdRaw: String, rawMsg: String) {
        var msgText = "Anda mendapat pesan baru"
        var roomId = roomIdRaw.replace("RoomId", "")
        var senderName = ""

        try {
            val json = JSONObject(rawMsg)
            val m = json.optString("Msg", "")
            if (m.isNotEmpty()) {
                // Media dikirim sebagai JSON; jangan tampilkan JSON mentah di notifikasi.
                msgText = if (m.startsWith("{") || m.startsWith("[")) "📎 Media" else m
            }
            val idFromPayload = json.optString("RoomId", "")
            if (idFromPayload.isNotEmpty()) roomId = idFromPayload
            senderName = json.optString(
                "SenderName",
                json.optString("Sender", json.optString("From", ""))
            )
        } catch (e: Exception) {
            Log.w(TAG, "JSON parse: ${e.message}")
        }

        if (msgText.length > 250) msgText = msgText.take(250) + "…"
        showChatNotification(roomId, senderName, msgText)
    }

    private fun showChatNotification(
        roomId: String,
        roomName: String,
        messageText: String,
    ) {
        try {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // SINGLE_TOP: jangan pakai CLEAR_TASK. Flag lama membuat seluruh
            // task dihancurkan dan aplikasi restart (splash + auth ulang)
            // setiap kali notifikasi diklik.
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_ROOM_ID, roomId)
                putExtra(EXTRA_ROOM_NAME, roomName)
            }
            val requestCode = if (roomId.isNotEmpty()) roomId.hashCode() else 0
            val pi = PendingIntent.getActivity(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notif = NotificationCompat.Builder(this, CHAT_CHANNEL_ID)
                .setSmallIcon(R.mipmap.launcher_icon)
                .setContentTitle(if (roomName.isNotEmpty()) roomName else "Pesan Baru")
                .setContentText(messageText)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setDefaults(Notification.DEFAULT_ALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setFullScreenIntent(pi, true) // Tembus MIUI lock screen
                .build()

            val uniqueId = (System.currentTimeMillis() % 100000).toInt() + 2000
            mgr.notify(uniqueId, notif)
            Log.d(TAG, "Notif posted id=$uniqueId")
        } catch (e: Exception) {
            Log.e(TAG, "showChatNotification failed: ${e.message}")
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nobox:signalr_bg")
            wakeLock?.acquire(60 * 60 * 1000L) // 1 jam max
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "acquireWakeLock failed: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "releaseWakeLock failed: ${e.message}")
        }
        wakeLock = null
        Log.d(TAG, "WakeLock released")
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                // Low-priority service channel
                mgr.createNotificationChannel(NotificationChannel(
                    CHANNEL_ID, "SignalR Background", NotificationManager.IMPORTANCE_LOW
                ))
                // High-priority chat channel
                mgr.createNotificationChannel(NotificationChannel(
                    CHAT_CHANNEL_ID, "Chat Notifications", NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    enableVibration(true)
                    enableLights(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                })
            } catch (e: Exception) {
                Log.w(TAG, "createNotificationChannels failed: ${e.message}")
            }
        }
    }

    private fun createServiceNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Nobox Chat")
            .setContentText(text)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateServiceNotification(text: String) {
        try {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            mgr.notify(NOTIFICATION_ID, createServiceNotification(text))
        } catch (e: Exception) {
            Log.w(TAG, "updateServiceNotification failed: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
