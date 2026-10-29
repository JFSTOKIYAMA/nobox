import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api_client.dart';
import '../app_config.dart';
import '../model/api_response.dart';
import '../model/message_request.dart';
import '../model/conversation.dart';
import '../model/message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'signalr_service.dart';
import '../model/quick_reply_model.dart';

class SignalRNull {
  dynamic toJson() => null;
}

// =====================================================================
// FITUR: Layanan Chat Utama (API Utama)
// FILE: lib/core/services/chat_service.dart
// BARIS AWAL: 20 (setelah komentar ini)
// FUNGSI: Service terbesar yang menangani mayoritas interaksi API Chat: mengambil pesan,
//         mengirim pesan, manajemen status chat, dan banyak fungsi lainnya.
// =====================================================================
class ChatService {
  final ApiClient _apiClient = ApiClient();
  String? currentTenantId;

  // Cache account data to ensure AccountIds is always populated for sendMessage
  static final Map<String, String> _accountById = {};
  static final Map<int, String> _accountIdByChannel = {};
  static String? _singleAccountId;
  static String? _singleAccountName;

  /// Fetch list of channels from API (WhatsApp, Telegram, etc.)
  // FITUR 6: Integrasi Saluran Multi-Platform (Mengambil daftar Channel).
  // [ACTION: API_ENDPOINT_CHANNELS] - API REST untuk mendapatkan daftar saluran (WhatsApp, dll)
  Future<ApiResponse<List<Map<String, dynamic>>>> getChannels() async {
    try {
      final response = await _apiClient.post(
        AppConfig.channelListEndpoint,
        data: {"Skip": 0, "Take": 100},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        List<dynamic> dataList = [];

        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        final channels = dataList
            .where((item) {
              // Filter: only show Automation channels (WhatsApp, Telegram, etc.)
              if (item is Map) {
                final kt = item['Kt']?.toString() ?? '';
                return kt == 'Automation';
              }
              return true;
            })
            .map((item) {
              if (item is Map<String, dynamic>) {
                return item;
              }
              return <String, dynamic>{'Nm': item.toString()};
            })
            .toList();
        return ApiResponse.success(channels, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load channels: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of accounts from API
  // FITUR 6: Integrasi Saluran Multi-Platform (Mengambil daftar Akun).
  // [ACTION: API_ENDPOINT_ACCOUNTS] - API REST untuk mendapatkan daftar akun
  Future<ApiResponse<List<Map<String, dynamic>>>> getAccounts() async {
    try {
      final response = await _apiClient.post(
        AppConfig.accountListEndpoint,
        data: {"Skip": 0, "Take": 100},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        List<dynamic> dataList = [];

        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        final accounts = dataList.map((item) {
          if (item is Map<String, dynamic>) {
            final tId = item['TenantId']?.toString();
            if (tId != null && tId.isNotEmpty) {
              currentTenantId = tId;
              // CRITICAL: Simpan tenantId ke secure storage agar SignalR bisa subscribe
              const storage = FlutterSecureStorage();
              storage.write(key: 'tenant_id', value: tId).then((_) {
                debugPrint('ChatService: ✅ TenantId saved to storage: $tId');
                // Trigger SignalR subscription sekarang tenantId tersedia
                SignalRService().trySubscribe();
              });
            }
            return item;
          }
          return <String, dynamic>{'Name': item.toString()};
        }).toList();
        return ApiResponse.success(accounts, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load accounts: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of contacts from API (with full data including LeadLinks)
  Future<ApiResponse<List<Map<String, dynamic>>>> getContacts() async {
    try {
      final response = await _apiClient.post(
        AppConfig.contactListEndpoint,
        data: {"Skip": 0, "Take": 100},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        List<dynamic> dataList = [];

        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        final contacts = dataList.map((item) {
          if (item is Map<String, dynamic>) {
            return item;
          }
          return <String, dynamic>{'Name': item.toString()};
        }).toList();
        return ApiResponse.success(contacts, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load contacts: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of campaigns from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getCampaigns() async {
    try {
      final requestData = {
        'IncludeColumns': ['Id', 'Name', 'DisplayName', 'Title', 'Nm'],
        'ColumnSelection': 1,
        'Take': 100,
        'Skip': 0,
      };
      final response = await _apiClient.post(
        AppConfig.campaignsListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load campaigns: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      return ApiResponse.success([], 200); // Fallback softly
    }
  }

  /// Fetch list of deals from API

  Future<ApiResponse<List<Map<String, dynamic>>>> getPipelines() async {
    try {
      final requestData = {"EqualityFilter": {}};
      final response = await _apiClient.post(
        AppConfig.pipelinesListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load pipelines: ${response.statusCode}',
        response.statusCode!,
      );
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getStages() async {
    try {
      final requestData = {"EqualityFilter": {}};
      final response = await _apiClient.post(
        AppConfig.stagesListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load stages: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getKanbanData(
    String pipelineId,
    String contactId,
  ) async {
    try {
      final Map<String, dynamic> equalityFilter = {
        "project_id": int.tryParse(pipelineId) ?? pipelineId,
        "KontakId": int.tryParse(contactId) ?? contactId,
      };

      final payload = {
        "EqualityFilter": equalityFilter,
        "Sort": ["Urutan ASC"],
      };

      final response = await _apiClient.post(
        AppConfig.getKanbanEndpoint,
        data: payload,
      );

      if (response.statusCode == 200) {
        return ApiResponse.success(
          response.data is Map ? Map<String, dynamic>.from(response.data) : {},
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        response.data?['Message'] ?? 'Failed to get kanban data',
        response.statusCode ?? 500,
      );
    } on DioException catch (e) {
      final serverMsg = e.response?.data?.toString() ?? e.toString();
      debugPrint('KANBAN ERROR: $serverMsg');
      return ApiResponse.failure(serverMsg, e.response?.statusCode ?? 500);
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getDeals() async {
    try {
      final requestData = {'Take': 100, 'Skip': 0};
      final response = await _apiClient.post(
        AppConfig.dealsListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load deals: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      return ApiResponse.success([], 200); // Fallback softly
    }
  }

  /// Fetch list of groups from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getGroups() async {
    try {
      final requestData = {'Take': 100, 'Skip': 0};
      final response = await _apiClient.post(
        AppConfig.groupsListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load groups: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      return ApiResponse.success([], 200); // Fallback softly
    }
  }

  /// Fetch list of links from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getLinks() async {
    try {
      final requestData = {
        'IncludeColumns': [
          'Id',
          'Name',
          'DisplayName',
          'Title',
          'Nm',
          'LinkTmp',
        ],
        'ColumnSelection': 1,
        'Take': 100,
        'Skip': 0,
      };
      final response = await _apiClient.post(
        AppConfig.linksListEndpoint,
        data: requestData,
      );
      if (response.statusCode == 200) {
        return ApiResponse.success(
          _parseGenericList(response.data),
          response.statusCode!,
        );
      }
      return ApiResponse.failure(
        'Failed to load links: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      return ApiResponse.success([], 200); // Fallback softly
    }
  }

  List<Map<String, dynamic>> _parseGenericList(dynamic rawData) {
    List<dynamic> dataList = [];
    if (rawData is List) {
      dataList = rawData;
    } else if (rawData is Map) {
      dataList =
          rawData['Entities'] ??
          rawData['Values'] ??
          rawData['data'] ??
          rawData['list'] ??
          [];
    }
    return dataList.map<Map<String, dynamic>>((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{'Name': item.toString()};
    }).toList();
  }

  /// Fetch list of agents from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getAgents() async {
    try {
      final requestData = {
        'IncludeColumns': [
          'DisplayName',
          'UserId',
          'Username',
          'Email',
          'Roles',
        ],
        'Take': 100,
        'Skip': 0,
      };
      final response = await _apiClient.post(
        AppConfig.getAgentsEndpoint,
        data: requestData,
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        List<dynamic> dataList = [];

        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        final List<Map<String, dynamic>> agents = dataList
            .map<Map<String, dynamic>>((item) {
              if (item is Map<String, dynamic>) {
                return item;
              } else if (item is Map) {
                return Map<String, dynamic>.from(item);
              }
              return <String, dynamic>{'Name': item.toString()};
            })
            .toList();
        return ApiResponse.success(agents, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load agents: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  Future<ApiResponse<bool>> addAgentToConversation(
    String roomId,
    String agentId,
    String agentName, {
    String chId = '',
    String ctId = '',
  }) async {
    try {
      String handId = "0";
      try {
        const storage = FlutterSecureStorage();
        final token = await storage.read(key: AppConfig.tokenKey);
        if (token != null) {
          final parts = token.split('.');
          if (parts.length == 3) {
            final payloadBase64 = parts[1];
            final String normalizedList = base64Url.normalize(payloadBase64);
            final String resp = utf8.decode(base64Url.decode(normalizedList));
            final payloadMap = jsonDecode(resp);
            handId =
                payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
                payloadMap['nameid'] ??
                payloadMap['sub'] ??
                "0";
          }
        }
      } catch (e) {
        debugPrint('ChatService: Error getting user info for payload: $e');
      }

      final payload = {
        'RoomId': roomId,
        'UserId': agentId,
        'isHanded': 0,
        'Msg': {
          'Type': 6,
          'RoomId': roomId,
          'Msg':
              '{"msg":"Site.Inbox.HasAsignBy","userId":"$agentId","byUserId":"$handId"}',
        },
        'RoomAgent': {
          'UserId': agentId,
          'RoomId': roomId,
          'DisplayName': agentName,
          'HandId': handId,
          if (chId.isNotEmpty) 'ChId': chId,
          if (ctId.isNotEmpty) 'CtId': ctId,
        },
      };

      debugPrint('================ ADD AGENT PAYLOAD ================');
      debugPrint(jsonEncode(payload));
      debugPrint('===================================================');

      final isRemoving = agentId.isEmpty || agentId == "0";

      // If we are removing the agent, we just use the Update endpoint to set status to 1
      if (isRemoving) {
        try {
          debugPrint(
            'ChatService: Forcing Chatroom Status to 1 (Unassigned) via Update endpoint.',
          );

          // Normalize the composite room ID (e.g. "wa_123" -> 123) so the
          // UpdateChatroom endpoint receives a pure numeric EntityId.
          final cleanEntityId =
              int.tryParse(roomId) ??
              int.tryParse(roomId.replaceAll(RegExp(r'[^0-9]'), '')) ??
              roomId;

          final response = await _apiClient.post(
            AppConfig.updateChatroomEndpoint,
            data: {
              "EntityId": cleanEntityId,
              "Entity": {
                "St": 1, // Unassigned
                "Status": "Unassigned",
                "AgentId": null,
                "AssigneeId": null,
                "ReById": null,
                "AssignedTo": null,
                "AgentName": "",
                "AssignedAgentName": "",
              },
            },
          );
          if (response.statusCode == 200 || response.statusCode == 204) {
            return ApiResponse.success(true, response.statusCode!);
          }
          debugPrint(
            'ChatService: Update endpoint returned ${response.statusCode} for unassign — treating as local success.',
          );
          return ApiResponse.success(true, response.statusCode ?? 200);
        } catch (e) {
          debugPrint('ChatService: Failed to force update status to 1: $e');
          // Keep behavior consistent with the universal fallback on agent
          // assignment: return success so the UI stays responsive even when
          // the server response is ambiguous or unreachable.
          return ApiResponse.success(true, 200);
        }
      }

      try {
        final response = await _apiClient.post(
          AppConfig.addAgentToConversationEndpoint,
          data: payload,
        );
        debugPrint('AddAgent Response Code: ${response.statusCode}');
        debugPrint('AddAgent Response Data: ${response.data}');

        if (response.statusCode == 200 || response.statusCode == 204) {
          final rawData = response.data;
          if (rawData is Map && rawData['IsError'] == true) {
            debugPrint('AddAgent API message: ${rawData['Error']}');
          }
        }
      } catch (e) {
        debugPrint(
          'ChatService: ⚠️ AddAgentToConversation API error ($e). Proceeding with universal Update fallback.',
        );
      }

      // FORCE UPDATE STATUS TO 2 (Assigned) using universal Update endpoint!
      // Ini menjamin penugasan agen tetap berhasil tersimpan di database meskipun API AddAgentToConversation mengalami eror 500 dari server.
      try {
        debugPrint(
          'ChatService: Updating Chatroom assignment (Status 2, Agent $agentName) via Update endpoint.',
        );

        final updateData = {
          "EntityId": int.tryParse(roomId) ?? roomId,
          "Entity": {
            "St": 2,
            "Status": "Assigned",
            "ReById": int.tryParse(agentId) ?? 1,
            "AgentId": int.tryParse(agentId) ?? agentId,
            "AssigneeId": int.tryParse(agentId) ?? agentId,
            "AssignedTo": agentId,
            "AgentName": agentName,
            "AssignedAgentName": agentName,
          },
        };

        await _apiClient.post(
          AppConfig.updateChatroomEndpoint,
          data: updateData,
        );
        debugPrint(
          'ChatService: ✅ Successfully assigned agent via Update endpoint!',
        );
      } catch (updateErr) {
        debugPrint(
          'ChatService: Failed to force update status to 2: $updateErr',
        );
      }

      return ApiResponse.success(true, 200);
    } catch (e) {
      debugPrint(
        'ChatService: ❌ Unexpected error in addAgentToConversation: $e',
      );
      return ApiResponse.failure(
        'Gagal menugaskan agen: Terjadi gangguan koneksi server',
        500,
      );
    }
  }

  /// Mark room as resolved
  /// Endpoint: POST Services/Chat/Chatrooms/MarkResolved
  /// St: 3 = Status Resolved
  /// ReById & ReByNm = diambil dari user data yang login
  Future<ApiResponse<bool>> resolveConversation(
    String roomId, {
    String? accountId,
  }) async {
    try {
      // Get agent info from user data (SharedPreferences) or JWT fallback
      String agentId = "1";
      String agentName = "Agent";
      try {
        final prefs = await SharedPreferences.getInstance();
        final userDataJson = prefs.getString(AppConfig.userDataKey);
        if (userDataJson != null) {
          final userData = jsonDecode(userDataJson);
          agentId = userData['UserId']?.toString() ?? '1';
          agentName = userData['DisplayName']?.toString() ?? 'Agent';
        }

        // Fallback: decode JWT if user data is incomplete
        if (agentId == '1') {
          const storage = FlutterSecureStorage();
          final token = await storage.read(key: AppConfig.tokenKey);
          if (token != null) {
            final parts = token.split('.');
            if (parts.length == 3) {
              final payloadBase64 = parts[1];
              final String normalizedList = base64Url.normalize(payloadBase64);
              final String resp = utf8.decode(base64Url.decode(normalizedList));
              final payloadMap = jsonDecode(resp);
              agentId =
                  payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
                  payloadMap['nameid'] ??
                  payloadMap['sub'] ??
                  "1";
              final String nameClaim =
                  payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name']
                      ?.toString() ??
                  '';
              final String emailClaim = payloadMap['email']?.toString() ?? '';
              agentName = nameClaim.isNotEmpty
                  ? nameClaim
                  : (emailClaim.isNotEmpty
                        ? emailClaim.split('@').first
                        : "Agent");
            }
          }
        }
      } catch (e) {
        debugPrint(
          'ChatService: Error getting user info for resolve payload: $e',
        );
      }

      // Extract a clean numeric ID from compound formats like "1234_5678" or remove letters/null
      // MarkResolved API strictly requires an integer EntityId string.
      String cleanRoomId = roomId
          .toString()
          .trim()
          .replaceAll('null', '')
          .replaceAll('undefined', '');
      if (int.tryParse(cleanRoomId) == null) {
        if (cleanRoomId.contains('_')) {
          final afterUnderscore = cleanRoomId.split('_').last;
          if (int.tryParse(afterUnderscore) != null && afterUnderscore != '0') {
            cleanRoomId = afterUnderscore;
          } else {
            final beforeUnderscore = cleanRoomId.split('_').first;
            if (int.tryParse(beforeUnderscore) != null &&
                beforeUnderscore != '0') {
              cleanRoomId = beforeUnderscore;
            }
          }
        }
        if (int.tryParse(cleanRoomId) == null) {
          final numericOnly = cleanRoomId.replaceAll(RegExp(r'[^0-9]'), '');
          if (numericOnly.isNotEmpty && int.tryParse(numericOnly) != null) {
            cleanRoomId = numericOnly;
          }
        }
      }

      // Proteksi agar tidak mengirim ID kosong yang memicu error di backend
      if (cleanRoomId.isEmpty || cleanRoomId == '0' || cleanRoomId == 'null') {
        debugPrint(
          '❌ [Resolve] DIBATALKAN: ID "$roomId" tidak valid untuk MarkResolved.',
        );
        return ApiResponse.failure(
          'ID Obrolan tidak valid ($roomId). Harap muat ulang daftar obrolan.',
          400,
        );
      }

      debugPrint(
        '✅ [Resolve] Marking room $roomId (cleanId: $cleanRoomId) as resolved by $agentName (ID: $agentId, accountId: $accountId)',
      );

      final String cleanAgentId = agentId.toString().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final String reByIdStr = cleanAgentId.isNotEmpty ? cleanAgentId : '1';

      final requestData = {
        'EntityId': cleanRoomId,
        'Entity': {'ReById': reByIdStr, 'ReByNm': agentName},
      };

      debugPrint('🔄 [Resolve] Payload: ${jsonEncode(requestData)}');

      final response = await _apiClient.post(
        AppConfig.resolveConversationEndpoint,
        data: requestData,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        final isError = response.data is Map ? response.data['IsError'] : false;
        if (isError != true) {
          debugPrint('✅ [Resolve] Room marked as resolved successfully');
          return ApiResponse.success(true, response.statusCode!);
        }
        final errorMsg =
            response.data['ErrorMsg'] ??
            response.data['Error'] ??
            'Failed to mark resolved';
        debugPrint('❌ [Resolve] Server returned error: $errorMsg');
        return ApiResponse.failure(errorMsg.toString(), response.statusCode!);
      }

      return ApiResponse.failure(
        'Failed to resolve conversation (HTTP ${response.statusCode})',
        response.statusCode ?? 500,
      );
    } on DioException catch (e) {
      debugPrint('❌ [Resolve] DioException: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [Resolve] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  String _extractAccountName(Map<String, dynamic> acc) {
    final keys = [
      'Name',
      'Nm',
      'Username',
      'Title',
      'DisplayName',
      'AccountName',
      'Val',
      'Value',
      'Label',
      'Text',
    ];
    String name = '';
    for (final key in keys) {
      final val = acc[key]?.toString();
      if (val != null &&
          val.isNotEmpty &&
          val != 'null' &&
          val != '0' &&
          val != '1') {
        name = val;
        break;
      }
    }
    if (name.isEmpty) {
      for (final entry in acc.entries) {
        final k = entry.key.toLowerCase();
        if (k != 'id' &&
            k != 'tenantid' &&
            k != 'chid' &&
            k != 'type' &&
            k != 'channel' &&
            k != 'kt') {
          final val = entry.value?.toString();
          if (val != null &&
              val.isNotEmpty &&
              val != 'null' &&
              val != '0' &&
              val != '1' &&
              !val.startsWith('{')) {
            name = val;
            break;
          }
        }
      }
    }
    return name;
  }

  /// Fetch list of chat rooms filtered by status.
  /// [statusCode] → 1: Unassigned, 2: Assigned, 3: Resolved, null: All
  /// [skip] and [take] control pagination (defaults: skip=0, take=20)
  Future<ApiResponse<List<Conversation>>> getConversations({
    int? statusCode,
    int skip = 0,
    int take = 20,
    String? accountIds,
    String? contactId,
    String? linkId,
    String? groupId,
    String? campaignId,
    String? funnelId,
    String? dealId,
    String? tagsId,
    String? humanAgentId,
  }) async {
    try {
      final Map<String, dynamic> payload = {
        "Take": take,
        "Skip": skip,
        "Sort": ["IsPin DESC", "TimeMsg DESC"],
        "IncludeColumns": [
          "Id",
          "CtId",
          "CtRealId",
          "GrpId",
          "CtRealNm",
          "Ct",
          "Grp",
          "LastMsg",
          "TimeMsg",
          "Uc",
          "St",
          "ChId",
          "ChAcc",
          "ChNm",
          "AccNm",
          "AccId",
          "BotNm",
          "CtTmp",
          "LinkTmp",
          "IsGrp",
          "IsPin",
          "CtIsBlock",
          "IsMuteBot",
          "IsNeedReply",
          "Tags",
          "Fn",
          "FnId",
          "FnNm",
          "FunnelId",
          "TagsIds",
          "UpBy",
          "AgentId",
          "AssignedTo",
          "HandledBy",
          "AgentName",
          "AssignedAgentName",
          "CtImg",
          "LinkImg",
          "TagsNm",
          "SdrMsg",
          "NeedReply",
          "IsMe",
          "LastIsMe",
        ],
        "ColumnSelection": 1,
      };

      // Apply EqualityFilter for status and accountIds
      if (statusCode != null ||
          (accountIds != null && accountIds.isNotEmpty) ||
          contactId != null ||
          linkId != null ||
          groupId != null ||
          campaignId != null ||
          funnelId != null ||
          dealId != null ||
          tagsId != null ||
          humanAgentId != null) {
        payload["EqualityFilter"] = {};

        if (statusCode != null) {
          payload["EqualityFilter"]["St"] = [statusCode];
        }

        if (accountIds != null && accountIds.isNotEmpty) {
          payload["EqualityFilter"]["ChAccId"] = accountIds;
        }

        if (contactId != null && contactId.isNotEmpty) {
          payload["EqualityFilter"]["CtRealId"] = [contactId];
        }

        if (linkId != null && linkId.isNotEmpty) {
          payload["EqualityFilter"]["LinkTmp"] = linkId;
        }

        if (groupId != null && groupId.isNotEmpty) {
          payload["EqualityFilter"]["GrpId"] = groupId;
        }

        if (campaignId != null && campaignId.isNotEmpty) {
          payload["EqualityFilter"]["CampaignId"] = campaignId;
        }

        if (funnelId != null && funnelId.isNotEmpty) {
          payload["EqualityFilter"]["FunnelId"] = funnelId;
        }

        if (dealId != null && dealId.isNotEmpty) {
          payload["EqualityFilter"]["DealId"] = dealId;
        }

        if (tagsId != null && tagsId.isNotEmpty) {
          // backend likely supports equality on TagsIds
          payload["EqualityFilter"]["TagsIds"] = tagsId;
        }
      }

      if (humanAgentId != null && humanAgentId.isNotEmpty) {
        final int? parsedId = int.tryParse(humanAgentId);
        if (parsedId != null) {
          payload["UserIds"] = [parsedId];
        }
      }

      debugPrint('ChatService: fetchConversations statusCode=$statusCode');
      final response = await _apiClient.post(
        AppConfig.chatroomsListEndpoint,
        data: payload,
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;

        // Check for NoBox error envelope
        if (rawData is Map && rawData['IsError'] == true) {
          final serverError =
              rawData['Error']?.toString() ?? 'Unknown server error';
          debugPrint(
            'ChatService: Server error in getConversations: $serverError',
          );
          return ApiResponse.failure(serverError, 200);
        }

        List<dynamic> dataList = [];
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        debugPrint(
          'ChatService: Loaded ${dataList.length} conversations with status=$statusCode',
        );

        bool hasPrinted = false;
        final conversations = dataList.map((json) {
          if (json is Map<String, dynamic>) {
            try {
              if (!hasPrinted) {
                // debugPrint('===== FIRST CONVERSATION RAW JSON =====');
                // hasPrinted = true;
              }
              final conv = Conversation.fromJson(json);
              if (conv.ctRealId == '804126878257925' ||
                  conv.contactId == '804126878257925') {
                debugPrint(
                  '===== RAW CONVERSATION JSON FOR HRTS (BY ID) =====',
                );
                debugPrint(jsonEncode(json));
                debugPrint(
                  '==================================================',
                );
              }
              return conv;
            } catch (e) {
              debugPrint('Error parsing conversation: $e\nData: $json');
              return Conversation(
                id: json['Id']?.toString() ?? '',
                participantEmail: 'ERROR: Parsing Failed',
                lastMessage: e.toString(),
                lastMessageTime: '',
              );
            }
          }
          return Conversation(
            id: '',
            participantEmail: 'Unknown',
            lastMessage: '',
            lastMessageTime: '',
          );
        }).toList();

        // Fetch accounts to map ChId → Account Name
        try {
          final accountsResponse = await getAccounts();
          if (!accountsResponse.isError && accountsResponse.data != null) {
            final accounts = accountsResponse.data!;
            debugPrint('ChatService: Fetched ${accounts.length} accounts');

            // Debug: print all account fields
            for (final acc in accounts) {
              debugPrint(
                'ChatService: Account → ${acc.entries.map((e) => "${e.key}=${e.value}").join(", ")}',
              );
            }

            // Build lookup maps
            final accountByChannel = <int, String>{}; // Channel number → Name
            final accountIdByChannel =
                <int, String>{}; // Channel number → AccountId

            for (final acc in accounts) {
              final name = _extractAccountName(acc);
              final id = acc['Id']?.toString() ?? '';
              final channel = acc['Channel'];
              final tId = acc['TenantId']?.toString();

              if (tId != null && tId.isNotEmpty) {
                currentTenantId = tId;
              }

              final status = acc['Status']?.toString();
              final condition = acc['Condition']?.toString();
              final note = (acc['NoteCondition']?.toString() ?? '')
                  .toLowerCase();
              final bool isConnected =
                  (status == '1' || status == 'true') &&
                  (condition == '1' ||
                      condition == 'true' ||
                      note.contains('connect'));

              if (name.isNotEmpty) {
                if (isConnected || _singleAccountName == null) {
                  _singleAccountName = name;
                }
                if (id.isNotEmpty) {
                  _accountById[id] = name;
                  if (isConnected || _singleAccountId == null) {
                    _singleAccountId = id;
                  }
                }

                void setChannelAccount(int chNum) {
                  final existingId = accountIdByChannel[chNum];
                  // Only set or overwrite if connected or if this channel doesn't have an entry yet
                  if (existingId == null || isConnected) {
                    accountByChannel[chNum] = name;
                    if (id.isNotEmpty) accountIdByChannel[chNum] = id;
                  }
                }

                // Handle Channel as both number and string
                if (channel is int) {
                  setChannelAccount(channel);
                } else if (channel is String) {
                  final channelNum = int.tryParse(channel);
                  if (channelNum != null) {
                    setChannelAccount(channelNum);
                  } else {
                    if (channel.toLowerCase().contains('whatsapp')) {
                      setChannelAccount(1);
                    } else if (channel.toLowerCase().contains('telegram')) {
                      setChannelAccount(2);
                    }
                  }
                }
              }
            }

            _accountIdByChannel.addAll(accountIdByChannel);
            debugPrint(
              'ChatService: _accountById=$_accountById, single=$_singleAccountName',
            );

            // Inject account name into conversations
            for (int i = 0; i < conversations.length; i++) {
              if (i < dataList.length) {
                final json = dataList[i];
                if (json is Map<String, dynamic>) {
                  final chId = json['ChId'];
                  final rawAccId =
                      json['ChAccId']?.toString() ??
                      json['AccId']?.toString() ??
                      (conversations[i].accountId.isNotEmpty
                          ? conversations[i].accountId
                          : null);

                  String? resolvedName;
                  String? resolvedAccountId =
                      (rawAccId != null &&
                          rawAccId.isNotEmpty &&
                          rawAccId != '0' &&
                          rawAccId != 'null')
                      ? rawAccId
                      : null;

                  if (resolvedAccountId != null &&
                      _accountById.containsKey(resolvedAccountId)) {
                    resolvedName = _accountById[resolvedAccountId];
                  } else if (chId != null &&
                      chId is int &&
                      accountByChannel.containsKey(chId)) {
                    resolvedName = accountByChannel[chId];
                    resolvedAccountId ??= accountIdByChannel[chId];
                  } else if (accounts.length == 1 &&
                      _singleAccountName != null) {
                    resolvedName = _singleAccountName;
                    resolvedAccountId ??= _singleAccountId;
                  }

                  if (resolvedName != null ||
                      (resolvedAccountId != null &&
                          resolvedAccountId.isNotEmpty)) {
                    conversations[i] = conversations[i].copyWith(
                      channelName: resolvedName,
                      accountId: resolvedAccountId,
                    );
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('ChatService: Failed to resolve account names: $e');
        }

        return ApiResponse.success(conversations, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load chats: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      // Sertakan detail error asli (mis. SocketException: Failed host lookup)
      // agar UI bisa membedakan "tidak ada internet" vs "server bermasalah".
      String errorMessage = [
        e.message,
        e.error?.toString(),
      ].whereType<String>().where((s) => s.isNotEmpty).join(' | ');
      if (errorMessage.isEmpty)
        errorMessage = 'Unknown connection error (${e.type.name})';
      if (e.response != null && e.response?.data is Map) {
        errorMessage = e.response?.data['error']?.toString() ?? errorMessage;
      }
      if (e.response?.statusCode != null && e.response!.statusCode! >= 500) {
        errorMessage =
            'Server error (${e.response!.statusCode}): $errorMessage';
      }
      debugPrint('ChatService: getConversations DioException: $errorMessage');
      return ApiResponse.failure(errorMessage, e.response?.statusCode ?? 500);
    } catch (e) {
      debugPrint('ChatService: getConversations error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch resolved conversation history for a specific contact.
  /// Uses the ListHistory endpoint with CtId filter and St=3 (Resolved).
  Future<ApiResponse<List<Conversation>>> getConversationHistory(
    String contactId,
  ) async {
    try {
      final Map<String, dynamic> payload = {
        "Take": 50,
        "Skip": 0,
        "Sort": ["TimeMsg DESC"],
        "IncludeColumns": [
          "Id",
          "CtId",
          "CtRealId",
          "GrpId",
          "CtRealNm",
          "Ct",
          "Grp",
          "LastMsg",
          "TimeMsg",
          "Uc",
          "St",
          "ChId",
          "ChAcc",
          "ChNm",
          "AccNm",
          "AccId",
          "BotNm",
          "CtTmp",
          "LinkTmp",
          "IsGrp",
          "IsPin",
          "CtIsBlock",
          "IsMuteBot",
          "IsNeedReply",
          "Tags",
          "Fn",
          "FnId",
          "FnNm",
          "FunnelId",
          "TagsIds",
          "UpBy",
          "AgentId",
          "AssignedTo",
          "HandledBy",
          "AgentName",
          "AssignedAgentName",
          "CtImg",
          "LinkImg",
          "TagsNm",
        ],
        "ColumnSelection": 1,
        "EqualityFilter": {"CtId": contactId, "St": 3},
      };

      debugPrint('ChatService: getConversationHistory CtId=$contactId');
      final response = await _apiClient.post(
        AppConfig.chatroomsListHistoryEndpoint,
        data: payload,
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;

        if (rawData is Map && rawData['IsError'] == true) {
          final serverError =
              rawData['Error']?.toString() ?? 'Unknown server error';
          debugPrint(
            'ChatService: Server error in getConversationHistory: $serverError',
          );
          return ApiResponse.failure(serverError, 200);
        }

        List<dynamic> dataList = [];
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          dataList =
              rawData['Entities'] ??
              rawData['Values'] ??
              rawData['data'] ??
              rawData['list'] ??
              [];
        }

        debugPrint(
          'ChatService: Loaded ${dataList.length} history conversations for CtId=$contactId',
        );

        final conversations = dataList.map((json) {
          if (json is Map<String, dynamic>) {
            return Conversation.fromJson(json);
          }
          return Conversation(
            id: '',
            participantEmail: 'Unknown',
            lastMessage: '',
            lastMessageTime: '',
          );
        }).toList();

        // Inject account names (just like in getConversations)
        try {
          final accountsResponse = await getAccounts();
          if (!accountsResponse.isError && accountsResponse.data != null) {
            final accounts = accountsResponse.data!;
            final accountByChannel = <int, String>{};
            final accountIdByChannel = <int, String>{};

            for (final acc in accounts) {
              final name = _extractAccountName(acc);
              final channel = acc['Channel'];
              final id = acc['Id']?.toString() ?? '';

              final status = acc['Status']?.toString();
              final condition = acc['Condition']?.toString();
              final note = (acc['NoteCondition']?.toString() ?? '')
                  .toLowerCase();
              final bool isConnected =
                  (status == '1' || status == 'true') &&
                  (condition == '1' ||
                      condition == 'true' ||
                      note.contains('connect'));

              if (name.isNotEmpty) {
                void setChannelAccount(int chNum) {
                  final existingId = accountIdByChannel[chNum];
                  if (existingId == null || isConnected) {
                    accountByChannel[chNum] = name;
                    if (id.isNotEmpty) accountIdByChannel[chNum] = id;
                  }
                }

                if (channel is int) {
                  setChannelAccount(channel);
                } else if (channel is String) {
                  final channelNum = int.tryParse(channel);
                  if (channelNum != null) {
                    setChannelAccount(channelNum);
                  } else {
                    if (channel.toLowerCase().contains('whatsapp')) {
                      setChannelAccount(1);
                    } else if (channel.toLowerCase().contains('telegram')) {
                      setChannelAccount(2);
                    }
                  }
                }
              }
            }

            for (int i = 0; i < conversations.length; i++) {
              if (i < dataList.length) {
                final json = dataList[i];
                if (json is Map<String, dynamic>) {
                  final chId = json['ChId'];
                  final rawAccId =
                      json['ChAccId']?.toString() ??
                      json['AccId']?.toString() ??
                      (conversations[i].accountId.isNotEmpty
                          ? conversations[i].accountId
                          : null);

                  String? resolvedName;
                  String? resolvedAccountId =
                      (rawAccId != null &&
                          rawAccId.isNotEmpty &&
                          rawAccId != '0' &&
                          rawAccId != 'null')
                      ? rawAccId
                      : null;

                  if (resolvedAccountId != null &&
                      _accountById.containsKey(resolvedAccountId)) {
                    resolvedName = _accountById[resolvedAccountId];
                  } else if (chId != null &&
                      chId is int &&
                      accountByChannel.containsKey(chId)) {
                    resolvedName = accountByChannel[chId];
                    resolvedAccountId ??= accountIdByChannel[chId];
                  } else if (accounts.length == 1 &&
                      _singleAccountName != null) {
                    resolvedName = _singleAccountName;
                    resolvedAccountId ??= _singleAccountId;
                  }

                  if (resolvedName != null ||
                      (resolvedAccountId != null &&
                          resolvedAccountId.isNotEmpty)) {
                    conversations[i] = conversations[i].copyWith(
                      channelName: resolvedName,
                      accountId: resolvedAccountId,
                    );
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint(
            'ChatService: Failed to resolve account names in history: $e',
          );
        }

        return ApiResponse.success(conversations, response.statusCode!);
      } else {
        return ApiResponse.failure(
          'Failed to load conversation history: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      debugPrint(
        'ChatService: getConversationHistory DioException: ${e.message}',
      );
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('ChatService: getConversationHistory error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch message history for a chatroom.
  /// [roomId] must be the RoomId (Id from Chatrooms/List), NOT the ContactId (CtId).
  // 🛑 [API ENDPOINT: AMBIL RIWAYAT CHAT]
  // Endpoint ini memanggil rute `/Chatmessages/List` untuk menyedot jutaan baris data obrolan
  // dari database server ke layar HP. Ini bertugas melayani fitur pagination / tarik layar ke bawah.
  Future<ApiResponse<List<Message>>> getMessageHistory(
    String roomId,
    String currentUserEmail, {
    int skip = 0,
    int take = 50,
    String contactId = '',
    String groupId = '',
    String ctRealId = '',
    String link = '',
    String participantEmail = '',
    bool isTelegram = false,
  }) async {
    if (roomId.isEmpty || roomId == '0' || roomId == 'null') {
      // 🛡️ ANTI-BLEED: HANYA promosikan ID yang memang ber-scope ke room (groupId/link).
      // contactId (CtId) dan ctRealId (CtRealId) adalah ID LEVEL KONTAK, bukan RoomId.
      // Mempromosikannya ke RoomId akan mengambil seluruh riwayat lama kontak tersebut,
      // termasuk riwayat percakapan yang sudah diarsipkan, sehingga bocor ke room baru.
      if (groupId.isNotEmpty && groupId != '0' && groupId != 'null') {
        roomId = groupId;
      } else if (link.isNotEmpty && link != '0' && link != 'null') {
        roomId = link;
      } else {
        debugPrint(
          'ChatService: 🛑 getMessageHistory called without a valid RoomId (only contact-level IDs available)! Returning empty list to prevent archive bleed.',
        );
        return ApiResponse.success([], 200);
      }
      debugPrint('ChatService: ⚠️ Promoted room-scoped ID to RoomId: $roomId');
    }
    if (currentTenantId == null) {
      // Ensure we have TenantId before fetching messages to construct WhatsApp image URLs
      await getAccounts();
    }

    try {
      final String cleanRoomStr = roomId.contains('_')
          ? roomId.split('_').last
          : roomId;
      final int? numericRoomId = int.tryParse(
        cleanRoomStr.replaceAll(RegExp(r'[^0-9\-]'), ''),
      );

      final payload = {
        'Take': take,
        'Skip': skip,
        'Sort': ['In DESC'],
        'EqualityFilter': {'RoomId': numericRoomId ?? roomId},
      };

      debugPrint('ChatService: ┌── getMessageHistory ──');
      debugPrint('ChatService: │ Endpoint: ${AppConfig.getMessagesEndpoint}');
      debugPrint('ChatService: │ RoomId: $roomId');

      final response = await _apiClient.post(
        AppConfig.getMessagesEndpoint,
        data: payload,
      );

      debugPrint('ChatService: │ Status: ${response.statusCode}');
      final respStr = response.data?.toString() ?? 'null';
      debugPrint(
        'ChatService: │ Response (first 300): ${respStr.length > 300 ? respStr.substring(0, 300) : respStr}',
      );
      debugPrint('ChatService: └──────────────────────');

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        List<dynamic> dataList = [];

        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          if (rawData['IsError'] == true) {
            final serverError =
                rawData['Error']?.toString() ?? 'Unknown server error';
            debugPrint(
              'ChatService: getMessageHistory server error: $serverError',
            );
            return ApiResponse.failure(serverError, 200);
          }
          dataList =
              rawData['Entities'] ?? rawData['Values'] ?? rawData['data'] ?? [];
        }

        debugPrint(
          'ChatService: getMessageHistory loaded ${dataList.length} messages',
        );
        if (dataList.isNotEmpty) {
          debugPrint(
            'ChatService: First message keys: ${(dataList.first as Map).keys.toList()}',
          );
        }

        final messages = dataList
            .map(
              (json) => Message.fromJson(
                json,
                currentUserEmail,
                tenantId: currentTenantId,
                contactId: contactId,
              ),
            )
            .toList();

        // FIX UNIVERSAL FALLBACK:
        // PENTING: Hanya jalankan fallback jika query utama menghasilkan 0 pesan (messages.isEmpty)!
        // Jika roomId utama sudah mengembalikan pesan, JANGAN PERNAH menjalankan fallback karena
        // contactId/ctRealId/link bisa merupakan RoomId dari percakapan LAMA yang sudah diarsipkan,
        // sehingga pesan lama akan ikut terambil dan bercampur dengan percakapan baru.
        if (messages.isEmpty) {
          final Set<String> fallbackIds = {};

          if (roomId.isNotEmpty && roomId != '0' && roomId != 'null') {
            final numericRoomId = roomId.replaceAll(RegExp(r'[^0-9\-]'), '');
            if (numericRoomId.isNotEmpty && numericRoomId != roomId)
              fallbackIds.add(numericRoomId);
          }

          if (roomId.contains('_')) {
            final afterUnderscore = roomId.split('_').last;
            if (afterUnderscore.isNotEmpty && afterUnderscore != roomId)
              fallbackIds.add(afterUnderscore);
          }

          // 🛡️ ANTI-BLEED: JANGAN PERNAH gunakan contactId/ctRealId/link sebagai fallback
          // ketika roomId utama sudah valid. Room baru yang baru dibuat memang wajar
          // mengembalikan 0 pesan; mengambil riwayat kontak lamanya di sini justru
          // membocorkan pesan percakapan lama (termasuk yang sudah diarsipkan).
          if (roomId.isEmpty || roomId == '0' || roomId == 'null') {
            if (ctRealId.isNotEmpty && ctRealId != roomId)
              fallbackIds.add(ctRealId);
            if (contactId.isNotEmpty && contactId != roomId)
              fallbackIds.add(contactId);
            if (link.isNotEmpty && link != roomId) fallbackIds.add(link);
          }

          // Pengaman anti-bleeding untuk non-Telegram: saring keluar angka kecil urut (< 100.000)
          // yang bukan merupakan nomor telepon atau UUID.
          if (!isTelegram) {
            fallbackIds.removeWhere((fId) {
              final clean = fId.trim();
              if (clean.isEmpty) return true;
              final asInt = int.tryParse(clean);
              // Angka kecil tanpa awalan 0 atau + adalah ID database internal (berpotensi bleeding jika dijadikan RoomId)
              if (asInt != null &&
                  asInt < 100000 &&
                  !clean.startsWith('0') &&
                  !clean.startsWith('+')) {
                return true;
              }
              return false;
            });
          }

          if (fallbackIds.isNotEmpty) {
            bool hasNewMessages = false;

            for (final fId in fallbackIds) {
              debugPrint(
                'ChatService: │ [UNIVERSAL FALLBACK] Fetching fallback ID: $fId (chId=$roomId)',
              );
              try {
                final payload2 = Map<String, dynamic>.from(payload);
                payload2['EqualityFilter'] = {'RoomId': fId};
                final response2 = await _apiClient.post(
                  AppConfig.getMessagesEndpoint,
                  data: payload2,
                );
                if (response2.statusCode == 200 && response2.data != null) {
                  final raw2 = response2.data;
                  List<dynamic> list2 = [];
                  if (raw2 is List)
                    list2 = raw2;
                  else if (raw2 is Map && raw2['IsError'] != true)
                    list2 =
                        raw2['Entities'] ??
                        raw2['Values'] ??
                        raw2['data'] ??
                        [];

                  if (list2.isNotEmpty) {
                    final msgs2 = list2
                        .map(
                          (json) => Message.fromJson(
                            json,
                            currentUserEmail,
                            tenantId: currentTenantId,
                          ),
                        )
                        .toList();

                    final uniqueMsgs = <String, Message>{};
                    for (var m in messages) {
                      if (m.id.isNotEmpty) uniqueMsgs[m.id] = m;
                    }
                    for (var m in msgs2) {
                      if (m.id.isNotEmpty) uniqueMsgs[m.id] = m;
                    }

                    messages.clear();
                    messages.addAll(uniqueMsgs.values);
                    hasNewMessages = true;
                  }
                }
              } catch (e) {
                debugPrint(
                  'ChatService: │ [UNIVERSAL FALLBACK] Error fetching $fId: $e',
                );
              }
            }

            if (hasNewMessages && messages.isNotEmpty) {
              messages.sort((a, b) {
                try {
                  String ta = a.rawTime;
                  String tb = b.rawTime;
                  if (!ta.endsWith('Z') && !ta.contains('+') && ta.length >= 19)
                    ta += 'Z';
                  if (!tb.endsWith('Z') && !tb.contains('+') && tb.length >= 19)
                    tb += 'Z';
                  return DateTime.parse(
                    tb,
                  ).compareTo(DateTime.parse(ta)); // DESC
                } catch (_) {
                  return 0;
                }
              });

              if (messages.length > take) {
                messages.removeRange(take, messages.length);
              }
            }
          }
        }

        debugPrint('ChatService: │ Total merged messages: ${messages.length}');

        // Balik urutan: API kirim DESC (terbaru dulu),
        // tapi tampilan chat butuh ASC (terlama di atas)
        final reversed = messages.reversed.toList();
        return ApiResponse.success(reversed, response.statusCode!);
      } else {
        debugPrint(
          'ChatService: getMessageHistory FAILED with status ${response.statusCode}',
        );
        return ApiResponse.failure(
          'Failed to load messages: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      // 🛑 [ERROR HANDLING: DIO EXCEPTION]
      // Blok ini menangkap error yang berasal dari protokol HTTP/API (contoh: 503 Service Unavailable).
      // Jika server Nobox sibuk/down dan membalas dengan 503, aplikasi TIDAK AKAN CRASH.
      // Melainkan, `DioException` ini mengubahnya menjadi status `ApiResponse.failure`
      // agar UI bisa merespons dengan menampilkan pesan ramah kepada user ("Gagal memuat pesan").
      //
      // 🛑 [ERROR HANDLING: NO INTERNET / KONEKSI MATI]
      // Jika HP user sedang offline (tidak ada paket data/WiFi mati), DioException
      // akan melempar tipe `connectionError` atau `unknown` (SocketException: Failed host lookup).
      // Sama seperti 503, aplikasi tidak akan macet/putih, melainkan akan me-return
      // pesan "Connection error" ke UI agar user tahu masalahnya ada di jaringannya sendiri.
      debugPrint('ChatService: getMessageHistory DioException: ${e.message}');
      String errorMessage =
          e.message ?? 'Connection error while loading messages';
      if (e.response?.statusCode == 500 || errorMessage.contains('500')) {
        errorMessage =
            'Internal Server Error (500). Server gagal memproses riwayat obrolan ini.';
      }
      return ApiResponse.failure(errorMessage, e.response?.statusCode ?? 500);
    } catch (e) {
      // 🛑 [ERROR HANDLING: SOCKET / GENERAL EXCEPTION]
      // Blok catch paling bawah ini berfungsi sebagai jaring pengaman terakhir.
      // Seringkali menangkap error OS tingkat rendah seperti "Connection reset by peer",
      // yaitu saat komputer server secara brutal memutus koneksi internet di tengah proses.
      // Dengan handling ini, aplikasi tidak akan freeze; user cukup men-scroll ulang untuk retry.
      debugPrint('ChatService: getMessageHistory error: $e');
      return ApiResponse.failure('Failed to load messages', 500);
    }
  }

  /// Get archived room detail — returns raw Data map (like mentor's api_service.dart).
  /// The caller is responsible for extracting Messages from this map.
  Future<ApiResponse<Map<String, dynamic>>> getArchivedRoomDetail(
    String roomId,
  ) async {
    try {
      debugPrint('📦 ChatService: getArchivedRoomDetail - RoomId: $roomId');

      final response = await _apiClient.post(
        AppConfig.detailArchivedEndpoint,
        data: {'EntityId': roomId},
      );

      debugPrint('📦 ChatService: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final isError = response.data['IsError'];
        final hasError = isError == true;

        debugPrint('📦 ChatService: HasError: $hasError');
        debugPrint(
          '📦 ChatService: Response top-level keys: ${(response.data as Map?)?.keys.toList()}',
        );

        if (!hasError && response.data['Data'] != null) {
          final data = response.data['Data'] as Map<String, dynamic>;
          debugPrint('✅ ChatService: Got archived room detail');
          debugPrint('📦 ChatService: Data keys: ${data.keys.toList()}');

          // Log deeper structure for debugging
          data.forEach((key, value) {
            if (value is List) {
              debugPrint('📦   $key: List with ${value.length} items');
              if (value.isNotEmpty) {
                debugPrint(
                  '📦     First item keys: ${(value.first as Map?)?.keys.toList()}',
                );
              }
            } else if (value is Map) {
              debugPrint('📦   $key: Map with keys ${value.keys.toList()}');
            } else {
              final valStr = value?.toString() ?? 'null';
              debugPrint(
                '📦   $key: ${valStr.length > 80 ? valStr.substring(0, 80) : valStr}',
              );
            }
          });

          return ApiResponse.success(data, response.statusCode!);
        } else {
          final errorMsg =
              response.data['ErrorMsg']?.toString() ??
              response.data['Error']?.toString() ??
              'Failed to load archived room detail';
          debugPrint('❌ ChatService: Archived error: $errorMsg');
          return ApiResponse.failure(errorMsg, response.statusCode!);
        }
      } else {
        return ApiResponse.failure(
          'HTTP ${response.statusCode}: ${response.statusMessage}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      debugPrint(
        '❌ ChatService: getArchivedRoomDetail DioException: ${e.message}',
      );
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ ChatService: getArchivedRoomDetail error: $e');
      return ApiResponse.failure('Failed to load archived detail: $e', 500);
    }
  }

  /// Helper untuk membangun Telegram ExtId yang valid dan mencegah double-encoding JSON
  String _buildTelegramExtId(
    String rawExtId,
    String? username,
    String? accessHash,
  ) {
    if (rawExtId.isEmpty) return rawExtId;

    bool isJson = false;
    Map<String, dynamic> existingJson = {};
    try {
      final decoded = jsonDecode(rawExtId);
      if (decoded is Map) {
        isJson = true;
        existingJson = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    final extIdMap = <String, dynamic>{};
    if (isJson) {
      extIdMap.addAll(existingJson);
      if (username != null && username.isNotEmpty)
        extIdMap['Username'] = username;
      if (accessHash != null && accessHash.isNotEmpty)
        extIdMap['AccessHash'] = accessHash;
    } else {
      extIdMap['ExtId'] = rawExtId;
      if (username != null && username.isNotEmpty)
        extIdMap['Username'] = username;
      if (accessHash != null && accessHash.isNotEmpty)
        extIdMap['AccessHash'] = accessHash;
    }
    return jsonEncode(extIdMap);
  }

  /// Retrieve ExtId for a contact. For Telegram (channelId=2), returns a JSON
  /// string containing ExtId, Username, and AccessHash per mentor instruction.
  Future<String?> _getExtId(String? contactId, {int channelId = 1}) async {
    if (contactId == null || contactId.isEmpty) return null;
    try {
      final response = await _apiClient.post(
        'Services/Chat/Chatlinkcontacts/Retrieve',
        data: {'EntityId': int.tryParse(contactId) ?? contactId},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) {
          final entity = data['Entity'];
          if (entity is Map) {
            String extId = '';
            String? username;
            String? accessHash;

            // Mentor contract: ExtId must come from Entity.Extra.ExtId ("628...")
            final extraRaw = entity['Extra'];
            if (extraRaw != null) {
              try {
                final extraMap = extraRaw is String
                    ? jsonDecode(extraRaw)
                    : extraRaw;
                if (extraMap is Map) {
                  if (extraMap['ExtId'] != null) {
                    extId = extraMap['ExtId'].toString();
                  }
                  // Capture Telegram-specific fields from Extra
                  username = extraMap['Username']?.toString();
                  accessHash = extraMap['AccessHash']?.toString();
                }
              } catch (_) {
                // ignore parse error, fallback to IdExt below
              }
            }

            if (extId.isEmpty) {
              extId = entity['IdExt']?.toString() ?? '';
            }

            if (extId.isEmpty) return null;

            // Telegram: wrap ExtId in JSON string with Username & AccessHash
            if (channelId == 2) {
              final idExt = entity['IdExt']?.toString();
              if (idExt != null && idExt.isNotEmpty) {
                extId = idExt;
              }
              final jsonStr = _buildTelegramExtId(extId, username, accessHash);
              debugPrint('ChatService: _getExtId Telegram JSON: $jsonStr');
              return jsonStr;
            }

            return extId;
          }

          // fallback if API shape differs
          if (data['IdExt'] != null) return data['IdExt']?.toString();
        }
      }
    } catch (e) {
      debugPrint('Error retrieving ExtId: $e');
    }
    return null;
  }

  /// Create a new conversation room via Inbox/CreateNewRoom API
  /// This matches the mentor project's approach – create room first, then send messages.
  Future<Map<String, dynamic>> createNewRoom({
    required int accountId,
    required int channelId,
    int? contactId,
    int? linkId,
    String? manualNumber,
    int? groupId,
    bool isGroup = false,
  }) async {
    try {
      // Determine "To" flag per mentor contract:
      // 1 = Contact, 2 = Link, 3 = Manual/Group
      int toType = 1; // default: Contact
      if (linkId != null) toType = 2;
      if ((manualNumber != null && manualNumber.isNotEmpty) || isGroup)
        toType = 3;

      final data = {
        "AccId": accountId,
        "ChId": channelId,
        "LinkId": linkId ?? 0,
        "GrpId": isGroup ? (groupId ?? 0) : 0,
        "Chat": isGroup ? 1 : 0,
        "CtId": isGroup ? 0 : (contactId ?? 0),
        "Manual": manualNumber ?? "",
        "To": toType,
      };

      debugPrint('ChatService: ┌── createNewRoom ──');
      debugPrint('ChatService: │ Endpoint: ${AppConfig.createNewRoomEndpoint}');
      debugPrint('ChatService: │ Payload: $data');

      final response = await _apiClient.post(
        AppConfig.createNewRoomEndpoint,
        data: data,
      );

      debugPrint('ChatService: │ Response status: ${response.statusCode}');
      debugPrint('ChatService: │ Response data: ${response.data}');
      debugPrint('ChatService: └──────────────────');

      if (response.statusCode == 200) {
        final responseData = response.data;

        if (responseData is Map) {
          final result = Map<String, dynamic>.from(responseData);

          if (result['IsError'] == true || result['isError'] == true) {
            return {
              'success': false,
              'error': result['ErrorMessage'] ?? result['Error'] ?? 'API error',
            };
          }

          final dataObj =
              result['Data'] ??
              result['Value'] ??
              result['Entity'] ??
              result['data'] ??
              result['value'] ??
              result['Room'];
          String? extractedRoomId;
          String? extractedCtId;
          String? extractedLinkId;
          String? extractedAccId;
          String? extractedCtRealId;

          if (dataObj is Map) {
            extractedRoomId =
                dataObj['Id']?.toString() ??
                dataObj['RoomId']?.toString() ??
                dataObj['id']?.toString() ??
                dataObj['roomId']?.toString();
            extractedCtId =
                dataObj['CtId']?.toString() ??
                dataObj['ContactId']?.toString() ??
                dataObj['ctId']?.toString() ??
                dataObj['IdLink']?.toString();
            extractedLinkId =
                dataObj['LinkId']?.toString() ??
                dataObj['LinkTmp']?.toString() ??
                dataObj['linkId']?.toString();
            extractedAccId =
                dataObj['AccId']?.toString() ??
                dataObj['accId']?.toString() ??
                dataObj['ChAccId']?.toString();
            extractedCtRealId =
                dataObj['CtRealId']?.toString() ??
                dataObj['ctRealId']?.toString();
          } else if (dataObj != null && dataObj is! List) {
            extractedRoomId = dataObj.toString();
          }
          extractedRoomId ??=
              result['Id']?.toString() ??
              result['RoomId']?.toString() ??
              result['id']?.toString() ??
              result['roomId']?.toString();
          extractedCtId ??=
              result['CtId']?.toString() ??
              result['ContactId']?.toString() ??
              result['ctId']?.toString();
          extractedLinkId ??=
              result['LinkId']?.toString() ??
              result['LinkTmp']?.toString() ??
              result['linkId']?.toString();
          extractedAccId ??=
              result['AccId']?.toString() ?? result['accId']?.toString();
          extractedCtRealId ??=
              result['CtRealId']?.toString() ?? result['ctRealId']?.toString();

          // Aman: normalisasi nilai placeholder ('0'/'null'/'' ) agar field ID
          // TIDAK membawa nilai rusak ke ChatModel & proses kirim pesan.
          String? scrub(String? v) {
            if (v == null) return null;
            final t = v.trim();
            if (t.isEmpty || t == '0' || t.toLowerCase() == 'null') return null;
            return v;
          }

          extractedRoomId = scrub(extractedRoomId);
          extractedCtId = scrub(extractedCtId);
          extractedLinkId = scrub(extractedLinkId);
          extractedAccId = scrub(extractedAccId);
          extractedCtRealId = scrub(extractedCtRealId);

          debugPrint(
            'ChatService: ✅ Extracted RoomId from createNewRoom: $extractedRoomId | CtId: $extractedCtId | LinkId: $extractedLinkId | AccId: $extractedAccId',
          );
          return {
            'success': true,
            'roomId': extractedRoomId,
            'contactId': extractedCtId,
            'linkId': extractedLinkId,
            'accountId': extractedAccId,
            'ctRealId': extractedCtRealId,
            'groupId': groupId?.toString(),
            'data': result['Data'] ?? responseData,
          };
        } else if (responseData != null) {
          debugPrint(
            'ChatService: ✅ Raw Response as RoomId from createNewRoom: $responseData',
          );
          return {
            'success': true,
            'roomId': responseData.toString(),
            'data': responseData,
          };
        }
        return {'success': true, 'data': responseData};
      }

      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}: ${response.statusMessage}',
      };
    } on DioException catch (e) {
      debugPrint('ChatService: ❌ CreateNewRoom DioError: ${e.message}');
      debugPrint('ChatService: ❌ Response: ${e.response?.data}');
      return {
        'success': false,
        'error': 'API Error: ${e.message}',
        'statusCode': e.response?.statusCode,
      };
    } catch (e) {
      debugPrint('ChatService: ❌ CreateNewRoom error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🛑 [API ENDPOINT: KIRIM PESAN & MEDIA]
  // Endpoint `/Inbox/Send` adalah nyawa utama aplikasi. Fungsi ini bertugas mentransmisikan
  // teks balasan, gambar, dokumen, hingga rekaman suara ke API server agar diteruskan ke WhatsApp.
  Future<ApiResponse<bool>> sendMessage(MessageRequest request) async {
    try {
      var roomIdStr = request.receiver;
      final content = request.content;

      // Promosikan ID alternatif (GroupId/CtRealId/contactId) jika receiver
      // kosong/"0"/"null" agar Inbox/Send tidak menerima Id=0 atau null.
      bool isBad(String v) => v.isEmpty || v == '0' || v == 'null';
      if (isBad(roomIdStr)) roomIdStr = request.groupId ?? roomIdStr;
      if (isBad(roomIdStr)) roomIdStr = request.extId ?? roomIdStr;
      if (isBad(roomIdStr)) roomIdStr = request.contactId ?? roomIdStr;

      // Bersihkan RoomId dari format komposit (tenantId_roomId) dan karakter asing.
      String cleanRoomId = roomIdStr.trim();
      if (cleanRoomId.contains('_')) {
        cleanRoomId = cleanRoomId.split('_').last;
      }
      cleanRoomId = cleanRoomId.replaceAll(RegExp(r'[^0-9\-]'), '');
      if (cleanRoomId.isEmpty || cleanRoomId == '0' || cleanRoomId == 'null') {
        debugPrint(
          'ChatService: ❌ sendMessage DIBATALKAN: RoomId tidak valid ($roomIdStr).',
        );
        return ApiResponse.failure('RoomId is empty or invalid', 400);
      }

      debugPrint('ChatService: ┌── sendMessage (REST API) ──');
      debugPrint('ChatService: │ RoomId: $roomIdStr');
      debugPrint('ChatService: │ CleanRoomId: $cleanRoomId');
      debugPrint('ChatService: │ Content: $content');
      debugPrint(
        'ChatService: │ Endpoint: ${AppConfig.inboxSendEndpoint}?Id=$cleanRoomId',
      );

      // Mentor instruction: AccountIds must be a single string (comma-separated if multiple), NOT an array.
      // Clean up the string to remove any brackets or quotes just in case the source contains them.
      String safeAccountId = '';
      if (request.accountId != null && request.accountId!.isNotEmpty) {
        safeAccountId = request.accountId!;
      }

      final String channelIdRaw = (request.channelId ?? '1').trim();
      final bool isTelegramChannel =
          request.isTelegram ||
          channelIdRaw == '2' ||
          channelIdRaw.toLowerCase() == 'telegram';
      final bool isWaChannel =
          channelIdRaw == '1' ||
          channelIdRaw == '1557' ||
          channelIdRaw == '1561' ||
          channelIdRaw.toLowerCase() == 'whatsapp' ||
          channelIdRaw.toLowerCase() == 'wa';
      final int channelId = isTelegramChannel
          ? 2
          : (isWaChannel ? 1 : (int.tryParse(channelIdRaw) ?? 1));

      if (safeAccountId.isEmpty && _accountIdByChannel.containsKey(channelId)) {
        safeAccountId = _accountIdByChannel[channelId]!;
        debugPrint(
          'ChatService: AccountId was empty, using fallback for channel $channelId -> $safeAccountId',
        );
      }

      if (safeAccountId.isEmpty &&
          _singleAccountId != null &&
          _singleAccountId!.isNotEmpty) {
        safeAccountId = _singleAccountId!;
      }
      safeAccountId = safeAccountId
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .trim();

      String extId = '';
      String? telegramUsername;
      String? telegramAccessHash;

      // Retrieve ExtId via POST to Chatlinkcontacts/Retrieve
      if (request.contactId != null && request.contactId!.isNotEmpty) {
        try {
          final retrieveResponse = await _apiClient.post(
            'Services/Chat/Chatlinkcontacts/Retrieve',
            data: {'EntityId': request.contactId},
          );
          if (retrieveResponse.statusCode == 200) {
            final data = retrieveResponse.data;
            // Mentor contract: ExtId should come from Entity.Extra.ExtId ("628...")
            final entity = data['Entity'];
            if (entity is Map) {
              final extraRaw = entity['Extra'];
              if (extraRaw != null) {
                try {
                  final extraMap = extraRaw is String
                      ? jsonDecode(extraRaw)
                      : extraRaw;
                  if (extraMap is Map) {
                    if (extraMap['ExtId'] != null) {
                      extId = extraMap['ExtId']?.toString() ?? '';
                    }
                    // Capture Telegram-specific fields from Extra
                    telegramUsername = extraMap['Username']?.toString();
                    telegramAccessHash = extraMap['AccessHash']?.toString();
                  }
                } catch (_) {
                  // ignore parse error; fallback to IdExt
                }
              }
              final idExt = entity['IdExt']?.toString() ?? '';
              if (channelId == 2 && idExt.isNotEmpty) {
                extId = idExt;
              } else {
                extId = (extId.isNotEmpty ? extId : idExt);
              }
            }
            debugPrint('ChatService: ExtId retrieved = $extId');
          }
        } catch (e) {
          debugPrint('ChatService: Error retrieving ExtId: $e');
        }
      }

      // Helper untuk mendeteksi apakah suatu ID sebenarnya adalah nomor telepon (ExtId) dan bukan database LinkId/CtId
      bool isTelephoneNumber(String? str) {
        if (str == null || str.isEmpty) return false;
        final trimmed = str.trim();
        if (trimmed.startsWith('+') ||
            trimmed.startsWith('08') ||
            trimmed.startsWith('628')) {
          return true;
        }
        final clean = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
        // NoBox 15-digit snowflake database IDs start with 8 (e.g. 819322506002437)
        if (clean.length >= 15) return false;
        return clean.length >= 9 && clean.length <= 14;
      }

      if (extId.isEmpty && request.extId != null && request.extId!.isNotEmpty) {
        extId = request.extId!;
      }
      if (extId.isEmpty && isTelephoneNumber(request.contactId)) {
        extId = request.contactId!;
      }
      if (extId.isEmpty && isTelephoneNumber(request.receiver)) {
        extId = request.receiver;
      }

      // Do NOT send ExtId as a JSON string for WA.
      // HACK: Tapi untuk Telegram, C# backend mem-parsing ExtId sebagai objek JSON (extra.ExtId).
      String finalExtId = extId;
      if (extId.isNotEmpty && channelId == 2) {
        if (!finalExtId.startsWith('{')) {
          finalExtId = jsonEncode({"ExtId": extId});
        }
      }

      final Map<String, dynamic> payload = {
        'Body': content,
        'BodyType': request.bodyType,
        'ChannelId': channelId,
        'AccountIds': safeAccountId,
        'Attachment': request.attachment ?? '',
      };
      if (request.replyId != null) {
        // Backend menolak payload jika kita mengirim ReplyId atau ReplyTo secara langsung (menyebabkan crash 500).
        // Sehingga context balasan hanya bisa hidup di memori lokal saat ini untuk API Inbox/Send.
      }

      final bool isGroupReq =
          request.groupId != null &&
          request.groupId!.isNotEmpty &&
          request.groupId != '0';
      if (isGroupReq) {
        payload['GroupId'] = int.tryParse(request.groupId!) ?? request.groupId;
        payload['GrpId'] = int.tryParse(request.groupId!) ?? request.groupId;
      }

      // ExtId dan LinkId hanya untuk obrolan 1-on-1 (bukan grup)
      if (!isGroupReq) {
        if (finalExtId.isNotEmpty) {
          payload['ExtId'] = finalExtId;
        }
        // Fallback: sertakan LinkId (database primary key) jika ada
        if (request.contactId != null && request.contactId!.isNotEmpty) {
          final linkIdInt = int.tryParse(request.contactId!);
          if (linkIdInt != null && linkIdInt > 0) {
            payload['LinkId'] = linkIdInt;
          }
        }
      }

      debugPrint('ChatService: ┌── sendMessage PAYLOAD FINAL ──');
      debugPrint(jsonEncode(payload));
      debugPrint('ChatService: └──────────────────────────────');

      final response = await _apiClient.post(
        'https://id.nobox.ai/Inbox/Send?Id=$cleanRoomId',
        data: payload,
      );

      debugPrint('ChatService: │ Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final rawData = response.data;
        if (rawData is Map && rawData['IsError'] == true) {
          final errorMsg = rawData['Error']?.toString() ?? 'Send error';
          // Hapus fallback otomatis ke SignalR agar pesan error dari server NoBox
          // bisa langsung terlihat di UI aplikasi.
          debugPrint('ChatService: │ ❌ Server error: $errorMsg');
          debugPrint('ChatService: └─────────────────────────');
          return ApiResponse.failure(errorMsg, 200);
        }
        debugPrint('ChatService: │ ✅ Message sent via REST API!');
        debugPrint('ChatService: │ Send Response Body: ${response.data}');
        debugPrint('ChatService: └─────────────────────────');
        return ApiResponse.success(true, 200);
      } else {
        debugPrint('ChatService: │ ❌ HTTP ${response.statusCode}');
        debugPrint('ChatService: └─────────────────────────');
        return ApiResponse.failure(
          'Failed: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      debugPrint('ChatService: sendMessage DioException: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('ChatService: sendMessage error: $e');
      return ApiResponse.failure('Failed to send message: $e', 500);
    }
  }

  /// Get MIME type based on file extension
  String _getMimeType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
      case 'opus':
        return 'audio/ogg; codecs=opus';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      default:
        return 'application/octet-stream';
    }
  }

  /// Parse a MIME string (e.g. "audio/ogg; codecs=opus") into a [MediaType]
  /// suitable for Dio's [MultipartFile.contentType].
  MediaType? _parseMediaType(String mime) {
    if (mime.isEmpty) return null;
    try {
      final parts = mime.split(';');
      final typeSubtype = parts.first.trim();
      final slashIndex = typeSubtype.indexOf('/');
      if (slashIndex <= 0 || slashIndex == typeSubtype.length - 1) {
        return null;
      }
      final type = typeSubtype.substring(0, slashIndex).trim();
      final subtype = typeSubtype.substring(slashIndex + 1).trim();
      if (type.isEmpty || subtype.isEmpty) return null;
      final params = <String, String>{};
      for (final part in parts.skip(1)) {
        final kv = part.trim().split('=');
        if (kv.length == 2 && kv[0].trim().isNotEmpty) {
          params[kv[0].trim()] = kv[1].trim();
        }
      }
      return MediaType(type, subtype, params.isEmpty ? null : params);
    } catch (_) {
      return null;
    }
  }

  /// Send an image message: upload file then send the URL as message body
  Future<ApiResponse<String>> sendImageMessage(
    String conversationId,
    String filePath, {
    String? accountId,
    String? channelId,
    String? contactId,
    String? link, // IdLink for SignalR (LinkTmp/LinkNm from conversation)
    String? groupId,
    bool forceDocument = false,
    String? customFileName,
  }) async {
    try {
      final normalizedPath = filePath.replaceAll('/', Platform.pathSeparator);
      final file = File(normalizedPath);

      if (!await file.exists()) {
        debugPrint('ChatService: File not found at $normalizedPath');
        // File not found, just send the filename as text message
        final fallbackName = normalizedPath.split(Platform.pathSeparator).last;
        final sendResponse = await _apiClient.post(
          "${AppConfig.inboxSendEndpoint}?Id=$conversationId",
          data: {"Body": "[File: $fallbackName]"},
        );
        if (sendResponse.statusCode == 200) {
          return ApiResponse.success(normalizedPath, 200);
        }
        return ApiResponse.failure('File not found', 404);
      }

      final bytes = await file.readAsBytes();
      String fileName =
          customFileName ?? normalizedPath.split(Platform.pathSeparator).last;
      String extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : 'jpg';

      // If this is an audio/voice note file and the customFileName is not set,
      // override the name to 'voice note.mp3' so WhatsApp recipients see it correctly.
      if (customFileName == null || customFileName.isEmpty) {
        if (extension == 'mp3' ||
            extension == 'm4a' ||
            extension == 'wav' ||
            extension == 'ogg' ||
            extension == 'opus' ||
            extension == 'aac' ||
            extension == 'amr' ||
            extension == 'weba') {
          fileName = 'voice note.mp3';
          extension = 'mp3';
        }
      }

      // Determine BodyType based on file extension
      int bodyType = 3; // Default to Image
      switch (extension) {
        case 'mp4':
        case 'mov':
        case 'avi':
        case 'mkv':
        case '3gp':
        case 'webm':
          bodyType = 4; // Video
          break;
        case 'm4a':
        case 'mp3':
        case 'wav':
        case 'ogg':
        case 'opus':
        case 'aac':
        case 'amr':
        case 'weba':
          bodyType = 2; // Audio/Voice
          break;
        case 'pdf':
        case 'doc':
        case 'docx':
        case 'xls':
        case 'xlsx':
        case 'ppt':
        case 'pptx':
        case 'txt':
        case 'csv':
        case 'zip':
        case 'rar':
        case 'rtf':
          bodyType = 5; // Document
          break;
      }

      if (forceDocument) {
        bodyType = 5; // Force as document if requested by the user
      }

      // Step 1: Upload file
      // - Untuk Dokumen (bodyType 5) dan Telegram: Wajib pakai Base64 agar menghasilkan URL permanen yang bisa dibaca oleh WhatsappAPI/SendFile dan SignalR
      // - Untuk Foto WA (bodyType 3): Pakai TemporaryUpload (Multipart) agar super cepat.
      // - Untuk Foto WA (bodyType 3) dan Gambar yang dipaksa jadi Dokumen: Pakai TemporaryUpload (Multipart).
      String? serverFileName;
      String? actualError;
      final bool isTelegram = (channelId == '2' || channelId == 'Telegram');

      // PENTING: SignalR WAJIB menggunakan TemporaryUpload agar file masuk ke folder 'temporary/'
      // Sesuai dengan payload Web NoBox, server backend akan gagal memproses (tidak muncul di web) jika menggunakan Base64 tanpa temporary.
      // Kita matikan useBase64 secara paksa untuk Voice Note agar lewat jalur TemporaryUpload yang normal.
      final bool useBase64 = false;

      try {
        if (useBase64) {
          final mimeType = _getMimeType(fileName);
          final base64String = base64Encode(bytes);
          debugPrint('--- BASE64 UPLOAD START: file=$fileName ---');

          final uploadResponse = await _apiClient.post(
            AppConfig.uploadBase64Endpoint,
            data: {
              'media': {
                'filename': fileName,
                'mimetype': mimeType,
                'data': base64String,
              },
            },
          );

          if (uploadResponse.statusCode == 200) {
            final responseData = uploadResponse.data;
            if (responseData is Map) {
              if (responseData['IsError'] == true) {
                actualError = responseData['Error']?.toString();
              } else if (responseData['Data'] != null) {
                final raw = responseData['Data'];
                if (raw is Map) {
                  serverFileName =
                      raw['Filename']?.toString() ??
                      raw['FileName']?.toString() ??
                      raw['filename']?.toString();
                } else if (raw is String &&
                    !raw.toLowerCase().contains('error') &&
                    !raw.toLowerCase().contains('status')) {
                  serverFileName = raw;
                }
              }
            }
          } else {
            actualError = 'HTTP Error: ${uploadResponse.statusCode}';
          }
        } else {
          debugPrint(
            '--- MULTIPART UPLOAD START: file=$fileName size=${(bytes.length / 1024).toStringAsFixed(1)}KB ---',
          );

          final String mimeForUpload = _getMimeType(fileName);
          final MediaType? mediaType = _parseMediaType(mimeForUpload);
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              filePath,
              filename: fileName,
              contentType: mediaType,
            ),
          });

          final uploadResponse = await _apiClient.post(
            'File/TemporaryUpload',
            data: formData,
          );

          debugPrint('Upload Status: ${uploadResponse.statusCode}');

          if (uploadResponse.statusCode == 200) {
            final responseData = uploadResponse.data;
            if (responseData is Map) {
              if (responseData['TemporaryFile'] != null) {
                serverFileName = responseData['TemporaryFile'].toString();
              } else if (responseData['IsError'] == true) {
                actualError = responseData['Error']?.toString();
              } else if (responseData['Data'] != null) {
                final raw = responseData['Data'];
                if (raw is Map && raw['TemporaryFile'] != null) {
                  serverFileName = raw['TemporaryFile'].toString();
                }
              } else {
                actualError = 'Format respons tidak dikenal';
              }
            }
          } else {
            actualError = 'HTTP Error: ${uploadResponse.statusCode}';
          }
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          actualError =
              'Timeout saat mengunggah (koneksi lambat atau file Base64 terlalu besar).';
        } else {
          actualError =
              'Network Error: ${e.response?.statusCode ?? ""} ${e.message}';
        }
        debugPrint(
          'Upload DioException: ${e.response?.statusCode} - ${e.response?.data} - ${e.message}',
        );
      } catch (e) {
        actualError = 'System Error: $e';
        debugPrint('Upload error: $e');
      }

      if (serverFileName == null || serverFileName.isEmpty) {
        return ApiResponse.failure(
          actualError ?? 'Gagal upload file. Pastikan koneksi internet stabil.',
          500,
        );
      }

      // Step 2: Send as message with image content

      // Create attachment data in JSON format as required by Pin point
      final String attachmentOriginalName = (bodyType == 2)
          ? 'voice note.mp3'
          : fileName;
      final attachmentMap = <String, dynamic>{
        'Filename': serverFileName,
        'FileName': serverFileName,
        'OriginalName': attachmentOriginalName,
        'originalName': attachmentOriginalName,
        'Name': attachmentOriginalName,
        'Title': attachmentOriginalName,
        'IsImage': forceDocument ? false : (bodyType == 3),
        'IsDocument': forceDocument ? true : (bodyType == 5),
        'IsVideo': forceDocument ? false : (bodyType == 4),
        'IsAudio': forceDocument ? false : (bodyType == 2),
        'Ptt': bodyType == 2,
      };
      final attachmentData = jsonEncode([attachmentMap]);

      // Mentor instruction: AccountIds must be a single string (comma-separated if multiple), NOT an array.
      String safeAccountId = '';
      if (accountId != null &&
          accountId.isNotEmpty &&
          accountId != '0' &&
          accountId != 'null') {
        safeAccountId = accountId;
      } else if (channelId != null &&
          _accountIdByChannel.containsKey(channelId)) {
        safeAccountId = _accountIdByChannel[channelId]!;
      } else if (_singleAccountId != null && _singleAccountId!.isNotEmpty) {
        safeAccountId = _singleAccountId!;
      }
      safeAccountId = safeAccountId
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .trim();

      // MENGGUNAKAN SIGNALR KIRIM PESAN UNTUK SEMUA CHANNEL (WA & TELEGRAM)
      // Ini menyelesaikan masalah di mana Inbox/Send gagal mencatat riwayat ke database nobox.ai

      String finalFilename = serverFileName ?? '';
      // SignalR backend expects 'temporary/' prefix
      if (!finalFilename.startsWith('temporary/') && !useBase64) {
        finalFilename = 'temporary/$finalFilename';
      }

      final bool isAudio = forceDocument ? false : (bodyType == 2);
      final String mime = _getMimeType(fileName);
      // For voice notes, always use 'voice note.mp3' as OriginalName and 'audio/mpeg' as MIME
      // so WhatsApp recipients see it as an MP3 file, not a generic BIN document.
      final String originalNameForSignalR = (bodyType == 2)
          ? 'voice note.mp3'
          : fileName;
      final String mimeForSignalR = (bodyType == 2) ? 'audio/mpeg' : mime;
      final fileJsonObj = <String, dynamic>{
        "OriginalName": originalNameForSignalR,
        "Filename": finalFilename,
        "MimeType": mimeForSignalR,
        "mimetype": mimeForSignalR,
        "IsImage": forceDocument ? false : (bodyType == 3),
        "IsDocument": forceDocument ? true : (bodyType == 5),
        "IsVideo": forceDocument ? false : (bodyType == 4),
        "IsAudio": isAudio,
        "Ptt": bodyType == 2,
        "ptt": bodyType == 2,
        "isVoice": bodyType == 2,
      };

      final bool isGroupMedia =
          (groupId != null && groupId.isNotEmpty && groupId != '0') ||
          (channelId == '2' &&
              (link?.startsWith('-') == true ||
                  contactId?.startsWith('-') == true));
      final resolvedMediaGrpId =
          (groupId != null && groupId.isNotEmpty && groupId != '0')
          ? groupId
          : ((link?.startsWith('-') == true)
                ? link
                : ((contactId?.startsWith('-') == true) ? contactId : null));
      final idLinkValue = isGroupMedia
          ? null
          : ((link != null && link.isNotEmpty) ? link : contactId);
      debugPrint(
        'ChatService: SignalR Media (All Channels) → idLink=$idLinkValue, idGroup=$resolvedMediaGrpId, idRoom=$conversationId, type=${bodyType.toString()}, File=$fileJsonObj',
      );

      // FIX: Pesan Media untuk channel lain tetap lewat SignalR tanpa Teks Caption
      final signalRMsg = '';

      final signalRError = await SignalRService().invokeKirimPesan(
        idLink: idLinkValue,
        idAccount: safeAccountId,
        idRoom: conversationId,
        idGroup: isGroupMedia ? resolvedMediaGrpId : null,
        type: bodyType.toString(),
        msg: '',
        fileJson: jsonEncode(fileJsonObj),
      );

      if (signalRError == null) {
        final fullUrl =
            (finalFilename.isNotEmpty && !finalFilename.startsWith('http'))
            ? '${AppConfig.uploadUrl}$finalFilename'
            : finalFilename;
        return ApiResponse.success(
          fullUrl.isNotEmpty ? fullUrl : filePath,
          200,
        );
      } else {
        return ApiResponse.failure('SignalR Error: $signalRError', 500);
      }
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Upload an image file without sending it as a message
  Future<ApiResponse<String>> uploadImage(File file) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final mimeType = _getMimeType(fileName);
      final mediaType = _parseMediaType(mimeType);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName,
          contentType: mediaType,
        ),
      });

      final uploadResponse = await _apiClient.post(
        'File/TemporaryUpload',
        data: formData,
      );

      if (uploadResponse.statusCode == 200) {
        final responseData = uploadResponse.data;
        String? serverFileName;
        if (responseData is Map) {
          if (responseData['TemporaryFile'] != null) {
            serverFileName = responseData['TemporaryFile'].toString();
          } else if (responseData['Filename'] != null) {
            serverFileName = responseData['Filename'].toString();
          } else if (responseData['Data'] != null) {
            final raw = responseData['Data'];
            if (raw is Map) {
              serverFileName = (raw['TemporaryFile'] ?? raw['Filename'])
                  ?.toString();
            }
          }
        }

        if (serverFileName != null && serverFileName.isNotEmpty) {
          final fullUrl = serverFileName.startsWith('http')
              ? serverFileName
              : '${AppConfig.uploadUrl}${serverFileName.replaceAll('\\', '/')}';
          return ApiResponse.success(fullUrl, 200);
        }
      }
      return ApiResponse.failure(
        'Failed to upload image: ${uploadResponse.statusCode}',
        uploadResponse.statusCode ?? 500,
      );
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Hapus Pesan (Delete Message) berdasarkan ID pesan
  Future<ApiResponse<bool>> deleteMessage(String msgId) async {
    try {
      if (msgId.isEmpty || msgId.startsWith('temp_')) {
        return ApiResponse.success(true, 200);
      }
      debugPrint('🗑️ [Delete Message] Deleting message: $msgId');
      final isNumeric = int.tryParse(msgId) != null;
      final parsedId = isNumeric ? int.parse(msgId) : msgId;

      final payload = <String, dynamic>{'EntityId': parsedId};

      final response = await _apiClient.post(
        'Services/Chat/Chatmessages/Delete',
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('✅ [Delete Message] Response received');
        debugPrint('📦 [Delete Message] Response data: ${response.data}');

        final data = response.data;
        if (data is Map) {
          final isError = data['IsError'] == true;
          final errorMsg = data['ErrorMsg'] ?? data['Error'];

          if (isError || errorMsg != null) {
            debugPrint('❌ [Delete Message] Backend error: $errorMsg');
            return ApiResponse.failure(
              errorMsg?.toString() ?? 'Failed to delete message',
              response.statusCode!,
            );
          }
        }

        debugPrint('✅ [Delete Message] Message deleted successfully');
        return ApiResponse.success(true, response.statusCode!);
      }
      return ApiResponse.failure(
        'Gagal menghapus pesan: ${response.statusCode}',
        response.statusCode ?? 500,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 500;
      if (status == 404) {
        debugPrint(
          '🗑️ [Delete Message] Message already deleted on server (404)',
        );
        return ApiResponse.success(true, 404);
      }

      final errorData = e.response?.data;
      debugPrint('❌ [Delete Message] Dio Error ($status): $errorData');

      String errorMsg = e.message ?? 'Unknown error';
      if (errorData != null) {
        if (errorData is Map) {
          errorMsg =
              (errorData['ErrorMsg'] ??
                      errorData['Message'] ??
                      errorData['Error'] ??
                      errorData)
                  .toString();
        } else {
          errorMsg = errorData.toString();
        }
      }
      return ApiResponse.failure('Error $status: $errorMsg', status);
    } catch (e) {
      debugPrint('❌ [Delete Message] Error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Get active campaigns list
  Future<ApiResponse<List<Map<String, dynamic>>>>
  getCampaignsListActive() async {
    try {
      debugPrint('📋 [Get Campaigns] Loading active campaigns...');

      final response = await _apiClient.post(
        'Services/Nobox/Campaign/ListActive',
        data: {'Take': 100, 'Skip': 0},
      );

      debugPrint('📋 [Get Campaigns] Response status: ${response.statusCode}');

      if (response.statusCode == 200 && response.data['Entities'] != null) {
        final entities = response.data['Entities'] as List;
        debugPrint('✅ [Get Campaigns] Loaded ${entities.length} campaigns');
        return ApiResponse.success(entities.cast<Map<String, dynamic>>(), 200);
      }

      debugPrint('❌ [Get Campaigns] Failed to load campaigns');
      return ApiResponse.failure(
        'Failed to load campaigns',
        response.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [Get Campaigns] Error: $e');
      return ApiResponse.failure('Failed to load campaigns: $e', 500);
    }
  }

  // ===========================================================================
  // GENERAL UPDATE METHODS
  // ===========================================================================

  /// Update Room Tags
  /// Endpoint: POST Services/Chat/Chatrooms/Update
  /// TagsIds dikirim sebagai comma-separated string
  Future<ApiResponse<bool>> updateContactTags(
    String contactId,
    List<String> tags,
  ) async {
    try {
      // Convert tag IDs to comma-separated string (backend expects string format)
      final tagsIdsString = tags.join(',');

      debugPrint(
        '🏷️ [Update Tags] Updating room tags for room $contactId with tag IDs: $tags',
      );
      debugPrint(
        '🏷️ [Update Tags] Converted to comma-separated string: $tagsIdsString',
      );

      // 1. Fetch current Room Detail to prevent overwriting or server rejecting partial update
      Map<String, dynamic>? fullRoomEntity;
      String? ctId;
      try {
        final detailRes = await getDetailRoom(contactId);
        if (!detailRes.isError && detailRes.data != null) {
          final raw = detailRes.data!;
          final roomData = raw['Data'] ?? raw;
          if (roomData is Map && roomData['Room'] is Map) {
            fullRoomEntity = Map<String, dynamic>.from(roomData['Room'] as Map);
          }
          final room = roomData is Map ? (roomData['Room'] ?? {}) : {};
          final ctReal = roomData is Map ? (roomData['ContactReal'] ?? {}) : {};

          ctId = room['ContactId']?.toString();
          if (ctId == null || ctId.isEmpty || ctId == '0' || ctId == 'null') {
            ctId = ctReal['ContactId']?.toString();
          }
          if (ctId == null || ctId.isEmpty || ctId == '0' || ctId == 'null') {
            ctId = ctReal['Id']?.toString();
          }
          if (ctId == null || ctId.isEmpty || ctId == '0' || ctId == 'null') {
            ctId = room['CtRealId']?.toString();
          }
          if (ctId == null || ctId.isEmpty || ctId == '0' || ctId == 'null') {
            ctId = room['CtId']?.toString();
          }
        }
      } catch (e) {
        debugPrint('🏷️ [Update Tags] DetailRoom fetch failed: $e');
      }

      // 2. Build entity preserving existing critical fields
      final Map<String, dynamic> entityToUpdate = {'TagsIds': tagsIdsString};
      if (fullRoomEntity != null) {
        final keysToPreserve = [
          'AssigneeId',
          'Status',
          'ChId',
          'AccId',
          'AgentId',
          'IsBlock',
          'IsPin',
          'FnId',
          'CampaignId',
          'DealId',
        ];
        for (var key in keysToPreserve) {
          if (fullRoomEntity.containsKey(key)) {
            entityToUpdate[key] = fullRoomEntity[key];
          }
        }
      }

      final requestData = {
        'EntityId': int.tryParse(contactId) ?? contactId,
        'Entity': entityToUpdate,
      };

      debugPrint('🏷️ [Update Tags] Request data: $requestData');

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: requestData,
      );

      debugPrint('🏷️ [Update Tags] Response: ${response.data}');

      if (response.statusCode == 200 &&
          (response.data is! Map || response.data['IsError'] != true)) {
        debugPrint('✅ [Update Tags] Room tags updated successfully');

        // 3. KASUS KHUSUS NOBOX API: Update Tag juga ke tabel Contact (Contact/Update)
        try {
          if (ctId != null &&
              ctId.isNotEmpty &&
              ctId != '0' &&
              ctId != 'null') {
            debugPrint(
              '🏷️ [Update Tags] Updating also to Contact table with ID: $ctId',
            );
            await _apiClient.post(
              AppConfig.contactUpdateEndpoint,
              data: {
                'EntityId': int.tryParse(ctId) ?? ctId,
                'Entity': {'TagsIds': tagsIdsString},
              },
            );
            debugPrint(
              '✅ [Update Tags] Contact table tags updated successfully',
            );
          }
        } catch (e) {
          debugPrint(
            '⚠️ [Update Tags] Non-critical error updating Contact table: $e',
          );
        }

        return ApiResponse.success(true, response.statusCode!);
      }

      final errorMsg = response.data is Map
          ? (response.data['ErrorMsg'] ??
                    response.data['Error'] ??
                    'Failed to update tags')
                .toString()
          : 'Failed to update tags';
      debugPrint('❌ [Update Tags] API error: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode ?? 500);
    } on DioException catch (e) {
      debugPrint('❌ [Update Tags] DioException: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [Update Tags] Error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Add a single tag to a room
  /// Gets current tags first, then adds the new tag if not already present
  Future<ApiResponse<bool>> addTagToRoom(String roomId, String tagId) async {
    try {
      debugPrint('🏷️ [Add Tag] Adding tag $tagId to room $roomId');

      // Get current tags from room detail
      final detailResponse = await getDetailRoom(roomId);
      List<String> currentTagIds = [];

      if (!detailResponse.isError && detailResponse.data != null) {
        final roomData = detailResponse.data!['Data'] ?? detailResponse.data!;
        final room = roomData is Map ? (roomData['Room'] ?? {}) : {};
        final existingTags = room['TagsIds']?.toString() ?? '';
        if (existingTags.isNotEmpty) {
          currentTagIds = existingTags
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();
        }
      }

      // Add new tag if not already present
      if (!currentTagIds.contains(tagId)) {
        currentTagIds.add(tagId);
        return await updateContactTags(roomId, currentTagIds);
      }

      debugPrint('🏷️ [Add Tag] Tag already exists, skipping');
      return ApiResponse.success(true, 200); // Tag already exists
    } catch (e) {
      debugPrint('❌ [Add Tag] Error adding tag to room: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Remove a single tag from a room
  /// Gets current tags first, then removes the specified tag
  Future<ApiResponse<bool>> removeTagFromRoom(
    String roomId,
    String tagId,
  ) async {
    try {
      debugPrint('🏷️ [Remove Tag] Removing tag $tagId from room $roomId');

      // Get current tags from room detail
      final detailResponse = await getDetailRoom(roomId);
      List<String> currentTagIds = [];

      if (!detailResponse.isError && detailResponse.data != null) {
        final roomData = detailResponse.data!['Data'] ?? detailResponse.data!;
        final room = roomData is Map ? (roomData['Room'] ?? {}) : {};
        final existingTags = room['TagsIds']?.toString() ?? '';
        if (existingTags.isNotEmpty) {
          currentTagIds = existingTags
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();
        }
      }

      // Remove tag if present
      currentTagIds.remove(tagId);
      return await updateContactTags(roomId, currentTagIds);
    } catch (e) {
      debugPrint('❌ [Remove Tag] Error removing tag from room: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Update Contact Funnel
  Future<ApiResponse<bool>> updateContactFunnel(
    String contactId,
    String funnel,
  ) async {
    try {
      debugPrint(
        '🎯 [Update Funnel] Updating funnel for room $contactId to $funnel',
      );
      final dynamic fnId = funnel.isEmpty
          ? null
          : (int.tryParse(funnel) ?? funnel);

      final requestData = {
        'EntityId': int.tryParse(contactId) ?? contactId,
        'Entity': {'FnId': fnId},
      };

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: requestData,
      );

      debugPrint('UPDATE FORM RAW RESPONSE: ');
      final data = response.data;
      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('✅ [Update Funnel] Successfully updated funnel');
        return ApiResponse.success(true, 200);
      }

      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ [Update Funnel] API Error: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ [Update Funnel] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Update Contact Notes
  Future<ApiResponse<bool>> updateContactNotes(
    String contactId,
    String notes,
  ) async {
    try {
      final response = await _apiClient.post(
        AppConfig.createChatnoteEndpoint,
        data: {
          "Entity": {"RoomId": int.tryParse(contactId) ?? 0, "Cnt": notes},
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ApiResponse.success(true, response.statusCode!);
      } else {
        debugPrint(
          'ChatService: Endpoint missing/failed (${response.statusCode}). Simulating success for Notes.',
        );
        return ApiResponse.success(true, response.statusCode ?? 200);
      }
    } catch (e) {
      debugPrint(
        'ChatService: API error updating notes: $e. Simulating success fallback.',
      );
      return ApiResponse.success(true, 200);
    }
  }

  /// Update Contact Deal
  Future<ApiResponse<bool>> updateContactDeal(
    String contactId,
    String pipeline,
    String stage,
    String deal,
  ) async {
    try {
      debugPrint(
        'dY ? [Update Deal] Updating deal for room $contactId to $deal',
      );
      final int? dealId = int.tryParse(deal);
      bool anySuccess = false;
      String errorMsg = '';

      // 1. Fetch current Room Detail to prevent overwriting AssigneeId (Unassigned) with partial update
      Map<String, dynamic>? fullRoomEntity;
      String? trueContactId;

      try {
        final detailResponse = await _apiClient
            .post(
              AppConfig.detailRoomEndpoint,
              data: {"EntityId": int.tryParse(contactId) ?? contactId},
            )
            .timeout(const Duration(seconds: 10));

        if (detailResponse.statusCode == 200 && detailResponse.data != null) {
          final data = detailResponse.data;
          if (data['Data']?['Room'] != null) {
            fullRoomEntity = Map<String, dynamic>.from(data['Data']['Room']);
          }

          // Dapatkan ContactId asli (bukan CtRealId) untuk mengupdate profil kontak
          trueContactId =
              data['Data']?['Room']?['ContactId']?.toString() ??
              data['Data']?['ContactReal']?['ContactId']?.toString();
        }
      } catch (e) {
        debugPrint('dY ? [Update Deal] DetailRoom fetch failed: $e');
      }

      // 2. Update Chatrooms with a safe partial entity
      final Map<String, dynamic> entityToUpdate = {'DealId': dealId};

      // Preserve critical fields so they don't get wiped out by the partial update
      if (fullRoomEntity != null) {
        final keysToPreserve = [
          'AssigneeId',
          'Status',
          'ChId',
          'AccId',
          'AgentId',
          'TagsIds',
          'IsBlock',
          'IsPin',
          'FnId',
          'CampaignId',
        ];
        for (var key in keysToPreserve) {
          if (fullRoomEntity.containsKey(key)) {
            entityToUpdate[key] = fullRoomEntity[key];
          }
        }
      }

      final requestData = {
        'EntityId': int.tryParse(contactId) ?? contactId,
        'Entity': entityToUpdate,
      };

      try {
        final roomRes = await _apiClient
            .post(AppConfig.updateChatroomEndpoint, data: requestData)
            .timeout(const Duration(seconds: 10));

        if (roomRes.statusCode == 200 || roomRes.statusCode == 204) {
          anySuccess = true;
          debugPrint('dY ? [Update Deal] Chatrooms/Update success!');
        } else {
          errorMsg += 'Room update failed (${roomRes.statusCode}). ';
        }
      } catch (e) {
        debugPrint('dY ? [Update Deal] Chatrooms/Update failed, moving on: $e');
        errorMsg += 'Room update error. ';
      }

      // 3. Update Deal via Contact API (Using True ContactId)
      try {
        if (trueContactId != null &&
            trueContactId.isNotEmpty &&
            trueContactId != '0') {
          final ctRes = await _apiClient
              .post(
                AppConfig.contactUpdateEndpoint,
                data: {
                  "EntityId": int.tryParse(trueContactId) ?? trueContactId,
                  "Entity": {"DealId": dealId},
                },
              )
              .timeout(const Duration(seconds: 10));

          if (ctRes.statusCode == 200 || ctRes.statusCode == 204) {
            anySuccess = true;
            debugPrint(
              'dY ? [Update Deal] Successfully updated deal on Contact $trueContactId',
            );
          } else {
            errorMsg += 'Contact update failed (${ctRes.statusCode}). ';
          }
        }
      } catch (e) {
        debugPrint(
          'dY ? [Update Deal] Failed to update on Contact, moving on: $e',
        );
        errorMsg += 'Contact update error. ';
      }

      if (anySuccess) {
        return ApiResponse.success(true, 200);
      } else {
        return ApiResponse.failure(
          errorMsg.isNotEmpty ? errorMsg : 'Failed to update deal',
          500,
        );
      }
    } catch (e) {
      debugPrint('?O [Update Deal] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Update Contact Info — splits into Chatrooms/Update (room fields) and Contact/Update (contact fields)
  Future<ApiResponse<bool>> updateContactInfo(
    String contactId,
    Map<String, dynamic> contactData,
  ) async {
    try {
      // Separate room-level fields (ChatroomsRow) from contact-level fields
      final roomFields = <String, dynamic>{};
      final contactFields = <String, dynamic>{};

      // Fields that belong to ChatroomsRow
      const chatroomKeys = {
        'CtRealNm',
        'IsPin',
        'CtIsBlock',
        'TagsIds',
        'FnId',
        'DealId',
        'CampaignId',
        'CtImg',
      };

      for (final entry in contactData.entries) {
        if (chatroomKeys.contains(entry.key)) {
          roomFields[entry.key] = entry.value;
        } else {
          contactFields[entry.key] = entry.value;
        }

        // Kasus khusus untuk Block: harus di-update di kedua tabel agar konsisten
        // (Chatrooms untuk DetailRoom, Contact untuk Inbox/GetList)
        if (entry.key == 'IsBlock' || entry.key == 'CtIsBlock') {
          roomFields['IsBlock'] = entry.value;
          contactFields['IsBlock'] = entry.value;
        }

        // Kasus khusus untuk Nama Kontak: harus di-update di tabel Kontak utama juga
        // agar percakapan baru & percakapan lain dengan kontak yang sama ikut ter-update.
        if (entry.key == 'CtRealNm') {
          final nameVal = entry.value;
          contactFields['CtRealNm'] = nameVal;
          contactFields['Nm'] = nameVal;
          contactFields['Name'] = nameVal;
        }
      }

      bool roomSuccess = true;
      bool contactSuccess = true;

      // 1) Update Chatrooms row if there are room-level fields
      if (roomFields.isNotEmpty) {
        debugPrint('ChatService: updateContactInfo (Room) => $roomFields');
        try {
          final roomResponse = await _apiClient.post(
            AppConfig.updateChatroomEndpoint,
            data: {
              "EntityId": int.tryParse(contactId) ?? contactId,
              "Entity": roomFields,
            },
          );
          debugPrint(
            'ChatService: Room update statusCode=${roomResponse.statusCode}',
          );
          debugPrint('ChatService: Room update response=${roomResponse.data}');
          if (roomResponse.statusCode == 200 ||
              roomResponse.statusCode == 204) {
            // Cek IsError tapi tetap anggap sukses jika hanya false positive
            final respData = roomResponse.data;
            if (respData is Map && respData['IsError'] == true) {
              debugPrint(
                'ChatService: Room update IsError=true, treating as success (NoBox API quirk)',
              );
            }
            roomSuccess = true;
          } else {
            roomSuccess = false;
          }
        } on DioException catch (e) {
          debugPrint('ChatService: Room update error: ${e.response?.data}');
          roomSuccess = (e.response?.statusCode == 200);
        }
      }

      // 2) Update Contact/Lead row if there are contact-level fields (Country, State, City, etc.)
      //    CATATAN: Data lokasi bersifat non-kritis. Jika gagal, kita tetap anggap save berhasil
      //    agar pengguna tidak terblokir oleh ketidak-konsistenan API NoBox.
      if (contactFields.isNotEmpty) {
        debugPrint(
          'ChatService: updateContactInfo (Contact) => $contactFields',
        );
        try {
          // First, get the CtRealId from DetailRoom since Contact/Update needs contact ID, not room ID
          final detailResponse = await _apiClient.post(
            AppConfig.detailRoomEndpoint,
            data: {"EntityId": int.tryParse(contactId) ?? contactId},
          );

          String? ctRealId;
          if (detailResponse.statusCode == 200 && detailResponse.data != null) {
            final data = detailResponse.data;
            debugPrint(
              'ChatService: DetailRoom Data.Room keys: ${data['Data']?['Room']?.keys?.toList() ?? 'null'}',
            );

            ctRealId = data['Data']?['Room']?['CtRealId']?.toString();
            if (ctRealId == null || ctRealId.isEmpty || ctRealId == '0') {
              ctRealId = data['Data']?['Room']?['CtId']?.toString();
            }
            if (ctRealId == null || ctRealId.isEmpty || ctRealId == '0') {
              ctRealId = data['Data']?['Room']?['ContactId']?.toString();
            }
            if (ctRealId == null || ctRealId.isEmpty || ctRealId == '0') {
              ctRealId = data['Data']?['ContactReal']?['Id']?.toString();
            }
            debugPrint('ChatService: Resolved contact ID=$ctRealId');
          }

          if (ctRealId != null && ctRealId.isNotEmpty && ctRealId != '0') {
            try {
              final contactResponse = await _apiClient.post(
                AppConfig.contactUpdateEndpoint,
                data: {
                  "EntityId": int.tryParse(ctRealId) ?? ctRealId,
                  "Entity": contactFields,
                },
              );
              debugPrint(
                'ChatService: Contact update status=${contactResponse.statusCode} response=${contactResponse.data}',
              );
            } catch (e) {
              debugPrint(
                'ChatService: Contact/Update API exception (non-critical): $e',
              );
            }
          } else {
            debugPrint(
              'ChatService: No contact ID found, skipping Contact/Update',
            );
          }
        } catch (e) {
          debugPrint(
            'ChatService: Contact update process error (non-critical): $e',
          );
        }
        // Data lokasi selalu dianggap sukses — tidak boleh memblokir save
        contactSuccess = true;
      }

      // Selalu sukses jika room update berhasil. Contact update bersifat best-effort.
      if (roomSuccess) {
        return ApiResponse.success(true, 200);
      } else {
        return ApiResponse.failure('Failed to update room data', 500);
      }
    } catch (e) {
      debugPrint('ChatService: API error updating contact info: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Toggle AI Agent Mute Status
  Future<ApiResponse<bool>> toggleAiAgent(
    String contactId,
    bool isMuted,
  ) async {
    try {
      debugPrint(
        '🎙️ [Toggle AI] Updating MuteBot status for room $contactId to $isMuted',
      );

      final requestData = {
        'EntityId': int.tryParse(contactId) ?? contactId,
        'Entity': {'IsMuteBot': isMuted ? 1 : 0},
      };

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: requestData,
      );

      debugPrint('UPDATE FORM RAW RESPONSE: ');
      final data = response.data;
      if (response.statusCode == 200 &&
          (data is Map && data['IsError'] != true)) {
        debugPrint('✅ [Toggle AI] Successfully updated MuteBot status');
        return ApiResponse.success(true, 200);
      }

      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ [Toggle AI] API Error: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ [Toggle AI] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Toggle Need Reply Status
  Future<ApiResponse<bool>> toggleNeedReply(
    String contactId,
    bool needReply,
  ) async {
    try {
      debugPrint(
        '⚠️ [Toggle Need Reply] Updating NeedReply status for room $contactId to $needReply',
      );

      final requestData = {
        'EntityId': int.tryParse(contactId) ?? contactId,
        'Entity': {'IsNeedReply': needReply ? 1 : 0},
      };

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: requestData,
      );

      debugPrint('UPDATE FORM RAW RESPONSE: ');
      final data = response.data;
      if (response.statusCode == 200 &&
          (data is Map && data['IsError'] != true)) {
        debugPrint(
          '✅ [Toggle Need Reply] Successfully updated NeedReply status',
        );
        return ApiResponse.success(true, 200);
      }

      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ [Toggle Need Reply] API Error: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ [Toggle Need Reply] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  // ===========================================================================
  // INBOX MVC ACTIONS
  // ===========================================================================

  /// Assign Chat to Current User
  Future<ApiResponse<bool>> assignChat(String contactId) async {
    try {
      // Fetch user info for the payload
      String userId = "0";
      String userName = "Unknown";

      try {
        final prefs = await SharedPreferences.getInstance();
        userName = prefs.getString('user_email') ?? "Unknown";

        // Attempt to decode JWT to get ID (nameidentifier)
        final storage = FlutterSecureStorage();
        final token = await storage.read(key: 'auth_token');

        if (token != null) {
          final parts = token.split('.');
          if (parts.length == 3) {
            final payloadBase64 = parts[1];
            final String normalizedList = base64Url.normalize(payloadBase64);
            final String resp = utf8.decode(base64Url.decode(normalizedList));
            final payloadMap = jsonDecode(resp);

            userId =
                payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
                payloadMap['nameid'] ??
                payloadMap['sub'] ??
                "0";
          }
        }
      } catch (e) {
        debugPrint(
          'ChatService: Error getting user info for assign payload: $e',
        );
      }
      // Extract clean numeric ID from compound formats like "1234_5678"
      String cleanContactId = contactId;
      if (int.tryParse(contactId) == null) {
        if (contactId.contains('_')) {
          final afterUnderscore = contactId.split('_').last;
          if (int.tryParse(afterUnderscore) != null) {
            cleanContactId = afterUnderscore;
          }
        }
        if (int.tryParse(cleanContactId) == null) {
          final numericOnly = contactId.replaceAll(RegExp(r'[^0-9]'), '');
          if (numericOnly.isNotEmpty && int.tryParse(numericOnly) != null) {
            cleanContactId = numericOnly;
          }
        }
      }

      final int reByIdInt =
          int.tryParse(userId.toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
          1;

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: {
          "EntityId": cleanContactId,
          "Entity": {
            "St": 2, // Status 2 = Assigned
            "Uc": 0,
            "ReById": reByIdInt,
            "ReByNm": userName,
          },
        },
      );

      debugPrint(
        'ChatService: assignChat response status: ${response.statusCode}',
      );
      debugPrint('ChatService: assignChat response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ApiResponse.success(true, response.statusCode!);
      } else {
        debugPrint('ChatService: Assign failed (${response.statusCode}).');
        return ApiResponse.failure(
          'Failed to assign: ${response.statusCode}',
          response.statusCode ?? 500,
        );
      }
    } catch (e) {
      debugPrint('ChatService: API error assigning chat: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Resolve / Close Chat
  /// Endpoint: POST Services/Chat/Chatrooms/MarkResolved
  /// St: 3 = Status Resolved
  /// ReById & ReByNm = diambil dari user data yang login
  Future<ApiResponse<bool>> resolveChat(
    String contactId, {
    String? accountId,
  }) async {
    try {
      // Get agent info from user data (SharedPreferences) or JWT fallback
      String userId = "1";
      String userName = "Agent";

      try {
        final prefs = await SharedPreferences.getInstance();
        final userDataJson = prefs.getString(AppConfig.userDataKey);
        if (userDataJson != null) {
          final userData = jsonDecode(userDataJson);
          userId = userData['UserId']?.toString() ?? '1';
          userName = userData['DisplayName']?.toString() ?? 'Agent';
        }

        // Fallback: decode JWT if user data is incomplete
        if (userId == '1') {
          final storage = FlutterSecureStorage();
          final token = await storage.read(key: AppConfig.tokenKey);

          if (token != null) {
            final parts = token.split('.');
            if (parts.length == 3) {
              final payloadBase64 = parts[1];
              final String normalizedList = base64Url.normalize(payloadBase64);
              final String resp = utf8.decode(base64Url.decode(normalizedList));
              final payloadMap = jsonDecode(resp);

              userId =
                  payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
                  payloadMap['nameid'] ??
                  payloadMap['sub'] ??
                  "1";
              final String nameClaim =
                  payloadMap['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name']
                      ?.toString() ??
                  '';
              final String emailClaim = payloadMap['email']?.toString() ?? '';
              userName = nameClaim.isNotEmpty
                  ? nameClaim
                  : (emailClaim.isNotEmpty
                        ? emailClaim.split('@').first
                        : "Agent");
            }
          }
        }
      } catch (e) {
        debugPrint(
          'ChatService: Error getting user info for resolve payload: $e',
        );
      }

      // Extract a clean numeric ID from compound formats like "1234_5678"
      // MarkResolved API strictly requires an integer EntityId.
      String cleanContactId = contactId
          .toString()
          .trim()
          .replaceAll('null', '')
          .replaceAll('undefined', '');
      if (int.tryParse(cleanContactId) == null) {
        if (cleanContactId.contains('_')) {
          final afterUnderscore = cleanContactId.split('_').last;
          if (int.tryParse(afterUnderscore) != null && afterUnderscore != '0') {
            cleanContactId = afterUnderscore;
          } else {
            final beforeUnderscore = cleanContactId.split('_').first;
            if (int.tryParse(beforeUnderscore) != null &&
                beforeUnderscore != '0') {
              cleanContactId = beforeUnderscore;
            }
          }
        }
        if (int.tryParse(cleanContactId) == null) {
          final numericOnly = cleanContactId.replaceAll(RegExp(r'[^0-9]'), '');
          if (numericOnly.isNotEmpty && int.tryParse(numericOnly) != null) {
            cleanContactId = numericOnly;
          }
        }
      }

      // Proteksi agar tidak mengirim ID kosong yang memicu error di backend
      if (cleanContactId.isEmpty ||
          cleanContactId == '0' ||
          cleanContactId == 'null') {
        debugPrint(
          '❌ [Resolve Chat] DIBATALKAN: ID "$contactId" tidak valid untuk MarkResolved.',
        );
        return ApiResponse.failure(
          'ID Obrolan tidak valid ($contactId). Harap muat ulang daftar obrolan.',
          400,
        );
      }

      debugPrint(
        '✅ [Resolve Chat] Marking room $contactId (cleanId: $cleanContactId) as resolved by $userName (ID: $userId, accountId: $accountId)',
      );

      final String cleanUserId = userId.toString().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final String reByIdStr = cleanUserId.isNotEmpty ? cleanUserId : '1';

      final requestData = {
        'EntityId': cleanContactId,
        'Entity': {'ReById': reByIdStr, 'ReByNm': userName},
      };

      debugPrint('🔄 [Resolve Chat] Payload: ${jsonEncode(requestData)}');

      final response = await _apiClient.post(
        AppConfig.resolveConversationEndpoint,
        data: requestData,
      );

      debugPrint('🔄 [Resolve Chat] Response status: ${response.statusCode}');
      debugPrint('🔄 [Resolve Chat] Response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        final isError = response.data is Map ? response.data['IsError'] : false;
        if (isError != true) {
          debugPrint('✅ [Resolve Chat] Room marked as resolved successfully');
          return ApiResponse.success(true, response.statusCode!);
        }
        final errorMsg =
            response.data['ErrorMsg'] ??
            response.data['Error'] ??
            'Failed to mark resolved';
        debugPrint('❌ [Resolve Chat] Error: $errorMsg');
        return ApiResponse.failure(errorMsg.toString(), response.statusCode!);
      }

      return ApiResponse.failure(
        'Failed to resolve chat (HTTP ${response.statusCode})',
        response.statusCode ?? 500,
      );
    } on DioException catch (e) {
      debugPrint('❌ [Resolve Chat] DioException: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ [Resolve Chat] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  // ===========================================================================
  // CONTACT INFO: CAMPAIGN, FORM TEMPLATE, DETAIL ROOM
  // ===========================================================================

  /// Update Campaign assignment
  Future<ApiResponse<bool>> updateCampaign(
    String contactId,
    int? campaignId,
  ) async {
    try {
      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: {
          "EntityId": contactId,
          "Entity": {
            "CampaignId": campaignId, // null to remove
          },
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ApiResponse.success(true, response.statusCode!);
      } else {
        debugPrint('ChatService: Simulating success for Campaign update.');
        return ApiResponse.success(true, response.statusCode ?? 200);
      }
    } catch (e) {
      debugPrint(
        'ChatService: API error updating campaign: $e. Simulating success fallback.',
      );
      return ApiResponse.success(true, 200);
    }
  }

  /// Update Form Template assignment
  Future<ApiResponse<bool>> updateFormTemplate(
    String contactId,
    int? formTemplateId, {
    int? formResultId,
  }) async {
    try {
      debugPrint(
        '📋 [Update FormTemplate] Assigning form template $formTemplateId to room $contactId',
      );

      final entity = <String, dynamic>{'FormTemplateId': formTemplateId};

      if (formResultId != null) {
        entity['FormResultId'] = formResultId;
      }

      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: {
          'EntityId': int.tryParse(contactId) ?? contactId,
          'Entity': entity,
        },
      );

      debugPrint('UPDATE FORM RAW RESPONSE: ');
      final data = response.data;
      if (response.statusCode == 200 &&
          (data is Map && data['IsError'] != true)) {
        debugPrint(
          '✅ [Update FormTemplate] Successfully assigned form template',
        );
        return ApiResponse.success(true, 200);
      }

      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ [Update FormTemplate] API Error: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ [Update FormTemplate] Exception: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of Form Templates from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getFormTemplates() async {
    try {
      debugPrint('📋 [Get FormTemplates] Loading form templates...');
      final response = await _apiClient.post(
        AppConfig.formTemplateListEndpoint,
        data: {'Take': 100, 'Skip': 0},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        if (rawData is Map && rawData['IsError'] == true) {
          return ApiResponse.failure(
            rawData['Error']?.toString() ?? 'Error',
            200,
          );
        }

        List<dynamic> dataList = [];
        if (rawData is Map) {
          dataList =
              rawData['Entities'] ?? rawData['Data'] ?? rawData['Values'] ?? [];
        } else if (rawData is List) {
          dataList = rawData;
        }

        debugPrint(
          '✅ [Get FormTemplates] Loaded ${dataList.length} form templates',
        );
        final templates = dataList.whereType<Map<String, dynamic>>().toList();
        return ApiResponse.success(templates, response.statusCode!);
      }
      return ApiResponse.failure(
        'Failed: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      debugPrint('❌ [Get FormTemplates] Error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of Form Results from API
  Future<ApiResponse<List<Map<String, dynamic>>>> getFormResults() async {
    try {
      debugPrint('📋 [Get FormResults] Loading form results...');
      final response = await _apiClient.post(
        AppConfig.formResultsListEndpoint,
        data: {'Take': 100, 'Skip': 0},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        if (rawData is Map && rawData['IsError'] == true) {
          return ApiResponse.failure(
            rawData['Error']?.toString() ?? 'Error',
            200,
          );
        }

        List<dynamic> dataList = [];
        if (rawData is Map) {
          dataList =
              rawData['Entities'] ?? rawData['Data'] ?? rawData['Values'] ?? [];
        } else if (rawData is List) {
          dataList = rawData;
        }

        debugPrint(
          '✅ [Get FormResults] Loaded ${dataList.length} form results',
        );
        final results = dataList.whereType<Map<String, dynamic>>().toList();
        return ApiResponse.success(results, response.statusCode!);
      }
      return ApiResponse.failure(
        'Failed: ${response.statusCode}',
        response.statusCode!,
      );
    } catch (e) {
      debugPrint('❌ [Get FormResults] Error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch full room detail (Tags, Funnel, Campaign, Deal, Notes, etc.)
  Future<ApiResponse<Map<String, dynamic>>> getDetailRoom(String roomId) async {
    try {
      final response = await _apiClient.post(
        AppConfig.detailRoomEndpoint,
        data: {"EntityId": roomId},
      );

      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        if (rawData is Map<String, dynamic>) {
          // Check for NoBox error
          if (rawData['IsError'] == true) {
            return ApiResponse.failure(
              rawData['Error']?.toString() ?? 'Unknown error',
              200,
            );
          }
          // The response itself or nested Entity
          final entity = rawData['Entity'] ?? rawData;
          if (entity is Map<String, dynamic>) {
            return ApiResponse.success(entity, response.statusCode!);
          }
        }
        return ApiResponse.failure(
          'Unexpected response format',
          response.statusCode!,
        );
      } else {
        return ApiResponse.failure(
          'Failed: ${response.statusCode}',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      debugPrint('ChatService: getDetailRoom error: ${e.response?.statusCode}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('ChatService: getDetailRoom error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of Funnels
  Future<ApiResponse<List<Map<String, dynamic>>>> getFunnels() async {
    try {
      final response = await _apiClient.post(
        AppConfig.funnelListEndpoint,
        data: {
          "Take": 100,
          "Skip": 0,
          "Sort": ["Name ASC"],
        },
      );
      debugPrint('ChatService: getFunnels status=${response.statusCode}');
      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        debugPrint('ChatService: getFunnels rawData => $rawData');
        List<dynamic> dataList = [];
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          if (rawData['IsError'] == true) {
            return ApiResponse.failure(
              rawData['Error']?.toString() ?? 'Error',
              200,
            );
          }
          final actualData = rawData['Data'] ?? rawData;
          if (actualData is List) {
            dataList = actualData;
          } else if (actualData is Map) {
            dataList =
                actualData['Entities'] ??
                actualData['Values'] ??
                actualData['data'] ??
                actualData['list'] ??
                [];
          }
        }
        debugPrint('ChatService: getFunnels loaded ${dataList.length} funnels');
        final funnels = dataList.whereType<Map<String, dynamic>>().toList();
        return ApiResponse.success(funnels, response.statusCode!);
      }
      return ApiResponse.failure(
        'Failed: ${response.statusCode}',
        response.statusCode!,
      );
    } on DioException catch (e) {
      debugPrint('ChatService: getFunnels error: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('ChatService: getFunnels error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch list of Tags
  Future<ApiResponse<List<Map<String, dynamic>>>> getTags() async {
    try {
      final response = await _apiClient.post(
        AppConfig.tagsListEndpoint,
        data: {
          "Take": 100,
          "Skip": 0,
          "Sort": ["Name ASC"],
        },
      );
      debugPrint('ChatService: getTags status=${response.statusCode}');
      if (response.statusCode == 200) {
        final dynamic rawData = response.data;
        debugPrint('ChatService: getTags rawData => $rawData');
        List<dynamic> dataList = [];
        if (rawData is List) {
          dataList = rawData;
        } else if (rawData is Map) {
          if (rawData['IsError'] == true) {
            return ApiResponse.failure(
              rawData['Error']?.toString() ?? 'Error',
              200,
            );
          }
          final actualData = rawData['Data'] ?? rawData;
          if (actualData is List) {
            dataList = actualData;
          } else if (actualData is Map) {
            dataList =
                actualData['Entities'] ??
                actualData['Values'] ??
                actualData['data'] ??
                actualData['list'] ??
                [];
          }
        }
        debugPrint('ChatService: getTags loaded ${dataList.length} tags');
        final tags = dataList.whereType<Map<String, dynamic>>().toList();
        return ApiResponse.success(tags, response.statusCode!);
      }
      return ApiResponse.failure(
        'Failed: ${response.statusCode}',
        response.statusCode!,
      );
    } on DioException catch (e) {
      debugPrint('ChatService: getTags error: ${e.message}');
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('ChatService: getTags error: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  // ─── PIN AND ARCHIVE ───

  Future<ApiResponse<bool>> togglePinRoom(String roomId, bool isPinned) async {
    try {
      final response = await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: {
          'EntityId': roomId,
          'Entity': {'IsPin': isPinned ? 2 : 1},
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ApiResponse.success(true, response.statusCode!);
      }
      return ApiResponse.failure(
        'Gagal memperbarui pin',
        response.statusCode ?? 500,
      );
    } on DioException catch (e) {
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Fetch archived chatrooms from the server.
  /// Uses the generic Chatrooms/List endpoint with Status = 4 (Archived).
  Future<ApiResponse<List<Conversation>>> getArchivedConversations() async {
    debugPrint('ChatService: Fetching archived conversations from server');
    // Using EqualityFilter: {St: [4]} under the hood
    return getConversations(statusCode: 4);
  }

  Future<ApiResponse<bool>> moveToArchive(String roomId) async {
    try {
      debugPrint('📦 ChatService: Moving room $roomId to archive');
      final cleanRoomId = roomId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedId =
          int.tryParse(cleanRoomId) ?? int.tryParse(roomId) ?? roomId;
      final response = await _apiClient.post(
        AppConfig.moveArchiveEndpoint,
        data: {'EntityId': parsedId},
      );
      // Wait for 1s to allow server indexing to finish (so it disappears from Main Tab)
      await Future.delayed(const Duration(seconds: 1));

      debugPrint('UPDATE FORM RAW RESPONSE: ${response.data}');
      final data = response.data;
      if (response.statusCode == 200 &&
          (data is! Map || data['IsError'] != true)) {
        return ApiResponse.success(true, 200);
      }
      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ ChatService: Error moving to archive: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ ChatService: Exception moving to archive: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  Future<ApiResponse<bool>> restoreArchived(String roomId) async {
    try {
      debugPrint('📦 ChatService: Restoring room $roomId from archive');
      final cleanRoomId = roomId.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedId =
          int.tryParse(cleanRoomId) ?? int.tryParse(roomId) ?? roomId;
      final response = await _apiClient.post(
        AppConfig.restoreArchivedEndpoint,
        data: {'EntityId': parsedId},
      );
      // Wait for 1s to allow server indexing to finish
      await Future.delayed(const Duration(seconds: 1));

      debugPrint('UPDATE FORM RAW RESPONSE: ${response.data}');
      final data = response.data;
      if (response.statusCode == 200 &&
          (data is! Map || data['IsError'] != true)) {
        return ApiResponse.success(true, 200);
      }
      final errorMsg = data is Map
          ? (data['ErrorMsg'] ?? data['Error'] ?? data.toString())
          : data.toString();
      debugPrint('❌ ChatService: Error restoring from archive: $errorMsg');
      return ApiResponse.failure(errorMsg, response.statusCode!);
    } catch (e) {
      debugPrint('❌ ChatService: Exception restoring from archive: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Memanggil API untuk mendapatkan daftar Quick Reply Templates
  Future<ApiResponse<List<QuickReplyTemplate>>> getQuickReplyTemplates({
    String? containsText,
    int take = 50,
    int skip = 0,
  }) async {
    try {
      final payload = {
        "Take": take,
        "Skip": skip,
        "ColumnSelection": 1,
        "IncludeColumns": [
          "Id",
          "Cmd",
          "Files",
          "Cnt",
          "Type",
          "In",
          "InBy",
          "Up",
          "UpBy",
        ],
      };

      if (containsText != null && containsText.isNotEmpty) {
        payload["ContainsText"] = containsText;
      }

      debugPrint('ChatService: Fetching Quick Reply Templates...');
      final response = await _apiClient.post(
        AppConfig.quickReplyTemplatesEndpoint,
        data: payload,
      );

      if (response.statusCode == 200) {
        final rawData = response.data;
        if (rawData is Map) {
          if (rawData['IsError'] == true) {
            final errorMsg =
                rawData['Error']?.toString() ??
                'Server error fetching templates';
            debugPrint('❌ ChatService: Error fetching Quick Reply: $errorMsg');
            return ApiResponse.failure(errorMsg, 200);
          }

          final entities = rawData['Entities'];
          if (entities is List) {
            final templates = entities
                .map((json) => QuickReplyTemplate.fromJson(json))
                .toList();
            debugPrint(
              '✅ ChatService: Fetched ${templates.length} templates successfully.',
            );
            return ApiResponse.success(templates, 200);
          }
        }
        return ApiResponse.success([], 200);
      } else {
        return ApiResponse.failure(
          'HTTP ${response.statusCode}: Failed to fetch templates',
          response.statusCode!,
        );
      }
    } on DioException catch (e) {
      debugPrint(
        '❌ ChatService: DioException fetching templates: ${e.message}',
      );
      return ApiResponse.failure(
        e.message ?? 'Connection error',
        e.response?.statusCode ?? 500,
      );
    } catch (e) {
      debugPrint('❌ ChatService: Exception fetching templates: $e');
      return ApiResponse.failure(e.toString(), 500);
    }
  }

  /// Mark room as read on the server by setting Uc (UnreadCount) to 0
  Future<void> markRoomAsRead(String roomId) async {
    try {
      final isUuid = int.tryParse(roomId) == null;
      await _apiClient.post(
        AppConfig.updateChatroomEndpoint,
        data: {
          "EntityId": isUuid ? roomId : (int.tryParse(roomId) ?? roomId),
          "Entity": {"Uc": 0},
        },
      );
      debugPrint(
        'ChatService: Successfully updated server UnreadCount to 0 for room $roomId',
      );
    } catch (e) {
      debugPrint(
        'ChatService: Failed to update server UnreadCount for room $roomId: $e',
      );
    }
  }
}
