// =====================================================================
// FITUR 1: Autentikasi Pengguna (Auth Provider)
// TUJUAN: Mengelola state login pengguna, menyimpan token JWT, dan memvalidasi kredensial.
// =====================================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async'; // for unawaited

import '../services/auth_service.dart';
import '../model/api_response.dart';
import '../model/login_request.dart';
import '../services/api_client.dart';
import '../app_config.dart';
import '../utils/globals.dart';
import '../utils/app_routes.dart';

// =====================================================================
// FITUR: Provider Autentikasi
// FILE: lib/core/providers/auth_provider.dart
// BARIS AWAL: 13 (setelah komentar ini)
// FUNGSI: Mengelola state login, logout, penyimpanan token, dan sesi pengguna
// =====================================================================
class AuthProvider with ChangeNotifier {
  String? _currentUser;
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _disposed = false;

  final AuthService _authService = AuthService();
  String? _token;

  // Penyimpanan aman (Secure storage) untuk data sensitif (seperti token)
  static const _secureStorage = FlutterSecureStorage();
  static const String _secureTokenKey = 'auth_token';

  AuthProvider() {
    ApiClient().onUnauthorized = logout;
  }

  bool get mounted => !_disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Kunci SharedPreferences (hanya untuk data yang tidak sensitif)
  static const String _userEmailKey = 'user_email';
  static const String _rememberEmailKey = 'remembered_email';

  bool get isLoggedIn => _currentUser != null;
  String? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticating => _isAuthenticating;
  String? get token => _token;

  // FITUR: Safe Read Secure Storage
  // Mencegah aplikasi gagal login jika keystore OS rusak/mengalami error
  Future<String?> _safeRead(String key, SharedPreferences prefs) async {
    String? val;
    try {
      val = await _secureStorage.read(key: key);
      debugPrint('AuthProvider: SecureStorage read [$key] = ${val != null ? "FOUND" : "NULL"}');
    } catch (e) {
      debugPrint('AuthProvider: SecureStorage Error ($key): $e');
    }
    
    if (val == null || val.isEmpty) {
      val = prefs.getString(key);
      debugPrint('AuthProvider: SharedPreferences fallback read [$key] = ${val != null ? "FOUND" : "NULL"}');
    }
    return val;
  }

  // FITUR: Cek Status Autentikasi
  // FUNGSI: Memeriksa apakah user sudah login atau belum saat aplikasi pertama dibuka
  // [ACTION: AUTH_CHECK] - Memeriksa token saat aplikasi pertama kali dibuka
  // OPTIMIZED: Non-blocking, fast-path for startup. Silent re-login DEFERRED.
  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    
    // FAST PATH: Read all needed values in parallel
    final futures = <Future<String?>>[
      Future.value(prefs.getString(_userEmailKey)),
      _safeRead(_secureTokenKey, prefs),
      _safeRead(AppConfig.lastUsernameKey, prefs),
      _safeRead(AppConfig.lastPasswordKey, prefs),
    ];
    
    final results = await Future.wait(futures);
    
    final String? currentUser = results[0];
    final String? token = results[1];
    final String? savedUsername = results[2];
    final String? savedPassword = results[3];

    _currentUser = currentUser;
    _token = token;

    // If token exists, restore it immediately (no network call)
    if (_token != null) {
      if (_currentUser == null) {
        _currentUser = savedUsername;
      }
      ApiClient().setToken(_token!);
      _isLoading = false;
      notifyListeners();
      debugPrint('AuthProvider: ✅ Fast auth restore (token found)');
      return;
    }

    // NO TOKEN: Don't block startup with silent re-login!
    // Defer it to background after splash navigates
    _currentUser = null;
    _isLoading = false;
    notifyListeners();
    
