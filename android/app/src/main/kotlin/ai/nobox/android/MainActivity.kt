package ai.nobox.android

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val CHANNEL = "ai.nobox.android/background_service"
    private val NOTIFICATION_CHANNEL = "ai.nobox.android/notification"
    private var methodChannel: MethodChannel? = null
    private var notificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startBackgroundService" -> {
                        val token = call.argument<String>("token") ?: ""
                        val userId = call.argument<String>("userId") ?: ""
                        val tenantId = call.argument<String>("tenantId") ?: ""
                        SignalRBackgroundService.startService(this, token, userId, tenantId)
                        result.success(true)
                    }
                    "stopBackgroundService" -> {
                        SignalRBackgroundService.stopService(this)
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }

        // Channel yang dipakai Dart (PushNotificationService) untuk membuka chat
        // dari notifikasi.
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)

        // Cold start dari notifikasi (aplikasi sebelumnya sudah ditutup).
        if (intent?.getStringExtra(SignalRBackgroundService.EXTRA_ROOM_ID) != null) {
            // Beri waktu inisialisasi Flutter + PushNotificationService selesai.
            notifyFlutterAboutRoom(intent, delayMs = 3000)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Aplikasi masih hidup: cukup teruskan room-nya ke Flutter.
        // Jangan gunakan FLAG_ACTIVITY_CLEAR_TASK agar aplikasi tidak
        // restart total hanya karena notifikasi diklik.
        notifyFlutterAboutRoom(intent, delayMs = 250)
    }

    private fun notifyFlutterAboutRoom(intent: Intent?, delayMs: Long) {
        val roomId = intent?.getStringExtra(SignalRBackgroundService.EXTRA_ROOM_ID) ?: return
        val roomName = intent.getStringExtra(SignalRBackgroundService.EXTRA_ROOM_NAME) ?: ""

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                notificationChannel?.invokeMethod(
                    "openChat",
                    mapOf("roomId" to roomId, "roomName" to roomName),
                )
            } catch (_: Exception) {
                // Diabaikan: bukan kegagalan fatal.
            }
        }, delayMs)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Sengaja tidak stopBackgroundService agar chat tetap jalan walau aplikasi ditutup.
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        notificationChannel = null
    }
}
