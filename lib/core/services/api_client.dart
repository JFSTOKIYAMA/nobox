import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import 'background_service_manager.dart';

// =====================================================================
// FITUR: Klien API (Network)
// FILE: lib/core/services/api_client.dart
// BARIS AWAL: 13 (setelah komentar ini)
// FUNGSI: Mengelola koneksi jaringan (HTTP requests), pengaturan token otorisasi, dan logika re-login diam-diam (silent re-login) jika token kedaluwarsa.
// =====================================================================
class ApiClient {
  late Dio _dio;
  String? _token;

  static const String baseUrl = 'https://id.nobox.ai/';

  static final ApiClient _instance = ApiClient._internal();

  /// Callback saat benar-benar harus logout (refresh token gagal)
  Function? onUnauthorized;

  /// Flag untuk mencegah multiple re-login bersamaan
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  factory ApiClient() {
    return _instance;
  }

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 120),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Tambahkan interceptors untuk logging, autentikasi, dan silent re-login
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          debugPrint('ApiClient: ${options.method} ${options.path}');

          // Pengamanan (Failsafe): muat token dari secure storage atau fallback jika tidak ada di memori
          if (_token == null) {
            const secureStorage = FlutterSecureStorage();
            final prefs = await SharedPreferences.getInstance();
            _token =
                await secureStorage.read(key: AppConfig.tokenKey) ??
                prefs.getString(AppConfig.tokenKey);
            if (_token != null) {
              debugPrint('ApiClient: Token restored from persistent storage');
            }
          }

          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          } else {
            debugPrint('ApiClient: No token found!');
          }
          return handler.next(options);
        },
        onError: (e, handler) async {
          final is401 = e.response?.statusCode == 401;
          final is400AccessDenied =
              e.response?.statusCode == 400 &&
              e.response?.data is Map &&
              e.response?.data['Error'] is Map &&
              e.response?.data['Error']['Code'] == 'AccessDenied';

          // Jangan intercept request login itu sendiri (hindari infinite loop)
          if ((is401 || is400AccessDenied) &&
              !e.requestOptions.path.contains('AccountAPI/GenerateToken')) {
            debugPrint(
              'ApiClient: 🔄 Token expired, attempting silent re-login...',
            );

            // Coba silent re-login
            final newToken = await _tryAutoReLogin();

            if (newToken != null) {
              // Re-login berhasil! Retry request yang gagal dengan token baru
              debugPrint(
                'ApiClient: ✅ Silent re-login success, retrying request...',
              );

              e.requestOptions.headers['Authorization'] = 'Bearer $newToken';

              try {
                final retryResponse = await _dio.fetch(e.requestOptions);
                return handler.resolve(retryResponse);
              } catch (retryError) {
                debugPrint(
                  'ApiClient: ❌ Retry failed after re-login: $retryError',
                );
                return handler.next(e);
              }
            } else {
              // Re-login gagal → benar-benar logout
              debugPrint(
                'ApiClient: ❌ Silent re-login failed, triggering logout',
              );
              onUnauthorized?.call();
              return handler.next(e);
            }
          }

          return handler.next(e);
        },
      ),
    );

    // Hanya catat log request/response di mode debug untuk menghindari
    // pemborosan memori pada payload besar (misal gambar base64) di tahap produksi.
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true),
      );
    }
  }

  /// Silent re-login: ambil saved credentials → login ulang → simpan token baru
  /// Menggunakan Completer agar multiple request yang gagal secara bersamaan
  /// hanya memicu 1x re-login (yang lain menunggu hasilnya).
  Future<String?> _tryAutoReLogin() async {
    // Jika sudah ada proses refresh berjalan, tunggu hasilnya
    if (_isRefreshing && _refreshCompleter != null) {
      debugPrint('ApiClient: Waiting for existing re-login to complete...');
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      const secureStorage = FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();

      // FIX: SecureStorage.read bisa melemparkan exception (PlatformException) di beberapa OS.
      // Jika dilempar exception, tangkap dan gunakan fallback SharedPreferences.
      String? savedUsername;
      String? savedPassword;
      try {
        savedUsername = await secureStorage.read(
          key: AppConfig.lastUsernameKey,
        );
        savedPassword = await secureStorage.read(
          key: AppConfig.lastPasswordKey,
        );
      } catch (e) {
        debugPrint('ApiClient: SecureStorage read error, using fallback: $e');
      }

      savedUsername ??= prefs.getString(AppConfig.lastUsernameKey);
      savedPassword ??= prefs.getString(AppConfig.lastPasswordKey);

      if (savedUsername == null || savedPassword == null) {
        debugPrint(
          'ApiClient: No saved credentials found, cannot auto re-login',
        );
        _refreshCompleter!.complete(null);
        return null;
      }

      debugPrint(
        'ApiClient: 🔑 Auto re-login with saved credentials for $savedUsername...',
      );

      // Login langsung pakai Dio baru (bypass interceptor agar tidak infinite loop)
      final loginDio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final response = await loginDio.post(
        AppConfig.generateTokenEndpoint,
        data: {'userName': savedUsername, 'password': savedPassword},
      );

      if (response.statusCode == 200 && response.data['token'] != null) {
        final newToken = response.data['token'] as String;

        // Simpan token baru
        _token = newToken;
        try {
          await secureStorage.write(key: AppConfig.tokenKey, value: newToken);
        } catch (e) {
          debugPrint('ApiClient: SecureStorage write error: $e');
        }
        await prefs.setString(AppConfig.tokenKey, newToken);

        // Sinkronkan token baru ke background service native (SignalR) agar
        // koneksi background memakai JWT aktif dan tidak kena error handshake 401.
        try {
          await BackgroundServiceManager.updateToken(newToken);
        } catch (e) {
          debugPrint(
            'ApiClient: ⚠️ Failed to sync token to background service: $e',
          );
        }

        debugPrint('ApiClient: ✅ Auto re-login successful! New token saved.');
        _refreshCompleter!.complete(newToken);
        return newToken;
      } else {
        debugPrint('ApiClient: ❌ Auto re-login failed: ${response.data}');
        _refreshCompleter!.complete(null);
        return null;
      }
    } catch (e) {
      debugPrint('ApiClient: ❌ Auto re-login error: $e');
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  Dio get dio => _dio;

  // GET Request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return response;
  }

  // POST Request
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
    );
    return response;
  }
}