    // Schedule deferred silent re-login (non-blocking)
    if (savedUsername != null && savedPassword != null) {
      debugPrint('AuthProvider: ⏳ Deferring silent re-login to background');
      unawaited(_tryDeferredAutoReLogin(savedUsername, savedPassword));
    } else {
      debugPrint('AuthProvider: No credentials, staying logged out');
    }
  }

  /// Background silent re-login - doesn't block startup
  Future<void> _tryDeferredAutoReLogin(String username, String password) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500)); // Let UI settle first
      if (!mounted) return; // Check if provider still alive
      
      final response = await _authService.login(
        LoginRequest(username: username, password: password),
      );

      if (!response.isError && response.data != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userEmailKey, username);
        try {
          await _secureStorage.write(key: _secureTokenKey, value: response.data!);
        } catch (e) {
          debugPrint('AuthProvider: SecureStorage write token error: $e');
        }
        await prefs.setString(_secureTokenKey, response.data!);
        
        _currentUser = username;
        _token = response.data;
        ApiClient().setToken(_token);
        notifyListeners();
        debugPrint('AuthProvider: ✅ Deferred silent re-login successful');
      } else {
        debugPrint('AuthProvider: ❌ Deferred silent re-login failed: ${response.error}');
      }
    } catch (e) {
      debugPrint('AuthProvider: ❌ Deferred silent re-login error: $e');
    }
  }

  Future<String?> getRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberEmailKey);
  }

  Future<void> saveRememberedEmail(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    if (email != null) {
      await prefs.setString(_rememberEmailKey, email);
    } else {
      await prefs.remove(_rememberEmailKey);
    }
  }

  // FITUR: Login
  // FUNGSI: Memproses permintaan login dari user ke API
  Future<ApiResponse<String>> login(String email, String password) async {
    _isAuthenticating = true;
    notifyListeners();

    try {
      final response = await _authService.login(
        LoginRequest(username: email, password: password),
      );

      if (!response.isError && response.data != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userEmailKey, email);
        
        // Simpan token di secure storage & SharedPreferences (sebagai fallback di OS tertentu)
        try {
          await _secureStorage.write(key: _secureTokenKey, value: response.data!);
        } catch (e) {
          debugPrint('AuthProvider: SecureStorage write token error: $e');
        }
        await prefs.setString(_secureTokenKey, response.data!);
        
        // Simpan credentials untuk auto re-login saat token expired
        try {
          await _secureStorage.write(key: AppConfig.lastUsernameKey, value: email);
          await _secureStorage.write(key: AppConfig.lastPasswordKey, value: password);
        } catch (e) {
          debugPrint('AuthProvider: SecureStorage write credentials error: $e');
        }
        await prefs.setString(AppConfig.lastUsernameKey, email);
        await prefs.setString(AppConfig.lastPasswordKey, password);
        debugPrint('AuthProvider: ✅ Credentials saved for auto re-login');
        
        _currentUser = email;
        _token = response.data;
        
        _isAuthenticating = false;
        notifyListeners();
        return response;
      }
      
      _isAuthenticating = false;
      notifyListeners();
      return response;
    } catch (e) {
      debugPrint('AuthProvider Login Error: $e');
      _isAuthenticating = false;
      notifyListeners();
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  // FITUR: Auto Re-Login (Silent)
  /// Silent re-login menggunakan saved credentials.
  /// Dipanggil dari splash_page, chat_detail, atau interceptor.
  /// Return true jika berhasil, false jika gagal.
  Future<bool> tryAutoReLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // GUNAKAN _safeRead agar tidak crash jika keystore OS rusak!
      final savedUsername = await _safeRead(AppConfig.lastUsernameKey, prefs);
      final savedPassword = await _safeRead(AppConfig.lastPasswordKey, prefs);

      if (savedUsername == null || savedPassword == null) {
        debugPrint('AuthProvider: tryAutoReLogin - No saved credentials');
        return false;
      }

      debugPrint('AuthProvider: 🔑 tryAutoReLogin for $savedUsername...');

      final response = await _authService.login(
        LoginRequest(username: savedUsername, password: savedPassword),
      );

      if (!response.isError && response.data != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userEmailKey, savedUsername);
        try {
          await _secureStorage.write(key: _secureTokenKey, value: response.data!);
        } catch (e) {
          debugPrint('AuthProvider: SecureStorage write token error in tryAutoReLogin: $e');
        }
        await prefs.setString(_secureTokenKey, response.data!);

        _currentUser = savedUsername;
        _token = response.data;
        ApiClient().setToken(_token);

        notifyListeners();
        debugPrint('AuthProvider: ✅ tryAutoReLogin successful');
        return true;
      }

      debugPrint('AuthProvider: ❌ tryAutoReLogin failed: ${response.error}');
      return false;
    } catch (e) {
      debugPrint('AuthProvider: ❌ tryAutoReLogin error: $e');
      return false;
    }
  }

  // FITUR: Logout
  // FUNGSI: Menghapus sesi, menghapus token, dan mengarahkan kembali ke halaman login
  // [ACTION: LOGOUT_EXECUTE] - Menghapus sesi, menghapus token, dan mengarahkan kembali ke halaman login
  void logout() async {
    // Guard: jika sudah logout, jangan jalankan ulang logika logout.
    // Ini mencegah respons 401/AccessDenied dari background process agar
    // tidak berulang kali mendorong halaman login dan menghapus teks input pengguna.
    if (_currentUser == null && _token == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_currentUser != null) {
      await prefs.setString(_rememberEmailKey, _currentUser!);
    }
    await prefs.remove(_userEmailKey);
    
    // Hapus token dari secure storage & fallback
    try {
      await _secureStorage.delete(key: _secureTokenKey);
    } catch (e) {
      debugPrint('AuthProvider: SecureStorage delete token error in logout: $e');
    }
    await prefs.remove(_secureTokenKey);
    
    // JANGAN hapus last_username & last_password saat logout
    // agar user bisa auto re-login saat buka app lagi
    // (credentials dihapus hanya jika user ganti akun)
    
    _currentUser = null;
    _token = null;
    ApiClient().setToken(null);
    notifyListeners();

    // Arahkan kembali ke layar login secara otomatis
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushNamedAndRemoveUntil(
        AppRoutes.login,
        (route) => false,
      );
    }
  }
}
