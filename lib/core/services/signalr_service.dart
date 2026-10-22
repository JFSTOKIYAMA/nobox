import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import 'push_notification_service.dart';

// =====================================================================
// FITUR: Layanan SignalR (Real-time / WebSocket)
// FILE: lib/core/services/signalr_service.dart
// BARIS AWAL: 17 (setelah komentar ini)
// FUNGSI: Mengelola koneksi real-time via SignalR untuk pesan instan.
//         Mendengarkan event: TerimaPesan, TerimaSubSpv, UcChanged, TerimaExpired.
// =====================================================================

// SignalRService terhubung ke server hub SignalR menggunakan Token JWT setelah login berhasil.
class SignalRService {
  static final SignalRService _instance = SignalRService._internal();
  factory SignalRService() => _instance;
  SignalRService._internal();

  HubConnection? _hubConnection;
  bool _isConnected = false;
  bool _isSubscribed = false;
  bool get isConnected => _isConnected;

  /// Callback ketika server memberi sinyal bahwa sesi/room kedaluwarsa (TerimaExpired).
  /// Atur ini dari lapisan aplikasi untuk menampilkan dialog atau memaksa logout.
  Function? onSessionExpired;

  // ── NoBox Server Event Names ──
  static const String eventTerimaPesan = 'TerimaPesan';
  static const String eventTerimaSubSpv = 'TerimaSubSpv';
  static const String eventTerimaSubAgent = 'TerimaSubAgent';
  static const String eventUcChanged = 'UcChanged';
  static const String eventTerimaExpired = 'TerimaExpired';
  static const String eventTerimaBlockUnblock = 'TerimaBlockUnblock';

  // ── Generic stream (backward-compatible) ──
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived =>
      _messageController.stream;

  // ── Typed streams for specific events ──
  final _terimaPesanController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTerimaPesan =>
      _terimaPesanController.stream;

  // ── Cached Messages (Fix race condition) ──
  final Map<String, List<Map<String, dynamic>>> _recentTerimaPesan = {};

  List<Map<String, dynamic>> getRecentMessagesForRoom(String roomId) {
    return _recentTerimaPesan[roomId] ?? [];
  }

  final _terimaSubSpvController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTerimaSubSpv =>
      _terimaSubSpvController.stream;

  final _ucChangedController = StreamController<int>.broadcast();
  Stream<int> get onUcChanged => _ucChangedController.stream;

  // ── Connection state stream ──
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionStateChanged =>
      _connectionStateController.stream;

  final _blockUnblockController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onBlockUnblock =>
      _blockUnblockController.stream;

  // Cache deduplikasi event TerimaSubSpv & TerimaSubAgent ganda
  String _lastProcessedSubSpvKey = '';
  DateTime _lastProcessedSubSpvTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hubungkan ke SignalR hub menggunakan token autentikasi pengguna.
  // FITUR 3: Terhubung ke server hub SignalR menggunakan Token JWT.
  // [ACTION: SIGNALR_CONNECT] - Membangun dan menjaga koneksi Web-Socket real-time
  // OPTIMIZED: Non-blocking, cached token, reduced main-thread work
  Future<void> connect() async {
    if (_hubConnection != null) {
      if (_hubConnection!.state == HubConnectionState.Connected) {
        debugPrint('SignalR: Already connected');
        _isConnected = true;
        return;
      }
      if (_hubConnection!.state == HubConnectionState.Disconnected) {
        debugPrint('SignalR: Reconnecting existing disconnected hub...');
        try {
          await _hubConnection!.start();
          _isConnected = true;
          _isSubscribed = false;
          _connectionStateController.add(true);
          debugPrint('SignalR: ✅ Reconnected successfully!');
          // CRITICAL: Re-subscribe setelah reconnect
          unawaited(_subscribeUser());
          return;
        } catch (e) {
          debugPrint(
            'SignalR: ❌ Reconnection failed, building new connection: $e',
          );
          // Fall through to build a new connection
        }
      }
    }

    try {
      debugPrint('SignalR: Connecting to ${AppConfig.signalRUrl}...');

      // Use cached token factory to avoid repeated SecureStorage reads
      _hubConnection = HubConnectionBuilder()
          .withUrl(
            AppConfig.signalRUrl,
            options: HttpConnectionOptions(
              requestTimeout: 30000,
              accessTokenFactory: _cachedTokenFactory,
            ),
          )
          .withAutomaticReconnect()
          .build();

      // Perbesar timeout agar tidak mudah disconnect di jaringan mobile
      _hubConnection!.serverTimeoutInMilliseconds =
          30000; // 30 detik (default 2 detik)
      _hubConnection!.keepAliveIntervalInMilliseconds = 15000; // 15 detik

      // ── Register handlers for NoBox events ──
      _registerEventHandlers();

      // Start the connection with timeout to prevent ANR
      final conn = _hubConnection;
      if (conn == null) throw Exception('SignalR hubConnection is null');
      final startFuture = conn.start();
      if (startFuture != null) {
        await startFuture.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('SignalR connection timeout (10s)');
          },
        );
      }
      _isConnected = true;
      _connectionStateController.add(true);
      debugPrint('SignalR: ✅ Connected successfully!');
      debugPrint('SignalR: ConnectionId = ${_hubConnection!.connectionId}');

