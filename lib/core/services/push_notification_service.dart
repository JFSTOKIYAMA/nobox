import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// FITUR: Tangani Pesan Latar Belakang (Background)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📨 Background message received: ${message.messageId}');
  
  // Jika server sudah memberikan parameter notification, Android OS otomatis menampilkannya
  // saat aplikasi di background/terminated. Kita skip agar tidak double notifikasi.
  if (message.notification != null) {
    debugPrint('📨 Background message has notification payload. OS will handle it.');
    return;
  }

  // Jika server hanya mengirim 'data' payload (seperti WA/Telegram), 
  // kita harus membangun local notification secara manual di background.
  try {
    final data = message.data;
    if (data.isEmpty) return;

    final roomId = data['roomId'] ?? data['id'] ?? data['room_id'];
    final senderName = data['senderName'] ?? data['sender_name'] ?? data['sender'] ?? 'Pesan Baru';
    final messageText = data['message'] ?? data['body'] ?? data['text'] ?? 'Kamu menerima pesan baru';
    final roomName = data['roomName'] ?? data['room_name'] ?? senderName;

    if (roomId != null) {
      // Inisialisasi plugin khusus untuk background isolate ini
      final localNotifications = FlutterLocalNotificationsPlugin();
      const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInitSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInitSettings, iOS: iosInitSettings);
      await localNotifications.initialize(initSettings);

      const androidDetails = AndroidNotificationDetails(
        'nobox_chat_channel',
        'Nobox Chat',
        channelDescription: 'Pemberitahuan pesan masuk Nobox',
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: DefaultStyleInformation(true, true), // Agar teks panjang tidak terpotong
        category: AndroidNotificationCategory.message,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final payloadString = jsonEncode({'roomId': roomId, 'roomName': roomName});

      await localNotifications.show(
        roomId.hashCode,
        senderName,
        messageText,
        const NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payloadString,
      );
      debugPrint('✅ Background notification shown for room: $roomId');
    }
  } catch (e) {
    debugPrint('❌ Error handling background message: $e');
  }
}

