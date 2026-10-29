import '../model/api_response.dart';
import 'chat_service.dart';

// =====================================================================
// FITUR: Layanan Filter API
// FILE: lib/core/services/filter_api_service.dart
// BARIS AWAL: 6 (setelah komentar ini)
// FUNGSI: Service khusus untuk mengambil data filter (Tags, Funnels, Agents). Mendelegasikan panggilan ke ChatService yang sudah teruji.
// =====================================================================
class FilterApiService {
  final ChatService _chatService = ChatService();

  /// Mengambil daftar Tags
  Future<ApiResponse<List<Map<String, dynamic>>>> getTags() {
    return _chatService.getTags();
  }

  /// Mengambil daftar Funnels
  Future<ApiResponse<List<Map<String, dynamic>>>> getFunnels() {
    return _chatService.getFunnels();
  }

  /// Mengambil daftar Agents (Agen)
  Future<ApiResponse<List<Map<String, dynamic>>>> getAgents() {
    return _chatService.getAgents();
  }

  /// Mengambil daftar Channels (Saluran)
  Future<ApiResponse<List<Map<String, dynamic>>>> getChannels() {
    return _chatService.getChannels();
  }

  /// Mengambil daftar Accounts (Akun)
  Future<ApiResponse<List<Map<String, dynamic>>>> getAccounts() {
    return _chatService.getAccounts();
  }

  /// Membuat Master Funnel baru
  Future<ApiResponse<Map<String, dynamic>>> createFunnel(String funnelName) {
    return _chatService.createFunnel(funnelName);
  }
}
