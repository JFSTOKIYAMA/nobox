import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../app_config.dart';

// =====================================================================
// FITUR: Pengelola Layanan Latar Belakang (Background Service)
// FILE: lib/core/services/background_service_manager.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Mengelola Background Service native Android untuk menjaga koneksi SignalR
//         tetap hidup saat aplikasi di-minimize. Berkomunikasi dengan SignalRBackgroundService.kt via MethodChannel.
// =====================================================================
class BackgroundServiceManager {
  static const _channel = MethodChannel('ai.nobox.android/background_service');
  static bool _isRunning = false;

  /// Memulai background service dengan token JWT terbaru.
  /// Dipanggil saat aplikasi masuk ke background (paused/hidden).
  static Future<void> startService() async {
    if (_isRunning) return;

    try {
      // Ambil token terbaru dari secure storage
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: AppConfig.tokenKey);

      if (token == null || token.isEmpty) {
        debugPrint('BackgroundServiceManager: No token found, skipping start.');
        return;
      }

      // Ambil tenantId
      final tenantId = await storage.read(key: 'tenant_id') ?? '';

      // Ekstrak userId dari JWT
      String userId = '1';
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payload));
          final payloadMap = jsonDecode(decoded);
          userId =
              payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
              payloadMap['nameid'] ??
              payloadMap['sub'] ??
              '1';
        }
      } catch (e) {
        debugPrint('BackgroundServiceManager: Failed to decode JWT: $e');
      }

      await _channel.invokeMethod('startBackgroundService', {
        'token': token,
        'userId': userId,
        'tenantId': tenantId,
      });
      _isRunning = true;
      debugPrint(
        'BackgroundServiceManager: ✅ Background service started. userId: $userId, tenantId: $tenantId',
      );
    } on PlatformException catch (e) {
      debugPrint('BackgroundServiceManager: ❌ PlatformException: ${e.message}');
    } on MissingPluginException {
      debugPrint(
        'BackgroundServiceManager: ⚠️ MethodChannel not available (not on Android?).',
      );
    } catch (e) {
      debugPrint('BackgroundServiceManager: ❌ Error starting service: $e');
    }
  }

  /// Sinkronkan token JWT terbaru ke background service native.
  /// Dipanggil saat ApiClient berhasil me-refresh token, agar koneksi SignalR
  /// background selalu memakai token aktif (menghindari error handshake 401).
  static Future<void> updateToken(String token) async {
    if (token.isEmpty) return;

    try {
      await _channel.invokeMethod('updateToken', {'token': token});
      debugPrint(
        'BackgroundServiceManager: 🔄 Token JWT diperbarui ke background service.',
      );
    } on PlatformException catch (e) {
      debugPrint(
        'BackgroundServiceManager: ❌ PlatformException (updateToken): ${e.message}',
      );
    } on MissingPluginException {
      debugPrint(
        'BackgroundServiceManager: ⚠️ MethodChannel not available (not on Android?).',
      );
    } catch (e) {
      debugPrint('BackgroundServiceManager: ❌ Error updating token: $e');
    }
  }

  /// Menghentikan background service.
  /// Dipanggil saat aplikasi kembali ke foreground (resumed) atau terminated.
  /// Parameter [force] memaksa stop meskipun flag _isRunning = false (berguna saat app di-kill).
  static Future<void> stopService({bool force = false}) async {
    if (!_isRunning && !force) return;

    try {
      await _channel.invokeMethod('stopBackgroundService');
      _isRunning = false;
      debugPrint(
        'BackgroundServiceManager: 🛑 Background service stopped${force ? " (forced)" : ""}.',
      );
    } on PlatformException catch (e) {
      debugPrint('BackgroundServiceManager: ❌ PlatformException: ${e.message}');
    } on MissingPluginException {
      debugPrint('BackgroundServiceManager: ⚠️ MethodChannel not available.');
    } catch (e) {
      debugPrint('BackgroundServiceManager: ❌ Error stopping service: $e');
    }
  }

  /// Cek apakah service sedang berjalan
  static bool get isRunning => _isRunning;
}
