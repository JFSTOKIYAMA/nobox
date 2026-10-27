import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/message.dart';
import '../services/chat_service.dart';
import '../services/signalr_service.dart';
import '../model/conversation.dart';
import '../model/api_response.dart';
import '../services/push_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// =====================================================================
// FITUR: Provider Chat Utama
// FILE: lib/core/providers/chat_provider.dart
// BARIS AWAL: 13 (setelah komentar ini)
// FUNGSI: Mengelola state daftar chat utama, pagination, fitur pencarian, filter lanjutan, dan integrasi SignalR
// =====================================================================
class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();
  List<ChatModel> _chats = [];
  // Master list berisi SEMUA percakapan (semua status) yang terakhir berhasil
  // di-load/fetch dari server saat tab aktif adalah 'All'. Dipakai sebagai
  // sumber truth untuk filter lokal (All/Unassigned/Assigned/Resolved) agar
  // perpindahan tab instan & badge tab tidak ikut hilang/terpotong.
  List<ChatModel> _allMasterChats = [];

  ChatProvider() {
    // Muat persisted state HANYA SEKALI di awal; jangan diulang di fetchChats().
    _loadPersistedState();
  }
  bool _isLoading = false;
  String? _error;
  // Error khusus dari fetchChats() (memuat daftar percakapan).
  // Dipisah dari _error karena _error juga dipakai aksi lain (arsip, tag, dll).
  String? _fetchError;
  Timer? _signalRRefreshTimer;

  // ANR/perf: penulisan SharedPreferences di-debounce agar tidak menulis
  // berulang-ulang (per item chat) saat fetch/refresh.
  Timer? _saveReadDebounce;
  Timer? _savePinnedDebounce;
  Timer? _saveArchivedDebounce;

  // Debounce pemanggilan server saat user berpindah-pindah tab filter dengan
  // cepat. Memastikan server hanya di-hit sekali untuk tab terakhir yang dipilih.
  Timer? _tabFetchDebounce;

  // ANR FIX: Batch notifyListeners to prevent UI freeze when multiple
  // SignalR events arrive rapidly (e.g., message burst).
  Timer? _notifyDebounce;
  bool _pendingNotify = false;

  // Cache waktu terakhir reference data (funnels/tags/agents/links/accounts/
  // contacts) diambil. Data ini tidak perlu di-fetch ulang setiap polling.
  DateTime? _lastReferenceDataFetch;

  // Guard agar refreshFirstPage tidak berjalan bertumpuk (mis. banyak event
  // SignalR datang bersamaan) yang bisa membuat UI sibuk dan terasa freeze.
  bool _isRefreshingFirstPage = false;

  // Pagination state
  static const int _pageSize = 25;
  int _currentSkip = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  String _searchQuery = '';
  String _activeFilter = 'All'; // All, Unassigned, Assigned, Resolved

  String? _filterMuteAi;
  String? _filterReadStatus;
  String? _filterChannel;
  String? _filterChatType;

  // New Advanced Filters
  List<String> _filterAccountIds = [];
  String? _filterContact;
  String? _filterLink;
  String? _filterGroup;
  String? _filterCampaign;
  String? _filterFunnel;
  String? _filterDeal;
  String? _filterTags;
  String? _filterHumanAgent;

  // Persisted local state
  Set<String> _pinnedIds = {};
  Set<String> _archivedIds = {};
  Set<String> _readIds = {};
  Set<String> _starredMessageIds = {};
  final List<Map<String, dynamic>> _starredMessages = [];

  bool _isDisposed = false;

  // Request tracking untuk mencegah race condition saat ganti tab cepat
  int _fetchGeneration = 0;

  /// Debounced notifyListeners to batch rapid updates (ANR prevention)
  /// Call this instead of notifyListeners() in hot paths (SignalR handlers, etc.)
  void _notifyDebounced() {
    if (_isDisposed) return;
    if (_pendingNotify) return; // Already scheduled

    _pendingNotify = true;
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 16), () {
      // ~1 frame
      if (!_isDisposed) {
        _pendingNotify = false;
        notifyListeners();
      }
    });
  }

  // FIX: Unread Override Shield
  // Backend kadang mereturn UnreadCount = 0 pada API/SignalR jika aplikasi sedang berjalan di foreground,
  // padahal User belum membuka room tersebut. Map ini memaksa nilai unread count lokal tetap eksis
  // sampai User benar-benar meng-klik/membuka (markAsRead) room tersebut.
  final Map<String, int> _localUnreadOverrides = {};

  static const String _pinnedKey = 'pinned_chats';
  static const String _archivedKey = 'archived_chats';
  static const String _readKey = 'read_chats';
  static const String _starredKey = 'starred_messages';
  static const String _starredDataKey = 'starred_messages_data';
  // Key untuk menyimpan nama kontak yang sudah di-save user secara lokal
  static const String _savedContactNamesKey = 'saved_contact_names';
  // Key untuk menyimpan data lokasi kontak secara lokal
  static const String _savedContactLocationsKey = 'saved_contact_locations';
  // Key untuk menyimpan override pesan lokal (supaya bertahan saat hot restart)
  static const String _localOverridesKey = 'local_overrides';
  // Key untuk menyimpan nama agent yang diassign agar tidak revert saat tombol back atau refresh
  static const String _savedAgentNamesKey = 'saved_agent_names';
  // Key untuk menyimpan status block/unblock lokal agar kontak baru tidak otomatis dianggap terblokir oleh backend NoBox
  static const String _savedBlockStatesKey = 'saved_block_states';
  // Key untuk menyimpan cache avatar URL terbaru dari DetailRoom
  static const String _cachedAvatarUrlsKey = 'cached_avatar_urls';

  // Map: roomId → nama kontak yang sudah disave (persisten melewati hot restart & refresh)
  Map<String, String> _savedContactNames = {};
  // Map: roomId → data lokasi kontak {Country, State, City, Address, Postal}
  Map<String, Map<String, String>> _savedContactLocations = {};
  // Map: roomId → nama agent yang ditugaskan (persisten melewati refresh & restart)
  Map<String, String> _savedAgentNames = {};
  // Map: roomId → status blokir lokal (true=blocked, false=unblocked)
  Map<String, bool> _savedBlockStates = {};
  // Map: roomId → URL avatar terbaru (diambil dari DetailRoom, untuk menggantikan URL stale dari list API)
  Map<String, String> _cachedAvatarUrls = {};

  /// Mendapatkan status blokir yang akurat dan melindunginya dari nilai default keliru pada API NoBox untuk kontak baru
  bool resolveIsBlocked(String roomId, bool serverIsBlocked) {
    if (_savedBlockStates.containsKey(roomId)) {
      return _savedBlockStates[roomId]!;
    }
    return serverIsBlocked;
  }

  /// Cek apakah suatu room sedang diarsipkan secara lokal atau di state memori.
  /// HANYA mencocokkan berdasarkan RoomId (dan varian numeriknya).
  /// TIDAK lagi mencocokkan contactId/ctRealId/link/extId agar status arsip
  /// sebuah percakapan lama TIDAK "menular" ke room BARU milik kontak yang sama.
  bool isRoomArchived(String roomId) {
    if (roomId.isEmpty) return false;

    // Bangun semua varian ID kandidat untuk pencocokan fleksibel:
    // - roomId mentah (bisa mengandung prefix tenant_channel, mis. "1022_14949")
    // - varian angka murni ("102214949")
    // - bagian setelah underscore untuk ID komposit ("1022_14949" -> "14949")
    final candidates = <String>{
      roomId,
      roomId.replaceAll(RegExp(r'[^0-9]'), ''),
      if (roomId.contains('_')) roomId.split('_').last,
    }..removeWhere((s) => s.isEmpty);

    // Bentuk numerik dari setiap id yang sudah diarsipkan untuk pencocokan silang.
    final archivedNumerics = _archivedIds
        .map((id) => id.replaceAll(RegExp(r'[^0-9]'), ''))
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final candidate in candidates) {
      if (_archivedIds.contains(candidate)) return true;
      final candidateNumeric = candidate.replaceAll(RegExp(r'[^0-9]'), '');
      if (candidateNumeric.isNotEmpty &&
          archivedNumerics.contains(candidateNumeric)) {
        return true;
      }
    }

    final idx = _chats.indexWhere((c) {
      for (final candidate in candidates) {
        if (c.id == candidate) return true;
        final cNumeric = c.id.replaceAll(RegExp(r'[^0-9]'), '');
        final candidateNumeric = candidate.replaceAll(RegExp(r'[^0-9]'), '');
        if (cNumeric.isNotEmpty &&
            candidateNumeric.isNotEmpty &&
            cNumeric == candidateNumeric) {
          return true;
        }
      }
      return false;
    });
    if (idx != -1) {
      final c = _chats[idx];
      if (c.isArchived) return true;
      if (_archivedIds.contains(c.id)) return true;
      final cNumeric = c.id.replaceAll(RegExp(r'[^0-9]'), '');
      if (cNumeric.isNotEmpty && archivedNumerics.contains(cNumeric))
        return true;
    }
    return false;
  }

  ChatModel _applyAgentOverride(ChatModel chat) {
    var updatedChat = chat;
    final persistedAgent = _savedAgentNames[chat.id];
    if (persistedAgent != null) {
      if (persistedAgent.isNotEmpty && persistedAgent != 'Unassigned') {
        updatedChat = updatedChat.copyWith(
          agentName: persistedAgent,
          status: 'Assigned',
        );
      } else {
        updatedChat = updatedChat.copyWith(agentName: '', status: 'Unassigned');
      }
    }
    if (_savedBlockStates.containsKey(chat.id)) {
      updatedChat = updatedChat.copyWith(
        isBlocked: _savedBlockStates[chat.id]!,
      );
    }
    return updatedChat;
  }

  // Map: roomId → list of ignored server times (used to ignore stale data after deleting a message)
  Map<String, List<String>> _ignoredServerTimes = {};

  void ignoreServerTime(String roomId, String time) {
    if (time.isEmpty) return;
    if (!_ignoredServerTimes.containsKey(roomId)) {
      _ignoredServerTimes[roomId] = [];
    }
    _ignoredServerTimes[roomId]!.add(time);
    if (!time.endsWith('Z')) {
      _ignoredServerTimes[roomId]!.add('${time}Z');
    } else {
      _ignoredServerTimes[roomId]!.add(time.substring(0, time.length - 1));
    }
  }

  // Tracking pesan yang dihapus secara lokal agar tidak tertimpa oleh data server usang
  final Map<String, Set<String>> _deletedMessageIds = {};
  final Map<String, Set<String>> _deletedMessageContents = {};
  final Set<String> _roomsWithDeletions = {};
  Map<String, String> _deletionTimestamps = {};

  void recordDeletedMessage(
    String roomId, {
    String? msgId,
    String? content,
    String? rawTime,
  }) {
    if (roomId.isEmpty) return;
    _roomsWithDeletions.add(roomId);
    _deletionTimestamps[roomId] = DateTime.now().toUtc().toIso8601String();
    _saveDeletionTimestamps();
    if (rawTime != null && rawTime.isNotEmpty) {
      ignoreServerTime(roomId, rawTime);
    }
    if (msgId != null && msgId.isNotEmpty) {
      _deletedMessageIds.putIfAbsent(roomId, () => <String>{}).add(msgId);
    }
    if (content != null && content.trim().isNotEmpty) {
      _deletedMessageContents
          .putIfAbsent(roomId, () => <String>{})
          .add(content.trim().toLowerCase());
    }
  }

  bool isMessageDeleted(
    String roomId, {
    String? msgId,
    String? content,
    String? rawTime,
  }) {
    if (roomId.isEmpty) return false;
    if (rawTime != null && _isTimeIgnored(roomId, rawTime)) return true;
    if (msgId != null &&
        msgId.isNotEmpty &&
        (_deletedMessageIds[roomId]?.contains(msgId) ?? false))
      return true;
    if (content != null && content.trim().isNotEmpty) {
      final clean = content.trim().toLowerCase();
      if (_deletedMessageContents[roomId]?.contains(clean) ?? false)
        return true;
    }
    return false;
  }

  // Map: roomId -> bool (true if recently received message was from us)
  // Digunakan untuk melindungi flag isMe yang akurat dari TerimaPesan agar tidak ditimpa
  // oleh data TerimaSubSpv (Conversation.fromJson) yang logika isLastMessageFromMe-nya lebih lemah.
  // Ini krusial ketika agen membalas pesan dari aplikasi native (seperti Telegram) langsung.
  Map<String, bool> _recentIsMeFlags = {};

  // Track pesan yang baru saja dikirim oleh aplikasi ini (roomId -> Map<cleanContent, DateTime>)
  // Mencegah echo SignalR atau refresh API menganggap pesan agen sebagai pesan masuk (isLastMessageFromMe = false)
  final Map<String, Map<String, DateTime>> _recentSentMessages = {};

  void recordRecentSentMessage(String roomId, String text) {
    if (roomId.isEmpty || text.isEmpty) return;
    final clean = text.trim().toLowerCase();
    _recentSentMessages.putIfAbsent(roomId, () => {})[clean] = DateTime.now();
    _recentIsMeFlags[roomId] = true;

    // Auto-cleanup pesan lebih dari 3 menit
    _recentSentMessages[roomId]!.removeWhere(
      (_, time) => DateTime.now().difference(time).inMinutes >= 3,
    );
  }

  bool isRecentMessageFromMe(String roomId, String text) {
    if (roomId.isEmpty) return false;
    final sentMap = _recentSentMessages[roomId];
    if (sentMap != null && sentMap.isNotEmpty) {
      final clean = text.trim().toLowerCase();
      for (final entry in sentMap.entries) {
        if (DateTime.now().difference(entry.value).inMinutes < 3) {
          if (clean == entry.key ||
              (clean.isNotEmpty && entry.key.contains(clean)) ||
              (entry.key.isNotEmpty && clean.contains(entry.key))) {
            return true;
          }
        }
      }
    }
    return _recentIsMeFlags[roomId] == true;
  }

  bool _isTimeIgnored(String roomId, String serverTimeStr) {
    if (serverTimeStr.isEmpty) return false;
    final ignoredTimes = _ignoredServerTimes[roomId];
    if (ignoredTimes == null || ignoredTimes.isEmpty) return false;

    if (ignoredTimes.contains(serverTimeStr)) return true;

    final serverTime = DateTime.tryParse(
      serverTimeStr.endsWith('Z') ? serverTimeStr : '${serverTimeStr}Z',
    );
    if (serverTime == null) return false;

    for (final ignoredStr in ignoredTimes) {
      final ignoredTime = DateTime.tryParse(
        ignoredStr.endsWith('Z') ? ignoredStr : '${ignoredStr}Z',
      );
      if (ignoredTime != null) {
        // Toleransi perbedaan milidetik (kurang dari 1 detik)
        if (serverTime.difference(ignoredTime).inMilliseconds.abs() < 1000) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _saveDeletionTimestamps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'deletion_timestamps',
        jsonEncode(_deletionTimestamps),
      );
    } catch (_) {}
  }

  /// Helper untuk mengecek apakah data server benar-benar lebih baru daripada data lokal.
  /// Melindungi dari bug server NoBox yang tidak me-rewind waktu/pesan saat ada pesan yang dihapus.
  bool _isServerDataNewer({
    required String roomId,
    required String serverTimeStr,
    required String serverLastMsg,
    required DateTime? localTime,
  }) {
    final lowerServerMsg = serverLastMsg.trim().toLowerCase();
    if (serverLastMsg == 'Site.Inbox.DeletedMessage' ||
        lowerServerMsg.contains('site.inbox.')) {
      return false;
    }

    if (isMessageDeleted(
      roomId,
      content: serverLastMsg,
      rawTime: serverTimeStr,
    )) {
      return false;
    }

    final isIgnored = _isTimeIgnored(roomId, serverTimeStr);
    if (isIgnored) return false;

    final serverTime = DateTime.tryParse(
      serverTimeStr.endsWith('Z') ? serverTimeStr : '${serverTimeStr}Z',
    );
    if (serverTime == null) return false;

    // Jika terjadi penghapusan pesan di room ini, serverTime HARUS lebih baru dari waktu penghapusan,
    // bukan sekadar lebih baru dari waktu pesan lokal yang tersisa!
    final deletionTimeStr = _deletionTimestamps[roomId];
    if (deletionTimeStr != null) {
      final deletionTime = DateTime.tryParse(
        deletionTimeStr.endsWith('Z') ? deletionTimeStr : '${deletionTimeStr}Z',
      );
      if (deletionTime != null) {
        if (!serverTime.isAfter(deletionTime)) {
          return false;
        }
      }
    }

    if (localTime == null) return true;

    final bool isAfterLocal = serverTime.isAfter(localTime);
    if (!isAfterLocal) return false;

    // Grace period untuk override yang baru saja dibuat (< 10 detik lalu)
    final overrideCreatedAtStr = _overrideTimestamps[roomId];
    if (overrideCreatedAtStr != null) {
      final overrideCreatedAt = DateTime.tryParse(
        overrideCreatedAtStr.endsWith('Z')
            ? overrideCreatedAtStr
            : '${overrideCreatedAtStr}Z',
      );
      if (overrideCreatedAt != null) {
        final age = DateTime.now()
            .toUtc()
            .difference(overrideCreatedAt)
            .inSeconds;
        if (age >= 0 && age < 10) {
          return false;
        }
      }
    }

    return true;
  }

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String? get fetchError => _fetchError;
  String get searchQuery => _searchQuery;
  String get activeFilter => _activeFilter;
  List<Map<String, dynamic>>? get cachedAccounts => _cachedAccounts;

  String? get filterMuteAi => _filterMuteAi;
  String? get filterReadStatus => _filterReadStatus;
  String? get filterChannel => _filterChannel;
  String? get filterChatType => _filterChatType;

  List<String> get filterAccountIds => _filterAccountIds;
  String? get filterContact => _filterContact;
  String? get filterLink => _filterLink;
  String? get filterGroup => _filterGroup;
  String? get filterCampaign => _filterCampaign;
  String? get filterFunnel => _filterFunnel;
  String? get filterDeal => _filterDeal;
  String? get filterTags => _filterTags;
  String? get filterHumanAgent => _filterHumanAgent;

  /// Mengembalikan true jika ada filter lanjutan yang aktif (digunakan untuk indikator badge)
  bool get hasActiveAdvancedFilters =>
      _filterMuteAi != null ||
      _filterReadStatus != null ||
      _filterChannel != null ||
      _filterChatType != null ||
      _filterAccountIds.isNotEmpty ||
      _filterContact != null ||
      _filterLink != null ||
      _filterGroup != null ||
      _filterCampaign != null ||
      _filterFunnel != null ||
      _filterDeal != null ||
      _filterTags != null ||
      _filterHumanAgent != null;

  void setSearchQuery(String query) {
    _searchQuery = query;
    if (_cachedContactsResponse == null && query.isNotEmpty) {
      getContactsResponse().then((_) {
        if (!_isDisposed) notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Mencari kontak dari direktori server (buku alamat NoBox)
  List<Map<String, dynamic>> searchServerContacts(String query) {
    if (query.trim().isEmpty) return [];
    final list = _cachedContactsResponse?.data ?? [];
    final q = query.trim().toLowerCase();
    return list.where((item) {
      final name = (item['Name'] ?? item['Nm'] ?? '').toString().toLowerCase();
      final hp =
          (item['Hp'] ?? item['Phone'] ?? item['Mobile'] ?? item['Telp'] ?? '')
              .toString()
              .toLowerCase();
      return name.contains(q) || hp.contains(q);
    }).toList();
  }

  void setActiveFilter(String filter) {
    if (_activeFilter == filter) return; // skip jika sama
    _activeFilter = filter;
    // Reset pagination karena filter berubah
    _currentSkip = 0;
    _hasMore = true;
    // TIDAK kosongkan _chats di sini → list lama tetap tampil selama fetch

    // INSTAN: filter lokal dari master list agar UI langsung ter-update tanpa
    // menunggu response server (0ms delay). Ini juga mencegah badge tab lain
    // menjadi 0 dan percakapan di tab 'All' tidak terpotong.
    if (_allMasterChats.isNotEmpty) {
      switch (filter) {
        case 'All':
          _chats = List.from(_allMasterChats);
          break;
        case 'Unassigned':
          _chats = _allMasterChats
              .where((c) => c.status == 'Unassigned')
              .toList();
          break;
        case 'Assigned':
          _chats = _allMasterChats
              .where((c) => c.status == 'Assigned')
              .toList();
          break;
        case 'Resolved':
          _chats = _allMasterChats
              .where((c) => c.status == 'Resolved')
              .toList();
          break;
      }
    }

    // Increment generation untuk cancel request lama secara implisit
    _fetchGeneration++;
    final currentGen = _fetchGeneration;
    notifyListeners(); // Update UI secara instan

    // Debounce 400ms: jika user mengetuk tab berpindah-pindah cepat, server hanya
    // dipanggil 1 kali untuk tab terakhir yang dipilih (mencegah request bertumpuk).
    _tabFetchDebounce?.cancel();
    _tabFetchDebounce = Timer(const Duration(milliseconds: 400), () {
      fetchChats(generation: currentGen);
    });
  }

  // FITUR: Filter Lanjutan
  /// Terapkan filter lanjutan dan picu pengambilan data ulang (fresh fetch).
  ///
  /// Semua parameter ID harus berupa raw ID, bukan display name:
  /// - [contact]    → CtId (ID kontak)
  /// - [link]       → LinkTmp / ID link  (client-side filtered)
  /// - [group]      → Id group           (server-side filtered)
  /// - [campaign]   → Id campaign        (server-side filtered)
  /// - [funnel]     → Id funnel          (client-side filtered)
  /// - [deal]       → Id deal            (server-side filtered)
  /// - [tags]       → Id tag             (client-side filtered)
  /// - [humanAgent] → Id / UserId agent  (client-side filtered)
  ///
  /// **Jalur 1 – Server-Side** (dikirim via EqualityFilter ke backend):
  ///   Account, Contact, Group, Campaign, Deal
  ///
  /// **Jalur 2 – Client-Side** (di-remove dari payload, filter lokal .where()):
  ///   ChatType, ReadStatus, Link, Funnel, Tag, HumanAgent
  void applyAdvancedFilters({
    String? muteAi,
    String? readStatus,
    String? channel,
    String? chatType,
    List<String>? accountIds,
    String? contact,
    String? link,
    String? group,
    String? campaign,
    String? funnel,
    String? deal,
    String? tags,
    String? humanAgent,
  }) {
    _filterMuteAi = muteAi;
    _filterReadStatus = readStatus;
    _filterChannel = channel;
    _filterChatType = chatType;
    _filterAccountIds = accountIds ?? [];
    _filterContact = contact;
    _filterLink = link;
    _filterGroup = group;
    _filterCampaign = campaign;
    _filterFunnel = funnel;
    _filterDeal = deal;
    _filterTags = tags;
    _filterHumanAgent = humanAgent;
    // Reset pagination lalu trigger fresh fetch dengan filter baru
    _currentSkip = 0;
    _hasMore = true;
    _chats = [];
    _fetchGeneration++;
    final currentGen = _fetchGeneration;
    notifyListeners();
    fetchChats(generation: currentGen);
  }

  void resetFilters() {
    _activeFilter = 'All';
    _filterMuteAi = null;
    _filterReadStatus = null;
    _filterChannel = null;
    _filterChatType = null;
    _filterAccountIds = [];
    _filterContact = null;
    _filterLink = null;
    _filterGroup = null;
    _filterCampaign = null;
    _filterFunnel = null;
    _filterDeal = null;
    _filterTags = null;
    _filterHumanAgent = null;
    _fetchGeneration++;
    final currentGen = _fetchGeneration;
    notifyListeners();
    fetchChats(generation: currentGen);
  }

  void clearChatDataForAccountSwitch() {
    _chats.clear();
    _cachedFunnels = null;
    _cachedTags = null;
    _cachedAgents = null;
    _cachedLinks = null;
    _cachedContactsResponse = null;
    _currentSkip = 0;
    _hasMore = true;
    _error = null;
    notifyListeners();
  }

  /// Memetakan string filter aktif ke kode status yang dipahami oleh API.
  /// 1=Unassigned, 2=Assigned, 3=Resolved, null=All
  int? _statusCodeForFilter(String filter) {
    switch (filter) {
      case 'Unassigned':
        return 1;
      case 'Assigned':
        return 2;
      case 'Resolved':
        return 3;
      default:
        return null; // 'All'
    }
  }

  /// Memetakan ID funnel dan ID tag mentah pada [ChatModel] ke nama yang mudah dibaca manusia
  /// menggunakan daftar funnel/tag dari cache. Mengembalikan ChatModel baru dengan nama yang diterapkan.
  ChatModel _applyTagAndFunnelMapping(ChatModel chat, Conversation conv) {
    // Funnel: resolve ID → name
    if ((chat.funnel.isEmpty || int.tryParse(chat.funnel) != null) &&
        conv.funnelId.isNotEmpty) {
      if (_cachedFunnels != null) {
        final matched = _cachedFunnels!.firstWhere(
          (f) => f['Id']?.toString() == conv.funnelId,
          orElse: () => <String, dynamic>{},
        );
        final name =
            matched['Name']?.toString() ?? matched['Nm']?.toString() ?? '';
        if (name.isNotEmpty) chat = chat.copyWith(funnel: name);
      }
    }
    // Tags: resolve IDs → names
    if (chat.tags.isEmpty &&
        conv.tagsIds.isNotEmpty &&
        conv.tagsIds != "null") {
      if (_cachedTags != null) {
        final tagIdList = conv.tagsIds
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != "null")
            .toList();
        final matchedNames = _cachedTags!
            .where((t) => tagIdList.contains(t['Id']?.toString()))
            .map((t) => t['Name']?.toString() ?? t['Nm']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (matchedNames.isNotEmpty) {
          chat = chat.copyWith(tags: matchedNames);
        } else if (tagIdList.any((id) => int.tryParse(id) == null)) {
          // Fallback: values are already names, not numeric IDs
          chat = chat.copyWith(tags: tagIdList);
        }
      }
    }
    return chat;
  }

  // FITUR: Ambil Data Chat
  // FUNGSI: Mengambil daftar percakapan dari server dengan dukungan pagination dan filter
  // FITUR 2: Mengambil daftar obrolan utama (20 data pertama) dari server.
  Future<void> fetchChats({int? generation}) async {
    // Jika generation tidak disediakan, gunakan current (untuk backward compat)
    final gen = generation ?? _fetchGeneration;
    // Hanya tampilkan loading jika benar-benar belum ada data sama sekali.
    // Jika data lokal sudah tersedia, lakukan silent background sync agar user
    // tetap bisa langsung melihat isi chat tanpa layar kosong/skeleton loading.
    if (_chats.isEmpty && _allMasterChats.isEmpty) {
      _isLoading = true;
    }
    _error = null;
    _fetchError = null;
    // Reset state pagination saat pengambilan data baru
    _currentSkip = 0;
    _hasMore = true;
    _isLoadingMore = false;
    notifyListeners();

    try {
      // Pre-fetch semua reference data yang dibutuhkan untuk
      // client-side ID-to-name resolution (Jalur 2 filters).
      //
      // PERF: sebelumnya 6 request ini dijalankan pada SETIAP refresh
      // (polling 60 detik, reconnect, resume). Sekarang dibatasi maksimal
      // sekali per 5 menit karena datanya jarang berubah.
      final now = DateTime.now();
      final needReferenceData =
          _lastReferenceDataFetch == null ||
          now.difference(_lastReferenceDataFetch!).inMinutes >= 5;
      if (needReferenceData) {
        _lastReferenceDataFetch = now;
        try {
          await Future.wait([
            getFunnels(),
            getTags(),
            getCachedAgents(),
            getCachedLinks(),
            getCachedAccounts(), // FIX: Fetch accounts untuk resolusi channel type (ChId → Code)
            getContactsResponse(),
          ]);
        } catch (e) {
          // Jangan gagalkan pemuatan daftar chat hanya karena reference data error.
          debugPrint('ChatProvider: reference data prefetch failed: $e');
        }
      }

      // Tentukan status mana yang akan diminta dari server
      final statusCode = _statusCodeForFilter(_activeFilter);
      // ── Jalur 1: Server-Side Filters (dikirim via EqualityFilter) ──────────
      // Account, Contact, Group, Campaign, Deal, HumanAgent → server-side aman
      // MuteAi, Channel, ChatType, ReadStatus, Link, Funnel, Tag → client-side (Jalur 2)
      // NOTE: LinkTmp sebagai EqualityFilter = HTTP 500 (tidak didukung server)
      final response = await _chatService.getConversations(
        statusCode: statusCode,
        skip: 0,
        take: _pageSize,
        accountIds: _filterAccountIds.isNotEmpty
            ? _filterAccountIds.join(',')
            : null,
        contactId: _filterContact, // CtRealId → server-side
        groupId: _filterGroup, // GrpId → server-side aman
        campaignId: _filterCampaign, // CampaignId → server-side aman
        dealId: _filterDeal, // DealId → server-side aman
        humanAgentId: _filterHumanAgent,
        // linkId → TIDAK bisa: EqualityFilter LinkTmp = HTTP 500
        // funnelId, tagsId → client-side
      );

      if (!response.isError && response.data != null) {
        // Guard: jika generation sudah berubah (user ganti tab lagi), abaikan response ini
        if (gen != _fetchGeneration) {
          debugPrint(
            'ChatProvider: fetchChats generation stale ($gen vs ${_fetchGeneration}), discarding',
          );
          _isLoading = false;
          notifyListeners();
          return;
        }

        final freshData = response.data!.where((c) {
          final name = c.participantEmail.toLowerCase().trim();
          return name != 'saved messages' && name != 'pesan tersimpan';
        }).toList();

        // Buat map dari chat yang sudah ada untuk komparasi unreadCount
        final oldChatsMap = {for (var c in _chats) c.id: c};

        _chats = freshData.map((c) {
          var chat = c.toChatModel();

          // FIX: Resolve channelType dari ChId menggunakan account cache
          // Contoh: ChId='1' → 'WhatsApp', ChId='2' → 'Telegram'
          if (chat.channelType.isEmpty && chat.chId.isNotEmpty) {
            final resolvedCode = _resolveChannelCode(chat.chId);
            if (resolvedCode.isNotEmpty) {
              chat = chat.copyWith(channelType: resolvedCode);
            }
          }

          // Apply locally cached mapping for tags and funnel
          chat = _applyTagAndFunnelMapping(chat, c);

          final oldChat = oldChatsMap[chat.id];

          bool isNewMessage = false;
          int forcedUnread = 0;

          if (oldChat != null) {
            // FIX: Cek apakah pesan terakhir adalah pesan yang baru kita kirim dari aplikasi ini
            final bool isSentByMeRecently = isRecentMessageFromMe(
              chat.id,
              chat.lastMessage,
            );

            if (isSentByMeRecently) {
              chat = chat.copyWith(
                isLastMessageFromMe: true,
                needReply: false,
                unreadCount: 0,
                sdrMsg: 'me',
              );
            } else if (!chat.isLastMessageFromMe &&
                oldChat.isLastMessageFromMe) {
              // FIX: Pewarisan isLastMessageFromMe dari cache lokal
              // Karena backend NoBox sering tidak menyertakan IsMe=true untuk balasan kita di endpoint List.
              // Jika pesan teksnya mirip/sama (atau media), kita wariskan statusnya agar tidak memicu unread palsu.
              final newLower = chat.lastMessage.toLowerCase().trim();
              final oldLower = oldChat.lastMessage.toLowerCase().trim();
              final isMediaJSON =
                  newLower.startsWith('{') || newLower.startsWith('[');
              final oldHasMediaLabel = [
                'photo',
                'foto',
                'video',
                'voice',
                'suara',
                'audio',
                'file',
                'document',
                'sticker',
                'location',
                'lokasi',
                'media',
              ].any((lbl) => oldLower.contains(lbl));
              final isTextMatch =
                  oldLower.isNotEmpty &&
                  newLower.isNotEmpty &&
                  newLower == oldLower;
              if (isTextMatch || (isMediaJSON && oldHasMediaLabel)) {
                chat = chat.copyWith(
                  isLastMessageFromMe: true,
                  needReply: false,
                  unreadCount: 0,
                  sdrMsg: 'me',
                );
              }
            }

            if (_recentIsMeFlags.containsKey(chat.id) &&
                _recentIsMeFlags[chat.id] == true) {
              chat = chat.copyWith(
                isLastMessageFromMe: true,
                needReply: false,
                unreadCount: 0,
                sdrMsg: 'me',
              );
            }

            // Jika chat sudah ada sebelumnya, kita cek apakah waktu pesannya berubah (lebih baru)
            final serverTimeParsed = DateTime.tryParse(
              chat.time.endsWith('Z') ? chat.time : chat.time + 'Z',
            );
            final oldTimeParsed = DateTime.tryParse(
              oldChat.time.endsWith('Z') ? oldChat.time : oldChat.time + 'Z',
            );

            final isServerNewer =
                serverTimeParsed != null &&
                (oldTimeParsed == null ||
                    serverTimeParsed.isAfter(oldTimeParsed));

            final isServerTimeDifferent =
                serverTimeParsed != null &&
                oldTimeParsed != null &&
                serverTimeParsed.difference(oldTimeParsed).inSeconds.abs() > 2;
            final isMessageDifferent =
                chat.lastMessage.trim() != oldChat.lastMessage.trim() &&
                chat.lastMessage != 'Site.Inbox.DeletedMessage';

            if ((isServerNewer ||
                    isServerTimeDifferent ||
                    isMessageDifferent) &&
                !chat.isLastMessageFromMe &&
                PushNotificationService.currentRoomId != chat.id) {
              isNewMessage = true;
              forcedUnread = chat.unreadCount > 0
                  ? chat.unreadCount
                  : ((_localUnreadOverrides[chat.id] ?? oldChat.unreadCount) +
                        1);
            } else if (chat.isLastMessageFromMe) {
              // Jika pesan terakhir dari Agen (isLastMessageFromMe = true),
              // Hapus override angka indikator dan tandai sebagai terbaca (0)
              // tanpa peduli apakah isi pesan/waktu berubah atau tidak (bugfix).
              _localUnreadOverrides.remove(chat.id);
              if (!_readIds.contains(chat.id)) _readIds.add(chat.id);
              chat = chat.copyWith(unreadCount: 0);
            } else if (isMessageDifferent && chat.unreadCount > 0) {
              isNewMessage = true;
            }
          } else if (chat.unreadCount > 0) {
            // Jika aplikasi baru dibuka/restart dan server API merespons unreadCount > 0,
            // paksa anggap sebagai pesan baru agar riwayat '_readIds' dihapus.
            isNewMessage = true;
          }
          if (isNewMessage) {
            // Pesan baru tiba! Hapus dari daftar terbaca agar badge muncul
            _readIds.remove(chat.id);
            if (forcedUnread > 0) {
              _localUnreadOverrides[chat.id] = forcedUnread;
              chat = chat.copyWith(unreadCount: forcedUnread);
              debugPrint(
                'ChatProvider: 📈 Incremented Unread (via fetchConversations) for room ${chat.id}. New Uc: $forcedUnread',
              );
            }
          } else {
            // Chat dari cache yang tidak di-increment.
            chat = chat.copyWith(
              unreadCount: _localUnreadOverrides[chat.id] ?? chat.unreadCount,
            );
          }
          _saveReadState();

          if (oldChat != null) {
            // FIX: Pertahankan isBlocked untuk Guest/New Contact (tanpa CtRealId)
            if (chat.ctRealId.isEmpty || chat.ctRealId == 'null') {
              if (oldChat.isBlocked) {
                chat = chat.copyWith(isBlocked: true);
              }
            }
            // FIX UNIVERSAL: Pertahankan nama kontak yang sudah di-save untuk SEMUA kontak.
            if (oldChat.sender.isNotEmpty && oldChat.sender != chat.sender) {
              final isOldSenderANumber = RegExp(
                r'^\+?[0-9\s\-()]+$',
              ).hasMatch(oldChat.sender);
              final isNewSenderANumber = RegExp(
                r'^\+?[0-9\s\-()]+$',
              ).hasMatch(chat.sender);
              if (!isOldSenderANumber || isNewSenderANumber) {
                chat = chat.copyWith(sender: oldChat.sender);
              }
            }

            // FIX UNIVERSAL MEDIA PRESERVATION:
            // Jika memori lokal mencatat pesan terakhir adalah media (Foto/Video/Voice),
            // tetapi API REST membalas dengan pesan kosong/generik (misal: "document(Empty)"),
            // TOLAK update API tersebut dan pertahankan wujud media lokalnya!
            final oldLower = oldChat.lastMessage.trim().toLowerCase();
            final isOldMedia =
                oldChat.lastMessageType == '2' ||
                oldChat.lastMessageType == '3' ||
                oldChat.lastMessageType == '4' ||
                oldChat.lastMessageType == '5' ||
                oldChat.lastMessageType == '16' ||
                oldLower.contains('voice') ||
                oldLower.contains('pesan suara') ||
                oldLower.contains('photo') ||
                oldLower.contains('foto') ||
                oldLower.contains('video') ||
                oldLower.contains('audio');

            final newLower = chat.lastMessage.trim().toLowerCase();
            final isNewGeneric =
                newLower.isEmpty ||
                newLower == 'null' ||
                newLower == 'lampiran' ||
                newLower == 'attachment' ||
                newLower == 'document' ||
                newLower == 'document(empty)' ||
                newLower == 'voice' ||
                newLower == 'voice(empty)' ||
                newLower == 'image(empty)' ||
                newLower == 'video(empty)' ||
                newLower == 'audio(empty)' ||
                newLower == 'file';

            if (isOldMedia && isNewGeneric) {
              chat = chat.copyWith(
                lastMessageType: oldChat.lastMessageType,
                lastMessage: oldChat.lastMessage,
              );
            } else if (chat.lastMessageType == '2' && isNewGeneric) {
              chat = chat.copyWith(
                lastMessageType: '2',
                lastMessage: '🎤 Pesan Suara',
              );
            }
          }

          // Cek apakah ada override lokal (pesan dihapus/kirim pesan yang belum tersinkron di LastMessage server)
          final override = _localOverrides[chat.id];
          if (override != null) {
            final localTimeStr = override.time;
            final localTime = DateTime.tryParse(
              localTimeStr.endsWith('Z') ? localTimeStr : '${localTimeStr}Z',
            );

            final serverIsNewer = _isServerDataNewer(
              roomId: chat.id,
              serverTimeStr: chat.time,
              serverLastMsg: chat.lastMessage,
              localTime: localTime,
            );

            if (!serverIsNewer) {
              chat = chat.copyWith(
                lastMessage: override.lastMessage,
                lastMessageType: override.lastMessageType,
                time: override.time,
                isLastMessageFromMe: override.isLastMessageFromMe,
                sdrMsg: override.isLastMessageFromMe
                    ? 'me'
                    : (override.sdrMsg.isNotEmpty
                          ? override.sdrMsg
                          : chat.sdrMsg),
                needReply: override.isLastMessageFromMe
                    ? false
                    : chat.needReply,
                unreadCount: override.isLastMessageFromMe
                    ? 0
                    : chat.unreadCount,
              );
            } else {
              // Override sudah terlalu lama, kita percaya pada data server saat ini
              _localOverrides.remove(chat.id);
              _overrideTimestamps.remove(chat.id);
              _deletionTimestamps.remove(chat.id);
              _roomsWithDeletions.remove(chat.id);
            }
          }

          // Terapkan nama dari persistent storage (menang atas semua sumber lain)
          final persistedName = _savedContactNames[chat.id];
          if (persistedName != null && persistedName.isNotEmpty) {
            chat = chat.copyWith(sender: persistedName);
          }
          // Terapkan assigned agent override agar status tidak revert ke Unassigned saat polling/refresh
          chat = _applyAgentOverride(chat);

          // FIX: Cegah string generik ("File", "Document") menimpa JSON array media yang sudah valid
          final shieldReference = oldChat ?? override;
          if (shieldReference != null) {
            final lowerNew = chat.lastMessage.toLowerCase().trim();
            final oldMsg = shieldReference.lastMessage.trim();

            final isGeneric =
                lowerNew.isEmpty ||
                lowerNew == 'null' ||
                const [
                  'file',
                  'document',
                  'document(empty)',
                  'voice',
                  'voice(empty)',
                  'voice note',
                  'photo',
                  'foto',
                  'image',
                  'image(empty)',
                  'video',
                  'video(empty)',
                  'audio',
                  'audio(empty)',
                  'attachment',
                  'lampiran',
                  'pesan suara',
                  'sticker',
                  'stiker',
                ].contains(lowerNew) ||
                (lowerNew.length <= 20 &&
                    (lowerNew.startsWith('document(') ||
                        lowerNew.startsWith('voice(') ||
                        lowerNew.startsWith('image(') ||
                        lowerNew.startsWith('video('))) ||
                RegExp(r'^[\d\.:]+$').hasMatch(lowerNew);

            final oldIsLocalLabel = [
              'voice note',
              'pesan suara',
              'photo',
              'foto',
              'video',
              'audio',
              'sticker',
            ].any((lbl) => oldMsg.toLowerCase().contains(lbl));

            if (isGeneric) {
              if (oldMsg.startsWith('{') ||
                  oldMsg.startsWith('[') ||
                  oldIsLocalLabel) {
                chat = chat.copyWith(
                  lastMessage: shieldReference.lastMessage,
                  lastMessageType: shieldReference.lastMessageType,
                );
              }
            } else if (lowerNew.startsWith('{') || lowerNew.startsWith('[')) {
              // Jika JSON baru datang, tapi tidak memiliki ciri-ciri audio yang jelas
              final newIsAudioJson =
                  lowerNew.contains('"type":2') ||
                  lowerNew.contains('"type": 2') ||
                  lowerNew.contains('"ptt":true') ||
                  lowerNew.contains('"ptt": true') ||
                  lowerNew.contains('.ogg') ||
                  lowerNew.contains('.mp3') ||
                  lowerNew.contains('.opus');

              final oldIsAudioJson =
                  oldMsg.toLowerCase().contains('"type":2') ||
                  oldMsg.toLowerCase().contains('"type": 2') ||
                  oldMsg.toLowerCase().contains('"ptt":true') ||
                  oldMsg.toLowerCase().contains('"ptt": true');
              final oldIsAudioLabel =
                  oldMsg.toLowerCase().contains('voice note') ||
                  oldMsg.toLowerCase().contains('pesan suara');
              if ((oldIsAudioJson || oldIsAudioLabel) && !newIsAudioJson) {
                chat = chat.copyWith(
                  lastMessage: shieldReference.lastMessage,
                  lastMessageType: shieldReference.lastMessageType,
                );
              }
            } else if ((oldIsLocalLabel ||
                    oldMsg.startsWith('{') ||
                    oldMsg.startsWith('[')) &&
                lowerNew.length <= 15 &&
                oldMsg.toLowerCase().contains(lowerNew)) {
              chat = chat.copyWith(
                lastMessage: shieldReference.lastMessage,
                lastMessageType: shieldReference.lastMessageType,
              );
            }
          }

          // Terapkan state lokal yang tersimpan (arsip, dibaca)
          // Status dan Pin berasal langsung dari server
          final isArchived = chat.isArchived || isRoomArchived(chat.id);
          if (isArchived) {
            _archivedIds.add(chat.id);
          }
          return chat.copyWith(
            isPinned: chat.isPinned || _pinnedIds.contains(chat.id),
            isArchived: isArchived,
            unreadCount: _readIds.contains(chat.id)
                ? 0
                : (_localUnreadOverrides[chat.id] ?? chat.unreadCount),
          );
        }).toList();

        // FIX: Registrasikan server-pinned chats ke local _pinnedIds secara stabil.
        // Pertahankan urutan yang sudah ada di _pinnedIds secara absolut agar tidak berubah posisi saat ada pesan baru.
        // KONSISTEN: Tambahkan pinned chat baru ke AWAL (beginning) seperti togglePin,
        // agar urutan "pinned terbaru di atas" konsisten di seluruh aplikasi.
        final serverPinnedIds = _chats
            .where((c) => c.isPinned)
            .map((c) => c.id)
            .toList();
        bool pinnedChanged = false;
        for (final id in serverPinnedIds) {
          if (!_pinnedIds.contains(id)) {
            // KONSISTEN dengan togglePin: tambah ke AWAL
            _pinnedIds = {id, ..._pinnedIds};
            pinnedChanged = true;
          }
        }
        if (pinnedChanged) {
          _savePinnedState();
        }

        // FIX: Pastikan percakapan lokal (dari New Conversation) yang tersimpan di _localOverrides
        // namun belum masuk di halaman pertama API NoBox tetap ada di daftar percakapan sesudah hot restart!
        for (final overrideEntry in _localOverrides.entries) {
          final overrideChat = overrideEntry.value;
          if (overrideChat.sender.isNotEmpty) {
            final existsInServer = _chats.any(
              (c) =>
                  c.id == overrideChat.id ||
                  (c.ctRealId.isNotEmpty &&
                      c.ctRealId == overrideChat.ctRealId) ||
                  (c.contactId.isNotEmpty &&
                      c.contactId == overrideChat.contactId &&
                      c.contactId != '0'),
            );
            if (!existsInServer) {
              _chats.insert(0, _applyAgentOverride(overrideChat));
              debugPrint(
                'ChatProvider: 📌 Restored persistent local chat ${overrideChat.id} (${overrideChat.sender}) across hot restart',
              );
            }
          }
        }

        // Perbarui state pagination
        _currentSkip = response.data!.length;
        _hasMore = response.data!.length >= _pageSize;
        debugPrint(
          '📄 [Pagination] Initial fetch: loaded ${response.data!.length} items, hasMore=$_hasMore',
        );

        // PERF: Simpan master list saat fetch pada tab 'All' selesai, supaya
        // filter lokal (setActiveFilter) instan dan tidak memotong data.
        if (_activeFilter == 'All') {
          _allMasterChats = List.from(_chats);
        }

        // Segera perbarui UI agar pengguna tidak menunggu lama
        _isLoading = false;
        notifyListeners();
      } else {
        // Guard: jika generation sudah berubah, abaikan error state
        if (gen != _fetchGeneration) return;
        _error = response.error ?? 'Gagal memuat chat';
        _fetchError = _error;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      // Guard: jika generation sudah berubah, abaikan error state
      if (gen != _fetchGeneration) return;
      _error = e.toString();
      _fetchError = _error;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Memperbarui data satu ruang chat langsung dari event SignalR TerimaSubSpv.
  /// Ini menghindari pemanggilan API dan memberikan pembaruan UI instan.
  ///
  /// [roomData] is the parsed JSON from TerimaSubSpv with keys like:
  /// Id, Ct, LastMsg, Uc, TimeMsg, IsPin, St, IsNeedReply, SdrMsg, etc.

  // Helper untuk mendapatkan waktu yang dipastikan berada di urutan teratas (mengatasi bug zona waktu server)
  String _getTopSortTime() {
    DateTime maxTime = DateTime.now().toUtc();
    for (var c in _chats) {
      if (!c.isPinned) {
        final t = _parseTimeForSort(c.time).toUtc();
        if (t.isAfter(maxTime)) {
          maxTime = t;
        }
      }
    }
    return maxTime.add(const Duration(seconds: 1)).toIso8601String();
  }

  DateTime _parseTimeForSort(String rawTime) {
    if (rawTime.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      String timeString = rawTime;
      if (!timeString.endsWith('Z') &&
          !timeString.contains('+') &&
          timeString.length >= 19) {
        timeString += 'Z';
      }
      return DateTime.parse(timeString).toLocal();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  // FITUR 3: Menyinkronkan status obrolan secara instan dari event SignalR.
  // [ACTION: UPDATE_ROOM_SIGNALR] - Memperbarui state chat saat ada pesan real-time masuk
  void updateRoomFromSignalR(Map<String, dynamic> roomData) {
    final roomId = roomData['Id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    // FIX: Abaikan update room dari Telegram "Saved Messages"
    final ctName =
        (roomData['Ct'] ?? roomData['CtRealNm'] ?? roomData['Name'] ?? '')
            .toString()
            .toLowerCase();
    if (ctName == 'saved messages' || ctName == 'pesan tersimpan') {
      return;
    }

    final index = _chats.indexWhere((c) => c.id == roomId);

    if (index >= 0) {
      // Update existing chat
      final existing = _chats[index];
      String lastMsg = roomData['LastMsg']?.toString() ?? existing.lastMessage;
      if (lastMsg.contains('[-{=||=}-]')) {
        lastMsg = '📍 Location';
      }

      // FIX: Lindungi dari data usang (pesan yang baru dihapus).
      // Karena jam HP pengguna bisa tidak sinkron dengan server, gunakan _isServerDataNewer.
      if (_localOverrides.containsKey(roomId)) {
        final serverTimeStr = roomData['TimeMsg']?.toString() ?? '';
        final localTimeStr = existing.time;
        final localTime = DateTime.tryParse(
          localTimeStr.endsWith('Z') ? localTimeStr : '${localTimeStr}Z',
        );

        final serverIsNewer = _isServerDataNewer(
          roomId: roomId,
          serverTimeStr: serverTimeStr,
          serverLastMsg: lastMsg,
          localTime: localTime,
        );

        if (!serverIsNewer) {
          lastMsg = existing.lastMessage;
          roomData['LastMessageType'] = existing.lastMessageType;
          roomData['TimeMsg'] =
              existing.time; // Lindungi waktu agar posisi tidak turun!
          debugPrint(
            'ChatProvider: 🛡️ Override protected for $roomId – incoming SignalR event is ignored',
          );
        } else {
          // Event SignalR baru yang valid! Hapus override lokal.
          _localOverrides.remove(roomId);
          _overrideTimestamps.remove(roomId);
          _deletionTimestamps.remove(roomId);
          _roomsWithDeletions.remove(roomId);
          _saveLocalOverrides();
          debugPrint(
            'ChatProvider: ✅ Override cleared for $roomId — valid new SignalR event received',
          );
        }
      }

      // FIX: Cegah string generik ("File", "Document") menimpa JSON array media yang sudah valid
      final lowerNew = lastMsg.toLowerCase().trim();
      final oldMsg = existing.lastMessage.trim();

      final isGeneric =
          lowerNew.isEmpty ||
          lowerNew == 'null' ||
          const [
            'file',
            'document',
            'document(empty)',
            'voice',
            'voice(empty)',
            'voice note',
            'photo',
            'foto',
            'image',
            'image(empty)',
            'video',
            'video(empty)',
            'audio',
            'audio(empty)',
            'attachment',
            'lampiran',
            'pesan suara',
            'sticker',
            'stiker',
          ].contains(lowerNew) ||
          (lowerNew.length <= 20 &&
              (lowerNew.startsWith('document(') ||
                  lowerNew.startsWith('voice(') ||
                  lowerNew.startsWith('image(') ||
                  lowerNew.startsWith('video('))) ||
          RegExp(r'^[\d\.:]+$').hasMatch(lowerNew);

      final oldIsLocalLabel = [
        'voice note',
        'pesan suara',
        'photo',
        'foto',
        'video',
        'audio',
        'sticker',
      ].any((lbl) => oldMsg.toLowerCase().contains(lbl));

      if (isGeneric) {
        if (oldMsg.startsWith('{') ||
            oldMsg.startsWith('[') ||
            oldIsLocalLabel) {
          lastMsg = existing.lastMessage;
        }
      } else if (lowerNew.startsWith('{') || lowerNew.startsWith('[')) {
        // Jika JSON baru datang, tapi tidak memiliki ciri-ciri audio yang jelas
        final newIsAudioJson =
            lowerNew.contains('"type":2') ||
            lowerNew.contains('"type": 2') ||
            lowerNew.contains('"type":"2"') ||
            lowerNew.contains('"type": "2"') ||
            lowerNew.contains('"ptt":true') ||
            lowerNew.contains('"ptt": true') ||
            lowerNew.contains('"isvoice":true') ||
            lowerNew.contains('"isaudio":true') ||
            lowerNew.contains('.ogg') ||
            lowerNew.contains('.mp3') ||
            lowerNew.contains('.opus') ||
            lowerNew.contains('.wav') ||
            lowerNew.contains('.m4a') ||
            lowerNew.contains('.aac') ||
            lowerNew.contains('.weba') ||
            lowerNew.contains('.amr') ||
            lowerNew.contains('voice_') ||
            lowerNew.contains('ptt-');

        // Apakah pesan lama adalah audio? (JSON lengkap ATAU label manual)
        final oldIsAudioJson =
            oldMsg.toLowerCase().contains('"type":2') ||
            oldMsg.toLowerCase().contains('"type": 2') ||
            oldMsg.toLowerCase().contains('"ptt":true') ||
            oldMsg.toLowerCase().contains('"ptt": true');
        final oldIsAudioLabel =
            oldMsg.toLowerCase().contains('voice note') ||
            oldMsg.toLowerCase().contains('pesan suara');
        if ((oldIsAudioJson || oldIsAudioLabel) && !newIsAudioJson) {
          lastMsg = existing.lastMessage;
        }
      } else if ((oldIsLocalLabel ||
              oldMsg.startsWith('{') ||
              oldMsg.startsWith('[')) &&
          lowerNew.length <= 15 &&
          oldMsg.toLowerCase().contains(lowerNew)) {
        lastMsg = existing.lastMessage;
      }

      final uc =
          int.tryParse(roomData['Uc']?.toString() ?? '') ??
          existing.unreadCount;
      String timeMsg = roomData['TimeMsg']?.toString() ?? existing.time;
      if (DateTime.tryParse(timeMsg) == null) {
        timeMsg =
            _getTopSortTime(); // Pastikan waktu pesan baru yang masuk selalu berada di atas
      } else {
        // Normalisasi TimeMsg dari SignalR agar setara dengan Chatrooms/List (kasus bug timezone dari backend)
        if (!timeMsg.endsWith('Z') &&
            !timeMsg.contains('+') &&
            timeMsg.length >= 19) {
          timeMsg += 'Z';
        }
      }
      final sdrMsg = roomData['SdrMsg']?.toString() ?? '';
      final bool isRecentMe = _recentIsMeFlags[roomId] == true;

      // Jika ada pesan baru yang masuk (unreadCount > 0 dan bukan dari kita), hapus blokir readIds!
      if (uc > 0 &&
          !isRecentMe &&
          sdrMsg.toLowerCase() != 'me' &&
          _readIds.contains(roomId)) {
        _readIds.remove(roomId);
        _localUnreadOverrides.remove(roomId);
        _saveReadState();
      }

      // FIX Bug #3: Also update isBlocked from CtIsBlock if present
      final bool resolvedIsBlocked;
      if (roomData.containsKey('CtIsBlock')) {
        resolvedIsBlocked =
            roomData['CtIsBlock'] == 1 || roomData['CtIsBlock'] == true;
      } else {
        resolvedIsBlocked = existing.isBlocked;
      }

      // FIX: Normalisasi LastMessageType dan LastMessage pada event SignalR
      String? updatedType =
          roomData['LastMessageType']?.toString() ?? existing.lastMessageType;
      final lowerResolved = lastMsg.trim().toLowerCase();

      final isGenericWord =
          lowerResolved.isEmpty ||
          lowerResolved == 'null' ||
          lowerResolved == 'document(empty)' ||
          lowerResolved == 'voice(empty)' ||
          lowerResolved == 'image(empty)' ||
          lowerResolved == 'video(empty)' ||
          lowerResolved == 'audio(empty)' ||
          lowerResolved == 'lampiran' ||
          lowerResolved == 'attachment' ||
          lowerResolved == 'document' ||
          lowerResolved == 'file' ||
          lowerResolved == 'voice' ||
          lowerResolved == 'voice note' ||
          lowerResolved == 'audio' ||
          lowerResolved == 'pesan suara';

      final isAudioLastMsg =
          lowerResolved.contains('🎤') ||
          lowerResolved.contains('pesan suara') ||
          lowerResolved.contains('voice note') ||
          lowerResolved.contains('.ogg') ||
          lowerResolved.contains('.opus') ||
          lowerResolved.contains('.mp3') ||
          lowerResolved.contains('.wav') ||
          lowerResolved.contains('.m4a') ||
          lowerResolved.contains('voice_') ||
          lowerResolved == 'voice(empty)' ||
          (existing.lastMessageType == '2' && isGenericWord);

      if (isAudioLastMsg ||
          updatedType == '2' ||
          updatedType == 'voice' ||
          updatedType == 'audio') {
        updatedType = '2';
        if (isGenericWord || lastMsg.isEmpty) {
          lastMsg = '🎤 Pesan Suara';
        }
      } else if (!lastMsg.startsWith('{') && !lastMsg.startsWith('[')) {
        if (!isGenericWord && lowerResolved.isNotEmpty) {
          if (updatedType != '1') {
            updatedType = '1';
          }
        }
      }
      if (updatedType == null) {
        updatedType = existing.lastMessageType ?? '1';
      }

      // FIX: Karena server NoBox sering salah mengirim SdrMsg (bukan 'You') untuk pesan kita sendiri,
      // kita cek apakah pesan baru ini teksnya sama persis dengan pesan terakhir yang kita ketik lokal.
      final bool isExistingMedia =
          existing.isLastMessageFromMe &&
          (existing.lastMessage == '📷 Photo' ||
              existing.lastMessage == '🎬 Video' ||
              existing.lastMessage.startsWith('📄') ||
              existing.lastMessage == '🎤 Pesan Suara' ||
              existing.lastMessage.startsWith('📍 Lokasi'));
      final bool isNewMedia =
          lastMsg.trim().startsWith('{') || lastMsg.trim().startsWith('[');

      final bool isSentByMeRecently = isRecentMessageFromMe(roomId, lastMsg);

      bool isSmartMeFallback =
          isSentByMeRecently ||
          (sdrMsg.toLowerCase() == 'me') ||
          (existing.channelName.isNotEmpty &&
              sdrMsg.toLowerCase() == existing.channelName.toLowerCase()) ||
          (existing.isLastMessageFromMe &&
              lastMsg.trim().toLowerCase() ==
                  existing.lastMessage.trim().toLowerCase()) ||
          (existing.isLastMessageFromMe && isExistingMedia && isNewMedia);
      // Dihapus: Deteksi Cerdas Agen berdasarkan nama pengirim.
      // SdrMsg dari API (khususnya Telegram) sangat tidak terduga dan bisa berisi nama bot atau null,
      // sehingga menyebabkan pesan pelanggan dikira pesan agen (dan mematikan badge unread).

      debugPrint('ChatProvider: 🛎 EVALUASI SIGNALR UNTUK ROOM $roomId');
      debugPrint('   - isSmartMeFallback: $isSmartMeFallback');
      debugPrint(
        '   - PushNotificationService.currentRoomId: ${PushNotificationService.currentRoomId}',
      );
      debugPrint('   - timeMsg (server): $timeMsg');
      debugPrint('   - existing.time (lokal): ${existing.time}');

      final serverTimeParsed = DateTime.tryParse(
        timeMsg.endsWith('Z') ? timeMsg : timeMsg + 'Z',
      );
      final existingTimeParsed = DateTime.tryParse(
        existing.time.endsWith('Z') ? existing.time : existing.time + 'Z',
      );

      if (!isSmartMeFallback &&
          PushNotificationService.currentRoomId != roomId) {
        debugPrint('   - serverTimeParsed: $serverTimeParsed');
        debugPrint('   - existingTimeParsed: $existingTimeParsed');
        debugPrint(
          '   - isAfter: ${serverTimeParsed?.isAfter(existingTimeParsed ?? DateTime.now())}',
        );
        debugPrint(
          '   - lastMsg != existingMsg: ${lastMsg.trim() != existing.lastMessage.trim()}',
        );

        final isFromAgent =
            isRecentMe ||
            sdrMsg.toLowerCase() == 'me' ||
            (sdrMsg.toLowerCase() == 'system' && !existing.isGroup) ||
            isSmartMeFallback;

        if (isFromAgent) {
          _localUnreadOverrides.remove(roomId);
          if (!_readIds.contains(roomId)) _readIds.add(roomId);
          _saveReadState();
          debugPrint(
            'ChatProvider: 🧹 Cleared Unread (via TerimaSubSpv - Agent Reply) for room $roomId',
          );
        } else {
          // Pesan dari pelanggan (Customer)!
          int finalUc;
          if (uc > 0) {
            // Gunakan Uc akurat dari server NoBox
            finalUc = uc;
          } else {
            final currentOver =
                _localUnreadOverrides[roomId] ?? existing.unreadCount;
            finalUc = currentOver > 0 ? currentOver : 1;
          }

          _localUnreadOverrides[roomId] = finalUc;
          _readIds.remove(roomId);
          _saveReadState();
          debugPrint(
            'ChatProvider: 📈 Using SignalR Uc ($finalUc) [Raw Server: $uc, Existing: ${existing.unreadCount}] for room $roomId',
          );
        }
      } else if (isSmartMeFallback ||
          PushNotificationService.currentRoomId == roomId) {
        _localUnreadOverrides.remove(roomId);
        if (!_readIds.contains(roomId)) _readIds.add(roomId);
        _saveReadState();
      }

      final bool isExplicitCustomer =
          sdrMsg.toLowerCase() == 'you' ||
          (!isRecentMe && sdrMsg.toLowerCase() != 'me' && !isSmartMeFallback);

      final bool isNewerOrDifferentForState =
          serverTimeParsed != null &&
          (existingTimeParsed == null ||
              serverTimeParsed.isAfter(existingTimeParsed) ||
              lastMsg.trim() != existing.lastMessage.trim());

      final bool isFromAgentForState;
      if (isExplicitCustomer) {
        isFromAgentForState = false;
      } else if (isNewerOrDifferentForState) {
        isFromAgentForState =
            isRecentMe ||
            isSentByMeRecently ||
            sdrMsg.toLowerCase() == 'me' ||
            (sdrMsg.toLowerCase() == 'system' && !existing.isGroup) ||
            isSmartMeFallback;
      } else {
        isFromAgentForState =
            existing.isLastMessageFromMe || isSentByMeRecently;
      }

      final bool finalNeedReply = isFromAgentForState
          ? false
          : (roomData.containsKey('IsNeedReply')
                ? (roomData['IsNeedReply'] == 1 ||
                      roomData['IsNeedReply'] == true)
                : (isExplicitCustomer ? true : existing.needReply));

      final String resolvedSdrMsg;
      if (isFromAgentForState) {
        resolvedSdrMsg = 'me';
      } else if (sdrMsg.isNotEmpty) {
        resolvedSdrMsg = sdrMsg;
      } else if (isExplicitCustomer) {
        resolvedSdrMsg = 'you';
      } else {
        resolvedSdrMsg = existing.sdrMsg.isNotEmpty ? existing.sdrMsg : 'you';
      }

      final bool isArchived =
          existing.isArchived ||
          isRoomArchived(roomId) ||
          isRoomArchived(existing.id);
      if (isArchived) {
        _archivedIds.add(roomId);
        _archivedIds.add(existing.id);
      }

      _chats[index] = existing.copyWith(
        lastMessage: lastMsg,
        lastMessageType: updatedType,
        unreadCount:
            (isFromAgentForState ||
                PushNotificationService.currentRoomId == roomId)
            ? 0
            : (_localUnreadOverrides[roomId] ??
                  (uc > 0
                      ? uc
                      : (existing.unreadCount > 0
                            ? existing.unreadCount
                            : (isExplicitCustomer ? 1 : 0)))),
        time: timeMsg,
        needReply: finalNeedReply,
        isLastMessageFromMe: isFromAgentForState,
        isBlocked: resolvedIsBlocked,
        sdrMsg: resolvedSdrMsg,
        isArchived: isArchived,
      );

      debugPrint(
        'ChatProvider: 🏠 Updated room $roomId from SignalR | lastMsg=$lastMsg | uc=$uc',
      );
      _notifyDebounced(); // ANR FIX: Batch rapid SignalR updates
    } else {
      // Room not in current list — BUT if it is archived, do NOT refresh!
      // Refreshing would cause the server to return the archived room (without
      // the archived flag) and it would leak into the main chat list.
      if (isRoomArchived(roomId)) {
        debugPrint(
          'ChatProvider: Room $roomId not in list but is ARCHIVED — skipping refreshFirstPage.',
        );
      } else {
        debugPrint(
          'ChatProvider: Room $roomId not in list, triggering refreshFirstPage',
        );
        refreshFirstPage();
      }
    }
  }

  // [ACTION: SYNC_LOCAL] - Fallback jika TerimaSubSpv telat/gagal.
  // Method ini dipanggil saat event TerimaPesan (Pesan Tunggal) muncul
  void handleTerimaPesanSync(
    String roomId, {
    bool isMe = false,
    String msgText = '',
  }) {
    if (roomId.isEmpty) return;
    if (msgText.toLowerCase() == 'saved messages' ||
        msgText.toLowerCase() == 'pesan tersimpan') {
      return;
    }

    final bool resolvedIsMe = isMe || isRecentMessageFromMe(roomId, msgText);

    // Simpan isMe yang akurat sementara waktu agar bisa ditangkap oleh updateRoomFromSignalR
    // (yang biasanya dipanggil berdekatan oleh TerimaSubSpv)
    _recentIsMeFlags[roomId] = resolvedIsMe;
    Future.delayed(const Duration(seconds: 30), () {
      _recentIsMeFlags.remove(roomId);
    });

    // Jika kita yang membalas, kita reset unread count dan batalkan perlindungan unread.
    if (resolvedIsMe) {
      _localUnreadOverrides.remove(roomId);
      if (!_readIds.contains(roomId)) _readIds.add(roomId);
      _saveReadState();
    } else if (_readIds.contains(roomId)) {
      _readIds.remove(roomId);
      // Jangan hapus _localUnreadOverrides di sini agar tidak menghapus badge sebelum TerimaSubSpv memprosesnya
      _saveReadState();
    }

    int index = _chats.indexWhere((c) => c.id == roomId);
    if (index == -1) {
      final cleanRoomId = roomId
          .replaceAll('@s.whatsapp.net', '')
          .replaceAll('@c.us', '')
          .replaceAll('@g.us', '')
          .replaceAll(RegExp(r'^[0-9]+_'), '');
      final numericRoomId = roomId.replaceAll(RegExp(r'[^0-9\-]'), '');
      index = _chats.indexWhere((c) {
        if (c.contactId == roomId ||
            c.ctRealId == roomId ||
            c.link == roomId ||
            c.extId == roomId)
          return true;
        if (cleanRoomId.isNotEmpty &&
            (c.contactId == cleanRoomId ||
                c.ctRealId == cleanRoomId ||
                c.link == cleanRoomId ||
                c.extId == cleanRoomId))
          return true;
        if (numericRoomId.isNotEmpty) {
          final cNum = c.id.replaceAll(RegExp(r'[^0-9\-]'), '');
          final ctNum = c.ctRealId.replaceAll(RegExp(r'[^0-9\-]'), '');
          if (cNum.isNotEmpty && cNum == numericRoomId) return true;
          if (ctNum.isNotEmpty && ctNum == numericRoomId) return true;
        }
        return false;
      });
    }

    if (index == -1) {
      // ARSIP SHIELD: Jika room tidak ditemukan tapi sudah diarsipkan, jangan
      // pernah trigger refreshFirstPage — ini mencegah room archived muncul
      // kembali di daftar utama karena server tidak tahu status arsip lokal.
      if (isRoomArchived(roomId)) {
        debugPrint(
          'ChatProvider: 🔒 Room $roomId missing (TerimaPesan) but is ARCHIVED — skipping refresh.',
        );
        return;
      }
      debugPrint(
        'ChatProvider: 🚨 Room $roomId missing on TerimaPesan! Triggering fallback refresh.',
      );
      refreshFirstPage();
    } else {
      final matchedChat = _chats[index];
      final isCurrentRoom =
          PushNotificationService.currentRoomId != null &&
          (PushNotificationService.currentRoomId == roomId ||
              PushNotificationService.currentRoomId == matchedChat.id ||
              PushNotificationService.currentRoomId == matchedChat.contactId ||
              PushNotificationService.currentRoomId == matchedChat.ctRealId);
      if (!isCurrentRoom && !resolvedIsMe) {
        final currentUc =
            _localUnreadOverrides[roomId] ??
            _localUnreadOverrides[matchedChat.id] ??
            matchedChat.unreadCount;
        final newUc = currentUc > 0 ? currentUc + 1 : 1;
        _localUnreadOverrides[roomId] = newUc;
        _localUnreadOverrides[matchedChat.id] = newUc;
        _readIds.remove(roomId);
        _readIds.remove(matchedChat.id);
        _saveReadState();
        debugPrint(
          'ChatProvider: 📈 Incremented Unread (via handleTerimaPesanSync) for room $roomId. New Uc: $newUc',
        );
      } else if (resolvedIsMe) {
        _localUnreadOverrides.remove(roomId);
        _localUnreadOverrides.remove(matchedChat.id);
        if (!_readIds.contains(roomId)) _readIds.add(roomId);
        if (!_readIds.contains(matchedChat.id)) _readIds.add(matchedChat.id);
        _chats[index] = _chats[index].copyWith(unreadCount: 0);
        _saveReadState();
      }

      // Update pesan terakhir secara instan agar UI (termasuk preview pesan) langsung terupdate.
      if (msgText.isNotEmpty) {
        if (msgText.contains('[-{=||=}-]')) {
          msgText = '📍 Location';
        }
        final lowerMsg = msgText.trim().toLowerCase();
        final isGeneric =
            lowerMsg == 'lampiran' ||
            lowerMsg == 'attachment' ||
            lowerMsg == 'document' ||
            lowerMsg == 'file' ||
            lowerMsg == 'document(empty)' ||
            lowerMsg == 'voice(empty)';

        String finalMsgText = msgText;
        String? finalLastType = _chats[index].lastMessageType;
        if (isGeneric &&
            (_chats[index].lastMessageType == '2' ||
                _chats[index].lastMessage.contains('🎤') ||
                _chats[index].lastMessage.contains('Pesan Suara'))) {
          finalMsgText = '🎤 Pesan Suara';
          finalLastType = '2';
        }

        final bool isArchived =
            matchedChat.isArchived ||
            isRoomArchived(roomId) ||
            isRoomArchived(matchedChat.id);
        if (isArchived) {
          _archivedIds.add(roomId);
          _archivedIds.add(matchedChat.id);
        }

        _chats[index] = _chats[index].copyWith(
          lastMessage: finalMsgText,
          lastMessageType: finalLastType,
          time: DateTime.now().toUtc().toIso8601String(),
          unreadCount: resolvedIsMe
              ? 0
              : (_localUnreadOverrides[roomId] ??
                    (_chats[index].unreadCount > 0
                        ? _chats[index].unreadCount
                        : 1)),
          isLastMessageFromMe: resolvedIsMe,
          needReply: resolvedIsMe ? false : true,
          sdrMsg: resolvedIsMe ? 'me' : 'you',
          isArchived: isArchived,
        );
        _chats.sort(
          (a, b) =>
              _parseTimeForSort(b.time).compareTo(_parseTimeForSort(a.time)),
        );
      }

      _notifyDebounced(); // ANR FIX: Batch rapid SignalR updates
    }

    // Sesuai arahan Mas Erik: Hapus background refresh API (yang dulu dibuat dengan delay 5 detik).
    // Ini yang sebelumnya menyebabkan Uc sempat terbaca 0 karena menembak API Chatrooms/List saat pesan baru masuk.
    // TerimaSubSpv akan mengirimkan data yang 100% akurat sesaat lagi.
    _signalRRefreshTimer?.cancel();
  }

  /// Mengambil pesan asli terakhir untuk ruangan yang pesan terakhirnya dihapus atau berupa log sistem
  Future<void> _fetchRealLastMessagesForDeletedRooms(
    List<String> roomIds,
  ) async {
    for (final roomId in roomIds) {
      try {
        final response = await _chatService.getMessageHistory(roomId, '');
        if (!response.isError &&
            response.data != null &&
            response.data!.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final deletedIds =
              prefs.getStringList('deleted_ids_$roomId') ?? <String>[];

          // Find the most recent message that is NOT a deleted message placeholder or system notification
          final validMessages = response.data!.where((m) {
            if (m.id.isNotEmpty && deletedIds.contains(m.id)) return false;
            if (m.content == 'Site.Inbox.DeletedMessage' || m.isSystemMessage)
              return false;
            final lower = m.content.toLowerCase();
            if (lower.contains('site.inbox.') ||
                lower.contains('percakapan di-assign') ||
                lower.contains('percakapan diselesaikan') ||
                lower.contains('pemberitahuan sistem'))
              return false;
            return true;
          }).toList();

          if (validMessages.isNotEmpty) {
            // NOTE: getMessageHistory mengembalikan urutan ASC (pesan terlama di index 0, terbaru di index .last).
            // WAJIB gunakan .last agar mengambil pesan chat ASLI TERBARU!
            final realLastMsg = validMessages.last;
            String typeStr = '1';
            if (realLastMsg.messageType == MessageType.voice)
              typeStr = '2';
            else if (realLastMsg.messageType == MessageType.image)
              typeStr = '3';
            else if (realLastMsg.messageType == MessageType.video)
              typeStr = '4';
            else if (realLastMsg.messageType == MessageType.document)
              typeStr = '5';
            else if (realLastMsg.messageType == MessageType.sticker)
              typeStr = '16';

            updateLocalLastMessage(
              roomId,
              realLastMsg.content,
              lastMessageType: typeStr,
              overrideTime: realLastMsg.rawTime,
              isFromMe: realLastMsg.isMe,
              updateTimeAndPosition: false,
              isDeletion: true,
            );
          } else {
            // All messages are deleted placeholders or system logs
            updateLocalLastMessage(
              roomId,
              '',
              lastMessageType: '1',
              updateTimeAndPosition: false,
              isDeletion: true,
            );
          }
        } else {
          // If room is completely empty
          updateLocalLastMessage(
            roomId,
            '',
            lastMessageType: '1',
            updateTimeAndPosition: false,
            isDeletion: true,
          );
        }
      } catch (e) {
        debugPrint(
          'ChatProvider: Error fetching real last message for room $roomId: $e',
        );
      }
    }
  }

  /// Menyisipkan obrolan baru secara lokal ke urutan teratas tanpa harus menunggu server.
  /// Ini memperbaiki bug di mana obrolan baru menghilang atau melempar ke chat acak.
  void insertLocalChat(ChatModel chat) {
    // Pastikan percakapan baru yang ditambahkan TIDAK dianggap terblokir oleh default API NoBox
    _savedBlockStates[chat.id] = false;
    _saveSavedBlockStates();

    // Simpan chat baru ke local overrides agar tersimpan secara permanen melewati hot restart
    _localOverrides[chat.id] = chat;
    _overrideTimestamps[chat.id] = DateTime.now().toUtc().toIso8601String();
    _saveLocalOverrides();

    // Hindari duplikasi
    final idx = _chats.indexWhere((c) => c.id == chat.id);
    if (idx != -1) {
      _chats[idx] = chat;
    } else {
      _chats.insert(0, chat);
    }
    notifyListeners();
  }

  void updateLocalLastMessage(
    String roomId,
    String lastMessage, {
    bool isFromMe = true,
    bool updateTimeAndPosition = true,
    String? overrideTime,
    String? lastMessageType,
    bool isDeletion = false,
  }) {
    if (lastMessage.contains('[-{=||=}-]')) {
      lastMessage = '📍 Location';
    }

    if (isFromMe) {
      recordRecentSentMessage(roomId, lastMessage);
      _localUnreadOverrides.remove(roomId);
      if (!_readIds.contains(roomId)) {
        _readIds.add(roomId);
        _saveReadState();
      }
    }

    if (isDeletion) {
      _roomsWithDeletions.add(roomId);
      _deletionTimestamps[roomId] = DateTime.now().toUtc().toIso8601String();
      _saveDeletionTimestamps();
    }

    final index = _chats.indexWhere((c) => c.id == roomId);
    if (index >= 0) {
      final newTime =
          overrideTime ??
          (updateTimeAndPosition ? _getTopSortTime() : _chats[index].time);
      String resolvedLastMessageType = lastMessageType ?? '1';
      if (lastMessageType == null) {
        final lowerMsg = lastMessage.toLowerCase().trim();
        if (lowerMsg.contains('🎤') ||
            lowerMsg.contains('pesan suara') ||
            lowerMsg.contains('voice note') ||
            lowerMsg.contains('.ogg') ||
            lowerMsg.contains('.opus') ||
            lowerMsg.contains('.mp3') ||
            lowerMsg.contains('.wav') ||
            lowerMsg.contains('.m4a') ||
            lowerMsg.contains('voice_')) {
          resolvedLastMessageType = '2';
        } else if (lowerMsg.contains('📷') ||
            lowerMsg.contains('foto') ||
            lowerMsg.contains('photo')) {
          resolvedLastMessageType = '3';
        } else if (lowerMsg.contains('🎬') || lowerMsg.contains('video')) {
          resolvedLastMessageType = '4';
        } else if (lowerMsg.contains('📄') || lowerMsg.contains('dokumen')) {
          resolvedLastMessageType = '5';
        } else if (lowerMsg.contains('🌟') || lowerMsg.contains('sticker')) {
          resolvedLastMessageType = '16';
        }
      }

      final bool isArchived =
          _chats[index].isArchived ||
          isRoomArchived(roomId) ||
          isRoomArchived(_chats[index].id);
      if (isArchived) {
        _archivedIds.add(roomId);
        _archivedIds.add(_chats[index].id);
      }

      final chat = _chats[index].copyWith(
        lastMessage: lastMessage,
        lastMessageType: resolvedLastMessageType,
        isLastMessageFromMe: isFromMe,
        needReply: isFromMe ? false : _chats[index].needReply,
        unreadCount: isFromMe ? 0 : _chats[index].unreadCount,
        time: newTime,
        sdrMsg: isFromMe ? 'me' : _chats[index].sdrMsg,
        isArchived: isArchived,
      );

      // Simpan sebagai override agar tidak tertimpa Inbox/GetList yang usang
      _localOverrides[roomId] = chat;
      _overrideTimestamps[roomId] = DateTime.now().toUtc().toIso8601String();
      _saveLocalOverrides();

      if (updateTimeAndPosition && !chat.isPinned && !isArchived) {
        // Pindahkan obrolan ke posisi paling atas (hanya untuk chat aktif yang TIDAK di-pin dan TIDAK di-arsip)
        // Chat yang di-pin posisinya diatur oleh getter sortedChats via _pinnedIds, bukan oleh posisi di _chats raw.
        _chats.removeAt(index);
        _chats.insert(0, chat);
      } else {
        // Update di tempat:
        // - Jika isPinned atau isArchived: jangan pindah posisi agar urutan tidak berubah saat ada pesan baru.
        // - Jika !updateTimeAndPosition: misal saat hapus pesan, waktu bisa mundur.
        _chats[index] = chat;
      }

      _saveLocalOverrides();
      notifyListeners();
    }
  }

  /// Hanya merefresh halaman pertama percakapan tanpa mereset pagination.
  /// Digunakan oleh SignalR dan polling untuk memperbarui data tanpa merusak scroll tanpa batas.
  Future<void> refreshFirstPage({
    int? customStatusCode,
    bool showLoading = false,
  }) async {
    if (_isLoading || _isLoadingMore || _isRefreshingFirstPage) return;
    _isRefreshingFirstPage = true;

    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final statusCode =
          customStatusCode ?? _statusCodeForFilter(_activeFilter);
      // ── Jalur 1: Server-Side Filters only ──────────────────────────────────
      final response = await _chatService.getConversations(
        statusCode: statusCode,
        skip: 0,
        take: _pageSize,
        accountIds: _filterAccountIds.isNotEmpty
            ? _filterAccountIds.join(',')
            : null,
        contactId: _filterContact,
        groupId: _filterGroup,
        campaignId: _filterCampaign,
        dealId: _filterDeal,
        humanAgentId: _filterHumanAgent,
        // linkId → HTTP 500, funnelId, tagsId → client-side
      );

      if (!response.isError && response.data != null) {
        final freshData = response.data!.where((c) {
          final name = c.participantEmail.toLowerCase().trim();
          return name != 'saved messages' && name != 'pesan tersimpan';
        }).toList();
        final existingIds = _chats.map((c) => c.id).toSet();

        // Update existing chats yang datanya berubah
        for (final conv in freshData) {
          var chat = conv.toChatModel();

          // FIX: Resolve channelType dari ChId menggunakan account cache
          if (chat.channelType.isEmpty && chat.chId.isNotEmpty) {
            final resolvedCode = _resolveChannelCode(chat.chId);
            if (resolvedCode.isNotEmpty) {
              chat = chat.copyWith(channelType: resolvedCode);
            }
          }

          // Apply locally cached mapping for tags and funnel
          chat = _applyTagAndFunnelMapping(chat, conv);

          // FIX: Jika API Backend mengatakan Agent yang terakhir membalas,
          // Maka unreadCount HARUS 0, dan kita harus menghapus local override yang mungkin salah (akibat false-negative SignalR).
          if (chat.isLastMessageFromMe) {
            _localUnreadOverrides.remove(chat.id);
            if (!_readIds.contains(chat.id)) _readIds.add(chat.id);
            chat = chat.copyWith(unreadCount: 0);
          } else if (chat.unreadCount > 0 || chat.needReply) {
            _readIds.remove(chat.id);
          }

          // Daftarkan server-pinned chat ke _pinnedIds jika belum ada
          // KONSISTEN: Tambahkan pinned chat baru ke AWAL (beginning) seperti togglePin
          if (chat.isPinned && !_pinnedIds.contains(chat.id)) {
            _pinnedIds = {chat.id, ..._pinnedIds};
            _savePinnedState();
          }

          // Apply persisted local state
          final isArchived = chat.isArchived || isRoomArchived(chat.id);
          if (isArchived) {
            _archivedIds.add(chat.id);
          }
          chat = chat.copyWith(
            isPinned: chat.isPinned || _pinnedIds.contains(chat.id),
            isArchived: isArchived,
            unreadCount:
                (chat.isLastMessageFromMe ||
                    PushNotificationService.currentRoomId == chat.id)
                ? 0
                : (_readIds.contains(chat.id)
                      ? 0
                      : (_localUnreadOverrides[chat.id] ?? chat.unreadCount)),
          );

          final idx = _chats.indexWhere((c) => c.id == chat.id);
          if (idx != -1) {
            final oldChat = _chats[idx];
            // ARSIP SHIELD: Pertahankan status arsip lokal agar tidak dibatalkan
            // oleh data server (St: 1/2) pada saat refreshFirstPage.
            if (oldChat.isArchived ||
                isRoomArchived(oldChat.id) ||
                isRoomArchived(chat.id)) {
              _archivedIds.add(oldChat.id);
              _archivedIds.add(chat.id);
              chat = chat.copyWith(isArchived: true);
            }
            // FIX: Pertahankan nama kontak yang sudah di-save secara lokal.
            if (oldChat.sender.isNotEmpty && oldChat.sender != chat.sender) {
              final isOldSenderANumber = RegExp(
                r'^\+?[0-9\s\-()]+$',
              ).hasMatch(oldChat.sender);
              final isNewSenderANumber = RegExp(
                r'^\+?[0-9\s\-()]+$',
              ).hasMatch(chat.sender);
              if (!isOldSenderANumber || isNewSenderANumber) {
                chat = chat.copyWith(sender: oldChat.sender);
              }
            }
            // Terapkan nama dari persistent storage (prioritas tertinggi)
            final persistedName = _savedContactNames[chat.id];
            if (persistedName != null && persistedName.isNotEmpty) {
              chat = chat.copyWith(sender: persistedName);
            }
            // Terapkan assigned agent override saat kembali ke halaman utama / refresh first page
            chat = _applyAgentOverride(chat);

            // FIX: Lindungi override lokal agar tidak tertimpa oleh data server yang USANG.
            // Override bertahan SELAMANYA sampai server mengirim pesan yang BENAR-BENAR lebih baru.
            if (_localOverrides.containsKey(chat.id)) {
              final localChat = _localOverrides[chat.id]!;
              final localTimeStr = localChat.time;
              final localTime = DateTime.tryParse(
                localTimeStr.endsWith('Z') ? localTimeStr : '${localTimeStr}Z',
              );

              final serverIsNewer = _isServerDataNewer(
                roomId: chat.id,
                serverTimeStr: chat.time,
                serverLastMsg: chat.lastMessage,
                localTime: localTime,
              );

              if (serverIsNewer) {
                // Ada pesan baru sungguhan, hapus override dan terima data server
                _localOverrides.remove(chat.id);
                _overrideTimestamps.remove(chat.id);
                _deletionTimestamps.remove(chat.id);
                _roomsWithDeletions.remove(chat.id);
                _saveLocalOverrides();
                // Jatuh ke logika generic/label di bawah
              } else {
                // Server masih mengembalikan data lama, PERTAHANKAN override lokal
                chat = chat.copyWith(
                  lastMessage: localChat.lastMessage,
                  lastMessageType: localChat.lastMessageType,
                  time: localChat.time,
                  isLastMessageFromMe: localChat.isLastMessageFromMe,
                );
                _chats[idx] = chat;
                continue;
              }
            }

            // FIX: Cegah string generik ("File", "Document") menimpa JSON array media yang sudah valid
            final lowerNew = chat.lastMessage.toLowerCase().trim();
            final oldMsg = oldChat.lastMessage.trim();

            final isGeneric =
                lowerNew.isEmpty ||
                lowerNew == 'null' ||
                const [
                  'file',
                  'document',
                  'document(empty)',
                  'voice',
                  'voice(empty)',
                  'voice note',
                  'photo',
                  'foto',
                  'image',
                  'image(empty)',
                  'video',
                  'video(empty)',
                  'audio',
                  'audio(empty)',
                  'attachment',
                  'lampiran',
                  'pesan suara',
                  'sticker',
                  'stiker',
                ].contains(lowerNew) ||
                (lowerNew.length <= 20 &&
                    (lowerNew.startsWith('document(') ||
                        lowerNew.startsWith('voice(') ||
                        lowerNew.startsWith('image(') ||
                        lowerNew.startsWith('video('))) ||
                RegExp(r'^[\d\.:]+$').hasMatch(lowerNew);

            final oldIsLocalLabel = [
              'voice note',
              'pesan suara',
              'photo',
              'foto',
              'video',
              'audio',
              'sticker',
            ].any((lbl) => oldMsg.toLowerCase().contains(lbl));

            if (isGeneric) {
              if (oldMsg.startsWith('{') ||
                  oldMsg.startsWith('[') ||
                  oldIsLocalLabel) {
                chat = chat.copyWith(
                  lastMessage: oldChat.lastMessage,
                  lastMessageType: oldChat.lastMessageType,
                );
              }
            } else if (lowerNew.startsWith('{') || lowerNew.startsWith('[')) {
              // Jika JSON baru datang, tapi tidak memiliki ciri-ciri audio yang jelas
              final newIsAudioJson =
                  lowerNew.contains('"type":2') ||
                  lowerNew.contains('"type": 2') ||
                  lowerNew.contains('"ptt":true') ||
                  lowerNew.contains('"ptt": true') ||
                  lowerNew.contains('.ogg') ||
                  lowerNew.contains('.mp3') ||
                  lowerNew.contains('.opus');

              // Apakah pesan lama adalah audio? (JSON lengkap ATAU label manual)
              final oldIsAudioJson =
                  oldMsg.toLowerCase().contains('"type":2') ||
                  oldMsg.toLowerCase().contains('"type": 2') ||
                  oldMsg.toLowerCase().contains('"ptt":true') ||
                  oldMsg.toLowerCase().contains('"ptt": true');
              final oldIsAudioLabel =
                  oldMsg.toLowerCase().contains('voice note') ||
                  oldMsg.toLowerCase().contains('pesan suara');
              if ((oldIsAudioJson || oldIsAudioLabel) && !newIsAudioJson) {
                chat = chat.copyWith(
                  lastMessage: oldChat.lastMessage,
                  lastMessageType: oldChat.lastMessageType,
                );
              }
            } else if ((oldIsLocalLabel ||
                    oldMsg.startsWith('{') ||
                    oldMsg.startsWith('[')) &&
                lowerNew.length <= 15 &&
                oldMsg.toLowerCase().contains(lowerNew)) {
              chat = chat.copyWith(
                lastMessage: oldChat.lastMessage,
                lastMessageType: oldChat.lastMessageType,
              );
            }

            // FIX: Cek apakah pesan terakhir adalah pesan yang baru kita kirim dari aplikasi ini
            final bool isSentByMeRecently = isRecentMessageFromMe(
              chat.id,
              chat.lastMessage,
            );

            if (isSentByMeRecently) {
              chat = chat.copyWith(
                isLastMessageFromMe: true,
                needReply: false,
                unreadCount: 0,
                sdrMsg: 'me',
              );
            } else if (!chat.isLastMessageFromMe &&
                oldChat.isLastMessageFromMe) {
              // FIX: Pewarisan isLastMessageFromMe dari cache lokal
              final newLower = chat.lastMessage.toLowerCase().trim();
              final oldLower = oldChat.lastMessage.toLowerCase().trim();
              final isMediaJSON =
                  newLower.startsWith('{') || newLower.startsWith('[');
              final oldHasMediaLabel = [
                'photo',
                'foto',
                'video',
                'voice',
                'suara',
                'audio',
                'file',
                'document',
                'sticker',
                'location',
                'lokasi',
                'media',
              ].any((lbl) => oldLower.contains(lbl));
              final isTextMatch =
                  oldLower.isNotEmpty &&
                  newLower.isNotEmpty &&
                  newLower == oldLower;
              if (isTextMatch || (isMediaJSON && oldHasMediaLabel)) {
                chat = chat.copyWith(
                  isLastMessageFromMe: true,
                  needReply: false,
                  unreadCount: 0,
                  sdrMsg: 'me',
                );
              }
            }

            if (_recentIsMeFlags.containsKey(chat.id) &&
                _recentIsMeFlags[chat.id] == true) {
              chat = chat.copyWith(
                isLastMessageFromMe: true,
                needReply: false,
                unreadCount: 0,
                sdrMsg: 'me',
              );
            }

            // FIX UNREAD COUNT DI API LIST:
            // Polling API List sering mengembalikan Uc: 0 jika Backend NoBox mendeteksi websocket aktif.
            // Jika waktu pesan ini lebih baru dan bukan dari kita, maka KITA HARUS MENG-INCREMENT UNREAD.
            final serverTimeParsed = DateTime.tryParse(
              chat.time.endsWith('Z') ? chat.time : chat.time + 'Z',
            );
            final oldTimeParsed = DateTime.tryParse(
              oldChat.time.endsWith('Z') ? oldChat.time : oldChat.time + 'Z',
            );

            if (serverTimeParsed != null &&
                (oldTimeParsed == null ||
                    serverTimeParsed.isAfter(oldTimeParsed))) {
              if (!chat.isLastMessageFromMe &&
                  PushNotificationService.currentRoomId != chat.id &&
                  chat.lastMessage != 'Site.Inbox.DeletedMessage') {
                final currentUc =
                    _localUnreadOverrides[chat.id] ?? oldChat.unreadCount;
                final forcedUc = currentUc + 1;
                _localUnreadOverrides[chat.id] = forcedUc;
                chat = chat.copyWith(unreadCount: forcedUc);
                _readIds.remove(chat.id);
                _saveReadState();
                debugPrint(
                  'ChatProvider: 📈 Incremented Unread (via API List) for room ${chat.id}. New Uc: $forcedUc',
                );
              } else if (chat.isLastMessageFromMe) {
                // Jika pesan baru ini dari kita (misal kita balas dari web), reset unread
                _localUnreadOverrides.remove(chat.id);
                if (!_readIds.contains(chat.id)) _readIds.add(chat.id);
                chat = chat.copyWith(unreadCount: 0);
                _saveReadState();
              }
            } else {
              // WAKTU SAMA (bukan pesan lebih baru).
              // FIX: Hormati cache unread lokal! Karena Backend NoBox sering mereturn uc=0 pada saat waktu sama (bug online),
              // Jika kita tidak menggunakan _localUnreadOverrides di sini, maka angka badge akan HILANG SECARA TIBA-TIBA (menjadi 0).
              chat = chat.copyWith(
                unreadCount: _localUnreadOverrides[chat.id] ?? chat.unreadCount,
              );
            }

            _chats[idx] = chat;
          } else {
            // FIX: Bersihkan/Timpa dummy chat (yang dibuat lokal) jika contactId cocok
            // Ini mencegah duplikasi chat room (satu asli, satu dummy)
            final dummyIdx = _chats.indexWhere(
              (c) =>
                  (c.id.isEmpty || c.id == '0') &&
                  c.contactId == chat.contactId,
            );
            if (dummyIdx != -1) {
              _chats[dummyIdx] = chat;
              existingIds.add(
                chat.id,
              ); // Cegah agar tidak ditambah ganda di step newChats
            }
          }
        }

        // Tambahkan kontak baru yang belum ada
        final newChats = freshData.where((c) => !existingIds.contains(c.toChatModel().id)).map((
          c,
        ) {
          var chat = c.toChatModel();

          // FIX: Resolve channelType dari ChId menggunakan account cache
          if (chat.channelType.isEmpty && chat.chId.isNotEmpty) {
            final resolvedCode = _resolveChannelCode(chat.chId);
            if (resolvedCode.isNotEmpty) {
              chat = chat.copyWith(channelType: resolvedCode);
            }
          }

          // Apply locally cached mapping for tags and funnel
          chat = _applyTagAndFunnelMapping(chat, c);

          // Terapkan nama dari persistent storage (prioritas tertinggi)
          final persistedName = _savedContactNames[chat.id];
          if (persistedName != null && persistedName.isNotEmpty) {
            chat = chat.copyWith(sender: persistedName);
          }
          chat = _applyAgentOverride(chat);

          // FIX: Terapkan local overrides saat app baru load (Hot Restart)
          if (_localOverrides.containsKey(chat.id)) {
            final localChat = _localOverrides[chat.id]!;
            final localTimeStr = localChat.time;
            final localTime = DateTime.tryParse(
              localTimeStr.endsWith('Z') ? localTimeStr : '${localTimeStr}Z',
            );

            final serverIsNewer = _isServerDataNewer(
              roomId: chat.id,
              serverTimeStr: chat.time,
              serverLastMsg: chat.lastMessage,
              localTime: localTime,
            );

            if (!serverIsNewer) {
              // Server masih mengembalikan data lama, PERTAHANKAN override lokal
              chat = chat.copyWith(
                lastMessage: localChat.lastMessage,
                lastMessageType:
                    localChat.lastMessageType ?? chat.lastMessageType,
                time: localChat.time,
                isLastMessageFromMe: localChat.isLastMessageFromMe,
              );
            } else {
              // Override kadaluarsa, terima data server
              _localOverrides.remove(chat.id);
              _overrideTimestamps.remove(chat.id);
              _deletionTimestamps.remove(chat.id);
              _roomsWithDeletions.remove(chat.id);
              _saveLocalOverrides();
            }
          }

          final oldIdx = _chats.indexWhere((c) => c.id == chat.id);
          if (oldIdx != -1) {
            bool isTimeDifferent = false;
            try {
              final t1 = DateTime.parse(
                chat.time.endsWith('Z') ? chat.time : chat.time + 'Z',
              );
              final t2 = DateTime.parse(
                _chats[oldIdx].time.endsWith('Z')
                    ? _chats[oldIdx].time
                    : _chats[oldIdx].time + 'Z',
              );
              isTimeDifferent = t1.difference(t2).inSeconds.abs() > 0;
            } catch (e) {
              isTimeDifferent = chat.time != _chats[oldIdx].time;
            }

            if (isTimeDifferent && chat.unreadCount > 0) {
              _readIds.remove(chat.id);
            }
          } else if (chat.unreadCount > 0) {
            _readIds.remove(chat.id);
          }

          // Tidak boleh memaksa unreadCount = 1 untuk obrolan dari API List New,
          // karena dapat menyebabkan obrolan lama yang sudah dibaca ikut muncul unread = 1.

          if (chat.isPinned && !_pinnedIds.contains(chat.id)) {
            // KONSISTEN: Tambahkan pinned chat baru ke AWAL (beginning) seperti togglePin
            _pinnedIds = {chat.id, ..._pinnedIds};
            _savePinnedState();
          }

          final isArchived = chat.isArchived || isRoomArchived(chat.id);
          if (isArchived) {
            _archivedIds.add(chat.id);
          }
          return chat.copyWith(
            isPinned: chat.isPinned || _pinnedIds.contains(chat.id),
            isArchived: isArchived,
            unreadCount: _readIds.contains(chat.id)
                ? 0
                : (_localUnreadOverrides[chat.id] ?? chat.unreadCount),
          );
        }).toList();

        // ARSIP SHIELD: Jangan pernah menambahkan room yang sudah diarsipkan ke
        // daftar utama, bahkan jika server mengembalikannya tanpa status archived.
        final nonArchivedNewChats = newChats.where((chat) {
          if (chat.isArchived) return false;
          if (_archivedIds.contains(chat.id)) return false;
          return true;
        }).toList();

        if (nonArchivedNewChats.isNotEmpty) {
          _chats.insertAll(0, nonArchivedNewChats);
        }

        // 1. Check for DeletedMessages, system logs, or rooms with deleted messages
        final prefs = await SharedPreferences.getInstance();
        final deletedRooms = _chats
            .where((c) {
              final lower = c.lastMessage.toLowerCase();
              final isSystemOrPlaceholder =
                  c.lastMessage == 'Site.Inbox.DeletedMessage' ||
                  lower.contains('site.inbox.') ||
                  lower.contains('percakapan di-assign') ||
                  lower.contains('percakapan diselesaikan') ||
                  lower.contains('bot diaktifkan') ||
                  lower.contains('pemberitahuan sistem');
              if (isSystemOrPlaceholder) return true;

              if (!_localOverrides.containsKey(c.id)) {
                final delList = prefs.getStringList('deleted_ids_${c.id}');
                if (delList != null && delList.isNotEmpty) {
                  return true;
                }
              }
              return false;
            })
            .map((c) => c.id)
            .toList();
        if (deletedRooms.isNotEmpty) {
          _fetchRealLastMessagesForDeletedRooms(deletedRooms);
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('ChatProvider: refreshFirstPage error: $e');
    } finally {
      _isRefreshingFirstPage = false;
      if (showLoading && _isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Mengambil lebih banyak chat untuk pagination scroll tanpa batas.
  /// Menambahkan data baru ke daftar yang sudah ada. Menjaga dari request ganda.
  // FITUR 2: Paging untuk mengambil data chat berikutnya berdasarkan posisi scroll.
  Future<void> fetchMoreChats() async {
    // Guard: prevent duplicate fetch
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _fetchGeneration++;
    final currentGen = _fetchGeneration;
    notifyListeners();

    try {
      final statusCode = _statusCodeForFilter(_activeFilter);
      // ── Jalur 1: Server-Side Filters only ──────────────────────────────────
      final response = await _chatService.getConversations(
        statusCode: statusCode,
        skip: _currentSkip,
        take: _pageSize,
        accountIds: _filterAccountIds.isNotEmpty
            ? _filterAccountIds.join(',')
            : null,
        contactId: _filterContact,
        groupId: _filterGroup,
        campaignId: _filterCampaign,
        dealId: _filterDeal,
        humanAgentId: _filterHumanAgent,
        // linkId → HTTP 500, funnelId, tagsId → client-side
      );

      // Guard: jika generation sudah berubah (user ganti tab), abaikan
      if (currentGen != _fetchGeneration) {
        _isLoadingMore = false;
        notifyListeners();
        return;
      }

      if (!response.isError && response.data != null) {
        final newConversations = response.data!;
        debugPrint(
          '📄 [Pagination] Loaded ${newConversations.length} more items (skip=$_currentSkip)',
        );

        if (newConversations.isEmpty) {
          _hasMore = false;
        } else {
          final existingIds = _chats.map((c) => c.id).toSet();

          final newChats = newConversations
              .map((c) {
                var chat = c.toChatModel();

                // Apply locally cached mapping for tags and funnel
                chat = _applyTagAndFunnelMapping(chat, c);

                if (chat.isPinned && !_pinnedIds.contains(chat.id)) {
                  // KONSISTEN: Tambahkan pinned chat baru ke AWAL (beginning) seperti togglePin
                  _pinnedIds = {chat.id, ..._pinnedIds};
                  _savePinnedState();
                }

                // Apply persisted local state
                final isArchived = chat.isArchived || isRoomArchived(chat.id);
                if (isArchived) {
                  _archivedIds.add(chat.id);
                }
                return chat.copyWith(
                  isPinned: chat.isPinned || _pinnedIds.contains(chat.id),
                  isArchived: isArchived,
                  unreadCount: _readIds.contains(chat.id)
                      ? 0
                      : (_localUnreadOverrides[chat.id] ?? chat.unreadCount),
                );
              })
              .where((chat) => !existingIds.contains(chat.id))
              .toList();

          _chats.addAll(newChats);
          _currentSkip += newConversations.length;

          // Jika data < 20, matikan hasMore
          if (newConversations.length < _pageSize) {
            _hasMore = false;
          } else {
            _hasMore = true;
          }

          debugPrint(
            '📄 [Pagination] Total chats now: ${_chats.length}, hasMore=$_hasMore',
          );

          // PERF: Perbarui master list saat paging pada tab 'All' agar filter
          // lokal selanjutnya tetap lengkap.
          if (_activeFilter == 'All') {
            _allMasterChats = List.from(_chats);
          }
        }
      } else {
        // Guard: jika generation sudah berubah, abaikan error
        if (currentGen != _fetchGeneration) {
          _isLoadingMore = false;
          notifyListeners();
          return;
        }
        debugPrint('📄 [Pagination] Error loading more: ${response.error}');
        // Don't set _hasMore to false on error — allow retry
      }
    } catch (e) {
      // Guard: jika generation sudah berubah, abaikan exception
      if (currentGen != _fetchGeneration) return;
      debugPrint('📄 [Pagination] Exception loading more: $e');
    } finally {
      // Guard: hanya notify jika generation masih sama
      if (currentGen == _fetchGeneration) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  // ── Persisted State Management ──

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load Overrides
      await _loadLocalOverrides();

      final pinnedJson = prefs.getString(_pinnedKey);
      if (pinnedJson != null) {
        _pinnedIds = Set<String>.from(jsonDecode(pinnedJson));
      }

      final archivedJson = prefs.getString(_archivedKey);
      if (archivedJson != null) {
        _archivedIds = Set<String>.from(jsonDecode(archivedJson));
      }

      final readJson = prefs.getString(_readKey);
      if (readJson != null) {
        _readIds = Set<String>.from(jsonDecode(readJson));
      }

      final starredJson = prefs.getString(_starredKey);
      if (starredJson != null) {
        _starredMessageIds = Set<String>.from(jsonDecode(starredJson));
      }

      final starredDataJson = prefs.getString(_starredDataKey);
      if (starredDataJson != null) {
        _starredMessages.clear();
        final list = jsonDecode(starredDataJson) as List;
        _starredMessages.addAll(list.cast<Map<String, dynamic>>());
      }

      // Load nama kontak yang sudah disave
      final savedNamesJson = prefs.getString(_savedContactNamesKey);
      debugPrint('ChatProvider: 🔍 savedContactNames raw: $savedNamesJson');
      if (savedNamesJson != null) {
        try {
          final decoded = jsonDecode(savedNamesJson) as Map<String, dynamic>;
          _savedContactNames = decoded.map((k, v) => MapEntry(k, v.toString()));
          debugPrint(
            'ChatProvider: ✅ Loaded ${_savedContactNames.length} saved names: $_savedContactNames',
          );
        } catch (e) {
          debugPrint('ChatProvider: ❌ Error decoding saved contact names: $e');
        }
      } else {
        debugPrint(
          'ChatProvider: ⚠️ No saved contact names in prefs (key=$_savedContactNamesKey)',
        );
      }

      // Load data lokasi kontak yang sudah disave
      final savedLocationsJson = prefs.getString(_savedContactLocationsKey);
      if (savedLocationsJson != null) {
        try {
          final decoded =
              jsonDecode(savedLocationsJson) as Map<String, dynamic>;
          _savedContactLocations = decoded.map((k, v) {
            final locMap = (v as Map<String, dynamic>).map(
              (lk, lv) => MapEntry(lk, lv.toString()),
            );
            return MapEntry(k, locMap);
          });
          debugPrint(
            'ChatProvider: ✅ Loaded ${_savedContactLocations.length} saved locations',
          );
        } catch (e) {
          debugPrint(
            'ChatProvider: ❌ Error decoding saved contact locations: $e',
          );
        }
      }

      // Load data agent assignments yang sudah disave
      final savedAgentsJson = prefs.getString(_savedAgentNamesKey);
      if (savedAgentsJson != null) {
        try {
          final decoded = jsonDecode(savedAgentsJson) as Map<String, dynamic>;
          _savedAgentNames = decoded.map((k, v) => MapEntry(k, v.toString()));
          debugPrint(
            'ChatProvider: ✅ Loaded ${_savedAgentNames.length} saved agent names: $_savedAgentNames',
          );
        } catch (e) {
          debugPrint('ChatProvider: ❌ Error decoding saved agent names: $e');
        }
      }

      // Load data status block/unblock yang sudah disave
      final savedBlocksJson = prefs.getString(_savedBlockStatesKey);
      if (savedBlocksJson != null) {
        try {
          final decoded = jsonDecode(savedBlocksJson) as Map<String, dynamic>;
          _savedBlockStates = decoded.map(
            (k, v) =>
                MapEntry(k, v == true || v == 'true' || v == 1 || v == '1'),
          );
          debugPrint(
            'ChatProvider: ✅ Loaded ${_savedBlockStates.length} saved block states',
          );
        } catch (e) {
          debugPrint('ChatProvider: ❌ Error decoding saved block states: $e');
        }
      }

      // Load cache avatar URL terbaru dari DetailRoom
      final savedAvatarsJson = prefs.getString(_cachedAvatarUrlsKey);
      if (savedAvatarsJson != null) {
        try {
          final decoded = jsonDecode(savedAvatarsJson) as Map<String, dynamic>;
          _cachedAvatarUrls = decoded.map((k, v) => MapEntry(k, v.toString()));
          debugPrint(
            'ChatProvider: ✅ Loaded ${_cachedAvatarUrls.length} cached avatar URLs',
          );
        } catch (e) {
          debugPrint('ChatProvider: ❌ Error decoding cached avatar URLs: $e');
        }
      }
    } catch (e) {
      debugPrint('ChatProvider: ❌ Error loading persisted state: $e');
    }

    notifyListeners();
  }

  // PERF: Debounce penulisan state agar tidak terjadi banyak write
  // SharedPreferences dalam satu frame (mis. saat iterasi daftar chat).
  void _savePinnedState() {
    _savePinnedDebounce?.cancel();
    _savePinnedDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pinnedKey, jsonEncode(_pinnedIds.toList()));
      } catch (e) {
        debugPrint('ChatProvider: Failed to save pinned state: $e');
      }
    });
  }

  void _saveArchivedState({bool immediate = false}) {
    if (immediate) {
      _saveArchivedDebounce?.cancel();
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setString(_archivedKey, jsonEncode(_archivedIds.toList()));
          })
          .catchError((e) {
            debugPrint(
              'ChatProvider: Failed to save archived state immediately: $e',
            );
          });
      return;
    }
    _saveArchivedDebounce?.cancel();
    _saveArchivedDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_archivedKey, jsonEncode(_archivedIds.toList()));
      } catch (e) {
        debugPrint('ChatProvider: Failed to save archived state: $e');
      }
    });
  }

  void _saveReadState() {
    _saveReadDebounce?.cancel();
    _saveReadDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_readKey, jsonEncode(_readIds.toList()));
      } catch (e) {
        debugPrint('ChatProvider: Failed to save read state: $e');
      }
    });
  }

  Future<void> _saveStarredState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_starredKey, jsonEncode(_starredMessageIds.toList()));
    await prefs.setString(_starredDataKey, jsonEncode(_starredMessages));
  }

  /// Simpan peta nama kontak ke SharedPreferences agar bertahan melewati restart.
  Future<void> _saveSavedContactNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedContactNamesKey,
      jsonEncode(_savedContactNames),
    );
  }

  /// Simpan peta data lokasi kontak ke SharedPreferences.
  Future<void> _saveSavedContactLocations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedContactLocationsKey,
      jsonEncode(_savedContactLocations),
    );
  }

  /// Simpan peta nama agent ke SharedPreferences.
  Future<void> _saveSavedAgentNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedAgentNamesKey, jsonEncode(_savedAgentNames));
  }

  /// Simpan peta status block ke SharedPreferences.
  Future<void> _saveSavedBlockStates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedBlockStatesKey, jsonEncode(_savedBlockStates));
  }

  /// Ambil data lokasi kontak yang disimpan secara lokal.
  Map<String, String>? getSavedContactLocation(String roomId) {
    return _savedContactLocations[roomId];
  }

  /// Ambil nama kontak yang disimpan secara lokal (optimistic save).
  String? getSavedContactName(String roomId) {
    return _savedContactNames[roomId];
  }

  /// Ambil nama agent yang disimpan secara lokal (optimistic update).
  String? getSavedAgentName(String roomId) {
    return _savedAgentNames[roomId];
  }

  /// Ambil URL avatar terbaru yang di-cache dari DetailRoom.
  String? getCachedAvatarUrl(String roomId) {
    return _cachedAvatarUrls[roomId];
  }

  /// Simpan URL avatar terbaru ke cache (dipanggil dari contact_info_page setelah dapat DetailRoom).
  Future<void> saveCachedAvatarUrl(String roomId, String avatarUrl) async {
    if (avatarUrl.isEmpty) return;
    _cachedAvatarUrls[roomId] = avatarUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedAvatarUrlsKey, jsonEncode(_cachedAvatarUrls));
  }

  // ── Getter Terkomputasi ──

  int get unassignedCount =>
      _chats.where((c) => !c.isArchived && c.status == 'Unassigned').length;
  int get assignedCount =>
      _chats.where((c) => !c.isArchived && c.status == 'Assigned').length;
  int get resolvedCount =>
      _chats.where((c) => !c.isArchived && c.status == 'Resolved').length;
  int get totalUnreadCount =>
      (_allMasterChats.isNotEmpty ? _allMasterChats : _chats)
          .where((c) => !c.isArchived)
          .fold(0, (sum, c) => sum + c.unreadCount);

  // Unread per tab
  int get unassignedUnread =>
      (_allMasterChats.isNotEmpty ? _allMasterChats : _chats)
          .where((c) => !c.isArchived && c.status == 'Unassigned')
          .fold(0, (sum, c) => sum + c.unreadCount);
  int get assignedUnread =>
      (_allMasterChats.isNotEmpty ? _allMasterChats : _chats)
          .where((c) => !c.isArchived && c.status == 'Assigned')
          .fold(0, (sum, c) => sum + c.unreadCount);
  int get resolvedUnread =>
      (_allMasterChats.isNotEmpty ? _allMasterChats : _chats)
          .where((c) => !c.isArchived && c.status == 'Resolved')
          .fold(0, (sum, c) => sum + c.unreadCount);

  // ── Starred Messages ──

  List<Map<String, dynamic>> get starredMessages =>
      List.unmodifiable(_starredMessages);
  bool isStarred(String messageId) => _starredMessageIds.contains(messageId);

  // FITUR 12: Menyimpan pesan-pesan tertentu yang dianggap penting oleh user.
  // [ACTION: STAR_MESSAGE_TOGGLE] - Menyimpan/hapus pesan penting ke SharedPreferences
  void toggleStar(
    String messageId, {
    String? content,
    String? sender,
    String? time,
  }) {
    if (_starredMessageIds.contains(messageId)) {
      _starredMessageIds.remove(messageId);
      _starredMessages.removeWhere((m) => m['id'] == messageId);
    } else {
      _starredMessageIds.add(messageId);
      _starredMessages.add({
        'id': messageId,
        'content': content ?? '',
        'sender': sender ?? '',
        'time': time ?? '',
        'starredAt': DateTime.now().toIso8601String(),
      });
    }
    _saveStarredState();
    notifyListeners();
  }

  // Getter untuk semua chat tanpa filter (berguna untuk lookup langsung by ID)
  List<ChatModel> get allChats => _chats;

  // Local overrides untuk lastMessage agar tidak tertimpa data usang dari server
  Map<String, ChatModel> _localOverrides = {};
  Map<String, String> _overrideTimestamps =
      {}; // Waktu kapan override dibuat (UTC)

  Future<void> _loadLocalOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final overridesJson = prefs.getString(_localOverridesKey);
      if (overridesJson != null) {
        final decoded = jsonDecode(overridesJson) as Map<String, dynamic>;
        _localOverrides.clear();
        for (final entry in decoded.entries) {
          final val = entry.value as Map<String, dynamic>;
          String lastMsgStr = val['lastMessage']?.toString() ?? '';
          if (lastMsgStr.contains('[-{=||=}-]')) {
            lastMsgStr = '📍 Location';
          }
          final lowerMsg = lastMsgStr.toLowerCase();
          final isBogusSystemMsg =
              lastMsgStr == 'Site.Inbox.DeletedMessage' ||
              lowerMsg.contains('site.inbox.') ||
              lowerMsg.contains('percakapan di-assign') ||
              lowerMsg.contains('percakapan diselesaikan') ||
              lowerMsg.contains('bot diaktifkan') ||
              lowerMsg.contains('pemberitahuan sistem');
          if (isBogusSystemMsg) {
            debugPrint(
              'ChatProvider: 🧹 Ignoring bogus system message override in SharedPreferences for room ${entry.key}',
            );
            continue;
          }
          _localOverrides[entry.key] = ChatModel(
            id: entry.key,
            sender: val['sender']?.toString() ?? '',
            contactId: val['contactId']?.toString() ?? '',
            ctRealId: val['ctRealId']?.toString() ?? '',
            accountId: val['accountId']?.toString() ?? '',
            chId: val['chId']?.toString() ?? '',
            channelName: val['channelName']?.toString() ?? '',
            channelType: val['channelType']?.toString() ?? '',
            link: val['link']?.toString() ?? '',
            isGroup: val['isGroup'] == true,
            isBlocked: val['isBlocked'] == true,
            status: val['status']?.toString() ?? 'Unassigned',
            lastMessage: lastMsgStr,
            lastMessageType: val['lastMessageType']?.toString(),
            time: val['time']?.toString() ?? '',
            isLastMessageFromMe: val['isLastMessageFromMe'] == true,
            needReply: val['isLastMessageFromMe'] == true
                ? false
                : (val['needReply'] == true),
            unreadCount: val['isLastMessageFromMe'] == true
                ? 0
                : (val['unreadCount'] is int ? val['unreadCount'] : 0),
          );
        }
      }

      final timestampsJson = prefs.getString('override_timestamps');
      if (timestampsJson != null) {
        final Map<String, dynamic> decodedTs = jsonDecode(timestampsJson);
        _overrideTimestamps = decodedTs.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      }

      final delTsJson = prefs.getString('deletion_timestamps');
      if (delTsJson != null) {
        final Map<String, dynamic> decodedDelTs = jsonDecode(delTsJson);
        _deletionTimestamps = decodedDelTs.map(
          (key, value) => MapEntry(key, value.toString()),
        );
        _roomsWithDeletions.addAll(_deletionTimestamps.keys);
      }
    } catch (e) {
      debugPrint('ChatProvider: Error loading local overrides: $e');
    }
  }

  Timer? _overrideDebounceTimer;

  Future<void> _saveLocalOverrides() async {
    _overrideDebounceTimer?.cancel();
    _overrideDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final Map<String, dynamic> data = _localOverrides.map(
          (k, v) => MapEntry(k, {
            'lastMessage': v.lastMessage,
            'lastMessageType': v.lastMessageType,
            'isLastMessageFromMe': v.isLastMessageFromMe,
            'needReply': v.needReply,
            'unreadCount': v.unreadCount,
            'time': v.time,
            'sender': v.sender,
            'contactId': v.contactId,
            'ctRealId': v.ctRealId,
            'accountId': v.accountId,
            'chId': v.chId,
            'channelName': v.channelName,
            'channelType': v.channelType,
            'link': v.link,
            'isGroup': v.isGroup,
            'isBlocked': v.isBlocked,
            'status': v.status,
          }),
        );
        await prefs.setString(_localOverridesKey, jsonEncode(data));
        await prefs.setString(
          'override_timestamps',
          jsonEncode(_overrideTimestamps),
        );
        await prefs.setString(
          'deletion_timestamps',
          jsonEncode(_deletionTimestamps),
        );
      } catch (e) {
        debugPrint('ChatProvider: Failed to save local overrides: $e');
      }
    });
  }

  // [ACTION: FILTER_APPLY] - Getter ini mengeksekusi filter (lokal) pada daftar chat
  List<ChatModel> get chats {
    var filtered = _chats.where((chat) {
      if (chat.isArchived || isRoomArchived(chat.id)) {
        return false;
      }
      final senderLower = chat.sender.toLowerCase().trim();
      if (senderLower == 'saved messages' || senderLower == 'pesan tersimpan') {
        return false;
      }
      return true;
    }).toList();

    // Apply Search (Hanya mencari berdasarkan Nama Kontak / Pengirim)
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (chat) =>
                chat.sender.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    // Apply Filter by status
    switch (_activeFilter) {
      case 'Unassigned':
        filtered = filtered
            .where((chat) => chat.status == 'Unassigned')
            .toList();
        break;
      case 'Assigned':
        filtered = filtered.where((chat) => chat.status == 'Assigned').toList();
        break;
      case 'Resolved':
        filtered = filtered.where((chat) => chat.status == 'Resolved').toList();
        break;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Advanced Filters — Arsitektur Dua Jalur
    // ══════════════════════════════════════════════════════════════════════
    // Jalur 1 (Server-Side): Account, Contact, Group, Campaign, Deal
    //   → Sudah difilter API via EqualityFilter. Tidak perlu filter lokal lagi.
    //
    // Jalur 2 (Client-Side): MuteAi, Channel, ChatType, ReadStatus,
    //                         Link, Funnel, Tag, HumanAgent
    //   → Filter lokal di sini menggunakan .where() + ID-to-name resolution.
    // ══════════════════════════════════════════════════════════════════════

    // MuteAi — client-side
    if (_filterMuteAi != null && _filterMuteAi != '--select--') {
      final isMuted = _filterMuteAi == 'Yes';
      filtered = filtered.where((c) => c.muteAiAgent == isMuted).toList();
    }

    // ReadStatus — client-side only (backend tidak support filter ini)
    if (_filterReadStatus != null && _filterReadStatus != '--select--') {
      final isRead =
          _filterReadStatus ==
          'Is Read'; // FIX: String dari UI adalah 'Is Read', bukan 'Read'
      filtered = filtered
          .where((c) => isRead ? c.unreadCount == 0 : c.unreadCount > 0)
          .toList();
    }

    // Channel — client-side (berdasarkan Code dari account list, misal: 'WhatsApp', 'Telegram')
    // _filterChannel berisi string seperti 'WhatsApp' yang dibandingkan dengan channelType
    // channelType sudah di-resolve dari ChId → Code di saat fetch data.
    if (_filterChannel != null && _filterChannel != '--select--') {
      filtered = filtered.where((c) {
        // Primary: bandingkan dengan channelType (sudah di-resolve dari account Code)
        if (c.channelType.isNotEmpty) {
          return c.channelType.toLowerCase().contains(
            _filterChannel!.toLowerCase(),
          );
        }
        // Fallback: bandingkan channelName (nama akun) jika channelType kosong
        return c.channelName.toLowerCase().contains(
          _filterChannel!.toLowerCase(),
        );
      }).toList();
    }

    // ChatType — client-side only (backend tidak support IsGrp filter via EqualityFilter)
    if (_filterChatType != null && _filterChatType != '--select--') {
      final isGroup = _filterChatType == 'Group';
      filtered = filtered.where((c) => c.isGroup == isGroup).toList();
    }

    // Contact — FIX: Jalur 1 server-side mengirim CtId ke EqualityFilter.
    // Namun ContactItem.id = Entity Id dari /Nobox/Contact/List yang sama dengan CtRealId chatroom.
    // Tambahkan client-side fallback: cocokkan c.ctRealId (Entity Id) dengan _filterContact.
    if (_filterContact != null && _filterContact!.isNotEmpty) {
      filtered = filtered
          .where(
            (c) =>
                c.ctRealId == _filterContact || c.contactId == _filterContact,
          )
          .toList();
    }

    // Group fallback
    if (_filterGroup != null && _filterGroup!.isNotEmpty) {
      filtered = filtered.where((c) => c.groupId == _filterGroup).toList();
    }

    // Campaign fallback
    if (_filterCampaign != null && _filterCampaign!.isNotEmpty) {
      filtered = filtered.where((c) => c.campaign == _filterCampaign).toList();
    }

    // Deal fallback
    if (_filterDeal != null && _filterDeal!.isNotEmpty) {
      filtered = filtered.where((c) => c.deal == _filterDeal).toList();
    }

    // Account fallback
    if (_filterAccountIds.isNotEmpty) {
      filtered = filtered
          .where((c) => _filterAccountIds.contains(c.accountId))
          .toList();
    }

    // ── Jalur 2: Filters berikut di-remove dari payload API ─────────────────

    // Link — CLIENT-SIDE ONLY
    // KONFIRMASI LOG: Chatlinkcontacts.Id = Chatroom.CtId
    // Contoh: Chatlinkcontacts {Id:814657018602245, Name:"Senikersku"}
    //         Chatroom: {CtId:814657018602245, Ct:"Senikersku"}
    // → filter: chat.contactId == _filterLink (membandingkan CtId)
    // EqualityFilter LinkTmp = HTTP 500 (tidak didukung server)
    if (_filterLink != null && _filterLink != '--select--') {
      filtered = filtered.where((c) => c.contactId == _filterLink!).toList();
      debugPrint(
        '[Link Filter] filterLink=$_filterLink, hasil=${filtered.length}',
      );
    }

    // Funnel — client-side only (mengirim FunnelId ke backend menyebabkan Error 500)
    // _filterFunnel menyimpan ID funnel → resolve ke nama untuk dibandingkan dengan chat.funnel
    if (_filterFunnel != null && _filterFunnel != '--select--') {
      final resolvedFunnelName = _resolveFunnelName(_filterFunnel!);
      if (resolvedFunnelName != null && resolvedFunnelName.isNotEmpty) {
        filtered = filtered
            .where(
              (c) => c.funnel.toLowerCase() == resolvedFunnelName.toLowerCase(),
            )
            .toList();
      } else {
        // Fallback: bandingkan ID langsung
        filtered = filtered
            .where(
              (c) =>
                  c.funnel.toLowerCase().contains(_filterFunnel!.toLowerCase()),
            )
            .toList();
      }
    }

    // Tag — client-side only (mengirim TagsIds ke backend menyebabkan Error 500)
    // _filterTags menyimpan ID tag → resolve ke nama untuk dibandingkan dengan chat.tags
    if (_filterTags != null && _filterTags != '--select--') {
      final resolvedTagName = _resolveTagName(_filterTags!);
      if (resolvedTagName != null && resolvedTagName.isNotEmpty) {
        filtered = filtered
            .where(
              (c) => c.tags.any(
                (t) => t.toLowerCase() == resolvedTagName.toLowerCase(),
              ),
            )
            .toList();
      } else {
        // Fallback: bandingkan ID langsung
        filtered = filtered
            .where(
              (c) => c.tags.any(
                (t) => t.toLowerCase() == _filterTags!.toLowerCase(),
              ),
            )
            .toList();
      }
    }

    // PENTING: sesama pinned chat kini diurutkan berdasarkan riwayat pin (statis di _pinnedIds)
    // agar tidak bergerak posisi ketika ada pesan baru masuk atau di-refresh.
    final pinnedInOrder = filtered.where((c) => c.isPinned).toList();

    // Pastikan semua pinned chat terdaftar di _pinnedIds agar urutannya konsisten dan stabil
    // KONSISTEN: Tambahkan pinned chat baru ke AWAL (beginning) seperti togglePin.
    // TIDAK menulis SharedPreferences di sini (side-effect disk I/O dihapus demi
    // menghindari lag saat getter dipanggil pada setiap frame build).
    for (final c in pinnedInOrder) {
      if (!_pinnedIds.contains(c.id)) {
        _pinnedIds = {c.id, ..._pinnedIds};
      }
    }

    final pinnedList = _pinnedIds.toList();
    pinnedInOrder.sort((a, b) {
      final indexA = pinnedList.indexOf(a.id);
      final indexB = pinnedList.indexOf(b.id);
      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(
          indexB,
        ); // Urutan pin pertama / atas tetap di atas
      } else if (indexA != -1) {
        return -1;
      } else if (indexB != -1) {
        return 1;
      } else {
        return 0; // Jangan pernah fallback ke _chats.indexWhere atau waktu pesan!
      }
    });

    final unpinned = filtered.where((c) => !c.isPinned).toList()
      ..sort((a, b) {
        final timeA = _parseTimeForSort(a.time);
        final timeB = _parseTimeForSort(b.time);
        return timeB.compareTo(timeA);
      });

    filtered = [...pinnedInOrder, ...unpinned];

    return filtered;
  }

  List<ChatModel> get archivedChats {
    return _chats
        .where((chat) => chat.isArchived || isRoomArchived(chat.id))
        .toList();
  }

  void markAsRead(String chatId) {
    _localUnreadOverrides.remove(chatId);
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index != -1 && _chats[index].unreadCount > 0) {
      _readIds.add(_chats[index].id);
      _chats[index] = _chats[index].copyWith(unreadCount: 0);
      _saveReadState();
      notifyListeners();

      // Sinkronisasikan secara diam-diam ke server agar server tidak
      // terus-menerus membalas dengan UnreadCount > 0 saat hot restart!
      _chatService.markRoomAsRead(chatId);
    }
  }

  Future<void> togglePin(String chatId) async {
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index != -1) {
      final newPinned = !_chats[index].isPinned;

      // Optimistic visual update
      _chats[index] = _chats[index].copyWith(isPinned: newPinned);
      if (newPinned) {
        // Ketika user menyematkan chat baru, letakkan di urutan teratas pinned list
        _pinnedIds.remove(chatId);
        _pinnedIds = {chatId, ..._pinnedIds};
      } else {
        _pinnedIds.remove(chatId);
      }
      _savePinnedState();
      notifyListeners();

      // Send to server
      final response = await _chatService.togglePinRoom(chatId, newPinned);

      if (response.isError) {
        // Revert on error
        _chats[index] = _chats[index].copyWith(isPinned: !newPinned);
        if (!newPinned) {
          _pinnedIds.remove(chatId);
          _pinnedIds = {chatId, ..._pinnedIds};
        } else {
          _pinnedIds.remove(chatId);
        }
        _savePinnedState();
        notifyListeners();
      }
    }
  }

  Future<bool> toggleBlockContact(
    String roomId,
    String contactId,
    bool isBlocked,
  ) async {
    // Simpan status baru secara persisten agar selalu akurat saat refresh/restart
    _savedBlockStates[roomId] = isBlocked;
    _saveSavedBlockStates();

    final index = _chats.indexWhere((chat) => chat.id == roomId);
    if (index != -1) {
      final chat = _chats[index];
      // Optimistic update
      _chats[index] = chat.copyWith(isBlocked: isBlocked);
      notifyListeners();

      // Get chat status for SignalR (1=Unassigned, 2=Assigned, 3=Resolved)
      // Status can be in Indonesian or English
      int statusCode = 1; // default Unassigned
      final statusLower = chat.status.toLowerCase();
      if (statusLower.contains('assign') || statusLower.contains('tugas')) {
        statusCode = 2; // Assigned / Ditugaskan
      } else if (statusLower.contains('resolv') ||
          statusLower.contains('selesai')) {
        statusCode = 3; // Resolved / Selesai
      }

      // Use SignalR for fast block/unblock (real-time), fallback to REST API if fails
      bool success = false;
      try {
        debugPrint(
          'ChatProvider: 🚫 Block/Unblock via SignalR: room=$roomId, contact=$contactId, isBlocked=$isBlocked',
        );
        final signalR = SignalRService();
        success = await signalR.invokeBlockUnblock(
          roomId: roomId,
          status: statusCode,
          contactId: contactId,
          shouldBlock: isBlocked,
        );
      } catch (e) {
        debugPrint(
          'ChatProvider: ❌ SignalR block/unblock failed, falling back to REST API: $e',
        );
        success = false;
      }

      // Fallback to REST API if SignalR failed
      if (!success) {
        debugPrint(
          'ChatProvider: 🚫 Falling back to REST API for block/unblock',
        );
        final updateResponse = await _chatService.updateContactInfo(roomId, {
          'CtIsBlock': isBlocked ? 1 : 0,
          'IsBlock': isBlocked ? 1 : 0,
        });
        success = !updateResponse.isError;
      }

      if (!success) {
        // Revert on error
        _chats[index] = _chats[index].copyWith(isBlocked: !isBlocked);
        notifyListeners();
        return false;
      }
      return true;
    }
    return false;
  }

  /// Sends a message via SignalR 'KirimPesan' instead of the REST API.
  /// Used specifically for real-time channels like Telegram.
  Future<String?> sendMessageViaSignalR({
    required ChatModel chat,
    required String type, // "1" for text, "3" for media
    String? msg,
    String? fileJson,
    String? replyId,
    String? replyMsg,
    String? replyFrom,
    String? replyType,
    String? replyFiles,
  }) async {
    String resolvedAccountId = chat.accountId;

    // --- SMART TELEGRAM & FALLBACK ACCOUNT ID ---
    final chIdStr = chat.chId.toString().trim();
    final chTypeStr = chat.channelType.toLowerCase();
    final chNameStr = chat.channelName.toLowerCase();
    final isTelegram =
        chIdStr == '2' ||
        chTypeStr.contains('telegram') ||
        chTypeStr.contains('tg') ||
        chNameStr.contains('telegram') ||
        chNameStr.contains('tg');
    final isWa =
        chIdStr == '1' ||
        chIdStr == '1557' ||
        chIdStr == '1561' ||
        chTypeStr.contains('whatsapp') ||
        chTypeStr.contains('wa') ||
        chNameStr.contains('whatsapp') ||
        chNameStr.contains('wa');

    bool isAccConnected(Map<String, dynamic> acc) {
      final status = acc['Status']?.toString();
      final condition = acc['Condition']?.toString();
      final note = (acc['NoteCondition']?.toString() ?? '').toLowerCase();
      return (status == '1' || status == 'true') &&
          (condition == '1' || condition == 'true' || note.contains('connect'));
    }

    bool isCurrentAccActive = true;
    if (_cachedAccounts != null &&
        _cachedAccounts!.isNotEmpty &&
        resolvedAccountId.isNotEmpty) {
      final existing = _cachedAccounts!
          .where((a) => a['Id']?.toString() == resolvedAccountId)
          .firstOrNull;
      if (existing != null) {
        isCurrentAccActive = isAccConnected(existing);
      }
    }

    if (resolvedAccountId.isEmpty ||
        resolvedAccountId == '0' ||
        resolvedAccountId == 'null' ||
        !isCurrentAccActive) {
      if (_cachedAccounts == null || _cachedAccounts!.isEmpty) {
        try {
          await getAccountsResponse();
        } catch (_) {}
      }
      if (_cachedAccounts != null && _cachedAccounts!.isNotEmpty) {
        try {
          final activeAcc = _cachedAccounts!.where((acc) {
            final ch = acc['Channel']?.toString() ?? '';
            final code = (acc['Code']?.toString() ?? '').toLowerCase();
            final accName = (acc['Name']?.toString() ?? '').toLowerCase();
            final connected = isAccConnected(acc);
            if (!connected) return false;

            if (isTelegram) {
              return ch == '2' ||
                  ch == chIdStr ||
                  code.contains('telegram') ||
                  code.contains('tg') ||
                  accName.contains('telegram');
            }
            if (isWa) {
              return ch == '1' ||
                  ch == '1557' ||
                  ch == '1561' ||
                  ch == chIdStr ||
                  code.contains('whatsapp') ||
                  code.contains('wa') ||
                  accName.contains('wa') ||
                  accName.contains('whatsapp');
            }
            return false;
          }).firstOrNull;

          if (activeAcc != null && activeAcc['Id'] != null) {
            resolvedAccountId = activeAcc['Id'].toString();
            debugPrint(
              'Smart Fallback: Resolved AccId from active cached accounts -> $resolvedAccountId (${activeAcc['Name']})',
            );
          } else {
            final anyConnected = _cachedAccounts!
                .where(isAccConnected)
                .firstOrNull;
            if (anyConnected != null && anyConnected['Id'] != null) {
              resolvedAccountId = anyConnected['Id'].toString();
            }
          }
        } catch (e) {
          debugPrint('Smart Fallback Failed: $e');
        }
      }
    }
    // --------------------------------

    final bool isGroupChat =
        chat.isGroup ||
        (chat.groupId.isNotEmpty &&
            chat.groupId != '0' &&
            chat.groupId != 'null') ||
        (chat.groupName.isNotEmpty &&
            chat.groupName != '0' &&
            chat.groupName != 'null') ||
        (isTelegram &&
            (chat.groupId.startsWith('-') ||
                chat.ctRealId.startsWith('-') ||
                chat.link.startsWith('-') ||
                chat.id.startsWith('-')));

    String? resolvedGroupId;
    String? idLinkValue;

    if (isGroupChat) {
      // GROUP CHAT: IdGroup harus diisi, dan IdLink harus NULL agar backend NoBox tidak memvalidasi IdLink ke kontak individu
      if (chat.groupId.isNotEmpty &&
          chat.groupId != '0' &&
          chat.groupId != 'null') {
        resolvedGroupId = chat.groupId;
      } else if (isTelegram &&
          chat.ctRealId.isNotEmpty &&
          chat.ctRealId.startsWith('-')) {
        resolvedGroupId = chat.ctRealId;
      } else if (isTelegram &&
          chat.link.isNotEmpty &&
          chat.link.startsWith('-')) {
        resolvedGroupId = chat.link;
      } else if (chat.link.isNotEmpty &&
          chat.link != '0' &&
          chat.link != 'null' &&
          !chat.link.contains('@s.whatsapp.net')) {
        resolvedGroupId = chat.link;
      } else if (chat.contactId.isNotEmpty &&
          chat.contactId != '0' &&
          chat.contactId != 'null' &&
          !chat.contactId.contains('@s.whatsapp.net')) {
        resolvedGroupId = chat.contactId;
      } else {
        resolvedGroupId = chat.id
            .replaceAll(RegExp(r'^[0-9]+_'), '')
            .replaceAll(RegExp(r'[^0-9\-]'), '');
      }
      idLinkValue = null; // IMPORTANT: For group chat, IdLink MUST be null!
    } else {
      // PRIVATE CHAT (1-to-1): IdLink diisi dengan ID kontak (database ID)

      // Helper: validasi bahwa string adalah ID yang valid
      bool isValidDbId(String s) {
        if (s.isEmpty || s == '0' || s == 'null') return false;
        final clean = s.replaceAll(RegExp(r'[^0-9]'), '');
        final num = int.tryParse(clean);
        return num != null && num > 0;
      }

      // Prioritas: link (IdLink) → ctRealId → contactId → strip dari chat.id
      if (isValidDbId(chat.link)) {
        idLinkValue = chat.link;
      } else if (isValidDbId(chat.ctRealId)) {
        idLinkValue = chat.ctRealId;
      } else if (isValidDbId(chat.contactId)) {
        idLinkValue = chat.contactId;
      } else {
        // Fallback terakhir: extract numeric part dari chat.id (format "tenantId_roomId")
        final extracted = chat.id
            .replaceAll(RegExp(r'^[0-9]+_'), '')
            .replaceAll(RegExp(r'[^0-9]'), '');
        if (extracted.isNotEmpty && isValidDbId(extracted)) {
          idLinkValue = extracted;
        } else {
          idLinkValue = chat.link.isNotEmpty ? chat.link : chat.contactId;
        }
      }

      resolvedGroupId = null;
    }

    // DEBUG: Dump semua field yang di-resolve untuk diagnosis pengiriman pesan
    debugPrint('ChatProvider: ┌── sendMessageViaSignalR DEBUG ──');
    debugPrint('ChatProvider: │ chat.id=${chat.id}');
    debugPrint('ChatProvider: │ chat.contactId=${chat.contactId}');
    debugPrint('ChatProvider: │ chat.link=${chat.link}');
    debugPrint('ChatProvider: │ chat.ctRealId=${chat.ctRealId}');
    debugPrint('ChatProvider: │ chat.groupId=${chat.groupId}');
    debugPrint('ChatProvider: │ chat.groupName=${chat.groupName}');
    debugPrint('ChatProvider: │ chat.accountId=${chat.accountId}');
    debugPrint('ChatProvider: │ chat.chId=${chat.chId}');
    debugPrint('ChatProvider: │ chat.channelType=${chat.channelType}');
    debugPrint('ChatProvider: │ chat.channelName=${chat.channelName}');
    debugPrint('ChatProvider: │ chat.sender=${chat.sender}');
    debugPrint('ChatProvider: │ chat.isGroup=${chat.isGroup}');
    debugPrint('ChatProvider: │ ─── Resolved Values ───');
    debugPrint('ChatProvider: │ resolvedAccountId=$resolvedAccountId');
    debugPrint('ChatProvider: │ isGroupChat=$isGroupChat');
    debugPrint('ChatProvider: │ resolvedGroupId=$resolvedGroupId');
    debugPrint('ChatProvider: │ idLinkValue=$idLinkValue');
    debugPrint(
      'ChatProvider: │ type=$type, msg=${(msg ?? "").length > 30 ? msg!.substring(0, 30) + "..." : msg}',
    );
    debugPrint('ChatProvider: └──────────────────────────────');

    final cleanMsg = (msg ?? '').trim();
    if (cleanMsg.isNotEmpty) {
      recordRecentSentMessage(chat.id, cleanMsg);
    }

    // Guard: SignalR membutuhkan IdRoom valid. Jika room id kosong/"0", jangan
    // kirim via SignalR (backend NoBox pasti menolak) — biarkan caller fallback
    // ke REST API Inbox/Send yang bisa resolve room id dari field lain.
    if (chat.id.isEmpty || chat.id == '0' || chat.id == 'null') {
      debugPrint(
        'ChatProvider: ❌ sendMessageViaSignalR DIBATALKAN: chat.id kosong/0 → fallback REST.',
      );
      return 'RoomId is empty or invalid (${chat.id})';
    }

    final error = await SignalRService().invokeKirimPesan(
      idLink: idLinkValue, // Null untuk group, contactId integer untuk private
      idAccount: resolvedAccountId,
      idRoom: chat.id,
      idGroup:
          resolvedGroupId, // Null untuk private, groupId integer untuk group
      type: type,
      msg: msg,
      fileJson: fileJson,
      replyId: replyId,
      replyMsg: replyMsg,
      replyFrom: replyFrom,
      replyType: replyType,
      replyFiles: replyFiles,
    );

    if (error != null) {
      debugPrint('ChatProvider: ❌ sendMessageViaSignalR FAILED: $error');
    } else {
      debugPrint('ChatProvider: ✅ sendMessageViaSignalR SUCCESS');
      updateLocalLastMessage(
        chat.id,
        cleanMsg.isNotEmpty
            ? cleanMsg
            : (type == '3' ? '📷 Photo' : 'Pesan terkirim'),
        isFromMe: true,
      );
    }

    return error;
  }

  /// Update block status from incoming SignalR TerimaBlockUnblock event.
  /// Called from main.dart when server broadcasts a block/unblock change
  /// (e.g. from web nobox.ai).
  void updateBlockStatusFromSignalR(String roomId, bool isBlocked) {
    final index = _chats.indexWhere((c) => c.id == roomId);
    if (index >= 0) {
      _chats[index] = _chats[index].copyWith(isBlocked: isBlocked);
      debugPrint(
        'ChatProvider: 🚫 Updated block status for room $roomId → isBlocked=$isBlocked',
      );
      notifyListeners();
    } else {
      debugPrint(
        'ChatProvider: 🚫 Room $roomId not found for block update, triggering refresh',
      );
      refreshFirstPage();
    }
  }

  // FITUR 11: Menyembunyikan chat aktif ke ruang arsip dan mengembalikannya.
  // [ACTION: ARCHIVE_TOGGLE] - Otak pemrosesan saat arsip diubah dari UI
  Future<void> toggleArchive(String chatId) async {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    final targetChat = index != -1 ? _chats[index] : null;
    final currentlyArchived =
        isRoomArchived(chatId) || (targetChat?.isArchived ?? false);
    final newArchived = !currentlyArchived;

    // Simpan HANYA varian RoomId (bukan contactId/ctRealId) agar arsip TIDAK
    // "menular" ke room baru milik kontak yang sama.
    final idsToUpdate = <String>{chatId};
    final numChatId = chatId.replaceAll(RegExp(r'[^0-9]'), '');
    if (numChatId.isNotEmpty) idsToUpdate.add(numChatId);

    if (targetChat != null) {
      if (targetChat.id.isNotEmpty) idsToUpdate.add(targetChat.id);
      final numId = targetChat.id.replaceAll(RegExp(r'[^0-9]'), '');
      if (numId.isNotEmpty) idsToUpdate.add(numId);
    }

    if (newArchived) {
      _archivedIds.addAll(idsToUpdate);
      _pinnedIds.remove(chatId);
      _savePinnedState();
    } else {
      _archivedIds.removeAll(idsToUpdate);
    }
    _saveArchivedState(immediate: true);

    if (index != -1) {
      _chats[index] = _chats[index].copyWith(
        isArchived: newArchived,
        isPinned: false,
      );
    }
    notifyListeners();

    // Kirim sinkronisasi ke backend NoBox di latar belakang
    // PENTING: JANGAN PERNAH ROLLBACK status arsip lokal jika server gagal/error!
    // Ini mengunci fitur "Tetap Arsipkan Chat" ala WhatsApp sehingga chat TIDAK
    // keluar ke daftar obrolan utama meskipun ada interaksi di WhatsApp atau server me-reset status.
    try {
      if (newArchived) {
        await _chatService.moveToArchive(chatId);
      } else {
        await _chatService.restoreArchived(chatId);
      }
    } catch (e) {
      debugPrint(
        'ChatProvider: Server archive/restore background sync error: $e',
      );
    }
  }

  /// Sinkronisasi percakapan yang diarsipkan dari server dan gabungkan ke memori
  Future<void> syncArchivedConversations() async {
    try {
      final archivedResponse = await _chatService.getArchivedConversations();
      if (!archivedResponse.isError && archivedResponse.data != null) {
        bool hasChanges = false;
        for (final archivedConv in archivedResponse.data!) {
          final archivedChat = archivedConv.toChatModel();
          final numId = archivedChat.id.replaceAll(RegExp(r'[^0-9]'), '');

          if (!_archivedIds.contains(archivedChat.id)) {
            _archivedIds.add(archivedChat.id);
            if (numId.isNotEmpty) _archivedIds.add(numId);
            hasChanges = true;
          }

          final idx = _chats.indexWhere(
            (c) =>
                c.id == archivedChat.id ||
                (numId.isNotEmpty &&
                    c.id.replaceAll(RegExp(r'[^0-9]'), '') == numId),
          );
          if (idx != -1) {
            if (!_chats[idx].isArchived) {
              _chats[idx] = _chats[idx].copyWith(isArchived: true);
              hasChanges = true;
            }
          } else {
            _chats.add(archivedChat.copyWith(isArchived: true));
            hasChanges = true;
          }
        }
        if (hasChanges) {
          _saveArchivedState(immediate: true);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('ChatProvider: Failed to sync archived conversations: $e');
    }
  }

  // ===========================================================================
  // CONTACT INFO UPDATES (Proxy to Service)
  // ===========================================================================

  Future<bool> updateContactTags(
    String contactId,
    List<String> tagIds, {
    List<String>? tagNames,
  }) async {
    _detailRoomCache.remove(contactId);
    final response = await _chatService.updateContactTags(contactId, tagIds);
    if (!response.isError) {
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(tags: tagNames ?? tagIds);
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  void updateLocalContactTags(
    String contactId,
    List<String> tagIds,
    List<String> tagNames,
  ) {
    _detailRoomCache.remove(contactId);
    final index = _chats.indexWhere((c) => c.id == contactId);
    if (index != -1) {
      _chats[index] = _chats[index].copyWith(tags: tagNames);
      notifyListeners();
    }
  }

  Future<bool> updateContactFunnel(
    String contactId,
    String funnelId, {
    String? funnelName,
  }) async {
    _detailRoomCache.remove(contactId);
    final response = await _chatService.updateContactFunnel(
      contactId,
      funnelId,
    );
    if (!response.isError) {
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        // Use the display name if provided, otherwise fallback to the ID string
        _chats[index] = _chats[index].copyWith(funnel: funnelName ?? funnelId);
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<bool> updateContactNotes(String contactId, String notes) async {
    _detailRoomCache.remove(contactId);
    final response = await _chatService.updateContactNotes(contactId, notes);
    if (!response.isError) {
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(notes: notes);
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<bool> updateContactDeal(
    String contactId,
    String pipeline,
    String stage,
    String deal,
  ) async {
    _detailRoomCache.remove(contactId);
    final response = await _chatService.updateContactDeal(
      contactId,
      pipeline,
      stage,
      deal,
    );
    if (!response.isError) {
      // Just returning true. For a full implementation, you'd add pipeline/stage/deal to ChatModel
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<String?> uploadImage(File file) async {
    final response = await _chatService.uploadImage(file);
    if (!response.isError && response.data != null) {
      return response.data;
    }
    _error = response.error;
    notifyListeners();
    return null;
  }

  Future<bool> updateContactInfo(
    String contactId,
    Map<String, dynamic> contactData,
  ) async {
    debugPrint(
      'ChatProvider: updateContactInfo called | roomId=$contactId | data=$contactData',
    );

    // Hapus cache DetailRoom agar ContactInfoPage memuat data terbaru (nama kontak)
    // setelah proses edit selesai, sehingga UI bersifat realtime/reaktif.
    _detailRoomCache.remove(contactId);

    // FIX: Saat mengedit nama atau info kontak, jika kontak tersebut tidak diblokir secara nyata,
    // kirimkan IsBlock/CtIsBlock=0 agar database server NoBox tidak mengunci nilai default CtIsBlock=1
    if (!contactData.containsKey('CtIsBlock') &&
        !contactData.containsKey('IsBlock')) {
      if (!resolveIsBlocked(contactId, false)) {
        contactData['CtIsBlock'] = 0;
        contactData['IsBlock'] = 0;
      }
    }

    // OPTIMISTIC SAVE: simpan nama ke memori dan disk SEBELUM memanggil API,
    // agar nama tetap tersimpan meski response API ambigu atau IsError=true.
    if (contactData['CtRealNm'] != null) {
      final newName = contactData['CtRealNm'].toString().trim();
      if (newName.isNotEmpty) {
        // 1. Update in-memory list
        final index = _chats.indexWhere((c) => c.id == contactId);
        if (index != -1) {
          _chats[index] = _chats[index].copyWith(sender: newName);
          notifyListeners();
        }
        // 2. Simpan ke persistent map
        _savedContactNames[contactId] = newName;
        // 3. Tulis ke disk segera (await agar pasti tersimpan sebelum hot restart)
        await _saveSavedContactNames();
        debugPrint(
          'ChatProvider: 💾 Optimistically saved contact name "$newName" for room $contactId',
        );
      }
    }

    // OPTIMISTIC SAVE: simpan data lokasi ke disk SEBELUM memanggil API,
    // agar lokasi tetap tersimpan meski API Contact/Update gagal.
    final locationFields = <String, String>{};
    for (final key in ['Country', 'State', 'City', 'Address', 'Postal']) {
      if (contactData.containsKey(key)) {
        locationFields[key] = contactData[key]?.toString() ?? '';
      }
    }
    if (locationFields.isNotEmpty) {
      _savedContactLocations[contactId] = {
        ...(_savedContactLocations[contactId] ?? {}),
        ...locationFields,
      };
      await _saveSavedContactLocations();
      debugPrint(
        'ChatProvider: 💾 Optimistically saved location for room $contactId: $locationFields',
      );
    }

    final response = await _chatService.updateContactInfo(
      contactId,
      contactData,
    );
    if (!response.isError) {
      return true;
    }
    // Meskipun API gagal, kita tetap return true jika data sudah di-persist lokal
    debugPrint(
      'ChatProvider: ⚠️ updateContactInfo API returned error: ${response.error} — but local data is persisted',
    );
    return true;
  }

  Future<bool> toggleAiAgent(String contactId, bool isMuted) async {
    final response = await _chatService.toggleAiAgent(contactId, isMuted);
    if (!response.isError) {
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(muteAiAgent: isMuted);
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<bool> toggleNeedReply(String contactId, bool needReply) async {
    final response = await _chatService.toggleNeedReply(contactId, needReply);
    if (!response.isError) {
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(needReply: needReply);
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  // ===========================================================================
  // INBOX ACTIONS (Proxy to Service)
  // ===========================================================================

  Future<bool> assignChat(String contactId) async {
    final response = await _chatService.assignChat(contactId);
    if (!response.isError) {
      // Immediately update local UI for snappy feel
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(status: 'Assigned');
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  /// Update status obrolan secara instan di memori lokal (optimistic update).
  ///
  /// Pencarian dilakukan secara fleksibel terhadap berbagai variasi ID yang
  /// dikirim oleh pemanggil (id room, contactId/ctId, ctRealId, link, maupun
  /// ID angka bersih). Hal ini mengatasi kasus pencarian index yang terlalu
  /// kaku sehingga status tidak ter-update di UI secara real-time.
  void updateChatStatus(
    String targetId,
    String newStatus, {
    String? agentName,
  }) {
    if (targetId.isEmpty) return;
    final cleanNumeric = targetId.replaceAll(RegExp(r'[^0-9]'), '');

    final index = _chats.indexWhere((c) {
      if (c.id == targetId) return true;
      if (c.contactId == targetId) return true;
      if (c.ctRealId == targetId) return true;
      if (c.link == targetId) return true;
      if (cleanNumeric.isNotEmpty &&
          c.id.replaceAll(RegExp(r'[^0-9]'), '') == cleanNumeric) {
        return true;
      }
      return false;
    });

    if (index != -1) {
      _chats[index] = _chats[index].copyWith(
        status: newStatus,
        agentName: agentName ?? _chats[index].agentName,
      );
      notifyListeners();
    }
  }

  Future<bool> resolveChat(
    String contactId, {
    String? accountId,
    String? agentName,
  }) async {
    // 1. Optimistic update langsung agar UI seketika berubah
    updateChatStatus(contactId, 'Resolved', agentName: agentName);

    // 2. Kirim ke API backend
    final response = await _chatService.resolveChat(
      contactId,
      accountId: accountId,
    );

    if (response.isError) {
      _error = response.error;
      notifyListeners();
      return false;
    }

    // 3. Sinkronisasi latar belakang secara silent
    refreshFirstPage(showLoading: false);
    return true;
  }

  // ===========================================================================
  // CONTACT INFO: CAMPAIGN, FORM TEMPLATE, DETAIL ROOM
  // ===========================================================================

  Future<bool> updateCampaign(String contactId, int? campaignId) async {
    final response = await _chatService.updateCampaign(contactId, campaignId);
    if (!response.isError) {
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<bool> updateFormTemplate(
    String contactId,
    int? formTemplateId, {
    int? formResultId,
  }) async {
    final response = await _chatService.updateFormTemplate(
      contactId,
      formTemplateId,
      formResultId: formResultId,
    );
    if (!response.isError) {
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  List<Map<String, dynamic>>? _formTemplatesCache;

  Future<List<Map<String, dynamic>>?> getFormTemplates({
    bool forceRefresh = false,
  }) async {
    if (_formTemplatesCache != null && !forceRefresh)
      return _formTemplatesCache;
    final response = await _chatService.getFormTemplates();
    if (!response.isError && response.data != null) {
      _formTemplatesCache = response.data;
      return response.data;
    }
    _error = response.error;
    return null;
  }

  List<Map<String, dynamic>>? _formResultsCache;

  Future<List<Map<String, dynamic>>?> getFormResults({
    bool forceRefresh = false,
  }) async {
    if (_formResultsCache != null && !forceRefresh) return _formResultsCache;
    final response = await _chatService.getFormResults();
    if (!response.isError && response.data != null) {
      _formResultsCache = response.data;
      return response.data;
    }
    _error = response.error;
    return null;
  }

  final Map<String, Map<String, dynamic>> _detailRoomCache = {};

  Future<Map<String, dynamic>?> getDetailRoom(
    String roomId, {
    bool forceRefresh = true,
  }) async {
    // 1. Cek cache memori (jika forceRefresh false)
    if (!forceRefresh && _detailRoomCache.containsKey(roomId)) {
      // Tarik diam-diam di background agar data selalu up-to-date
      _chatService.getDetailRoom(roomId).then((response) {
        if (!response.isError && response.data != null) {
          _detailRoomCache[roomId] = response.data!;
        }
      });
      return _detailRoomCache[roomId];
    }

    // 2. Selalu utamakan dari server agar sinkron dengan perubahan terbaru
    final response = await _chatService.getDetailRoom(roomId);
    if (!response.isError && response.data != null) {
      _detailRoomCache[roomId] = response.data!;
      return response.data;
    }
    _error = response.error;
    // Fallback ke cache jika koneksi bermasalah
    if (_detailRoomCache.containsKey(roomId)) {
      return _detailRoomCache[roomId];
    }
    return null;
  }

  // ===========================================================================
  // HUMAN AGENT METHODS
  // ===========================================================================

  Future<List<Map<String, dynamic>>?> getAgents() async {
    final response = await _chatService.getAgents();
    if (!response.isError && response.data != null) {
      return response.data;
    }
    _error = response.error;
    return null;
  }

  Future<bool> assignAgent(
    String contactId,
    String agentId,
    String agentName, {
    String chId = '',
    String ctId = '',
  }) async {
    _detailRoomCache.remove(contactId);
    _savedAgentNames[contactId] = agentName;
    _saveSavedAgentNames();

    final response = await _chatService.addAgentToConversation(
      contactId,
      agentId,
      agentName,
      chId: chId,
      ctId: ctId,
    );
    if (!response.isError) {
      // Update local state immediately
      final index = _chats.indexWhere((c) => c.id == contactId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(
          agentName: agentName,
          status: 'Assigned',
        );
        notifyListeners();
      }
      return true;
    }
    _error = response.error;
    notifyListeners();
    return false;
  }

  Future<bool> removeAgent(String contactId) async {
    // Optimistic update lokal: langsung hapus cache agent dan kosongkan nama
    // agent di memori/disk, lalu update state chat menjadi Unassigned seketika.
    _detailRoomCache.remove(contactId);
    _savedAgentNames[contactId] = "";
    _saveSavedAgentNames();

    final index = _chats.indexWhere((c) => c.id == contactId);
    if (index != -1) {
      _chats[index] = _chats[index].copyWith(
        agentName: "",
        status: 'Unassigned',
      );
      notifyListeners();
    }

    // Panggil API untuk menghapus agent di server (berjalan async, hasilnya
    // tidak memblokir UI karena perubahan lokal sudah diterapkan di atas).
    await _chatService.addAgentToConversation(contactId, "", "");
    return true;
  }

  // ===========================================================================
  // FUNNELS & TAGS LIST
  // ===========================================================================

  List<Map<String, dynamic>>? _cachedFunnels;
  List<Map<String, dynamic>>? _cachedTags;
  List<Map<String, dynamic>>?
  _cachedAgents; // untuk client-side HumanAgent filter
  List<Map<String, dynamic>>? _cachedLinks; // untuk client-side Link filter
  List<Map<String, dynamic>>?
  _cachedAccounts; // untuk channel type resolution (ChId → Code)

  // Map dari ChId (string) ke Channel Code (misal: '1' → 'WhatsApp')
  // Dibangun dari _cachedAccounts saat accounts di-fetch
  Map<String, String> _chIdToChannelCode = {};

  // Cache untuk dialog filter agar tidak load berulang kali
  ApiResponse<List<Map<String, dynamic>>>? _cachedChannelsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedContactsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedGroupsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedCampaignsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedPipelinesResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedStagesResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedDealsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedAccountsResponse;
  ApiResponse<List<Map<String, dynamic>>>? _cachedLinksResponse;

  Future<ApiResponse<List<Map<String, dynamic>>>> getChannelsResponse() async {
    if (_cachedChannelsResponse != null) return _cachedChannelsResponse!;
    _cachedChannelsResponse = await _chatService.getChannels();
    return _cachedChannelsResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getContactsResponse() async {
    if (_cachedContactsResponse != null) return _cachedContactsResponse!;
    _cachedContactsResponse = await _chatService.getContacts();
    return _cachedContactsResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getGroupsResponse() async {
    if (_cachedGroupsResponse != null) return _cachedGroupsResponse!;
    _cachedGroupsResponse = await _chatService.getGroups();
    return _cachedGroupsResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getCampaignsResponse({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCampaignsResponse != null)
      return _cachedCampaignsResponse!;
    _cachedCampaignsResponse = await _chatService.getCampaigns();
    return _cachedCampaignsResponse!;
  }

  Future<ApiResponse<Map<String, dynamic>>> getKanbanData(
    String pipelineId,
    String contactId,
  ) async {
    return await _chatService.getKanbanData(pipelineId, contactId);
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getPipelinesResponse({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedPipelinesResponse != null)
      return _cachedPipelinesResponse!;
    _cachedPipelinesResponse = await _chatService.getPipelines();
    return _cachedPipelinesResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getStagesResponse({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedStagesResponse != null)
      return _cachedStagesResponse!;
    _cachedStagesResponse = await _chatService.getStages();
    return _cachedStagesResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getDealsResponse({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedDealsResponse != null)
      return _cachedDealsResponse!;
    _cachedDealsResponse = await _chatService.getDeals();
    return _cachedDealsResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getAccountsResponse() async {
    if (_cachedAccountsResponse != null) return _cachedAccountsResponse!;
    _cachedAccountsResponse = await _chatService.getAccounts();

    // Build _chIdToChannelCode sekalian
    if (!_cachedAccountsResponse!.isError &&
        _cachedAccountsResponse!.data != null) {
      _cachedAccounts = _cachedAccountsResponse!.data;
      _chIdToChannelCode = {};
      for (final account in _cachedAccounts!) {
        final channelNum = account['Channel']?.toString();
        final code = account['Code']?.toString();
        final accId = account['Id']?.toString();
        if (code != null && code.isNotEmpty) {
          if (channelNum != null && channelNum.isNotEmpty)
            _chIdToChannelCode[channelNum] = code;
          if (accId != null && accId.isNotEmpty)
            _chIdToChannelCode.putIfAbsent(accId, () => code);
        }
      }
    }

    return _cachedAccountsResponse!;
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> getLinksResponse() async {
    if (_cachedLinksResponse != null) return _cachedLinksResponse!;
    _cachedLinksResponse = await _chatService.getLinks();

    // Build cache biasa juga
    if (!_cachedLinksResponse!.isError && _cachedLinksResponse!.data != null) {
      _cachedLinks = _cachedLinksResponse!.data;
    }

    return _cachedLinksResponse!;
  }

  Future<List<Map<String, dynamic>>?> getFunnels({
    bool forceRefresh = false,
  }) async {
    if (_cachedFunnels != null && !forceRefresh) return _cachedFunnels;
    final response = await _chatService.getFunnels();
    if (!response.isError && response.data != null) {
      _cachedFunnels = response.data;
      return _cachedFunnels;
    }
    _error = response.error;
    return null;
  }

  Future<List<Map<String, dynamic>>?> getTags({
    bool forceRefresh = false,
  }) async {
    if (_cachedTags != null && !forceRefresh) return _cachedTags;
    final response = await _chatService.getTags();
    if (!response.isError && response.data != null) {
      _cachedTags = response.data;
      return _cachedTags;
    }
    _error = response.error;
    return null;
  }

  /// Fetch dan cache list of Accounts.
  /// Membangun _chIdToChannelCode map untuk resolusi channel type.
  Future<List<Map<String, dynamic>>?> getCachedAccounts({
    bool forceRefresh = false,
  }) async {
    if (_cachedAccounts != null && !forceRefresh) return _cachedAccounts;
    final response = await _chatService.getAccounts();
    if (!response.isError && response.data != null) {
      _cachedAccounts = response.data;
      // Build map: Channel (angka) → Code (nama platform)
      // Contoh: {"1": "WhatsApp", "2": "Telegram", "1505": "TokopediaCom"}
      _chIdToChannelCode = {};
      for (final account in _cachedAccounts!) {
        final channelNum = account['Channel']?.toString();
        final code = account['Code']?.toString();
        if (channelNum != null &&
            channelNum.isNotEmpty &&
            code != null &&
            code.isNotEmpty) {
          _chIdToChannelCode[channelNum] = code;
        }
        // Juga map dari account Id ke code (untuk jaga-jaga jika ChId = AccId)
        final accId = account['Id']?.toString();
        if (accId != null &&
            accId.isNotEmpty &&
            code != null &&
            code.isNotEmpty) {
          _chIdToChannelCode.putIfAbsent(accId, () => code);
        }
      }
      debugPrint('ChatProvider: _chIdToChannelCode = $_chIdToChannelCode');
      return _cachedAccounts;
    }
    debugPrint('ChatProvider: getCachedAccounts soft-fail: ${response.error}');
    return null;
  }

  /// Resolves ChId → Channel Code menggunakan [_chIdToChannelCode].
  /// Misal: '1' → 'WhatsApp', '2' → 'Telegram'
  String _resolveChannelCode(String chId) {
    return _chIdToChannelCode[chId] ?? '';
  }

  /// Fetch dan cache list of Agents.
  /// Digunakan untuk client-side HumanAgent filter (Jalur 2) — ID-to-name resolution.
  Future<List<Map<String, dynamic>>?> getCachedAgents({
    bool forceRefresh = false,
  }) async {
    if (_cachedAgents != null && !forceRefresh) return _cachedAgents;
    final response = await _chatService.getAgents();
    if (!response.isError && response.data != null) {
      _cachedAgents = response.data;
      return _cachedAgents;
    }
    // Soft-fail: agents bersifat opsional untuk filtering, jangan propagate error
    debugPrint('ChatProvider: getCachedAgents soft-fail: ${response.error}');
    return null;
  }

  /// Fetch dan cache list of Links.
  /// Digunakan untuk client-side Link filter (Jalur 2) — ID-to-name resolution.
  Future<List<Map<String, dynamic>>?> getCachedLinks({
    bool forceRefresh = false,
  }) async {
    if (_cachedLinks != null && !forceRefresh) return _cachedLinks;
    final response = await _chatService.getLinks();
    if (!response.isError && response.data != null) {
      _cachedLinks = response.data;
      return _cachedLinks;
    }
    // Soft-fail: links bersifat opsional untuk filtering, jangan propagate error
    debugPrint('ChatProvider: getCachedLinks soft-fail: ${response.error}');
    return null;
  }

  // ── ID-to-Name Resolvers (untuk Jalur 2 client-side filtering) ─────────────

  /// Memperbaiki ID dan status chat dummy dengan ID asli dari server
  void repairChatState(String oldId, String newRoomId, {String? newStatus}) {
    final index = _chats.indexWhere((c) => c.id == oldId);
    if (index != -1) {
      if (newStatus != null) {
        _chats[index] = _chats[index].copyWith(
          id: newRoomId,
          status: newStatus,
        );
      } else {
        _chats[index] = _chats[index].copyWith(id: newRoomId);
      }
      notifyListeners();
      debugPrint(
        'ChatProvider: 🛠️ Repaired dummy chat state (ID: $oldId -> $newRoomId, Status: $newStatus)',
      );
    }
  }

  /// Memperbarui State Chat di memori agar sinkron dengan yang ada di DetailPage
  void updateLocalChat(ChatModel updatedChat) {
    final index = _chats.indexWhere(
      (c) =>
          c.id == updatedChat.id ||
          (c.id.isEmpty && c.contactId == updatedChat.contactId),
    );
    if (index != -1) {
      _chats[index] = updatedChat;
      notifyListeners();
    }
  }

  /// Resolves Funnel ID → display name menggunakan [_cachedFunnels].
  /// Returns null jika tidak ditemukan (caller harus fallback ke raw value).
  String? _resolveFunnelName(String id) {
    if (_cachedFunnels == null) return null;
    final matched = _cachedFunnels!.firstWhere(
      (f) => f['Id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return matched['Name']?.toString() ?? matched['Nm']?.toString();
  }

  /// Resolves Tag ID → display name menggunakan [_cachedTags].
  String? _resolveTagName(String id) {
    if (_cachedTags == null) return null;
    final matched = _cachedTags!.firstWhere(
      (t) => t['Id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return matched['Name']?.toString() ?? matched['Nm']?.toString();
  }

  @override
  void dispose() {
    _notifyDebounce?.cancel();
    _saveReadDebounce?.cancel();
    _savePinnedDebounce?.cancel();
    _saveArchivedDebounce?.cancel();
    _tabFetchDebounce?.cancel();
    _signalRRefreshTimer?.cancel();
    _isDisposed = true;
    super.dispose();
  }
}