// =====================================================================
// FITUR: Layanan Notifikasi Push (FCM & Local)
// FILE: lib/core/services/push_notification_service.dart
// BARIS AWAL: 76 (setelah komentar ini)
// FUNGSI: Mengelola integrasi Firebase Cloud Messaging (FCM), notifikasi lokal, dan aksi ketukan notifikasi.
// =====================================================================
class PushNotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static const MethodChannel _notificationChannel = MethodChannel('ai.nobox.android/notification');
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  static Function(String roomId, String roomName)? _onNotificationTap;
  static bool _isInitialized = false;
  static String? _currentRoomId;
  static final Map<String, List<Map<String, String>>> _notificationMessages = {};

  static Future<void> initialize({
    Function(String roomId, String roomName)? onNotificationTap,
  }) async {
    if (_isInitialized) return;
    _onNotificationTap = onNotificationTap;

    try {
      // Menangkap ketukan dari Native notification (Notifikasi bawaan Android/iOS)
      _notificationChannel.setMethodCallHandler((call) async {
        if (call.method == 'openChat') {
          final roomId = call.arguments['roomId'] as String?;
          final roomName = call.arguments['roomName'] as String?;
          if (roomId != null && roomName != null) {
            debugPrint('📱 Opening chat from native notification: $roomId');
            _onNotificationTap?.call(roomId, roomName);
          }
        }
      });

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await _initializeLocalNotifications();
      await _initializeFirebaseMessaging();

      _isInitialized = true;
      debugPrint('✅ Push notification service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize push notifications: $e');
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    const androidChannel = AndroidNotificationChannel(
      'chat_notifications',
      'Chat Notifications',
      description: 'Notifications for new chat messages',
      importance: Importance.max, // Penting maksimal agar notifikasi muncul melayang (heads-up)
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<void> _initializeFirebaseMessaging() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true, badge: true, sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ Push notification permission granted');
      
      // Pengambilan token FCM - non-fatal jika Google Play Services tidak tersedia
      try {
        String? token = await _firebaseMessaging.getToken();
        if (token != null) {
          debugPrint('📱 FCM Token: $token');
          await syncTokenWithBackend(token);
        }
      } catch (e) {
        debugPrint('⚠️ FCM token retrieval failed (Google Play Services mungkin tidak tersedia): $e');
        debugPrint('⚠️ Local notifications tetap aktif, tapi push dari server tidak akan bekerja');
      }

      _firebaseMessaging.onTokenRefresh.listen((token) {
        syncTokenWithBackend(token);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      try {
        RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
        if (initialMessage != null) _handleNotificationTap(initialMessage);
      } catch (e) {
        debugPrint('⚠️ getInitialMessage failed: $e');
      }
      
    } else {
      debugPrint('❌ Push notification permission denied');
    }
  }

  static Future<void> syncTokenWithBackend(String token) async {
    try {
      final secureStorage = const FlutterSecureStorage();
      await secureStorage.write(key: 'fcm_token', value: token);
      
      // Mengirim token ke backend agar server bisa mengirim push notification ke perangkat ini
      try {
        await ApiClient().post('Notify/Subs', data: {
          'Endpoint': token,
          'Auth': '',
          'P256DH': '',
        });
        debugPrint('✅ FCM Token synced to backend');
      } catch (e) {
        debugPrint('⚠️ FCM token sync to backend failed: $e');
        debugPrint('⚠️ Push notifications dari server tidak akan bekerja');
      }
      
      debugPrint('✅ FCM Token saved locally');
    } catch (e) {
      debugPrint('⚠️ FCM token sync warning: $e');
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        final roomId = data['roomId'] as String?;
        final roomName = data['roomName'] as String?;

        if (roomId != null && roomName != null) {
          _onNotificationTap?.call(roomId, roomName);
        }
      } catch (e) {
        debugPrint('❌ Error parsing notification payload: $e');
      }
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final roomId = data['roomId'];

    if (_currentRoomId != null && _currentRoomId == roomId) return;

    if (roomId != null) {
      // 🔕 FIX DOUBLE NOTIFICATION: Disabled because SignalR already handles
      // ReceiveMessage and triggers notifications in foreground.
      // Keeping this would cause duplicate notifications (FCM + SignalR).
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final roomId = data['roomId'];
    final roomName = data['roomName'] ?? 'Chat';

    if (roomId != null) {
      _onNotificationTap?.call(roomId, roomName);
    }
  }

  static Future<String?> _downloadAndSaveImage(String url) async {
    // Download image asynchronously (non-blocking) - no need for isolate
    // since this is already async and runs on a background thread pool
    return _downloadAndSaveImageFallback(url);
  }

  /// Download and save image for notification - runs async on background thread
  static Future<String?> _downloadAndSaveImageFallback(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = url.hashCode.toString();
        final file = File('${tempDir.path}/$fileName.jpg');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download profile image: $e');
    }
    return null;
  }

  static Future<void> showChatNotification({
    required String roomId,
    required String roomName,
    required String senderName,
    required String message,
    String? profileImageUrl,
  }) async {
    try {
      if (!_notificationMessages.containsKey(roomId)) {
        _notificationMessages[roomId] = [];
      }
      _notificationMessages[roomId]!.add({
        'sender': senderName,
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      if (_notificationMessages[roomId]!.length > 10) {
        _notificationMessages[roomId]!.removeAt(0);
      }

      AndroidBitmap<Object>? largeIcon;
      if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
        try {
          String? imagePath;
          if (profileImageUrl.startsWith('http://') || profileImageUrl.startsWith('https://')) {
            imagePath = await _downloadAndSaveImage(profileImageUrl);
          } else {
            imagePath = profileImageUrl;
          }
          if (imagePath != null) largeIcon = FilePathAndroidBitmap(imagePath);
        } catch (e) {
          debugPrint('⚠️ Profile image load error: $e');
        }
      }

      final bigTextStyle = BigTextStyleInformation(
        message,
        htmlFormatBigText: true,
        contentTitle: senderName,
        htmlFormatContentTitle: true,
        summaryText: roomName,
        htmlFormatSummaryText: true,
      );

      final androidDetails = AndroidNotificationDetails(
        'chat_notifications',
        'Chat Notifications',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: const Color(0xFF3B82F6),
        largeIcon: largeIcon,
        styleInformation: bigTextStyle,
        groupKey: 'chat_$roomId',
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);

      final payload = jsonEncode({'roomId': roomId, 'roomName': roomName});

      await _localNotifications.show(
        roomId.hashCode,
        senderName,
        message,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('❌ Error showing chat notification: $e');
    }
  }

  static Future<void> cancelNotificationsForRoom(String roomId) async {
    await _localNotifications.cancel(roomId.hashCode);
    _notificationMessages.remove(roomId);
  }

  static String? get currentRoomId => _currentRoomId;

  static void setCurrentRoom(String? roomId) {
    _currentRoomId = roomId;
  }
}