      // CRITICAL: Subscribe user agar server tahu harus kirim event ke koneksi ini
      // (Seperti project mentor: SubscribeUserAgent + SubscribeUserSpv)
      // Run subscription in background, don't await
      unawaited(_subscribeUser());
      if (_currentJoinedRoomId != null && _currentJoinedRoomId!.isNotEmpty) {
        unawaited(joinConversation(_currentJoinedRoomId!));
      }
    } catch (e, stack) {
      debugPrint('SignalR: ❌ Connection failed: $e');
      debugPrint('Stack: $stack');
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }

  /// Cached token factory - avoids repeated SecureStorage reads
  static String? _cachedToken;
  static DateTime? _tokenCacheTime;
  static const _tokenCacheTtl = Duration(minutes: 5);

  Future<String> _cachedTokenFactory() async {
    // Return cached token if still valid
    if (_cachedToken != null &&
        _tokenCacheTime != null &&
        DateTime.now().difference(_tokenCacheTime!) < _tokenCacheTtl) {
      return _cachedToken!;
    }

    // Read fresh token
    String? token;
    try {
      const storage = FlutterSecureStorage();
      token = await storage.read(key: AppConfig.tokenKey);
    } catch (e) {
      debugPrint('SignalR: SecureStorage read error: $e');
    }

    if (token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(AppConfig.tokenKey);
      if (token != null && token.isNotEmpty) {
        debugPrint(
          'SignalR: Token recovered from SharedPreferences fallback',
        );
      }
    }

    _cachedToken = token ?? '';
    _tokenCacheTime = DateTime.now();
    return _cachedToken!;
  }

  void _registerEventHandlers() {
    // [ACTION: SIGNALR_RECEIVE_MSG] - Menerima balasan pesan/chat masuk secara real-time
    _hubConnection!.on(eventTerimaPesan, (args) {
      _handleTerimaPesan(args);
    });

    _hubConnection!.on(eventTerimaSubSpv, (args) {
      _handleTerimaSubSpv(args);
    });

    _hubConnection!.on(eventTerimaSubAgent, (args) {
      _handleTerimaSubSpv(args);
    });

    _hubConnection!.on(eventUcChanged, (args) {
      _handleUcChanged(args);
    });

    _hubConnection!.on(eventTerimaExpired, (args) {
      _handleTerimaExpired(args);
    });

    _hubConnection!.on(eventTerimaBlockUnblock, (args) {
      _handleTerimaBlockUnblock(args);
    });

    // ── Connection state handlers ──
    _hubConnection!.onclose(({error}) {
      debugPrint('SignalR: Connection closed. Error: $error');
      _isConnected = false;
      _connectionStateController.add(false);
    });

    _hubConnection!.onreconnecting(({error}) {
      debugPrint('SignalR: Reconnecting... Error: $error');
      _isConnected = false;
      _connectionStateController.add(false);
    });

    _hubConnection!.onreconnected(({connectionId}) {
      debugPrint('SignalR: Reconnected! ConnectionId: $connectionId');
      _isConnected = true;
      _isSubscribed = false;
      _connectionStateController.add(true);
      // Re-subscribe setelah reconnect (seperti project mentor)
      unawaited(_subscribeUser());
      final currentRoom = PushNotificationService.currentRoomId;
      if (currentRoom != null && currentRoom.isNotEmpty) {
        unawaited(joinConversation(currentRoom));
      }
      if (_currentJoinedRoomId != null && _currentJoinedRoomId!.isNotEmpty) {
        unawaited(joinConversation(_currentJoinedRoomId!));
      }
    });
  }

  // ══════════════════════════════════════════════
  //  User Subscription (CRITICAL - dari project mentor)
  // ══════════════════════════════════════════════

  /// Mendaftarkan (subscribe) pengguna ke hub SignalR agar menerima event.
  /// Tanpa ini, server TIDAK akan mengirim TerimaPesan, TerimaSubSpv, dll.
  // OPTIMIZED: Uses compute for JWT decoding, parallel storage reads
  Future<void> _subscribeUser() async {
    if (_hubConnection == null ||
        _hubConnection!.state != HubConnectionState.Connected) {
      debugPrint('SignalR: ⚠️ Cannot subscribe - not connected');
      return;
    }

    try {
      const storage = FlutterSecureStorage();

      // 1. Read token and tenantId in PARALLEL
      final results = await Future.wait([
        storage.read(key: 'auth_token'),
        storage.read(key: 'tenant_id'),
      ]);
      
      final token = results[0];
      final tenantId = results[1];

      if (token == null) {
        debugPrint('SignalR: ⚠️ Cannot subscribe - no token');
        return;
      }

      if (tenantId == null || tenantId.isEmpty) {
        debugPrint(
          'SignalR: ⚠️ TenantId not available yet, subscription deferred',
        );
        return;
      }

      // 2. Decode JWT on background isolate to avoid blocking main thread
      final userId = await compute(_extractUserIdFromToken, token);

      debugPrint(
        'SignalR: 📡 Subscribing user - UserId: $userId, TenantId: $tenantId',
      );

      // 3. Subscribe as Agent & Supervisor in PARALLEL
      await Future.wait([
        _hubConnection!.invoke('SubscribeUserAgent', args: [userId, tenantId])
            .then((_) => debugPrint('SignalR: ✅ Subscribed as Agent'))
            .catchError((e) => debugPrint('SignalR: ❌ SubscribeUserAgent failed: $e')),
        _hubConnection!.invoke('SubscribeUserSpv', args: [tenantId])
            .then((_) => debugPrint('SignalR: ✅ Subscribed as Supervisor'))
            .catchError((e) => debugPrint('SignalR: ⚠️ SubscribeUserSpv failed: $e')),
      ]);

      _isSubscribed = true;
      debugPrint(
        'SignalR: 🎉 Subscription complete - ready to receive real-time events!',
      );
    } catch (e) {
      debugPrint('SignalR: ❌ Subscription failed: $e');
    }
  }

  /// Extract userId from JWT token - runs on background isolate via compute()
  static String _extractUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = base64Url.normalize(parts[1]);
        final decoded = utf8.decode(base64Url.decode(payload));
        final payloadMap = jsonDecode(decoded);
        return payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
               payloadMap['nameid'] ??
               payloadMap['sub'] ??
               '1';
      }
    } catch (e) {
      debugPrint('SignalR: ⚠️ Failed to decode JWT: $e');
    }
    return '1';
  }

  /// Public method: dipanggil dari ChatService setelah tenantId tersedia.
  /// Kalau sudah subscribe, skip. Kalau belum, subscribe sekarang.
  Future<void> trySubscribe() async {
    if (_isSubscribed) {
      debugPrint('SignalR: Already subscribed, skip');
      return;
    }
    if (!_isConnected) {
      debugPrint('SignalR: Not connected yet, cannot subscribe');
      return;
    }
    debugPrint('SignalR: 🔄 trySubscribe called - attempting subscription...');
    unawaited(_subscribeUser());
  }

  // ══════════════════════════════════════════════
  //  Event Handlers
  // ══════════════════════════════════════════════

  /// Handle incoming chat message (TerimaPesan).
  ///
  /// args[0] = "RoomId{id}" (String with prefix)
  /// args[1] = JSON string of message data ({Id, RoomId, Msg, From, To, Type, Files, ...})
  /// args[2] = 0 (int)
  /// args[3] = JSON string of sender info ({Name, Photo}) — optional
  void _handleTerimaPesan(List<Object?>? arguments) {
    if (arguments == null || arguments.length < 2) {
      debugPrint(
        'SignalR: TerimaPesan - invalid arguments (length: ${arguments?.length})',
      );
      return;
    }

    try {
      // Extract room ID from "RoomId794312812470277" format
      final roomIdRaw = arguments[0]?.toString() ?? '';
      final roomId = roomIdRaw.replaceFirst('RoomId', '');

      // Parse message JSON
      Map<String, dynamic> messageData = {};
      if (arguments[1] is String) {
        messageData =
            jsonDecode(arguments[1] as String) as Map<String, dynamic>;
      } else if (arguments[1] is Map) {
        messageData = Map<String, dynamic>.from(arguments[1] as Map);
      }

      // Parse sender info (optional, args[3])
      Map<String, dynamic>? senderData;
      if (arguments.length > 3 && arguments[3] is String) {
        try {
          senderData =
              jsonDecode(arguments[3] as String) as Map<String, dynamic>;
        } catch (e) {
          debugPrint(
            'Error caught at _handleTerimaPesan (parse senderData): $e',
          );
        }
      }

      final msgContent = messageData['Msg']?.toString() ?? '';
      final msgType = messageData['Type']?.toString() ?? messageData['type']?.toString() ?? messageData['BodyType']?.toString() ?? '';
      
      // DEBUG: Log tipe pesan untuk diagnosis pesan edit
      if (msgType.isNotEmpty && msgType != '1') {
        debugPrint('🔍 SignalR: Message received | Type=$msgType | Content="${msgContent.length > 100 ? msgContent.substring(0, 100) : msgContent}" | Room=$roomId');
      }
      
      if (msgContent == 'Site.Inbox.DeletedMessage') {
        debugPrint(
          'SignalR: 🚫 Ignoring Site.Inbox.DeletedMessage to preserve local last message',
        );
        return;
      }

      // FIX: Jangan proses pesan Telegram "Saved Messages" (Pesan Tersimpan ke diri sendiri)
      final sdrName = senderData?['Name']?.toString().toLowerCase() ?? '';
      final msgSender = messageData['Sender']?.toString().toLowerCase() ?? '';
      final msgSenderName = messageData['SenderName']?.toString().toLowerCase() ?? '';

      final isSavedMessage = (sdrName == 'saved messages' || sdrName == 'pesan tersimpan' ||
          msgSender == 'saved messages' || msgSender == 'pesan tersimpan' ||
          msgSenderName == 'saved messages' || msgSenderName == 'pesan tersimpan');

      if (isSavedMessage) {
        debugPrint('SignalR: 🛡️ Ignoring Telegram Saved Message to preserve chat list');
        return;
      }

      final Map<String, dynamic> parsed = {
        'roomId': roomId,
        'message': messageData,
        'sender': senderData,
      };

      // Simpan di cache lokal untuk race condition
      _recentTerimaPesan.putIfAbsent(roomId, () => <Map<String, dynamic>>[]);
      _recentTerimaPesan[roomId]!.add(parsed);
      if (_recentTerimaPesan[roomId]!.length > 50) {
        _recentTerimaPesan[roomId]!.removeAt(0);
      }

      debugPrint(
        'SignalR: 📩 TerimaPesan | room=$roomId | msg=${messageData['Msg']}',
      );

      // Emit to typed stream (untuk consumer lain: chat_detail_page, dll)
      _terimaPesanController.add(parsed);

      // Emit to generic stream
      _messageController.add({
        'method': eventTerimaPesan,
        'arguments': [messageData],
        'parsed': parsed,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // ── Langsung trigger notifikasi dari sini (seperti project mentor) ──
      _handleNewMessageNotification(roomId, messageData, senderData);
    } catch (e) {
      debugPrint('SignalR: ❌ Error parsing TerimaPesan: $e');
    }
  }

  /// Tampilkan notifikasi untuk pesan masuk baru.
  /// Dipanggil langsung dari _handleTerimaPesan (seperti project mentor).
  ///
  /// Suppression rules:
  /// - Skip jika pesan dari agent (agentId > 0)
  /// - Skip jika user sedang di room yang sama
  /// - Skip jika pesan kosong
  void _handleNewMessageNotification(
    String roomId,
    Map<String, dynamic> messageData,
    Map<String, dynamic>? senderData,
  ) {
    try {
      final msgText = messageData['Msg']?.toString() ?? '';
      final senderName = senderData?['Name']?.toString() ?? 'Pesan Baru';
      final isMe =
          messageData['IsMe'] == true ||
          messageData['LastIsMe'] == true ||
          senderName.toLowerCase() == 'you';

      // Skip notifikasi untuk pesan dari kita sendiri
      if (isMe) {
        debugPrint('SignalR: 🔕 Skip notification (own message) room=$roomId');
        return;
      }

      // Skip jika pesan kosong
      if (msgText.isEmpty) {
        debugPrint(
          'SignalR: 🔕 Skip notification (empty message) room=$roomId',
        );
        return;
      }

      // Skip jika user sedang membuka room ini
      final currentRoomId = PushNotificationService.currentRoomId;
      if (currentRoomId != null &&
          (currentRoomId == roomId || currentRoomId.endsWith(roomId))) {
        debugPrint('SignalR: 🔕 Skip notification (user in room) room=$roomId');
        return;
      }

      // Tampilkan notifikasi (DIPINDAHKAN KE chat_provider.dart)
      // SignalR service tidak bisa secara akurat membedakan pesan dari diri sendiri (akibat bug backend NoBox).
      // Oleh karena itu, tugas memanggil PushNotificationService.showChatNotification dipindahkan
      // ke dalam ChatProvider -> updateRoomFromSignalR yang memiliki pencocokan teks (isMeFallback).
      debugPrint(
        'SignalR: 🔔 Delegating notification to ChatProvider for room=$roomId sender=$senderName',
      );
    } catch (e) {
      debugPrint('SignalR: ❌ Error delegating notification: $e');
    }
  }

  /// Handle room/subscription update (TerimaSubSpv).
  ///
  /// args[0] = tenantId (int)
  /// args[1] = JSON string of room data ({Id, St, Ct, LastMsg, Uc, TimeMsg, ...})
  void _handleTerimaSubSpv(List<Object?>? arguments) {
    if (arguments == null || arguments.length < 2) {
      debugPrint(
        'SignalR: TerimaSubSpv - invalid arguments (length: ${arguments?.length})',
      );
      return;
    }

    try {
      final tenantId = arguments[0]?.toString() ?? '';

      Map<String, dynamic> roomData = {};
      if (arguments[1] is String) {
        roomData = jsonDecode(arguments[1] as String) as Map<String, dynamic>;
      } else if (arguments[1] is Map) {
        roomData = Map<String, dynamic>.from(arguments[1] as Map);
      }

      // FIX: Jangan proses update room dari "Saved Messages"
      final ctName = (roomData['Ct'] ?? roomData['CtRealNm'] ?? roomData['Name'] ?? '').toString().toLowerCase();
      final isSavedSub = (ctName == 'saved messages' || ctName == 'pesan tersimpan');
      if (isSavedSub) {
        debugPrint('SignalR: 🛡️ Ignoring TerimaSubSpv for Saved Messages');
        return;
      }

      final roomId = roomData['Id']?.toString() ?? '';
      final lastMsg = roomData['LastMsg']?.toString() ?? '';
      final timeMsg = roomData['TimeMsg']?.toString() ?? '';
      final uc = roomData['Uc']?.toString() ?? '';

      // Deduplikasi event ganda (misal server broadcast TerimaSubSpv & TerimaSubAgent sekaligus)
      final dedupeKey = '${roomId}_${lastMsg}_${timeMsg}_$uc';
      final now = DateTime.now();
      if (dedupeKey == _lastProcessedSubSpvKey &&
          now.difference(_lastProcessedSubSpvTime).inMilliseconds < 1200) {
        debugPrint(
          'SignalR: ⏩ Skipping duplicate TerimaSubSpv/SubAgent for room $roomId within 1200ms',
        );
        return;
      }
      _lastProcessedSubSpvKey = dedupeKey;
      _lastProcessedSubSpvTime = now;

      final parsed = {'tenantId': tenantId, 'room': roomData};

      debugPrint(
        'SignalR: 🏠 TerimaSubSpv | room=${roomData['Id']} | lastMsg=${roomData['LastMsg']} | uc=${roomData['Uc']}',
      );

      // Emit to typed stream
      _terimaSubSpvController.add(parsed);

      // Emit to generic stream
      _messageController.add({
        'method': eventTerimaSubSpv,
        'arguments': [roomData],
        'parsed': parsed,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // ── Trigger notifikasi dari TerimaSubSpv (server kirim ini untuk pesan masuk) ──
      _handleSubSpvNotification(roomData);
    } catch (e) {
      debugPrint('SignalR: ❌ Error parsing TerimaSubSpv: $e');
    }
  }

  /// Tampilkan notifikasi dari TerimaSubSpv event.
  /// Server mengirim event ini saat ada pesan masuk, berisi data room + lastMsg + uc.
  void _handleSubSpvNotification(Map<String, dynamic> roomData) {
    try {
      final roomId = roomData['Id']?.toString() ?? '';
      final uc = roomData['Uc'];
      final lastMsg = roomData['LastMsg']?.toString() ?? '';
      final contactName =
          roomData['CtRealNm']?.toString() ??
          roomData['Ct']?.toString() ??
          roomData['Grp']?.toString() ??
          'Pesan Baru';
      final upBy = roomData['UpBy'];

      // Skip jika unread count = 0 (bukan pesan masuk baru, mungkin update status saja)
      if (uc == null || uc == 0) {
        debugPrint('SignalR: 🔕 Skip SubSpv notification (uc=0) room=$roomId');
        return;
      }

      // Skip jika pesan terakhir dari agent (pesan keluar, bukan masuk)
      if (upBy != null && upBy.toString() != '0') {
        // upBy biasanya diisi userId agent yang mengirim pesan
        // Tapi untuk pesan masuk dari customer, upBy bisa null atau 0
        // Kita cek apakah lastMsg berubah karena pesan customer
      }

      // Skip jika pesan kosong
      if (lastMsg.isEmpty) {
        debugPrint(
          'SignalR: 🔕 Skip SubSpv notification (empty message) room=$roomId',
        );
        return;
      }

      // Skip jika user sedang membuka room ini
      final currentRoomId = PushNotificationService.currentRoomId;
      if (currentRoomId != null &&
          (currentRoomId == roomId || currentRoomId.endsWith(roomId))) {
        debugPrint(
          'SignalR: 🔕 Skip SubSpv notification (user in room) room=$roomId',
        );
        return;
      }

      // 🔔 NOTIFIKASI DIHIDUPKAN KEMBALI DI SINI
      // Pemanggilan notifikasi di ChatProvider terlalu mudah error karena pengecekan waktu,
      // sehingga menyebabkan notifikasi Android mati/hilang. Di sini tempat yang paling aman.
      debugPrint(
        'SignalR: 🔔 Notification from SubSpv | room=$roomId | sender=$contactName | msg=$lastMsg',
      );
      PushNotificationService.showChatNotification(
        roomId: roomId,
        roomName: contactName,
        senderName: contactName,
        message: lastMsg,
        profileImageUrl:
            roomData['CtImg']?.toString() ?? roomData['LinkImg']?.toString(),
      );
    } catch (e) {
      debugPrint('SignalR: ❌ Error in SubSpv notification: $e');
    }
  }

  /// Handle unread count change (UcChanged).
  ///
  /// args[0] = total unread count (int)
  void _handleUcChanged(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;

    try {
      final count = arguments[0] is int
          ? arguments[0] as int
          : int.tryParse(arguments[0].toString()) ?? 0;

      debugPrint('SignalR: 🔢 UcChanged: $count');

      // Emit to typed stream
      _ucChangedController.add(count);

      // Emit to generic stream
      _messageController.add({
        'method': eventUcChanged,
        'arguments': arguments,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SignalR: ❌ Error parsing UcChanged: $e');
    }
  }

  /// Handle session expired (TerimaExpired).
  ///
  /// args[0] = roomId
  /// args[1] = timestamp (String)
  /// args[2] = message (String)
  /// args[3] = bool
  void _handleTerimaExpired(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;

    try {
      debugPrint('SignalR: ⏰ TerimaExpired | room=${arguments[0]}');

      _messageController.add({
        'method': eventTerimaExpired,
        'arguments': arguments,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Notify the app layer so it can show a dialog / force logout
      onSessionExpired?.call();
    } catch (e) {
      debugPrint('SignalR: ❌ Error parsing TerimaExpired: $e');
    }
  }

  /// Handle TerimaBlockUnblock event
  /// args[0] = roomId, args[1] = status, args[2] = contactId, args[3] = blockStatus (1=blocked, 0=unblocked)
  void _handleTerimaBlockUnblock(List<Object?>? arguments) {
    if (arguments == null || arguments.length < 4) return;
    try {
      final roomId = arguments[0]?.toString() ?? '';
      final contactId = arguments[2]?.toString() ?? '';
      final blockStatus = arguments[3];
      final isBlocked =
          blockStatus == 1 || blockStatus == '1' || blockStatus == true;

      debugPrint(
        'SignalR: 🚫 TerimaBlockUnblock | room=$roomId | isBlocked=$isBlocked',
      );

      _blockUnblockController.add({
        'roomId': roomId,
        'contactId': contactId,
        'isBlocked': isBlocked,
      });
    } catch (e) {
      debugPrint('SignalR: ❌ Error parsing TerimaBlockUnblock: $e');
    }
  }

  // ══════════════════════════════════════════════
  //  Client → Server Methods
  // ══════════════════════════════════════════════

  /// Invoke a method on the hub (fire-and-forget).
  Future<void> invoke(String methodName, {List<Object>? args}) async {
    if (!_isConnected || _hubConnection == null) {
      debugPrint(
        'SignalR: Not connected. Attempting to reconnect before invoking "$methodName"...',
      );
      await connect();
      if (!_isConnected || _hubConnection == null) {
        debugPrint(
          'SignalR: Cannot invoke "$methodName" — reconnection failed.',
        );
        throw Exception('SignalR not connected');
      }
    }
    try {
      debugPrint('SignalR: Invoking "$methodName" with args: $args');
      await _hubConnection!.invoke(methodName, args: args);
      debugPrint('SignalR: ✅ "$methodName" invoked successfully');
    } catch (e) {
      debugPrint('SignalR: ❌ Error sending "$methodName": $e');
      rethrow;
    }
  }

  /// Mark messages as read for a room (sends ReadMsgCount to server).
  Future<void> sendReadCount(int roomId) async {
    try {
      await invoke('ReadMsgCount', args: [roomId]);
    } catch (e) {
      debugPrint('SignalR: Failed to send ReadMsgCount for room $roomId: $e');
    }
  }

  String? _currentJoinedRoomId;

  /// Join a conversation room group in SignalR so the server streams TerimaPesan directly.
  Future<void> joinConversation(dynamic roomId) async {
    final rawRoomStr = roomId?.toString().trim() ?? '';
    String cleanRoomStr = rawRoomStr;
    if (rawRoomStr.contains('_')) {
      cleanRoomStr = rawRoomStr.split('_').last;
    }
    final parsedIdRoom = int.tryParse(cleanRoomStr.replaceAll(RegExp(r'[^0-9\-]'), ''));
    final joinRoomId = parsedIdRoom?.toString() ?? cleanRoomStr;
    if (joinRoomId.isEmpty || joinRoomId == '0' || joinRoomId == 'null') return;

    _currentJoinedRoomId = joinRoomId;

    if (_hubConnection == null || _hubConnection!.state != HubConnectionState.Connected) {
      debugPrint('SignalR: ⚠️ Cannot JoinConversation yet (not connected) - Room $joinRoomId will join upon connect');
      return;
    }
    try {
      debugPrint('SignalR: 🚪 Invoking JoinConversation for Room $joinRoomId');
      try {
        await invoke('JoinConversation', args: [joinRoomId, ""]);
      } catch (e) {
        if (parsedIdRoom != null) {
          await invoke('JoinConversation', args: [parsedIdRoom, ""]);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('SignalR: ⚠️ JoinConversation failed: $e');
    }
  }

  /// Leave a conversation room group in SignalR.
  Future<void> leaveConversation(dynamic roomId) async {
    _currentJoinedRoomId = null;
    if (_hubConnection == null || _hubConnection!.state != HubConnectionState.Connected) {
      return;
    }
    try {
      final rawRoomStr = roomId?.toString().trim() ?? '';
      String cleanRoomStr = rawRoomStr;
      if (rawRoomStr.contains('_')) {
        cleanRoomStr = rawRoomStr.split('_').last;
      }
      final parsedIdRoom = int.tryParse(cleanRoomStr.replaceAll(RegExp(r'[^0-9\-]'), ''));
      final joinRoomId = parsedIdRoom?.toString() ?? cleanRoomStr;
      if (joinRoomId.isEmpty || joinRoomId == '0' || joinRoomId == 'null') return;
      debugPrint('SignalR: 🚪 Invoking LeaveConversation for Room $joinRoomId');
      await invoke('LeaveConversation', args: [joinRoomId, ""]);
    } catch (_) {
      // Backend may not implement LeaveConversation, safe to ignore
    }
  }

  /// Invoke ContactBlockUnblock
  Future<bool> invokeBlockUnblock({
    required dynamic roomId,
    required dynamic status,
    required dynamic contactId,
    required bool shouldBlock,
  }) async {
    final blockValue = shouldBlock ? 1 : 0;
    try {
      final roomIdInt = roomId is int
          ? roomId
          : int.tryParse(roomId.toString()) ?? 0;
      final contactIdInt = contactId is int
          ? contactId
          : int.tryParse(contactId.toString()) ?? 0;
      final statusInt = status is int
          ? status
          : int.tryParse(status.toString()) ?? 0;

      debugPrint(
        'SignalR: 🚫 Invoking ContactBlockUnblock: room=$roomIdInt, ct=$contactIdInt, block=$blockValue',
      );
      await invoke(
        'ContactBlockUnblock',
        args: [roomIdInt, statusInt, contactIdInt, blockValue],
      );
      return true;
    } catch (e) {
      debugPrint('SignalR: ❌ Failed to send ContactBlockUnblock: $e');
      return false;
    }
  }

  Future<String?> invokeKirimPesan({
    required dynamic idLink,
    required dynamic idAccount,
    required dynamic idRoom,
    dynamic idGroup,
    required String type, // "0" or "1" for text, "3" for media
    String? msg,
    String? fileJson,
    String? replyId,
    String? replyMsg,
    String? replyFrom,
    String? replyType,
    String? replyFiles,
  }) async {
    try {
      // FIX: parseIntSafe sekarang mendukung angka negatif (untuk Telegram group ID)
      // dan tidak lagi mengembalikan null untuk value 0 (0 = valid ID di beberapa konteks)
      int? parseIntSafe(dynamic val) {
        if (val == null) return null;
        final rawStr = val.toString().trim();
        if (rawStr.isEmpty || rawStr == 'null') return null;
        // Pertahankan tanda minus untuk Telegram group ID negatif
        final str = rawStr.replaceAll(RegExp(r'[^0-9\-]'), '');
        if (str.isEmpty) return null;
        final valInt = int.tryParse(str);
        // Hanya return null jika benar-benar bukan angka, BUKAN untuk 0
        return valInt;
      }

      dynamic safeNumOrString(dynamic val) {
        if (val == null) return null;
        final str = val.toString().trim();
        if (str.isEmpty) return null;
        return int.tryParse(str) ?? str;
      }

      // FIX: Type harus dikirim dalam format aslinya (biasanya string "1")
      // Jangan di-parse ke integer karena backend mungkin melakukan strict deserialization
      final msgMap = <String, dynamic>{
        "Msg": (msg == null || msg.isEmpty) ? null : msg,
        "Type": type,
      };
      if (fileJson != null && fileJson.isNotEmpty) {
        msgMap["File"] = fileJson;
      }
      msgMap["Files"] = null;

      if (replyId != null && replyId.toString().trim().isNotEmpty) {
        msgMap["ReplyId"] = safeNumOrString(replyId);
        msgMap["ReplyMsg"] = replyMsg ?? "";
        msgMap["ReplyFrom"] = safeNumOrString(replyFrom);
        msgMap["ReplyType"] = safeNumOrString(replyType ?? "0");
        msgMap["ReplyFiles"] = replyFiles;
      }

      // Parse room ID: strip prefix jika formatnya "tenantId_roomId"
      final rawRoomStr = idRoom?.toString() ?? '';
      final roomParts = rawRoomStr.split('_');
      final roomNumericPart = roomParts.length > 1 ? roomParts.last : rawRoomStr;
      final parsedIdRoom = parseIntSafe(roomNumericPart);
      final parsedIdLink = parseIntSafe(idLink);
      final parsedIdGroup = parseIntSafe(idGroup);
      final parsedIdAccount = parseIntSafe(idAccount);

      // DEBUG: Log setiap field yang sudah di-parse untuk diagnosis
      debugPrint('SignalR: ┌── KirimPesan PAYLOAD DEBUG ──');
      debugPrint('SignalR: │ Raw idRoom=$idRoom → parsed=$parsedIdRoom');
      debugPrint('SignalR: │ Raw idLink=$idLink → parsed=$parsedIdLink');
      debugPrint('SignalR: │ Raw idGroup=$idGroup → parsed=$parsedIdGroup');
      debugPrint('SignalR: │ Raw idAccount=$idAccount → parsed=$parsedIdAccount');
      debugPrint('SignalR: │ msg=${(msg ?? "").length > 50 ? msg!.substring(0, 50) : msg}');
      debugPrint('SignalR: │ type=$type → parsed=${int.tryParse(type) ?? 1}');
      debugPrint('SignalR: │ fileJson=${fileJson != null ? "present" : "null"}');
      debugPrint('SignalR: │ Connection state: ${_hubConnection?.state}');
      debugPrint('SignalR: │ isConnected=$_isConnected');
      debugPrint('SignalR: └──────────────────────────────');

      final payload = {
        "Room": {
          "IdRoom": parsedIdRoom,
          "IdLink": parsedIdLink,
          "IdGroup": parsedIdGroup,
          "IdAccount": parsedIdAccount,
        },
        "Msg": msgMap,
      };

      // Payload must be sent as a single JSON string argument according to the network log
      final jsonPayload = jsonEncode(payload);

      // FIX: JoinConversation menggunakan numeric room ID, bukan raw composite ID
      final joinRoomId = parsedIdRoom?.toString() ?? rawRoomStr;
      debugPrint('SignalR: ✉️ Invoking JoinConversation for Room $joinRoomId');
      try {
        await invoke('JoinConversation', args: [joinRoomId, ""]);
        // Beri jeda sedikit agar server sempat memproses Join
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('SignalR: ⚠️ JoinConversation failed, but continuing: $e');
      }

      debugPrint('SignalR: ✉️ Invoking KirimPesan: $jsonPayload');
      await invoke('KirimPesan', args: [jsonPayload]);
      return null; // Return null on success
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains("underlying connection being closed") ||
          errorStr.contains("Connection disconnected") ||
          errorStr.contains("invocation canceled")) {
        debugPrint(
          'SignalR: ⚠️ Connection reset after KirimPesan (likely processed by server): $errorStr',
        );
        return null; // Treat as success like in Aplikasi
      }
      debugPrint('SignalR: ❌ Failed to send KirimPesan: $e');
      return errorStr;
    }
  }

  /// Delete a message via SignalR
  Future<String?> invokeDelMsg({
    required dynamic idRoom,
    required dynamic idMsg,
  }) async {
    try {
      final safeRoomId = int.tryParse(idRoom.toString()) ?? idRoom;
      final safeMsgId = int.tryParse(idMsg.toString()) ?? idMsg;

      debugPrint('SignalR: 🗑️ Invoking DelMsg: [$safeRoomId, $safeMsgId]');
      await invoke('DelMsg', args: [safeRoomId, safeMsgId]);
      return null;
    } catch (e) {
      debugPrint('SignalR: ❌ Failed to invoke DelMsg: $e');
      return e.toString();
    }
  }

  /// Disconnect from the hub.
  Future<void> disconnect() async {
    if (_hubConnection != null) {
      await _hubConnection!.stop();
      _isConnected = false;
      _connectionStateController.add(false);
      debugPrint('SignalR: Disconnected');
    }
  }

  /// Dispose resources.
  void dispose() {
    _messageController.close();
    _terimaPesanController.close();
    _terimaSubSpvController.close();
    _ucChangedController.close();
    _connectionStateController.close();
    _blockUnblockController.close();
    disconnect();
  }
}
