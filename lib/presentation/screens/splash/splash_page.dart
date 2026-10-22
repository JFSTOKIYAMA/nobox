import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/chat_settings_provider.dart';
import '../../../core/services/signalr_service.dart';
import '../../../core/utils/app_routes.dart';

// =====================================================================
// FITUR: Halaman Splash Screen
// FILE: lib/presentation/screens/splash/splash_page.dart
// BARIS AWAL: 15 (setelah komentar ini)
// FUNGSI: Layar pertama yang muncul saat aplikasi dibuka. Menjalankan fungsi inisialisasi 
//         seperti cek status login, muat tema, dan koneksi awal sebelum pindah halaman.
// =====================================================================
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static SharedPreferences? _sharedPrefsCache;
  Timer? _navigationTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    debugPrint('SplashPage: initState');
    // Start initialization immediately but DON'T block the first frame
    _initializeApp();
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  /// Initialize app components in background, navigate when ready
  /// This runs asynchronously without blocking the UI thread
  Future<void> _initializeApp() async {
    try {
      debugPrint('SplashPage: Starting background initialization');
      
      // Pre-warm SharedPreferences instance for faster subsequent access
      _sharedPrefsCache = await SharedPreferences.getInstance();
      
      final auth = context.read<AuthProvider>();
      final theme = context.read<ThemeProvider>();
      final chatSettings = context.read<ChatSettingsProvider>();

      // Run initialization tasks in parallel with a SHORT timeout (3s max for ANR safety)
      // Android ANR threshold is ~5 seconds, so we must complete well within that
      await Future.wait([
        auth.checkAuth(),
        theme.loadTheme(),
        chatSettings.loadSettings(),
      ]).timeout(const Duration(seconds: 3), onTimeout: () {
        debugPrint('SplashPage: ⚠️ Initialization timed out (3s), proceeding anyway');
        return [];
      });

      debugPrint('SplashPage: ✅ Initialization complete, navigating...');

      if (!mounted) return;

      // Navigate IMMEDIATELY after init - NO artificial delays!
      _navigateBasedOnAuth(auth);
      
    } catch (e, stack) {
      debugPrint('SplashPage: ❌ Initialization error: $e');
      debugPrint('Stack: $stack');
      if (mounted && !_hasNavigated) {
        _navigateToFallback();
      }
    }
  }

  void _navigateBasedOnAuth(AuthProvider auth) {
    if (_hasNavigated) return;
    
    if (auth.isLoggedIn) {
      _hasNavigated = true;
      
      // Defer SignalR connection to AFTER navigation + first frame
      // This ensures the home page renders before heavy SignalR work starts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Small delay to let home page build first
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          _connectSignalRSafely();
        });
      });
      
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      _navigateToWelcomeOrLogin();
    }
  }

  void _connectSignalRSafely() {
    try {
      debugPrint('SplashPage: Starting deferred SignalR connection...');
      SignalRService().connect();
    } catch (e) {
      debugPrint('SplashPage: SignalR connection error (non-fatal): $e');
    }
  }

  void _navigateToWelcomeOrLogin() {
    if (_hasNavigated || !mounted) return;
    
    final hasSeenWelcome = _sharedPrefsCache?.getBool('has_seen_welcome') ?? false;
    
    _hasNavigated = true;
    if (!hasSeenWelcome) {
      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  void _navigateToFallback() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    
    final prefs = _sharedPrefsCache;
    final hasSeenWelcome = prefs?.getBool('has_seen_welcome') ?? false;
    
    if (!hasSeenWelcome) {
      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This builds IMMEDIATELY - no async work here!
    return Material(
      color: Colors.white,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              // Logo
              Hero(
                tag: 'app_logo',
                child: Image.asset(
                  'assets/nobox2.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.chat_bubble_rounded,
                      size: 100,
                      color: Color(0xFF0084FF),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // App Name
              const Text(
                'NoBox Chat',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              // Subtitle
              const Text(
                'Ai Powered Chatbot',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black45,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(flex: 2),
              // Loading Progress
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0084FF)),
                  backgroundColor: Color(0xFFF0F0F0),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black38,
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight async wrapper for SharedPreferences when cache isn't ready
class SharedPreferencesAsync {
  Future<SharedPreferences> get _instance => SharedPreferences.getInstance();
  
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await _instance;
    return prefs.getBool(key) ?? defaultValue;
  }
}
