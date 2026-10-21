import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/chat_status_provider.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/chat_settings_provider.dart';
import 'core/providers/locale_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/signalr_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/background_service_manager.dart';
import 'core/utils/app_routes.dart';
import 'presentation/screens/splash/splash_page.dart';
import 'presentation/screens/welcome/welcome_page.dart';
import 'presentation/screens/auth/login_page.dart';
import 'presentation/screens/chat/chat_list_page.dart';
import 'presentation/screens/chat/chat_detail_page.dart';
import 'presentation/screens/chat/archive_list_page.dart';
import 'core/utils/globals.dart';
import 'presentation/screens/home/responsive_chat_home.dart';
import 'core/model/message.dart';

void main() {
  debugPrint('App: main started');
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => ChatStatusProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider(create: (_) => ChatSettingsProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e, stack) {
    debugPrint('App: Fatal error during startup: $e');
    debugPrint(stack.toString());
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _terimaPesanSub;
  StreamSubscription<Map<String, dynamic>>? _terimaSubSpvSub;
  StreamSubscription<int>? _ucChangedSub;
  StreamSubscription<bool>? _reconnectSub;
  StreamSubscription<Map<String, dynamic>>? _blockUnblockSub;
  Timer? _messagePollingTimer;
  bool _isPolling = false;
  bool _wasInBackground = false; // Tracks if app went to background

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle (foreground/background)
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize Firebase and PushNotifications after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await PushNotificationService.initialize(
          onNotificationTap: (roomId, roomName) {
            debugPrint('Main: Notification tapped | room=$roomId | name=$roomName');
            // Navigate to ChatDetailPage using the global navigator key
            navigatorKey.currentState?.pushNamed(
              AppRoutes.chatDetail,
              arguments: ChatModel(
                id: roomId,
                sender: roomName,
                lastMessage: '',
                time: '',
              ),
            );
          },
        );
      } catch (e) {
        debugPrint('Firebase init failed (maybe google-services.json is missing): $e');
      }
      _subscribeToSignalR();
      _startMessagePolling();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('Main: App lifecycle state = $state');

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Pastikan notifikasi tidak disembunyikan/ditelan jika aplikasi berada di background!
      PushNotificationService.setCurrentRoom(null);
      
      // Mark that we went to background
      if (!_wasInBackground) {
        _wasInBackground = true;
        _messagePollingTimer?.cancel();
        _messagePollingTimer = null;
        debugPrint('🔄 Polling stopped (app in background)');
        // Start native background service to keep SignalR alive
        BackgroundServiceManager.startService();
      }
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      debugPrint('🔄 App resumed from background — restoring connections...');

      // Stop native background service (Flutter SignalR takes over)
      BackgroundServiceManager.stopService();
      _startMessagePolling();

      // Ensure SignalR reconnects if it was disconnected by the OS while suspended
      SignalRService().connect();

      // Defer heavy work to next frame so UI stays responsive
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleResumeSync();
      });
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated (killed/swiped from recent apps)
      debugPrint('🔴 App detached (terminated) — cleaning up resources...');
      _cleanupOnTerminate();
    }
  }

  /// Cleanup when app is terminated (killed/swiped from recent apps)
  void _cleanupOnTerminate() {
    debugPrint('🧹 Cleaning up on app termination...');
    
    // Stop background service (force stop in case _isRunning flag is out of sync)
    BackgroundServiceManager.stopService(force: true);
    
    // Cancel polling timer
    _messagePollingTimer?.cancel();
    _messagePollingTimer = null;
    
    // Disconnect SignalR explicitly
    SignalRService().disconnect();
    
    // Clear current room so notifications can work on next launch
    PushNotificationService.setCurrentRoom(null);
    
    _wasInBackground = false;
    debugPrint('✅ Termination cleanup complete');
  }

  /// Handle post-resume sync without blocking UI
  void _handleResumeSync() async {
    // Small delay to let UI settle first
    await Future.delayed(const Duration(milliseconds: 150));
    
    if (!mounted) return;
    
    try {
      final chatProvider = context.read<ChatProvider>();
      
      // Only refresh if SignalR is actually connected (avoid unnecessary API call)
      final signalR = SignalRService();
      if (signalR.isConnected) {
        debugPrint('🔄 Resume: SignalR connected, doing light sync...');
        // Light sync: just refresh chat list, not full page reload
        await chatProvider.refreshFirstPage();
      } else {
        debugPrint('🔄 Resume: SignalR not yet connected, waiting for reconnect...');
        // Wait for SignalR to reconnect (max 3 seconds)
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;
          if (signalR.isConnected) {
            debugPrint('🔄 Resume: SignalR connected, syncing...');
            await chatProvider.refreshFirstPage();
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in _handleResumeSync: $e');
    }
  }

  void _subscribeToSignalR() {
    final signalR = SignalRService();

    // ── TerimaPesan: incoming chat message ──
    // Notifikasi sudah di-handle langsung di signalr_service.dart (_handleNewMessageNotification)
    // Listener ini hanya untuk logging/debugging
    _terimaPesanSub = signalR.onTerimaPesan.listen((data) {
      if (data == null) return;
      
      final roomId = data['roomId']?.toString() ?? '';
      if (roomId.isEmpty) return;

      final message = data['message'] as Map<String, dynamic>? ?? {};

      final sender = data['sender'] as Map<String, dynamic>?;
      final msgText = message['Msg']?.toString() ?? '';
      final senderName = sender?['Name']?.toString() ?? 'Pesan Baru';

      final chatProvider = context.read<ChatProvider>();
      final isRecentSent = chatProvider.isRecentMessageFromMe(roomId, msgText);

      // FIX: Cek isMe secara komprehensif dari payload agar pesan keluar (outbound) tidak dianggap sebagai pesan masuk
      final agentId = message['agent_id'] ?? message['AgentId'] ?? message['agentId'];
      final isNobox = message['is_nobox'] ?? message['IsNobox'];
      final dirStr = message['dir']?.toString().toLowerCase();
      final isOutbound = message['IsOutbound'] ?? message['IsOutBound'] ?? message['Outbound'] ?? message['isOutbound'];
      
      final extFrom = message['From']?.toString() ?? message['FromId']?.toString() ?? message['IdAccount']?.toString() ?? '';
      final extChAccId = message['ChAccId']?.toString() ?? '';
      final extSenderId = message['SenderId']?.toString() ?? '';
      
      bool isMe = isRecentSent ||
          (agentId != null && agentId != 0 && agentId.toString() != '0') ||
          (isNobox == 1 || isNobox == '1' || isNobox == true) ||
          (dirStr == '1' || dirStr == '2' || dirStr == 'out' || dirStr == 'outbound' || dirStr == 'true') ||
          (isOutbound == true || isOutbound == 'true' || isOutbound == 1);

      isMe = isMe || message['IsMe'] == true;

      // Cek fallback berdasarkan ChAccId vs From
      if (!isMe && extChAccId.isNotEmpty && extFrom.isNotEmpty) {
        if (extFrom == extChAccId) {
          isMe = true;
        }
      }

      // Logika deteksi IsMe diserahkan ke fallback di atas dan model Message.

      debugPrint('Main: TerimaPesan | room=$roomId | sender=$senderName | msg=$msgText | isMe=$isMe');
      
      // FIX: Panggil sinkronisasi fallback jika backend lupa mengirim TerimaSubSpv (Sering terjadi pada Grup)
      try {
        chatProvider.handleTerimaPesanSync(roomId, isMe: isMe, msgText: msgText);
      } catch (e) {
        debugPrint('Main: Could not sync from TerimaPesan: $e');
      }
    });

    // ── TerimaSubSpv: room data update → update chat list directly ──
    _terimaSubSpvSub = signalR.onTerimaSubSpv.listen((data) {
      final roomData = data['room'] as Map<String, dynamic>? ?? {};
      debugPrint('Main: TerimaSubSpv | room=${roomData['Id']}');

      try {
        final chatProvider = context.read<ChatProvider>();
        chatProvider.updateRoomFromSignalR(roomData);
      } catch (e) {
        debugPrint('Main: Could not update chat list from TerimaSubSpv: $e');
      }
    });

    // ── UcChanged: total unread count changed ──
    // Sesuai saran Mas Erik: Jangan hit ulang API Chatrooms/List saat ada chat masuk (race condition Uc 0)
    // List sudah diupdate secara lokal lewat TerimaSubSpv
    _ucChangedSub = signalR.onUcChanged.listen((count) {
      debugPrint('Main: UcChanged | total=$count (Ignored refresh to prevent race condition)');
    });

    // ── Reconnect: sync data after reconnection ──
    _reconnectSub = signalR.onConnectionStateChanged.listen((connected) {
      if (connected) {
        debugPrint('Main: SignalR reconnected, syncing data...');
        try {
          context.read<ChatProvider>().refreshFirstPage();
        } catch (e) {
          debugPrint('Error caught at _reconnectSub (refreshFirstPage): $e');
        }
      }
    });

    // ── TerimaExpired: session expired → show dialog and logout ──
    signalR.onSessionExpired = () {
      debugPrint('Main: Session expired event received');
      _handleSessionExpired();
    };

    // ── TerimaBlockUnblock: block/unblock from web → update local state ──
    _blockUnblockSub = signalR.onBlockUnblock.listen((data) {
      final roomId = data['roomId']?.toString() ?? '';
      final isBlocked = data['isBlocked'] == true;
      debugPrint('Main: TerimaBlockUnblock | room=$roomId | isBlocked=$isBlocked');
      try {
        final chatProvider = context.read<ChatProvider>();
        chatProvider.updateBlockStatusFromSignalR(roomId, isBlocked);
      } catch (e) {
        debugPrint('Main: Could not update block status: $e');
      }
    });
  }

  // ── Session Expired Handler ──
  static bool _isShowingExpiredDialog = false;

  void _handleSessionExpired() {
    // Guard: prevent stacking multiple dialogs
    if (_isShowingExpiredDialog) return;
    _isShowingExpiredDialog = true;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      // No navigator context — force logout silently
      _forceLogout();
      _isShowingExpiredDialog = false;
      return;
    }

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Sesi Berakhir'),
          ],
        ),
        content: const Text(
          'Sesi Anda telah kedaluwarsa. Silakan login kembali untuk melanjutkan.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              _forceLogout();
            },
            child: const Text('Login Ulang'),
          ),
        ],
      ),
    ).then((_) {
      _isShowingExpiredDialog = false;
    });
  }

  void _forceLogout() {
    try {
      final auth = context.read<AuthProvider>();
      auth.logout();
      SignalRService().disconnect();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.login,
        (_) => false,
      );
    } catch (e) {
      debugPrint('Main: Error during force logout: $e');
    }
  }

  // ── Safety-net Polling (data sync only, NO notifications) ──
  void _startMessagePolling() {
    _messagePollingTimer?.cancel();
    _messagePollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _pollForNewMessages();
    });
    debugPrint('🔄 Safety-net polling started (every 60s)');
  }

  Future<void> _pollForNewMessages() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      // Data sync only — no notifications (SignalR handles those)
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.refreshFirstPage();
    } catch (e) {
      debugPrint('🔄 Polling error: $e');
    } finally {
      _isPolling = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _terimaPesanSub?.cancel();
    _terimaSubSpvSub?.cancel();
    _ucChangedSub?.cancel();
    _reconnectSub?.cancel();
    _blockUnblockSub?.cancel();
    _messagePollingTimer?.cancel();
    // Explicitly disconnect SignalR to clean up WebSocket connection
    SignalRService().disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MyApp: build called');
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'NoBox Chat',
          themeMode: themeProvider.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          scaffoldMessengerKey: scaffoldMessengerKey,
          navigatorKey: navigatorKey,
          home: const SplashPage(),
          routes: {
            AppRoutes.welcome: (_) => const WelcomePage(),
            AppRoutes.login: (_) => const LoginPage(),
            AppRoutes.home: (_) => const ResponsiveChatHome(),
            AppRoutes.chatDetail: (_) => const ChatDetailPage(),
            AppRoutes.archivedChats: (_) => const ArchiveListPage(),
          },
        );
      },
    );
  }
}
