import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../../../core/services/api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import '../../../core/model/message.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/signalr_service.dart';
import '../../../core/model/message_request.dart';
import '../../../core/providers/chat_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../core/model/quick_reply_model.dart';

import '../../../core/providers/chat_settings_provider.dart';
import '../../../core/utils/date_time_helper.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../widgets/authenticated_avatar.dart';
import 'contact_info_page.dart';
import 'starred_messages_page.dart';
import 'location_picker_page.dart';
import '../../widgets/add_agent_dialog.dart';
import '../../widgets/channel_icon.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../core/services/push_notification_service.dart';
import '../../widgets/message_bubble_widget.dart';
import '../../widgets/voice_recording_bottom_sheet.dart';
import '../../widgets/message_shimmer_widget.dart';
import 'file_preview_screen.dart';

// =====================================================================
// FITUR: Halaman Detail Chat (Room)
// FILE: lib/presentation/screens/chat/chat_detail_page.dart
// FUNGSI: Halaman utama ruang obrolan dengan seseorang. Menangani pesan real-time
//         via SignalR, REST API, attachment media, input bar, dan daftar pesan.
//
// ── DIREKTORI KATA KUNCI & RENTANG BARIS FITUR ────────────────────────
// 1. [HEADER (APPBAR)]
//    - Baris ~4410 - 4550 : [KATA KUNCI: Status AppBar | Blocked | Resolved]
//    - Baris ~4465 - 4550 : [KATA KUNCI: Menu Titik Tiga | Add Agent | Mark Resolved]
//    - Baris ~4560 - 4610 : [KATA KUNCI: Archived AppBar | Chat Arsip | Restore Chat]
//    - Baris ~4610 - 4750 : [KATA KUNCI: Normal AppBar | Header Chat Utama | Avatar]
//    - Baris ~4800 - 4950 : [KATA KUNCI: Selection AppBar | Mode Seleksi Pesan | Multi Select]
//
// 2. [DAFTAR PESAN (MESSAGE LIST)]
//    - Baris ~4040 - 4110 : [KATA KUNCI: Scroll Ke Bawah | Scroll To Bottom | Unread Badge]
//    - Baris ~5170 - 5330 : [KATA KUNCI: Message List | Daftar Pesan | ListView Pesan | Bubble]
//    - Baris ~5340 - 5390 : [KATA KUNCI: Status Divider | Pembatas Status Chat | Resolved Divider]
//    - Baris ~5395 - 5450 : [KATA KUNCI: Date Separator | Pembatas Tanggal | Hari Ini]
//
// 3. [INPUT BAR DI BAWAH]
//    - Baris ~610  - 750  : [KATA KUNCI: Quick Reply List | Template Balasan Cepat]
//    - Baris ~6485 - 6595 : [KATA KUNCI: Input Bar | Kolom Chat | TextField Pesan | Send Button]
//    - Baris ~6600 - 6695 : [KATA KUNCI: Attachment Panel | Panel Lampiran | Menu Media]
//    - Baris ~6700 - 6780 : [KATA KUNCI: Emoji Picker | Keyboard Emoji | Emoticon]
//    - Baris ~6795 - 6850 : [KATA KUNCI: Reply Preview | Balas Pesan | Pratinjau Balasan]
//
// 4. [FITUR INTERAKSI PESAN]
//    - Baris ~2665 - 2755 : [KATA KUNCI: Kirim Pesan Teks | Send Message]
//    - Baris ~2880 - 2975 : [KATA KUNCI: Kamera | Camera Picker | Ambil Foto]
//    - Baris ~2980 - 3220 : [KATA KUNCI: Video | Video Picker | Kirim Video]
//    - Baris ~3225 - 3350 : [KATA KUNCI: Dokumen | File Picker | Kirim Dokumen | PDF]
//    - Baris ~3360 - 3450 : [KATA KUNCI: Lokasi | Share Location | Google Maps]
//    - Baris ~3460 - 3550 : [KATA KUNCI: Foto | Galeri | Kirim Gambar | Image Picker]
//    - Baris ~3790 - 3860 : [KATA KUNCI: Voice Note | Rekam Suara | Audio Recorder]
//    - Baris ~4885 - 4950 : [KATA KUNCI: Hapus Pesan | Delete Message | Dialog Hapus]
//    - Baris ~5560 - 5645 : [KATA KUNCI: Opsi Pesan | Message Options | Star | Salin]
//    - Baris ~5650 - 5840 : [KATA KUNCI: Teruskan Pesan | Forward Message | Dialog Teruskan]
// =====================================================================

class ChatDetailPage extends StatefulWidget {
  final ChatModel? chat;
  final bool isReadOnly;
  const ChatDetailPage({super.key, this.chat, this.isReadOnly = false});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

// Helper class untuk local cache pesan yang belum dikonfirmasi server
class _CachedSentMessage {
  final Message message;
  final DateTime addedAt;
  _CachedSentMessage(this.message, this.addedAt);

  Map<String, dynamic> toMap() => {
    'message': message.toMap(),
    'addedAt': addedAt.toIso8601String(),
  };

  factory _CachedSentMessage.fromMap(Map<String, dynamic> map) {
    return _CachedSentMessage(
      Message.fromMap(Map<String, dynamic>.from(map['message'] as Map)),
      DateTime.tryParse(map['addedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  late ChatModel chat;
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();

  bool get _isTelegramChat =>
      chat.chId == '2' ||
      chat.channelType.toLowerCase().contains('telegram') ||
      chat.channelName.toLowerCase().contains('telegram');

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    bool isRemoved = false;

    void removeToast() {
      if (!isRemoved) {
        isRemoved = true;
        try {
          entry.remove();
        } catch (_) {}
      }
    }

    entry = OverlayEntry(
      builder: (context) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) {
            return Positioned(
              top: MediaQuery.of(context).padding.top + 12 + (val * 8) - 8,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: val.clamp(0.0, 1.0),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: isError
                            ? const Color(0xFFE53935)
                            : const Color(0xFF2B2D30),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isError ? Icons.error_outline : Icons.check_circle,
                            color: isError
                                ? Colors.white
                                : const Color(0xFF4CAF50),
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    try {
      overlay.insert(entry);
      Future.delayed(const Duration(milliseconds: 2200), () {
        removeToast();
      });
    } catch (_) {}
  }

  // *** LOCAL SENT CACHE ***
  // Menyimpan pesan yang sudah dikirim tapi belum dikonfirmasi server.
  // Bertahan selama app berjalan (static). Dibersihkan setelah 2 jam atau dikonfirmasi AckPolling.
  static final Map<String, List<_CachedSentMessage>> _localSentCache = {};

  // FITUR: State Pesan Utama
  // FUNGSI: Menyimpan data daftar pesan (_messages) dan state loading saat memuat histori.
  List<Message> _messages = [];

  Set<String> _getPersistenceKeys() {
    final keys = <String>{};
    // ANTI-BLEED: Persistence HANYA boleh di-scope ke chat.id aktif.
    // JANGAN PERNAH fallback ke contactId/ctRealId/link/sender/nomor telepon,
    // karena satu kontak bisa memiliki banyak percakapan (misal percakapan lama
    // yang diarsipkan dan percakapan baru yang aktif). Fallback ke contactId akan
    // membocorkan cache pesan percakapan lama ke room baru.
    if (chat.id.isNotEmpty && chat.id != 'null' && chat.id != '0') {
      keys.add(chat.id);
      return keys;
    }
    // Room baru yang belum memiliki id valid: JANGAN restore/simpan cache lama.
    // Biarkan list pesan tetap kosong hingga id room terbentuk.
    return keys;
  }

  Timer? _savePersistentDebounce;

  void _savePersistentMessages() {
    _savePersistentDebounce?.cancel();
    _savePersistentDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();

        // FIX: Batasi pesan yang disimpan secara lokal maksimal 50 pesan terakhir
        // Menggunakan debounce agar tidak membekukan UI thread saat pesan masuk secara cepat
        final int maxPersistent = 50;
        final List<Message> messagesToSave = _messages.length > maxPersistent
            ? _messages.sublist(_messages.length - maxPersistent)
            : _messages;

        final List<Map<String, dynamic>> mapList = messagesToSave
            .map((m) => m.toMap())
            .toList();
        final jsonStr = jsonEncode(mapList);
        final keys = _getPersistenceKeys();

        for (final key in keys) {
          await prefs.setString('persist_msgs_$key', jsonStr);
          await prefs.setStringList(
            'deleted_ids_$key',
            _deletedMessageIds.toList(),
          );
        }

        // Bersihkan cache legacy yang sempat tersimpan menggunakan contactId / phoneOnly
        // agar tidak membocorkan pesan lama ke percakapan lain
        if (chat.id.isNotEmpty && chat.id != 'null' && chat.id != '0') {
          if (chat.contactId.isNotEmpty && chat.contactId != chat.id) {
            await prefs.remove('persist_msgs_${chat.contactId}');
            await prefs.remove('sent_cache_${chat.contactId}');
          }
          final phoneOnly = chat.sender.replaceAll(RegExp(r'[^0-9]'), '');
          if (phoneOnly.isNotEmpty && phoneOnly != chat.id) {
            await prefs.remove('persist_msgs_$phoneOnly');
            await prefs.remove('sent_cache_$phoneOnly');
          }
        }

        final cacheList = (_localSentCache[chat.id] ?? [])
            .map((c) => c.toMap())
            .toList();
        if (cacheList.isNotEmpty) {
          final cacheJsonStr = jsonEncode(cacheList);
          for (final key in keys) {
            await prefs.setString('sent_cache_$key', cacheJsonStr);
          }
        } else {
          for (final key in keys) {
            await prefs.remove('sent_cache_$key');
          }
        }
      } catch (e) {
        debugPrint('ChatDetail: ❌ Error saving persistent messages: $e');
      }
    });
  }

  int _parseMessageTimestamp(Message m) {
    if (m.rawTime.isEmpty) return 0;
    try {
      String t = m.rawTime.replaceFirst(' ', 'T').replaceAll('ZZ', 'Z');
      if (!t.endsWith('Z') && !t.contains('+') && t.length >= 19) t += 'Z';
      return DateTime.parse(t).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  void _addMessageInOrder(Message newMessage) {
    final newTime = _parseMessageTimestamp(newMessage);
    if (_messages.isEmpty) {
      _messages.add(newMessage);
      return;
    }

    final lastTime = _parseMessageTimestamp(_messages.last);
    if (newTime >= lastTime) {
      // 99.9% dari pesan realtime yang masuk adalah pesan terbaru: O(1) append langsung
      _messages.add(newMessage);
    } else {
      // Jika waktu pesan lebih lampau (out of order), sisipkan di indeks yang tepat
      int insertIdx = _messages.indexWhere(
        (m) => _parseMessageTimestamp(m) > newTime,
      );
      if (insertIdx != -1) {
        _messages.insert(insertIdx, newMessage);
      } else {
        _messages.add(newMessage);
      }
    }
  }

  Future<void> _restorePersistentMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Message>? restored;
      final keys = _getPersistenceKeys();

      for (final key in keys) {
        final delList = prefs.getStringList('deleted_ids_$key');
        if (delList != null) _deletedMessageIds.addAll(delList);
      }

      for (final key in keys) {
        final jsonStr = prefs.getString('persist_msgs_$key');
        if (jsonStr != null && jsonStr.isNotEmpty) {
          final decoded = jsonDecode(jsonStr) as List;
          restored = decoded
              .map((m) => Message.fromMap(m as Map<String, dynamic>))
              .where((m) {
                if (m.id.isNotEmpty && _deletedMessageIds.contains(m.id)) {
                  return false;
                }
                // Guard: Jika pesan memiliki roomId yang berbeda dari chat.id saat ini, lewati
                if (chat.id.isNotEmpty && chat.id != '0' && chat.id != 'null') {
                  if (m.roomId.isNotEmpty && m.roomId != chat.id) {
                    return false;
                  }
                }
                return true;
              })
              .toList();
          if (restored.isNotEmpty) {
            debugPrint(
              'ChatDetail: ⚡ Restored ${restored.length} messages from key persist_msgs_$key',
            );
            break;
          }
        }
      }

      if (restored != null && mounted) {
        setState(() {
          _messages = restored!;
        });
        debugPrint(
          'ChatDetail: ⚡ IMMEDIATELY RESTORED ${_messages.length} persistent messages across Hot Restart!',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleInitialScroll();
        });
      }

      for (final key in keys) {
        final sentJson = prefs.getString('sent_cache_$key');
        if (sentJson != null && sentJson.isNotEmpty) {
          final decodedSent = jsonDecode(sentJson) as List;
          final loaded = decodedSent
              .map((c) => _CachedSentMessage.fromMap(c as Map<String, dynamic>))
              .where(
                (c) =>
                    c.message.id.isEmpty ||
                    !_deletedMessageIds.contains(c.message.id),
              )
              .toList();
          _localSentCache[chat.id] = loaded;
          debugPrint(
            'ChatDetail: ⚡ RESTORED ${_localSentCache[chat.id]!.length} _localSentCache items from key sent_cache_$key',
          );
          break;
        }
      }
    } catch (e) {
      debugPrint('ChatDetail: ❌ Error restoring persistent messages: $e');
    }
  }

  bool _isLoadingMessages = true;
  Message? _repliedMessage;
  ChatStatusProvider? _statusProvider;
  ChatProvider? _chatProvider;
  AuthProvider? _authProvider;
  String _currentUserEmail = '';
  StreamSubscription<Map<String, dynamic>>? _signalRSubscription;
  StreamSubscription<Map<String, dynamic>>? _subSpvSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  bool _showEmojiPicker = false;
  bool _showAttachmentPanel = false;
  final FocusNode _focusNode = FocusNode();

  // FITUR: Tombol Scroll ke Bawah (Scroll-To-Bottom)
  // FUNGSI: Mengontrol visibilitas tombol pintasan scroll ke pesan terbaru saat pengguna menggulir ke atas,
  //         serta menghitung jumlah pesan baru yang masuk saat pengguna sedang membaca histori obrolan lama.
  bool _showScrollToBottomButton = false;
  int _unreadIncomingCountWhileScrolled = 0;
  final GlobalKey _messageListKey = GlobalKey();
  final GlobalKey _firstUnreadKey = GlobalKey();
  final Map<String, GlobalKey> _unreadMessageKeys = {};
  final Set<String> _passedUnreadMessageIds = {};
  String? _firstUnreadMessageId;
  int? _firstUnreadDisplayIndex;
  int _initialUnreadCount = 0;
  double _initialUnreadOffset = 0.0;
  bool _hasPositionedAtUnread = false;
  bool _allInitialUnreadSeen = false;

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 30.0;
  }

  /// Menghitung jumlah pesan belum dibaca yang sebenarnya berada di bawah garis pembatas (divider)
  int get _actualUnreadCount {
    if (_allInitialUnreadSeen) {
      return _unreadIncomingCountWhileScrolled;
    }
    int loadedCount = 0;
    if (_firstUnreadMessageId != null && _firstUnreadMessageId!.isNotEmpty) {
      final displayMessages = _messages
          .where((m) => !m.isSystemMessage)
          .toList();
      final firstIdx = displayMessages.indexWhere(
        (m) =>
            m.id == _firstUnreadMessageId ||
            (m.idAlias != null && m.idAlias == _firstUnreadMessageId),
      );
      if (firstIdx != -1) {
        for (int i = firstIdx; i < displayMessages.length; i++) {
          if (!displayMessages[i].isMe) loadedCount++;
        }
      }
    }
    if (loadedCount == 0 && _firstUnreadDisplayIndex != null) {
      final displayMessages = _messages
          .where((m) => !m.isSystemMessage)
          .toList();
      if (_firstUnreadDisplayIndex! >= 0 &&
          _firstUnreadDisplayIndex! < displayMessages.length) {
        for (
          int i = _firstUnreadDisplayIndex!;
          i < displayMessages.length;
          i++
        ) {
          if (!displayMessages[i].isMe) loadedCount++;
        }
      }
    }
    if (_initialUnreadCount > loadedCount) {
      return _initialUnreadCount;
    }
    if (loadedCount > 0) return loadedCount;
    if (_unreadIncomingCountWhileScrolled > 0) {
      return _unreadIncomingCountWhileScrolled;
    }
    return 0;
  }

  /// Menghitung sisa pesan belum dibaca yang BELUM dilewati saat user scroll ke bawah.
  /// Jika user scroll kembali ke atas setelah semua pesan dibaca, tidak ada lagi badge unread.
  int get _remainingUnreadBadgeCount {
    if (_allInitialUnreadSeen) {
      return _unreadIncomingCountWhileScrolled;
    }

    if (_firstUnreadMessageId != null && _initialUnreadCount > 0) {
      final remaining = _initialUnreadCount - _passedUnreadMessageIds.length;
      if (remaining <= 0) {
        return _unreadIncomingCountWhileScrolled;
      }
      return remaining + _unreadIncomingCountWhileScrolled;
    }

    return _unreadIncomingCountWhileScrolled;
  }

  // FITUR: Mode Seleksi Pesan (Multiple Selection)
  // FUNGSI: Digunakan saat pengguna menahan pesan untuk memilih beberapa pesan (misal untuk forward/delete).
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageKeys = {};
  final Set<String> _deletedMessageIds = {};

  String _getMessageKey(Message m) {
    if (m.messageType == MessageType.voice &&
        m.audioPath != null &&
        m.audioPath!.isNotEmpty) {
      final cleanAudio = m.audioPath!.split('?').first.split('/').last;
      return 'voice_$cleanAudio';
    }
    if (m.id.isNotEmpty) return 'id_${m.id}';
    return 'local_${m.time}_${m.content}_${m.messageType}';
  }

  bool _isInit = false;
  String _archivedDateLabel = '';

  // FITUR: Quick Reply (Balasan Cepat)
  // FUNGSI: Menyimpan template balasan cepat (dipicu dengan karakter '/') dan cache template dari server.
  bool _isShowingQuickReply = false;
  List<QuickReplyTemplate> _masterTemplates = [];
  List<QuickReplyTemplate> _quickReplyTemplates = [];
  bool _hasFetchedQuickReplies = false;
  bool _isLoadingQuickReply = false;
  Timer? _quickReplyDebounce;
  bool _isSettingQuickReply = false;

  // FITUR: Paginasi Pesan (Infinite Scroll ke atas)
  // FUNGSI: Mengelola pengambilan pesan terdahulu berdasarkan batas (_messagePageSize) saat menggulir.
  static const int _messagePageSize = 50;
  int _messageSkip = 0;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUserEmail = _authProvider?.currentUser ?? '';
    _statusProvider = Provider.of<ChatStatusProvider>(context, listen: false);
    if (!_isInit) {
      if (widget.chat != null) {
        chat = widget.chat!;
      } else {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is ChatModel) {
          chat = args;
        } else {
          debugPrint(
            'Error: ChatDetailPage opened without valid ChatModel. Navigating back.',
          );
          chat = ChatModel(
            id: '',
            sender: 'Unknown',
            lastMessage: '',
            time: '',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }
      }

      debugPrint('=== DIAGNOSTIC CHAT IDS ===');
      debugPrint('RoomId (id): ${chat.id}');
      debugPrint('ContactId: ${chat.contactId}');
      debugPrint('CtRealId: ${chat.ctRealId}');
      debugPrint('AccountId: ${chat.accountId}');
      debugPrint('Link: ${chat.link}');
      debugPrint('GroupId: ${chat.groupId}');
      debugPrint('ChannelType: ${chat.channelType}');
      _isInit = true;
      if (chat.unreadCount <= 0) {
        _allInitialUnreadSeen = true;
      }

      if (chat.id.isNotEmpty) {
        // Suppress notifications while chatting in this room
        PushNotificationService.setCurrentRoom(chat.id);
        // Hapus notifikasinya kalau masih ada menggantung
        PushNotificationService.cancelNotificationsForRoom(chat.id);
      }
    }
  }

  // Voice message state
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isRecordingPaused = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  // New state for recording bottom sheet
  String? _recordedVoicePath;
  int? _recordedVoiceDuration;

  Timer? _ackPollTimer;

  @override
  void deactivate() {
    _ackPollTimer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _ackPollTimer?.cancel();
    _savePersistentDebounce?.cancel();
    _recordingTimer?.cancel();
    _quickReplyDebounce?.cancel();
    _signalRSubscription?.cancel();
    _subSpvSubscription?.cancel();
    SignalRService().leaveConversation(chat.id);
    _syncLastMessageToProvider();
    // Reset notification suppression when leaving chat
    if (_isInit) {
      PushNotificationService.setCurrentRoom(null);
      final provider = _statusProvider;
      final sender = chat.sender;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider?.setLastSeen(sender);
      });
    }
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeChat();

    // Listener gulir (scroll) untuk memuat pesan-pesan terdahulu & tombol scroll ke bawah
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        // Pada mode reverse (terbalik), maxScrollExtent = pesan paling lama (di bagian atas layar)
        if (_scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 200 &&
            !_isLoadingOlderMessages &&
            _hasMoreMessages &&
            !chat.isArchived) {
          _loadOlderMessages();
        }

        final pixels = _scrollController.position.pixels;
        final isAtBottom = pixels <= 30.0;
        final hasUnreadState =
            _firstUnreadMessageId != null ||
            _unreadIncomingCountWhileScrolled > 0;

        if (isAtBottom) {
          _allInitialUnreadSeen = true;
        }

        if (isAtBottom && hasUnreadState) {
          setState(() {
            _allInitialUnreadSeen = true;
            _unreadIncomingCountWhileScrolled = 0;
            _firstUnreadMessageId = null;
            _firstUnreadDisplayIndex = null;
            _initialUnreadCount = 0;
            _initialUnreadOffset = 0.0;
            _passedUnreadMessageIds.clear();
            _unreadMessageKeys.clear();
            _showScrollToBottomButton = false;
          });
        } else {
          final shouldShow =
              !isAtBottom &&
              ((hasUnreadState &&
                      (_remainingUnreadBadgeCount > 0 || pixels > 80.0)) ||
                  (!hasUnreadState && pixels > 150.0));

          if (shouldShow != _showScrollToBottomButton) {
            setState(() {
              _showScrollToBottomButton = shouldShow;
            });
          }
        }

        // Periksa pesan belum dibaca yang telah dilewati saat scroll ke bawah
        if (_firstUnreadMessageId != null) {
          _checkUnreadMessagesPassed();
        }
      }
    });
    _messageController.addListener(() {
      if (!mounted) return;
      if (_isSettingQuickReply)
        return; // Lewati jika sistem sedang memasukkan template teks otomatis

      final text = _messageController.text;
      final composing = text.trim().isNotEmpty;
      if (composing != _isComposing) {
        setState(() => _isComposing = composing);
      }

      // Deteksi Panggilan Balasan Cepat (Quick Reply)
      if (text.startsWith('/')) {
        final searchText = text.substring(1);
        if (!_isShowingQuickReply) {
          setState(() => _isShowingQuickReply = true);
        }

        // Penundaan (Debounce) untuk memfilter pencarian lokal agar tidak memberatkan memori
        if (_quickReplyDebounce?.isActive ?? false)
          _quickReplyDebounce!.cancel();
        _quickReplyDebounce = Timer(const Duration(milliseconds: 300), () {
          _fetchQuickReplies(searchText);
        });
      } else {
        if (_isShowingQuickReply) {
          setState(() => _isShowingQuickReply = false);
        }
      }
    });

    // Listen to audio player state changes
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
        });
      }
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _playbackDuration = dur);
    });
  }

  // [ACTION: QUICK_REPLY_SHOW] - Memuat daftar balas cepat jika user mengetik awalan '/'
  Future<void> _fetchQuickReplies(String searchText) async {
    if (!_hasFetchedQuickReplies) {
      setState(() => _isLoadingQuickReply = true);
      final response = await _chatService.getQuickReplyTemplates(
        containsText: '',
      );
      if (mounted) {
        setState(() {
          _isLoadingQuickReply = false;
          _hasFetchedQuickReplies = true;
          if (!response.isError && response.data != null) {
            _masterTemplates = response.data!;
          }
        });
      }
    }

    if (!mounted) return;

    setState(() {
      if (searchText.isEmpty) {
        _quickReplyTemplates = List.from(_masterTemplates);
      } else {
        final query = searchText.toLowerCase();
        _quickReplyTemplates = _masterTemplates.where((t) {
          return (t.command.toLowerCase().contains(query)) ||
              (t.content.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  // =====================================================================
  // [KATA KUNCI: Quick Reply List | Template Balasan Cepat | Shortcut Chat]
  // [FITUR: Daftar Template Balasan Cepat (Quick Reply)]
  // [RENTANG: Baris ~610 - 750]
  // [FUNGSI: Menampilkan daftar popup berisi template pesan cepat saat pengguna
  //          mengetik karakter '/' di input bar. Memungkinkan pemilihan template
  //          secara instan tanpa harus mengetik ulang seluruh pesan.]
  // =====================================================================
  Widget _buildQuickReplyList(bool isDark) {
    return Container(
      key: const ValueKey('quickReplyList'),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.flash_on, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Quick Reply Templates',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_isLoadingQuickReply)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                else
                  Text(
                    '${_quickReplyTemplates.length} templates',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List Items
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _quickReplyTemplates.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final template = _quickReplyTemplates[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final newText = template.content;

                    _isSettingQuickReply = true; // flag ON

                    setState(() {
                      _isShowingQuickReply = false; // tutup popup dulu
                    });

                    _messageController.text = newText;
                    _messageController.selection = TextSelection.collapsed(
                      offset: newText.length,
                    );

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _focusNode.requestFocus();
                      _isSettingQuickReply = false; // flag OFF
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            template.command,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          template.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _debugApiState = '';

  // FITUR: Memuat Daftar Pesan (API Call)
  // FUNGSI: Mengambil daftar pesan dari backend untuk ruang chat aktif (menggunakan GraphQL/REST) atau arsip (REST), kemudian di-parse ke model Message.
  void _loadInitialMessages() async {
    await _restorePersistentMessages();
    if (!mounted) return;
    final currentUserEmail = _currentUserEmail.isNotEmpty
        ? _currentUserEmail
        : (_authProvider?.currentUser ??
              (mounted
                  ? Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    ).currentUser
                  : '') ??
              '');

    setState(() {
      _isLoadingMessages = true;
      _debugApiState = 'Memanggil API untuk RoomId: ${chat.id}...';
    });

    if (chat.isArchived) {
      // ── ARCHIVED: gunakan endpoint DetailArchived (seperti mentor) ──
      debugPrint('ChatDetail: Chat is archived, using getArchivedRoomDetail');

      final archivedResponse = await _chatService.getArchivedRoomDetail(
        chat.id,
      );

      debugPrint(
        'ChatDetail: Archived response - Error? ${archivedResponse.isError}',
      );

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _isLoadingMessages = false;

            if (archivedResponse.isError) {
              _debugApiState = 'API Error: ${archivedResponse.error}';
              return;
            }

            final data = archivedResponse.data;
            if (data == null) {
              _debugApiState = 'API mengembalikan data null.';
              return;
            }

            // Debug: log tipe & nilai dari key Messages
            debugPrint(
              'ChatDetail: data["Messages"] runtimeType=${data['Messages']?.runtimeType}',
            );

            // Struktur dari DetailArchived:
            // Data.Messages = Map { Id, RoomId, St, Msgs: [...] }
            // Pesan sebenarnya ada di Data.Messages.Msgs
            List<dynamic> messagesList = [];

            final messagesObj = data['Messages'];
            if (messagesObj is Map && messagesObj['Msgs'] != null) {
              final msgs = messagesObj['Msgs'];
              if (msgs is List) {
                messagesList = msgs;
                debugPrint(
                  'ChatDetail: ✅ Found ${messagesList.length} messages at Data.Messages.Msgs (List)',
                );
              } else if (msgs is String) {
                // Msgs mungkin berupa JSON string
                try {
                  final decoded = jsonDecode(msgs);
                  if (decoded is List) {
                    messagesList = decoded;
                    debugPrint(
                      'ChatDetail: ✅ Found ${messagesList.length} messages at Data.Messages.Msgs (decoded JSON string)',
                    );
                  }
                } catch (e) {
                  debugPrint('ChatDetail: ❌ Failed to decode Msgs string: $e');
                }
              }
            } else if (messagesObj is List) {
              messagesList = messagesObj;
              debugPrint(
                'ChatDetail: ✅ Found ${messagesList.length} messages at Data.Messages (List)',
              );
            }

            if (messagesList.isEmpty) {
              final keysInfo = data.entries
                  .map((e) => '${e.key}(${e.value?.runtimeType})')
                  .join(', ');
              debugPrint('ChatDetail: ⚠️ No messages found. Detail: $keysInfo');
              _debugApiState =
                  'Msgs kosong. Data.Messages type=${messagesObj?.runtimeType}';
              return;
            }

            if (messagesList.isEmpty) {
              _debugApiState =
                  'API berhasil tapi 0 pesan (kosong) dari server.';
              return;
            }

            // Ambil tanggal arsip dari Room data
            if (data['Room'] is Map) {
              final room = data['Room'] as Map;
              final timeArchived = room['TimeArchived']?.toString() ?? '';
              final roomIn = room['In']?.toString() ?? '';
              // TimeArchived dari API bisa berupa angka hari atau timestamp
              if (timeArchived.isNotEmpty && timeArchived != 'null') {
                // Coba parse sebagai datetime dulu
                final dt = DateTime.tryParse(timeArchived);
                if (dt != null) {
                  _archivedDateLabel =
                      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                } else {
                  // Jika numerik (hari), hitung dari room.In
                  final days = int.tryParse(timeArchived);
                  final baseDate = DateTime.tryParse(roomIn);
                  if (days != null && baseDate != null) {
                    final archivedDate = baseDate.add(Duration(days: days));
                    _archivedDateLabel =
                        '${archivedDate.day.toString().padLeft(2, '0')}/${archivedDate.month.toString().padLeft(2, '0')}/${archivedDate.year} ${archivedDate.hour.toString().padLeft(2, '0')}:${archivedDate.minute.toString().padLeft(2, '0')}';
                  } else {
                    _archivedDateLabel = timeArchived;
                  }
                }
              }
            }

            // Parse ke List<Message>
            try {
              _messages = messagesList.map((json) {
                return Message.fromJson(
                  json,
                  currentUserEmail,
                  tenantId: _chatService.currentTenantId,
                  contactId: chat.contactId,
                );
              }).toList();
              _debugApiState =
                  'Berhasil mengambil ${_messages.length} pesan dari arsip.';
              debugPrint(
                'ChatDetail: ✅ Parsed ${_messages.length} archived messages',
              );
              _injectLocalReplies(_messages).then((_) {
                if (mounted) {
                  setState(() {
                    _invalidateDisplayMessagesCache();
                  });
                }
              });
            } catch (e) {
              debugPrint('ChatDetail: ❌ Error parsing archived messages: $e');
              _debugApiState = 'Error parsing pesan: $e';
            }
          });
          // Mulai polling setelah data arsip selesai dimuat
          if (mounted) _startChatSyncPolling();
        });
      }
    } else {
      // ── NORMAL: gunakan getMessageHistory seperti biasa ──
      debugPrint('ChatDetail: Chat is active, using getMessageHistory');

      // FIX: Fetch more messages (take: 75) and sort locally by absolute ISO time
      // to fix UTC timezone sorting bugs from the backend for Telegram messages.
      final isTelegram =
          chat.chId == '2' ||
          chat.channelType.toLowerCase().contains('telegram') ||
          chat.channelName.toLowerCase().contains('telegram');

      // *** DEBUG *** - Tampilkan semua ID agar kita tahu kenapa pesan WA hilang
      debugPrint('===== LOAD MESSAGES DEBUG =====');
      debugPrint('chat.id       : ${chat.id}');
      debugPrint('chat.contactId: ${chat.contactId}');
      debugPrint('chat.ctRealId : ${chat.ctRealId}');
      debugPrint('chat.groupId  : ${chat.groupId}');
      debugPrint('chat.chId     : ${chat.chId}');
      debugPrint('chat.accountId: ${chat.accountId}');
      debugPrint('isTelegram    : $isTelegram');
      final initialTake = (chat.unreadCount > 75)
          // ANR FIX: jangan memuat ribuan pesan sekaligus saat unreadCount
          // sangat besar. Pesan lama tetap bisa dimuat lewat pagination
          // ketika pengguna scroll ke atas.
          ? (chat.unreadCount + 10).clamp(75, 200).toInt()
          : 75;
      final response = await _chatService.getMessageHistory(
        chat.id,
        currentUserEmail,
        take: initialTake,
        contactId: chat.contactId,
        groupId: chat.groupId,
        ctRealId: chat.ctRealId,
        link: chat.link,
        isTelegram: isTelegram,
      );

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _isLoadingMessages = false;
            if (response.isError) {
              _debugApiState = 'API Error: ${response.error}';
            } else {
              if (response.data == null || response.data!.isEmpty) {
                _debugApiState =
                    'Kamar obrolan terhubung (Riwayat percakapan masih kosong).';
                if (_messages.isEmpty) {
                  _messages = [];
                } else {
                  debugPrint(
                    'ChatDetail: 🛡️ Server API mengembalikan 0 pesan, mempertahankan ${_messages.length} pesan lokal persisten (Hot Restart Protection)',
                  );
                }
              } else {
                _messageSkip = response.data!.length;
                _debugApiState =
                    'Berhasil mengambil ${response.data!.length} pesan.';

                // Tampilkan isi JSON mentah dari pesan pertama untuk keperluan debug
                if (response.data!.isNotEmpty) {
                  try {
                    // Karena response.data sudah berisi List<Message>, kita tidak bisa print JSON mentah lagi
                    // kecuali kita ubah getMessageHistory. Tapi kita bisa print ID yang ter-parse!
                    final first = response.data!.first;
                    debugPrint('===== MSG DEBUG =====');
                    debugPrint('First Msg ID: ${first.id}');
                    debugPrint('First Msg FromId: ${first.fromId}');
                    debugPrint('First Msg ToId: ${first.toId}');
                    debugPrint('First Msg RoomId: ${first.roomId}');
                    debugPrint('chat.accountId: ${chat.accountId}');
                    debugPrint('=====================');

                    // 🚨 REPAIR MECHANISM 🚨
                    // Jika chat.id terdeteksi KOSONG (misal gagal ter-parse dari JSON API),
                    // namun payload pesan memiliki RoomId, kita PERBAIKI secara lokal!
                    if ((chat.id.isEmpty ||
                            chat.id == 'null' ||
                            chat.id == '0') &&
                        first.roomId.isNotEmpty &&
                        !context.read<ChatProvider>().isRoomArchived(
                          first.roomId,
                        )) {
                      chat = chat.copyWith(id: first.roomId);
                      context.read<ChatProvider>().updateLocalChat(chat);
                      debugPrint(
                        'ChatDetail: 🛠️ REPAIRED EMPTY CHAT ID using Message.roomId = ${first.roomId}',
                      );
                    }
                  } catch (e) {}
                }

                // Lakukan sorting lokal untuk memastikan urutan sesuai waktu
                final sortedList = List<Message>.from(response.data!).map((m) {
                  if (chat.ctRealId.isNotEmpty && chat.ctRealId != '0') {
                    final cleanCtRealId = chat.ctRealId.replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    final cleanContactId = chat.contactId.replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    final cleanExtTo = (m.toId ?? '').replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    final cleanExtFrom = (m.fromId ?? '').replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );

                    if (cleanCtRealId.isNotEmpty) {
                      bool matched = false;
                      if (cleanExtTo.isNotEmpty &&
                          (cleanExtTo == cleanCtRealId ||
                              cleanExtTo == cleanContactId)) {
                        m = m.copyWith(isMe: true);
                        matched = true;
                      } else if (cleanExtFrom.isNotEmpty &&
                          (cleanExtFrom == cleanCtRealId ||
                              (cleanContactId.isNotEmpty &&
                                  cleanExtFrom == cleanContactId))) {
                        m = m.copyWith(isMe: false);
                        matched = true;
                      }

                      if (!matched &&
                          cleanExtFrom.isNotEmpty &&
                          chat.groupId.isEmpty) {
                        m = m.copyWith(isMe: true);
                      }
                    }
                  }
                  return m;
                }).toList();
                sortedList.sort((a, b) {
                  if (a.rawTime.isEmpty || b.rawTime.isEmpty) return 0;
                  try {
                    String ta = a.rawTime
                        .replaceFirst(' ', 'T')
                        .replaceAll('ZZ', 'Z');
                    String tb = b.rawTime
                        .replaceFirst(' ', 'T')
                        .replaceAll('ZZ', 'Z');
                    if (!ta.endsWith('Z') &&
                        !ta.contains('+') &&
                        ta.length >= 19)
                      ta += 'Z';
                    if (!tb.endsWith('Z') &&
                        !tb.contains('+') &&
                        tb.length >= 19)
                      tb += 'Z';
                    return DateTime.parse(ta).compareTo(DateTime.parse(tb));
                  } catch (_) {
                    return 0;
                  }
                });

                // FIX HOT RESTART: Jangan timpa pesan yang sudah ter-restore di memori!
                // Gabungkan sortedList dari server dengan pesan lokal di _messages.
                final existingLocal = List<Message>.from(_messages);
                final List<Message> mergedList = [];
                final Set<String> seenApiKeys = {};

                for (final msg in sortedList) {
                  // Tambahkan sedikit salt dari time/content untuk mencegah penimpaan pesan yang dikirim sangat cepat
                  final k = msg.id.isNotEmpty && msg.id != '0'
                      ? '${msg.id}_${msg.content.hashCode}'
                      : 'api_${msg.rawTime}_${msg.content.hashCode}';

                  if (!seenApiKeys.contains(k)) {
                    seenApiKeys.add(k);
                    mergedList.add(msg);
                  }
                }

                // Buat daftar pesan server yang masih "bisa di-match" untuk 1-to-1 deduplikasi
                final List<Message> serverMessagesToMatch = List.from(
                  mergedList,
                );

                for (final localMsg in existingLocal) {
                  // Guard: Jika pesan memiliki roomId yang berbeda dari chat.id saat ini, lewati
                  if (chat.id.isNotEmpty &&
                      chat.id != '0' &&
                      chat.id != 'null') {
                    if (localMsg.roomId.isNotEmpty &&
                        localMsg.roomId != chat.id) {
                      continue;
                    }
                  }

                  if (localMsg.id.isNotEmpty && localMsg.id != '0') {
                    if (!mergedList.any((s) => s.id == localMsg.id)) {
                      mergedList.add(localMsg);
                    }
                    continue;
                  }

                  // Cari 1 pesan server yang COCOK dan BELUM DI-MATCH
                  int matchIdx = serverMessagesToMatch.indexWhere((s) {
                    if (s.isMe == localMsg.isMe &&
                        s.content.trim().toLowerCase() ==
                            localMsg.content.trim().toLowerCase()) {
                      if (s.rawTime == localMsg.rawTime || s.id.isEmpty)
                        return true;
                      try {
                        String ta = s.rawTime
                            .replaceFirst(' ', 'T')
                            .replaceAll('ZZ', 'Z');
                        String tb = localMsg.rawTime
                            .replaceFirst(' ', 'T')
                            .replaceAll('ZZ', 'Z');
                        if (!ta.endsWith('Z') &&
                            !ta.contains('+') &&
                            ta.length >= 19)
                          ta += 'Z';
                        if (!tb.endsWith('Z') &&
                            !tb.contains('+') &&
                            tb.length >= 19)
                          tb += 'Z';
                        final dtA = DateTime.parse(ta);
                        final dtB = DateTime.parse(tb);
                        if (dtA.difference(dtB).inMinutes.abs() <= 2) {
                          return true;
                        }
                      } catch (_) {}
                    }
                    return false;
                  });

                  if (matchIdx != -1) {
                    // Ketemu! Pesan lokal ini sudah ada di server.
                    // Hapus dari serverMessagesToMatch agar tidak di-match lagi oleh pesan lokal ganda lainnya.
                    serverMessagesToMatch.removeAt(matchIdx);
                  } else {
                    // Tidak ketemu! Pesan lokal ini belum ada di server (atau gagal).
                    // Pertahankan pesan lokal ini di UI!
                    mergedList.add(localMsg);
                    debugPrint(
                      'ChatDetail: 🛡️ Mempertahankan pesan lokal: "${localMsg.content}"',
                    );
                  }
                }
                final finalSorted = mergedList;
                finalSorted.sort((a, b) {
                  if (a.rawTime.isEmpty || b.rawTime.isEmpty) return 0;
                  try {
                    String ta = a.rawTime
                        .replaceFirst(' ', 'T')
                        .replaceAll('ZZ', 'Z');
                    String tb = b.rawTime
                        .replaceFirst(' ', 'T')
                        .replaceAll('ZZ', 'Z');
                    if (!ta.endsWith('Z') &&
                        !ta.contains('+') &&
                        ta.length >= 19)
                      ta += 'Z';
                    if (!tb.endsWith('Z') &&
                        !tb.contains('+') &&
                        tb.length >= 19)
                      tb += 'Z';
                    return DateTime.parse(ta).compareTo(DateTime.parse(tb));
                  } catch (_) {
                    return 0;
                  }
                });
                _messages = finalSorted
                    .where(
                      (m) => m.id.isEmpty || !_deletedMessageIds.contains(m.id),
                    )
                    .toList();

                // FIX: Populate missing reply content from local list jika server gagal mengembalikan isi ReplyMsg
                for (int i = 0; i < _messages.length; i++) {
                  final msg = _messages[i];
                  if (msg.repliedMessage != null &&
                      msg.repliedMessage!.content == 'Pesan terkait...') {
                    final originalId = msg.repliedMessage!.id;
                    try {
                      final originalMsg = _messages.firstWhere(
                        (m) => m.id == originalId || m.idAlias == originalId,
                      );
                      if (originalMsg.content.isNotEmpty) {
                        _messages[i] = msg.copyWith(
                          repliedMessage: msg.repliedMessage!.copyWith(
                            content: originalMsg.content,
                          ),
                        );
                      }
                    } catch (_) {}
                  }
                }
              }
              // *** MERGE LOCAL SENT CACHE ***
              // Tambahkan pesan yang sudah dikirim tapi belum dikonfirmasi server
              final cache = _localSentCache[chat.id] ?? [];
              debugPrint(
                'LocalCache: Found ${cache.length} items in cache for ${chat.id} before filter.',
              );

              // Bersihkan cache yang sudah > 2 jam atau sudah dihapus user
              final activeCache = cache
                  .where(
                    (c) =>
                        DateTime.now().difference(c.addedAt).inHours < 2 &&
                        (c.message.id.isEmpty ||
                            !_deletedMessageIds.contains(c.message.id)),
                  )
                  .toList();

              final List<_CachedSentMessage> remainingCache = [];
              final serverMatchedIndices = <int>{};

              for (final cached in activeCache) {
                final cContent = cached.message.content.trim().toLowerCase();
                final cTime = cached.message.time;

                // Cari 1-to-1 match dengan pesan dari server (cek teks & jam yang sama, dengan toleransi 2 menit)
                int matchIdx = _messages.indexWhere((m) {
                  int idx = _messages.indexOf(m);
                  if (serverMatchedIndices.contains(idx)) return false;
                  if (!m.isMe || m.content.trim().toLowerCase() != cContent)
                    return false;
                  if (m.time == cTime ||
                      (cached.message.id.isNotEmpty &&
                          m.id == cached.message.id))
                    return true;

                  // Toleransi perbedaan waktu (delay server)
                  if (m.rawTime.isNotEmpty &&
                      cached.message.rawTime.isNotEmpty) {
                    try {
                      final mt = DateTime.parse(
                        m.rawTime.replaceFirst(' ', 'T').replaceAll('ZZ', 'Z'),
                      );
                      final ct = DateTime.parse(
                        cached.message.rawTime
                            .replaceFirst(' ', 'T')
                            .replaceAll('ZZ', 'Z'),
                      );
                      if (mt.difference(ct).inMinutes.abs() <= 2) return true;
                    } catch (_) {}
                  }
                  return false;
                });

                if (matchIdx != -1) {
                  serverMatchedIndices.add(matchIdx);
                  debugPrint(
                    'LocalCache: Server ALREADY HAS "${cached.message.content}". Dropping from cache.',
                  );
                } else {
                  remainingCache.add(cached);
                  _messages.add(cached.message);
                  debugPrint(
                    'LocalCache: INJECTED: "${cached.message.content}"',
                  );
                }
              }

              // Update cache hanya dengan pesan yang benar-benar belum masuk server
              _localSentCache[chat.id] = remainingCache;
              debugPrint(
                'LocalCache: Cache updated. ${remainingCache.length} items remaining.',
              );

              // *** MERGE SIGNALR CACHE (TELEGRAM/WA DELAY FIX) ***
              final currentRoomIdExt = chat.id.contains('_')
                  ? chat.id.split('_').last
                  : chat.id;

              // ONLY add fallback IDs if it's Telegram, otherwise strict RoomId checking for WhatsApp
              final possibleRoomIds = <String>{chat.id, currentRoomIdExt};
              if (currentRoomIdExt.isNotEmpty)
                possibleRoomIds.add(currentRoomIdExt);

              if (isTelegram) {
                final numericChatId = chat.id.replaceAll(RegExp(r'[^0-9]'), '');
                if (chat.contactId.isNotEmpty)
                  possibleRoomIds.add(chat.contactId);
                if (chat.groupId.isNotEmpty) possibleRoomIds.add(chat.groupId);
                if (chat.ctRealId.isNotEmpty)
                  possibleRoomIds.add(chat.ctRealId);
                if (numericChatId.isNotEmpty)
                  possibleRoomIds.add(numericChatId);
              }

              for (final rId in possibleRoomIds) {
                final recentMsgs = SignalRService().getRecentMessagesForRoom(
                  rId,
                );
                for (final recent in recentMsgs) {
                  final messageData =
                      recent['message'] as Map<String, dynamic>? ?? {};
                  final senderData = recent['sender'] as Map<String, dynamic>?;
                  final parsedMsg = Message.fromJson(
                    messageData,
                    currentUserEmail,
                    tenantId: _chatService.currentTenantId,
                    contactId: chat.contactId,
                  );
                  Message newMsg = parsedMsg.copyWith(
                    status: MessageStatus.read,
                  );

                  // FILTER: Jangan injeksi pesan Telegram "Saved Messages"
                  final sdrName =
                      (senderData?['Name'] ??
                              messageData['Sender'] ??
                              messageData['SenderName'] ??
                              '')
                          .toString()
                          .toLowerCase();
                  if (sdrName == 'saved messages' ||
                      sdrName == 'pesan tersimpan') {
                    continue; // Skip Telegram Saved Messages
                  }

                  // FILTER: Strict Account Isolation untuk Injeksi SignalR
                  if (chat.accountId.isNotEmpty && !isTelegram) {
                    if (newMsg.roomId.isEmpty ||
                        (newMsg.roomId != chat.id &&
                            int.tryParse(newMsg.roomId) == null)) {
                      final fromStr = newMsg.fromId?.toString() ?? '';
                      final toStr = newMsg.toId?.toString() ?? '';
                      if (fromStr != chat.accountId &&
                          toStr != chat.accountId) {
                        debugPrint(
                          'ChatDetail: 🛡️ Blocked SignalR cache message ${newMsg.id} from another channel!',
                        );
                        continue; // Skip pesan ini karena milik channel lain
                      }
                    }
                  }

                  // FILTER: Skip pesan yang sudah dihapus oleh user
                  if (newMsg.id.isNotEmpty &&
                      _deletedMessageIds.contains(newMsg.id)) {
                    continue;
                  }

                  // Cek apakah sudah ada di _messages
                  final exists = _messages.any(
                    (m) =>
                        (m.id.isNotEmpty &&
                            newMsg.id.isNotEmpty &&
                            m.id == newMsg.id) ||
                        (m.content == newMsg.content && m.time == newMsg.time),
                  );
                  if (!exists) {
                    debugPrint(
                      'ChatDetail: ⚡ INJECTING cached SignalR message ${newMsg.id} (${newMsg.content}) due to API delay',
                    );

                    // FIX: Populate missing reply content from local list untuk pesan realtime masuk
                    if (newMsg.repliedMessage != null &&
                        newMsg.repliedMessage!.content == 'Pesan terkait...') {
                      final originalId = newMsg.repliedMessage!.id;
                      try {
                        final originalMsg = _messages.firstWhere(
                          (m) => m.id == originalId || m.idAlias == originalId,
                        );
                        if (originalMsg.content.isNotEmpty) {
                          newMsg = newMsg.copyWith(
                            repliedMessage: newMsg.repliedMessage!.copyWith(
                              content: originalMsg.content,
                            ),
                          );
                        }
                      } catch (_) {}
                    }

                    _messages.add(newMsg);
                  }
                }
              }

              // Lakukan sorting ulang setelah injeksi cache
              _messages.sort((a, b) {
                if (a.rawTime.isEmpty || b.rawTime.isEmpty) return 0;
                try {
                  String ta = a.rawTime
                      .replaceFirst(' ', 'T')
                      .replaceAll('ZZ', 'Z');
                  String tb = b.rawTime
                      .replaceFirst(' ', 'T')
                      .replaceAll('ZZ', 'Z');
                  if (!ta.endsWith('Z') && !ta.contains('+') && ta.length >= 19)
                    ta += 'Z';
                  if (!tb.endsWith('Z') && !tb.contains('+') && tb.length >= 19)
                    tb += 'Z';
                  return DateTime.parse(ta).compareTo(DateTime.parse(tb));
                } catch (_) {
                  return 0;
                }
              });
              _savePersistentMessages();
            }
          });
          if (!response.isError && _messages.isNotEmpty) {
            _injectLocalReplies(_messages).then((_) {
              if (mounted) {
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _handleInitialScroll();
                });
              }
            });

            _syncLastMessageToProvider();
          }
          // Mulai polling setelah pesan awal selesai dimuat
          if (mounted) _startChatSyncPolling();
        });
      }
    }
  }

  /// Sinkronisasi pesan terakhir secara akurat ke ChatProvider (Chat List)
  void _syncLastMessageToProvider() {
    if (_messages.isEmpty) return;
    final chatProv =
        _chatProvider ??
        (mounted ? Provider.of<ChatProvider>(context, listen: false) : null);
    if (chatProv == null) return;

    final realMessages = _messages.where((m) {
      if (m.isSystemMessage || m.content == 'Site.Inbox.DeletedMessage') {
        return false;
      }
      if (m.id.isNotEmpty && _deletedMessageIds.contains(m.id)) {
        return false;
      }
      final lower = m.content.toLowerCase();
      return !lower.contains('site.inbox.') &&
          !lower.contains('percakapan di-assign') &&
          !lower.contains('percakapan diselesaikan') &&
          !lower.contains('pemberitahuan sistem');
    }).toList();

    if (realMessages.isNotEmpty) {
      final lastMsg = realMessages.last;
      String newContent = lastMsg.content;
      String typeStr = '1';
      if (lastMsg.messageType == MessageType.image) {
        final isSticker =
            (lastMsg.imageUrl ?? '').toLowerCase().endsWith('.webp') ||
            (lastMsg.imagePath ?? '').toLowerCase().endsWith('.webp') ||
            newContent.toLowerCase().endsWith('.webp');
        if (isSticker) {
          newContent = '🌟 Sticker';
          typeStr = '16';
        } else {
          final cleaned = newContent
              .replaceAll('📷', '')
              .replaceAll('🖼️', '')
              .replaceAll('🖼', '')
              .replaceAll(RegExp(r'^(Photo|Foto)\s*', caseSensitive: false), '')
              .trim();
          newContent = cleaned.isNotEmpty ? '📷 $cleaned' : '📷 Foto';
          typeStr = '3';
        }
      } else if (lastMsg.messageType == MessageType.voice) {
        newContent = '🎤 Pesan Suara';
        typeStr = '2';
      } else if (lastMsg.messageType == MessageType.video) {
        final cleaned = newContent
            .replaceAll('🎬', '')
            .replaceAll('🎥', '')
            .replaceAll('📹', '')
            .replaceAll('Video', '')
            .trim();
        newContent = '🎬 Video${cleaned.isNotEmpty ? ' $cleaned' : ''}';
        typeStr = '4';
      } else if (lastMsg.messageType == MessageType.document) {
        if (!newContent.contains('📄') && !newContent.contains('📁')) {
          newContent = '📄 $newContent';
        }
        typeStr = '5';
      } else if (lastMsg.messageType == MessageType.sticker) {
        newContent = '🌟 Sticker';
        typeStr = '16';
      }

      if (chat.lastMessage == newContent &&
          chat.lastMessageType == typeStr &&
          chat.isLastMessageFromMe == lastMsg.isMe) {
        return; // Sudah up to date, lewati update provider redundan
      }

      chatProv.updateLocalLastMessage(
        chat.id,
        newContent,
        lastMessageType: typeStr,
        isFromMe: lastMsg.isMe,
        updateTimeAndPosition: false,
        overrideTime: lastMsg.rawTime.isNotEmpty ? lastMsg.rawTime : null,
        isDeletion: _deletedMessageIds.isNotEmpty,
      );
    } else {
      chatProv.updateLocalLastMessage(
        chat.id,
        '',
        lastMessageType: '1',
        updateTimeAndPosition: false,
        isDeletion: _deletedMessageIds.isNotEmpty,
      );
    }
  }

  // FITUR: Sinkronisasi Pesan Latar Belakang (Ack Polling)
  // FUNGSI: Memulai proses polling interval untuk memperbarui status baca/terkirim (ack) pada pesan, jika koneksi real-time tidak memadai.
  // FITUR 4: Timer polling untuk memperbarui status centang di layar secara berkala.
  // [ACTION: ACK_POLLING] - Proses sinkronisasi status pesan di background
  bool _isSyncingMessages = false;
  bool _hasPendingSync = false;

  // FITUR: Sinkronisasi Pesan Instan & Latar Belakang
  // FUNGSI: Mengambil pesan terbaru dari server secara langsung (dipicu oleh event TerimaSubSpv atau timer polling berkala)
  Future<void> _fetchLatestMessagesImmediately({int take = 25}) async {
    if (!mounted) return;
    if (_isSyncingMessages) {
      _hasPendingSync = true;
      return;
    }
    _isSyncingMessages = true;
    try {
      final isTelegram =
          chat.chId == '2' ||
          chat.channelType.toLowerCase().contains('telegram') ||
          chat.channelName.toLowerCase().contains('telegram');

      final currentUserEmail = _currentUserEmail.isNotEmpty
          ? _currentUserEmail
          : (_authProvider?.currentUser ??
                (mounted
                    ? Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      ).currentUser
                    : '') ??
                '');
      final response = await _chatService.getMessageHistory(
        chat.id,
        currentUserEmail,
        take: take,
        contactId: chat.contactId,
        groupId: chat.groupId,
        ctRealId: chat.ctRealId,
        link: chat.link,
        isTelegram: isTelegram,
      );
      if (!mounted) return;

      if (!response.isError && response.data != null) {
        final List<Message> newMessages = List<Message>.from(
          (response.data ?? []).where(
            (m) => m.id.isEmpty || !_deletedMessageIds.contains(m.id),
          ),
        );

        debugPrint(
          'ChatSync: Fetched ${newMessages.length} filtered messages. Matching...',
        );
        setState(() {
          bool hasNewMessages = false;
          final currentIds = _messages
              .map((m) => m.id)
              .where((id) => id.isNotEmpty)
              .toSet();

          // 1. Match locally sent messages (without ID) to server messages FIRST
          final matchedServerIds =
              <
                String
              >{}; // Lacak ID server yang sudah dicocokkan untuk mencegah duplikasi klaim

          for (var i = 0; i < _messages.length; i++) {
            final oldMsg = _messages[i];
            if (oldMsg.isMe && oldMsg.id.isEmpty && oldMsg.ack != 4) {
              final newMsgIdx = newMessages.indexWhere((m) {
                if (!m.isMe)
                  return false; // Harus sama-sama dari pengirim (isMe)
                if (m.id.isNotEmpty && matchedServerIds.contains(m.id))
                  return false; // Jangan cocokkan ke pesan server yang sudah diklaim!
                if (m.id.isNotEmpty && currentIds.contains(m.id))
                  return false; // Jangan cocokkan ke pesan lawas yang sudah ada di memori lokal!

                // 1. Coba cocokkan berdasarkan konten teks (HANYA UNTUK PESAN TEKS)
                if (oldMsg.messageType == MessageType.text &&
                    m.messageType == MessageType.text) {
                  final mClean = m.content
                      .replaceAll(RegExp(r'\s+'), '')
                      .toLowerCase();
                  final oldClean = oldMsg.content
                      .replaceAll(RegExp(r'\s+'), '')
                      .toLowerCase();

                  // Pencocokan persis (exact match)
                  if (mClean == oldClean) {
                    // Pastikan jam-nya sama agar tidak tertukar dengan pesan masa lalu yang kebetulan teksnya persis
                    if (m.time == oldMsg.time) return true;
                  }

                  // Pencocokan sebagian (hanya aman jika pesannya panjang, misalnya > 5 karakter)
                  // dan waktunya harus SANGAT berdekatan (jam/menit sama)
                  if (oldClean.length > 5 &&
                      (mClean.contains(oldClean) ||
                          oldClean.contains(mClean))) {
                    if (m.time == oldMsg.time) {
                      debugPrint(
                        'AckPolling MATCH: Partial text match successful for ID ${m.id}',
                      );
                      return true;
                    }
                  }
                }

                // 2. Coba cocokkan berdasarkan URL (jika sudah ada response.data dari upload)
                final oldUrl =
                    oldMsg.documentUrl ??
                    oldMsg.imageUrl ??
                    oldMsg.videoUrl ??
                    oldMsg.audioPath;
                if (oldUrl != null && oldUrl.isNotEmpty) {
                  if (oldUrl == m.documentUrl ||
                      oldUrl == m.imageUrl ||
                      oldUrl == m.videoUrl ||
                      oldUrl == m.audioPath) {
                    return true;
                  }
                }

                // 3. Coba cocokkan berdasarkan nama file lampiran (gambar/dokumen/voice/video)
                if (oldMsg.messageType == MessageType.document) {
                  if (oldMsg.documentName != null) {
                    final docName = oldMsg.documentName!;
                    // Server mungkin mengubah BodyType=5 menjadi Type=3 (Image) atau Type=4 (Video)
                    if (m.documentUrl?.contains(docName) == true ||
                        m.imageUrl?.contains(docName) == true ||
                        m.videoUrl?.contains(docName) == true) {
                      return true;
                    }
                  }
                } else if (oldMsg.messageType == MessageType.image) {
                  if (oldMsg.imagePath != null) {
                    final localFileName = oldMsg.imagePath!.split('/').last;
                    if (m.imageUrl?.contains(localFileName) == true ||
                        m.documentUrl?.contains(localFileName) == true) {
                      return true;
                    }
                  }
                } else if (oldMsg.messageType == MessageType.voice) {
                  if (oldMsg.audioPath != null) {
                    final localFileName = oldMsg.audioPath!.split('/').last;
                    if (m.audioPath?.contains(localFileName) == true ||
                        m.documentUrl?.contains(localFileName) == true) {
                      return true;
                    }
                  }
                } else if (oldMsg.messageType == MessageType.video ||
                    oldMsg.messageType == MessageType.sticker) {
                  final checkUrl = oldMsg.videoUrl ?? oldMsg.imageUrl;
                  if (checkUrl != null) {
                    final localFileName = checkUrl.split('/').last;
                    if (m.videoUrl?.contains(localFileName) == true ||
                        m.imageUrl?.contains(localFileName) == true ||
                        m.documentUrl?.contains(localFileName) == true) {
                      return true;
                    }
                  }
                }

                // RACE CONDITION FALLBACK 1: Tipe media berubah
                if (!currentIds.contains(m.id) &&
                    oldMsg.messageType != MessageType.text &&
                    m.messageType != MessageType.text) {
                  if (m.time == oldMsg.time) return true;
                }

                return false;
              });

              if (newMsgIdx != -1) {
                debugPrint(
                  'AckPolling: Berhasil mencocokkan oldMsg (Type: ${oldMsg.messageType}) -> Index Server: $newMsgIdx',
                );
                final updatedMsg = newMessages[newMsgIdx];
                if (updatedMsg.id.isNotEmpty) {
                  matchedServerIds.add(
                    updatedMsg.id,
                  ); // Tandai sebagai sudah diklaim

                  // FIX: Jangan pernah timpa messageType media jika pesan lokal sudah punya tipe yang jelas (kecuali teks).
                  // Server sering mengklasifikasikan ulang file audio/dokumen secara salah (misal gambar jadi voice note).
                  // Prioritas 100%: tipe lokal menang!
                  final resolvedType =
                      _messages[i].messageType != MessageType.text
                      ? _messages[i].messageType
                      : updatedMsg.messageType;

                  _messages[i] = _messages[i].copyWith(
                    id: updatedMsg.id,
                    ack: updatedMsg.ack,
                    status: updatedMsg.ack >= 3
                        ? MessageStatus.delivered
                        : MessageStatus.sent,
                    messageType: resolvedType,
                    imageUrl: resolvedType == MessageType.image
                        ? (_messages[i].imagePath ?? updatedMsg.imageUrl)
                        : updatedMsg.imageUrl,
                    videoUrl: resolvedType == MessageType.video
                        ? (_messages[i].videoUrl ?? updatedMsg.videoUrl)
                        : updatedMsg.videoUrl,
                    documentUrl: updatedMsg.documentUrl,
                    audioPath: resolvedType == MessageType.voice
                        ? ((_messages[i].audioPath != null &&
                                  File(_messages[i].audioPath!).existsSync())
                              ? _messages[i].audioPath
                              : updatedMsg.audioPath)
                        : updatedMsg.audioPath,
                    audioDuration: _messages[i].audioDuration > 0
                        ? _messages[i].audioDuration
                        : updatedMsg.audioDuration,
                  );
                  // UPDATE: Save local reply if this message had a repliedMessage
                  if (_messages[i].repliedMessage != null) {
                    _saveLocalReplyContext(
                      updatedMsg.id,
                      _messages[i].repliedMessage!,
                    );
                  }

                  // REMOVE DARI CACHE LOKAL KARENA SUDAH DIKONFIRMASI SERVER
                  final cacheList = _localSentCache[chat.id];
                  if (cacheList != null) {
                    int removeIdx = cacheList.indexWhere(
                      (c) =>
                          c.message.content.trim().toLowerCase() ==
                              _messages[i].content.trim().toLowerCase() &&
                          c.message.time == _messages[i].time,
                    );
                    if (removeIdx != -1) {
                      cacheList.removeAt(removeIdx);
                      debugPrint(
                        'LocalCache: Dihapus dari cache via AckPolling karena sudah dikonfirmasi ID-nya.',
                      );
                    }
                  }
                }
              }
            } else if (oldMsg.isMe &&
                oldMsg.id.isNotEmpty &&
                oldMsg.repliedMessage != null) {
              // Pesan sudah memiliki ID (mungkin dari echo-back SignalR),
              // pastikan context reply-nya tetap disave ke local cache.
              _saveLocalReplyContext(oldMsg.id, oldMsg.repliedMessage!);
            }
          }

          // 2. Add or update messages from server
          final updatedCurrentIds = _messages
              .map((m) => m.id)
              .where((id) => id.isNotEmpty)
              .toSet();
          // Juga kumpulkan konten dari pesan lokal yang BELUM punya ID (masih pending)
          // Ini mencegah duplikasi saat pesan lokal gagal dicocokkan di Step 1
          final pendingLocalContents = _messages
              .where((m) => m.isMe && m.id.isEmpty)
              .map((m) => m.content.trim().toLowerCase())
              .toSet();

          // Lakukan sorting lokal untuk memastikan urutan sesuai waktu
          final sortedList = List<Message>.from(newMessages);
          sortedList.sort((a, b) {
            if (a.rawTime.isEmpty || b.rawTime.isEmpty) return 0;
            try {
              String ta = a.rawTime;
              String tb = b.rawTime;
              if (!ta.endsWith('Z') && !ta.contains('+') && ta.length >= 19)
                ta += 'Z';
              if (!tb.endsWith('Z') && !tb.contains('+') && tb.length >= 19)
                tb += 'Z';
              return DateTime.parse(ta).compareTo(DateTime.parse(tb));
            } catch (_) {
              return 0;
            }
          });

          final List<Message> newCustomerIncomingMessages = [];
          for (final msg in sortedList) {
            if (msg.id.isNotEmpty && _deletedMessageIds.contains(msg.id)) {
              continue; // Abaikan pesan yang sudah dihapus oleh pengguna
            }
            if (msg.id.isNotEmpty && !updatedCurrentIds.contains(msg.id)) {
              // FIX: Hindari bug duplikasi dari backend (dua pesan identik dengan ID berbeda dikembalikan oleh API)
              bool isBackendDuplicate = false;
              if (msg.isMe) {
                final cleanNew = msg.content.trim().toLowerCase().replaceAll(
                  RegExp(r'\s+'),
                  '',
                );
                final duplicateIdx = _messages.indexWhere((m) {
                  if (!m.isMe || m.id.isEmpty || m.id.startsWith('temp_'))
                    return false;
                  final cleanM = m.content.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    '',
                  );
                  if (cleanM == cleanNew) {
                    if (m.rawTime.isNotEmpty && msg.rawTime.isNotEmpty) {
                      try {
                        final mt = DateTime.parse(
                          m.rawTime
                              .replaceFirst(' ', 'T')
                              .replaceAll('ZZ', 'Z'),
                        );
                        final nt = DateTime.parse(
                          msg.rawTime
                              .replaceFirst(' ', 'T')
                              .replaceAll('ZZ', 'Z'),
                        );
                        if (mt.difference(nt).inSeconds.abs() <= 10)
                          return true; // Sangat berdekatan = duplikat backend
                      } catch (_) {}
                    }
                  }
                  return false;
                });

                if (duplicateIdx != -1) {
                  debugPrint(
                    'AckPolling: 🚫 Mengabaikan pesan duplikat dari backend! ID: ${msg.id}',
                  );
                  isBackendDuplicate = true;
                  updatedCurrentIds.add(msg.id); // Anggap sudah diproses
                }
              }
              if (isBackendDuplicate) continue;

              // FIX: Cocokkan dengan pesan lokal yang belum punya ID nyata (kosong atau 'temp_')
              // Mencegah duplikasi ganda ketika TerimaPesan memberikan ID temp_ lalu AckPolling memberikan ID asli
              bool matchedPending = false;
              if (msg.isMe) {
                final cleanNew = msg.content.trim().toLowerCase().replaceAll(
                  RegExp(r'\s+'),
                  '',
                );
                final matchIdx = _messages.indexWhere((m) {
                  if (!m.isMe || (!m.id.isEmpty && !m.id.startsWith('temp_')))
                    return false;
                  final cleanM = m.content.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    '',
                  );

                  if (cleanM.isNotEmpty &&
                      cleanNew.isNotEmpty &&
                      (cleanM == cleanNew ||
                          cleanNew.contains(cleanM) ||
                          cleanM.contains(cleanNew))) {
                    return true;
                  }

                  if (msg.messageType != MessageType.text &&
                      m.messageType == msg.messageType) {
                    if (m.time == msg.time) return true;
                    // FIX: Cocokkan voice note berdasarkan nama file audio
                    if (m.messageType == MessageType.voice &&
                        m.audioPath != null &&
                        msg.audioPath != null) {
                      final nameLocal = m.audioPath!
                          .split('?')
                          .first
                          .split('/')
                          .last;
                      final nameServer = msg.audioPath!
                          .split('?')
                          .first
                          .split('/')
                          .last;
                      if (nameLocal.isNotEmpty &&
                          nameServer.isNotEmpty &&
                          (nameLocal == nameServer ||
                              nameServer.contains(nameLocal) ||
                              nameLocal.contains(nameServer))) {
                        return true;
                      }
                    }
                  }

                  return false;
                });

                if (matchIdx != -1) {
                  final existingMsg = _messages[matchIdx];
                  final keepAudioPath =
                      existingMsg.messageType == MessageType.voice &&
                          existingMsg.audioPath != null &&
                          existingMsg.audioPath!.isNotEmpty &&
                          File(existingMsg.audioPath!).existsSync()
                      ? existingMsg.audioPath
                      : (msg.audioPath ?? existingMsg.audioPath);

                  _messages[matchIdx] = _messages[matchIdx].copyWith(
                    id: msg.id,
                    ack: msg.ack,
                    status: msg.ack >= 3
                        ? MessageStatus.delivered
                        : MessageStatus.sent,
                    audioPath: keepAudioPath,
                    audioDuration: existingMsg.audioDuration > 0
                        ? existingMsg.audioDuration
                        : msg.audioDuration,
                  );
                  matchedPending = true;
                  updatedCurrentIds.add(
                    msg.id,
                  ); // Tandai sudah diproses agar else-if block di bawah bekerja dengan baik
                  debugPrint(
                    'AckPolling: ✅ Matched local message! Assigned ID ${msg.id}',
                  );
                } else {
                  // LOG WHY IT FAILED
                  debugPrint(
                    'AckPolling: ❌ Failed to match local message for content: "${msg.content}"',
                  );
                  for (final m in _messages.where(
                    (m) => m.isMe && (m.id.isEmpty || m.id.startsWith('temp_')),
                  )) {
                    final cleanM = m.content.trim().toLowerCase().replaceAll(
                      RegExp(r'\s+'),
                      '',
                    );
                    debugPrint('   -> Compared with local: "${m.content}"');
                    debugPrint('   -> Clean API: "$cleanNew"');
                    debugPrint('   -> Clean Local: "$cleanM"');
                  }
                }
              } else {
                // UPDATE: Cocokkan pesan masuk instan 'temp_sub_' dengan pesan server resmi
                final cleanNew = msg.content.trim().toLowerCase().replaceAll(
                  RegExp(r'\s+'),
                  '',
                );
                final matchIdx = _messages.indexWhere((m) {
                  if (m.isMe || !m.id.startsWith('temp_sub_')) return false;
                  final cleanM = m.content.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    '',
                  );
                  return cleanM.isNotEmpty &&
                      cleanNew.isNotEmpty &&
                      cleanM == cleanNew;
                });

                if (matchIdx != -1) {
                  _messages[matchIdx] = msg;
                  matchedPending = true;
                  updatedCurrentIds.add(msg.id);
                  debugPrint(
                    'ChatSync: ✅ Replaced instant temp_sub message with official server message ID: ${msg.id}',
                  );
                }
              }
              if (matchedPending) continue;

              debugPrint(
                'AckPolling ADDING NEW MESSAGE: ID=${msg.id}, Content=${msg.content}, Type=${msg.messageType}, IsMe=${msg.isMe}',
              );
              _messages.add(msg);
              hasNewMessages = true;
              if (!msg.isMe) {
                newCustomerIncomingMessages.add(msg);
              }
            } else if (msg.id.isNotEmpty) {
              final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
              if (existingIdx != -1) {
                final oldMsg = _messages[existingIdx];
                if (msg.ack > oldMsg.ack) {
                  _messages[existingIdx] = _messages[existingIdx].copyWith(
                    ack: msg.ack,
                    status: msg.ack >= 3
                        ? MessageStatus.delivered
                        : MessageStatus.sent,
                  );
                }
              }
            }
          }

          if (hasNewMessages) {
            // Lakukan sorting lokal lagi untuk memastikan urutan total tidak berantakan
            _messages.sort((a, b) {
              if (a.rawTime.isEmpty || b.rawTime.isEmpty) return 0;
              try {
                String ta = a.rawTime;
                String tb = b.rawTime;
                if (!ta.endsWith('Z') && !ta.contains('+') && ta.length >= 19)
                  ta += 'Z';
                if (!tb.endsWith('Z') && !tb.contains('+') && tb.length >= 19)
                  tb += 'Z';
                return DateTime.parse(ta).compareTo(DateTime.parse(tb));
              } catch (_) {
                return 0;
              }
            });

            // FIX: Aggressive deduplication pasca-polling
            // Hapus duplikat yang mungkin lolos (pesan terkirim dengan teks sama dan waktu berdekatan)
            final uniqueMessages = <Message>[];
            for (final m in _messages) {
              if (m.isMe &&
                  m.messageType == MessageType.text &&
                  m.content.isNotEmpty) {
                final cleanM = m.content.trim().toLowerCase().replaceAll(
                  RegExp(r'\s+'),
                  '',
                );
                final isDuplicate = uniqueMessages.any((existing) {
                  if (!existing.isMe ||
                      existing.messageType != MessageType.text)
                    return false;
                  final cleanExisting = existing.content
                      .trim()
                      .toLowerCase()
                      .replaceAll(RegExp(r'\s+'), '');
                  if (cleanM == cleanExisting) {
                    // Cek kedekatan waktu
                    if (m.rawTime.isNotEmpty && existing.rawTime.isNotEmpty) {
                      try {
                        final mt = DateTime.parse(
                          m.rawTime
                              .replaceFirst(' ', 'T')
                              .replaceAll('ZZ', 'Z'),
                        );
                        final et = DateTime.parse(
                          existing.rawTime
                              .replaceFirst(' ', 'T')
                              .replaceAll('ZZ', 'Z'),
                        );
                        if (mt.difference(et).inSeconds.abs() <= 15)
                          return true; // Sangat berdekatan = hapus
                      } catch (_) {}
                    }
                  }
                  return false;
                });
                if (isDuplicate) {
                  debugPrint(
                    'AckPolling Cleanup: 🗑️ Menghapus duplikat agresif -> ${m.content}',
                  );
                  continue; // Jangan masukkan ke uniqueMessages
                }
              }
              uniqueMessages.add(m);
            }
            _messages = uniqueMessages;

            if (mounted) {
              setState(() {
                // UI update trigger
              });
              _savePersistentMessages();
              _syncLastMessageToProvider();
            }

            if (newCustomerIncomingMessages.length > 1) {
              // Jika ada banyak pesan masuk sekaligus dari lawan bicara, jangan langsung gulir ke paling bawah,
              // melainkan posisikan penanda di awal pesan baru tersebut dan tampilkan tombol scroll ke bawah dengan counter.
              if (mounted) {
                setState(() {
                  _firstUnreadMessageId ??=
                      newCustomerIncomingMessages.first.id;
                  _initialUnreadCount =
                      (_initialUnreadCount > 0 ? _initialUnreadCount : 0) +
                      newCustomerIncomingMessages.length;
                  _unreadIncomingCountWhileScrolled +=
                      newCustomerIncomingMessages.length;
                  _showScrollToBottomButton = true;
                });
              }
            } else if (_isNearBottom &&
                _unreadIncomingCountWhileScrolled == 0 &&
                _firstUnreadMessageId == null) {
              _scrollToBottom();
            } else {
              if (mounted) {
                setState(() {
                  if (newCustomerIncomingMessages.isNotEmpty) {
                    _unreadIncomingCountWhileScrolled +=
                        newCustomerIncomingMessages.length;
                    if (_firstUnreadMessageId != null) {
                      _initialUnreadCount += newCustomerIncomingMessages.length;
                    }
                  } else {
                    _unreadIncomingCountWhileScrolled++;
                    if (_firstUnreadMessageId != null) {
                      _initialUnreadCount++;
                    }
                  }
                  _showScrollToBottomButton = true;
                });
              }
            }
            try {
              final roomIdInt = int.tryParse(chat.id);
              if (roomIdInt != null) {
                SignalRService().sendReadCount(roomIdInt);
              }
            } catch (_) {}
          }
        });
      } else {
        debugPrint('ChatSync: ❌ API Error: ${response.error}');
      }
    } catch (e) {
      debugPrint('ChatSync: ❌ Error during sync: $e');
    } finally {
      _isSyncingMessages = false;
      if (_hasPendingSync && mounted) {
        _hasPendingSync = false;
        _fetchLatestMessagesImmediately(take: 25);
      }
    }
  }

  void _startChatSyncPolling() {
    debugPrint('ChatSync: Started polling timer.');
    _ackPollTimer?.cancel();
    // PERF: 2.5 detik terlalu agresif (24 request/menit per room). SignalR
    // sudah menangani pesan real-time, polling ini hanya jaring pengaman
    // untuk sinkronisasi ID/ack, jadi 6 detik sudah cukup.
    _ackPollTimer = Timer.periodic(const Duration(milliseconds: 6000), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _fetchLatestMessagesImmediately(take: 25);
    });
  }

  // FITUR: Koneksi Pesan Real-time (SignalR)
  // FUNGSI: Mendaftarkan listener WebSocket (SignalR) untuk menerima pesan masuk secara instan ke dalam UI, dan mengirim status "sudah dibaca".
  void _subscribeToSignalR() {
    _signalRSubscription?.cancel();
    _subSpvSubscription?.cancel();
    final signalR = SignalRService();

    // Listen to TerimaSubSpv / TerimaSubAgent for instant room update notifications
    _subSpvSubscription = signalR.onTerimaSubSpv.listen((data) {
      final roomData = data['room'] as Map<String, dynamic>? ?? {};
      final incomingRoomId = roomData['Id']?.toString() ?? '';
      if (incomingRoomId.isEmpty) return;

      final isMatch =
          incomingRoomId == chat.id ||
          (chat.contactId.isNotEmpty && incomingRoomId == chat.contactId) ||
          (chat.ctRealId.isNotEmpty && incomingRoomId == chat.ctRealId) ||
          (chat.link.isNotEmpty && incomingRoomId == chat.link) ||
          (chat.groupId.isNotEmpty && incomingRoomId == chat.groupId) ||
          (incomingRoomId.replaceAll(RegExp(r'[^0-9]'), '') ==
              chat.id.replaceAll(RegExp(r'[^0-9]'), ''));

      if (isMatch) {
        debugPrint(
          'ChatDetailPage: ⚡ Realtime TerimaSubSpv matched for room $incomingRoomId! Processing...',
        );

        // 1. INSTANT BUBBLE: Tampilkan pesan masuk seketika (0 ms delay) jika ada pesan baru dari lawan bicara
        final lastMsg = (roomData['LastMsg'] ?? roomData['lastMsg'] ?? '')
            .toString();
        final timeMsg = (roomData['TimeMsg'] ?? roomData['timeMsg'] ?? '')
            .toString();
        final sdrMsg = (roomData['SdrMsg'] ?? roomData['sdrMsg'] ?? '')
            .toString()
            .toLowerCase();
        final lastIsMe =
            roomData['LastIsMe'] == true ||
            roomData['lastIsMe'] == true ||
            sdrMsg == 'me';
        final upBy = roomData['UpBy']?.toString();
        final isFromCustomer = !lastIsMe && (upBy == null || upBy == '0');

        if (isFromCustomer &&
            lastMsg.isNotEmpty &&
            lastMsg != 'Site.Inbox.DeletedMessage') {
          final cleanLast = lastMsg.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            '',
          );
          final alreadyPresent = _messages.any((m) {
            final cleanM = m.content.trim().toLowerCase().replaceAll(
              RegExp(r'\s+'),
              '',
            );
            return cleanM == cleanLast;
          });

          if (!alreadyPresent && mounted) {
            DateTime parsedTime = DateTime.now();
            if (timeMsg.isNotEmpty) {
              try {
                String tStr = timeMsg;
                if (!tStr.endsWith('Z') &&
                    !tStr.contains('+') &&
                    tStr.length >= 19)
                  tStr += 'Z';
                parsedTime = DateTime.parse(tStr).toLocal();
              } catch (_) {}
            }

            final instantMsg = Message(
              id: 'temp_sub_${DateTime.now().millisecondsSinceEpoch}',
              content: lastMsg.contains('[-{=||=}-]') ? '📍 Location' : lastMsg,
              time: _formatFullTime(parsedTime),
              rawTime: timeMsg.isNotEmpty
                  ? timeMsg
                  : DateTime.now().toIso8601String(),
              isMe: false,
              status: MessageStatus.read,
              fromId: chat.sender,
              roomId: chat.id,
            );
            setState(() {
              _addMessageInOrder(instantMsg);
              if (!_isNearBottom) {
                _unreadIncomingCountWhileScrolled++;
                if (_firstUnreadMessageId != null) {
                  _initialUnreadCount++;
                }
              }
            });
            if (_isNearBottom &&
                _unreadIncomingCountWhileScrolled == 0 &&
                _firstUnreadMessageId == null) {
              _scrollToBottom();
            } else {
              setState(() {
                _showScrollToBottomButton = true;
              });
            }
            _syncLastMessageToProvider();
            debugPrint(
              'ChatDetailPage: ⚡ Rendered instant message bubble from TerimaSubSpv!',
            );
          }
        }

        // 2. Sinkronisasi pesan resmi dari server (ID, attachment, metadata)
        _fetchLatestMessagesImmediately(take: 25);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _fetchLatestMessagesImmediately(take: 25);
        });
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _fetchLatestMessagesImmediately(take: 25);
        });
      }
    });

    // Listen to TerimaPesan (pre-parsed by SignalRService)
    _signalRSubscription = signalR.onTerimaPesan.listen((data) {
      final incomingRoomId = data['roomId']?.toString() ?? '';
      final messageData = data['message'] as Map<String, dynamic>? ?? {};
      final senderData = data['sender'] as Map<String, dynamic>?;

      debugPrint(
        'ChatDetailPage: TerimaPesan | room=$incomingRoomId | current=${chat.id}',
      );

      // ❗ FILTER: Hanya proses pesan yang ditujukan untuk ROOM INI (dengan pencocokan luas untuk pesan teman)
      final fromVal = messageData['From']?.toString() ?? '';
      final toVal = messageData['To']?.toString() ?? '';
      final ctIdVal = messageData['ContactId']?.toString() ?? '';
      final linkVal = messageData['Link']?.toString() ?? '';
      final ctRealIdVal = messageData['CtRealId']?.toString() ?? '';
      final msgRoomId = messageData['RoomId']?.toString() ?? '';

      // FIX: Jangan proses Telegram Saved Messages
      final isTelegram =
          chat.chId == '2' ||
          chat.channelType.toLowerCase().contains('telegram') ||
          chat.channelName.toLowerCase().contains('telegram');
      final sdrName =
          (senderData?['Name'] ??
                  messageData['Sender'] ??
                  messageData['SenderName'] ??
                  '')
              .toString()
              .toLowerCase();
      if (sdrName == 'saved messages' || sdrName == 'pesan tersimpan') {
        debugPrint(
          'ChatDetailPage: 🛡️ Ignored Telegram Saved Message from SignalR',
        );
        return;
      }

      // Channel & Account Isolation Guard: Cegah pesan channel/akun lain masuk (hanya untuk WhatsApp / non-Telegram)
      if (!isTelegram) {
        bool isSameChannel(String c1, String c2) {
          if (c1 == c2) return true;
          final isWa1 = c1 == '1' || c1 == '1557' || c1 == '1561';
          final isWa2 = c2 == '1' || c2 == '1557' || c2 == '1561';
          if (isWa1 && isWa2) return true;
          final isTg1 = c1 == '2';
          final isTg2 = c2 == '2';
          if (isTg1 && isTg2) return true;
          return false;
        }

        final incomingChId =
            (messageData['ChId'] ?? messageData['ch_id'])?.toString() ?? '';
        if (incomingChId.isNotEmpty &&
            chat.chId.isNotEmpty &&
            !isSameChannel(incomingChId, chat.chId)) {
          debugPrint(
            'ChatDetailPage: 🛡️ Ignored message from different channel: incoming $incomingChId vs current ${chat.chId}',
          );
          return;
        }

        final incomingAccId =
            (messageData['ChAccId'] ??
                    messageData['IdAccount'] ??
                    messageData['AccountId'])
                ?.toString() ??
            '';
        if (incomingAccId.isNotEmpty &&
            chat.accountId.isNotEmpty &&
            incomingAccId != '0' &&
            chat.accountId != '0' &&
            incomingAccId != chat.accountId) {
          debugPrint(
            'ChatDetailPage: 🛡️ Ignored message from different account: incoming $incomingAccId vs current ${chat.accountId}',
          );
          return;
        }
      }

      final isResolved =
          chat.status.toLowerCase() == 'resolved' ||
          chat.status == '3' ||
          chat.isArchived;

      final numericChatId = chat.id.replaceAll(RegExp(r'[^0-9\-]'), '');
      final numericIncomingId = incomingRoomId.replaceAll(
        RegExp(r'[^0-9\-]'),
        '',
      );
      final numericMsgRoomId = msgRoomId.replaceAll(RegExp(r'[^0-9\-]'), '');

      bool isMatch = false;

      // 1. Direct RoomId match (selalu valid untuk semua kondisi, termasuk resolved)
      if ((incomingRoomId.isNotEmpty && incomingRoomId == chat.id) ||
          (msgRoomId.isNotEmpty && msgRoomId == chat.id) ||
          (numericIncomingId.isNotEmpty &&
              numericChatId.isNotEmpty &&
              numericIncomingId == numericChatId) ||
          (numericMsgRoomId.isNotEmpty &&
              numericChatId.isNotEmpty &&
              numericMsgRoomId == numericChatId) ||
          (incomingRoomId.isNotEmpty &&
              incomingRoomId.replaceAll(RegExp(r'^[0-9]+_'), '') ==
                  chat.id.replaceAll(RegExp(r'^[0-9]+_'), '')) ||
          (msgRoomId.isNotEmpty &&
              msgRoomId.replaceAll(RegExp(r'^[0-9]+_'), '') ==
                  chat.id.replaceAll(RegExp(r'^[0-9]+_'), ''))) {
        isMatch = true;
      }

      // 2. Pencocokan ID kontak/channel (ContactId, CtRealId, Link, Phone, GroupId, Sender)
      // Hanya izinkan jika chat BUKAN status Resolved (mencegah chat resolved lama ter-update oleh sesi baru),
      // namun untuk Telegram tetap izinkan pencocokan identifier.
      if (!isMatch && (!isResolved || isTelegram)) {
        String cleanPhone(String s) => s
            .replaceAll('@s.whatsapp.net', '')
            .replaceAll('@c.us', '')
            .replaceAll('@g.us', '')
            .replaceAll(RegExp(r'^[0-9]+_'), '');

        String cleanDigits(String s) => s.replaceAll(RegExp(r'[^0-9\-]'), '');

        final candidateSet = <String>{};
        void addCandidate(String? v) {
          if (v == null) return;
          final s = v.trim();
          if (s.isEmpty ||
              s == '0' ||
              s == 'null' ||
              s == 'false' ||
              s == 'true' ||
              s == 'undefined')
            return;
          candidateSet.add(s);
          final cp = cleanPhone(s);
          if (cp.isNotEmpty && cp != s) candidateSet.add(cp);
          final cd = cleanDigits(s);
          if (cd.isNotEmpty && cd != s && cd != cp) candidateSet.add(cd);
        }

        addCandidate(incomingRoomId);
        addCandidate(msgRoomId);
        addCandidate(ctIdVal);
        addCandidate(ctRealIdVal);
        addCandidate(linkVal);
        addCandidate(fromVal);
        addCandidate(toVal);
        addCandidate(messageData['SenderId']?.toString());
        addCandidate(messageData['GroupId']?.toString());

        final myIdSet = <String>{};
        void addMyId(String? v) {
          if (v == null) return;
          final s = v.trim();
          if (s.isEmpty ||
              s == '0' ||
              s == 'null' ||
              s == 'false' ||
              s == 'true' ||
              s == 'undefined')
            return;
          myIdSet.add(s);
          final cp = cleanPhone(s);
          if (cp.isNotEmpty && cp != s) myIdSet.add(cp);
          final cd = cleanDigits(s);
          if (cd.isNotEmpty && cd != s && cd != cp) myIdSet.add(cd);
        }

        addMyId(chat.id);
        addMyId(chat.contactId);
        addMyId(chat.ctRealId);
        addMyId(chat.link);
        addMyId(chat.groupId);
        addMyId(chat.extId);
        if (RegExp(r'^[0-9\-\+\s]+$').hasMatch(chat.sender.trim())) {
          addMyId(chat.sender);
        }

        final intersection = candidateSet.intersection(myIdSet);
        if (intersection.isNotEmpty) {
          isMatch = true;
          debugPrint(
            'ChatDetailPage: ✅ Room matched via identifier: ${intersection.first}',
          );
        }
      }

      if (!isMatch) {
        final errMsg =
            '🛑 IGNORED! Incoming: $incomingRoomId (msgRoom: $msgRoomId) | ChatId: ${chat.id} | CtId: ${chat.contactId} | GrpId: ${chat.groupId} | RealId: ${chat.ctRealId}';
        debugPrint(errMsg);
        return;
      }

      // 🚨 AUTO-REPAIR CHAT ID DI REALTIME 🚨
      final realRoomId =
          (msgRoomId.isNotEmpty && msgRoomId != '0' && msgRoomId != 'null')
          ? msgRoomId
          : incomingRoomId;
      if ((chat.id.isEmpty ||
              chat.id == '0' ||
              chat.id == 'null' ||
              !RegExp(r'^[0-9]+$').hasMatch(chat.id)) &&
          realRoomId.isNotEmpty &&
          realRoomId != '0' &&
          realRoomId != 'null' &&
          RegExp(r'^[0-9]+$').hasMatch(realRoomId)) {
        chat = chat.copyWith(id: realRoomId);
        try {
          context.read<ChatProvider>().updateLocalChat(chat);
        } catch (_) {}
        debugPrint(
          'SignalR: 🛠️ REPAIRED EMPTY/NON-NUMERIC CHAT ID in Realtime to $realRoomId',
        );
      }

      // Pesan pantulan (echo-back) dari pesan yang kita kirim sendiri (AgentId ada = dikirim oleh agen/kita)
      // Daripada mengabaikannya secara langsung, kita periksa apakah nilai Ack diperbarui oleh server
      // sehingga kita bisa memperbarui status centang pesan secara real-time.
      final agentId = messageData['AgentId'];
      final isNobox = messageData['IsNobox'];
      final dirVal =
          messageData['Dir'] ?? messageData['Direction'] ?? messageData['dir'];
      final dirStr = dirVal?.toString().toLowerCase() ?? '';
      final isOutbound =
          messageData['IsOutbound'] ??
          messageData['IsOutBound'] ??
          messageData['Outbound'] ??
          messageData['isOutbound'];

      bool isEchoBack =
          (agentId != null && agentId != 0 && agentId.toString() != '0') ||
          (isNobox == 1 || isNobox == '1' || isNobox == true) ||
          (dirStr == '1' ||
              dirStr == '2' ||
              dirStr == 'out' ||
              dirStr == 'outbound' ||
              dirStr == 'true') ||
          (isOutbound == true || isOutbound == 'true' || isOutbound == 1);

      bool messageFoundLocally = false;
      if (isEchoBack) {
        final echoAck = messageData['Ack'] ?? messageData['ack'];
        final echoId = messageData['Id']?.toString() ?? '';

        if (echoId.isNotEmpty && _deletedMessageIds.contains(echoId)) {
          debugPrint(
            'SignalR: 🗑️ Mengabaikan pesan echo $echoId karena sudah dihapus user.',
          );
          return;
        }

        final rawMsg = messageData['Msg'];
        String echoMsg = '';
        if (rawMsg is String) {
          echoMsg = rawMsg;
        } else if (rawMsg is Map) {
          echoMsg =
              rawMsg['msg']?.toString() ??
              rawMsg['text']?.toString() ??
              rawMsg.toString();
        } else {
          echoMsg = rawMsg?.toString() ?? '';
        }
        if (echoMsg.isEmpty ||
            echoMsg.trim() == '{}' ||
            echoMsg.trim() == '[]') {
          echoMsg =
              messageData['Body']?.toString() ??
              messageData['Message']?.toString() ??
              messageData['Content']?.toString() ??
              '';
        }

        int newAck = 1;
        if (echoAck is int) {
          newAck = echoAck;
        } else if (echoAck is String) {
          newAck = int.tryParse(echoAck) ?? 1;
        }

        debugPrint(
          'SignalR: 💬 Own echo-back | id=$echoId | ack=$newAck | msg=$echoMsg',
        );

        if (mounted) {
          setState(() {
            // 1. Coba cocokkan pesan berdasarkan ID pesannya terlebih dahulu
            int matchIdx = -1;
            if (echoId.isNotEmpty) {
              matchIdx = _messages.indexWhere((m) => m.id == echoId && m.isMe);
            }
            // 2. Cadangan (Fallback): cocokkan berdasarkan isi konten untuk pesan yang belum punya ID (baru saja dikirim)
            if (matchIdx == -1 && echoMsg.isNotEmpty) {
              final cleanEcho = echoMsg.trim().toLowerCase().replaceAll(
                RegExp(r'\s+'),
                '',
              );
              for (int i = _messages.length - 1; i >= 0; i--) {
                if (_messages[i].isMe &&
                    (_messages[i].id.isEmpty ||
                        _messages[i].id.startsWith('temp_'))) {
                  // Cek apakah konten sama (abaikan spasi/trim)
                  final cleanMsg = _messages[i].content
                      .trim()
                      .toLowerCase()
                      .replaceAll(RegExp(r'\s+'), '');
                  if (cleanMsg == cleanEcho ||
                      _messages[i].content.trim() == echoMsg.trim()) {
                    matchIdx = i;
                    break;
                  }
                }
              }
            }

            if (matchIdx != -1) {
              messageFoundLocally = true;
              final existingMsg = _messages[matchIdx];
              final updatedId = echoId.isNotEmpty ? echoId : existingMsg.id;
              final updatedAck = newAck > existingMsg.ack
                  ? newAck
                  : existingMsg.ack;

              debugPrint(
                'SignalR: 🔄 Updating echo message at index $matchIdx | ID: $updatedId | Ack: ${existingMsg.ack} -> $updatedAck',
              );
              _messages[matchIdx] = existingMsg.copyWith(
                id: updatedId.isNotEmpty ? updatedId : null,
                ack: updatedAck,
                status: updatedAck >= 3
                    ? MessageStatus.delivered
                    : MessageStatus.sent,
              );
            }
          });
        }

        // FIX: Jika pesan ditemukan secara lokal, hentikan agar tidak duplikat.
        // TAPI jika TIDAK ditemukan (misal: dikirim dari Web Dashboard/Platform lain), jangan di-return!
        // Biarkan proses lanjut ke bawah agar pesan ini ditambahkan ke antarmuka aplikasi.
        if (messageFoundLocally) {
          if (mounted &&
              chat.id.isNotEmpty &&
              _localSentCache.containsKey(chat.id)) {
            final cacheList = _localSentCache[chat.id]!;
            final idxToRemove = cacheList.indexWhere(
              (c) => c.message.content.trim() == echoMsg.trim(),
            );
            if (idxToRemove != -1) cacheList.removeAt(idxToRemove);
          }
          return; // Don't add as a new message
        }
      }

      // Extract ID and check duplicate
      final incomingId = messageData['Id']?.toString() ?? '';
      if (incomingId.isNotEmpty && _deletedMessageIds.contains(incomingId)) {
        debugPrint(
          'SignalR: 🗑️ Mengabaikan pesan masuk $incomingId karena sudah dihapus user.',
        );
        return;
      }

      // Guard duplikasi: cek apakah pesan ini sudah ada di list (berdasarkan ID)
      int existingIdx = _messages.indexWhere((m) {
        if (incomingId.isNotEmpty && m.id == incomingId) return true;
        return false;
      });

      if (existingIdx != -1) {
        debugPrint(
          'SignalR: ⚠️ Pesan duplikat terdeteksi. ID=$incomingId. Updating status if needed.',
        );
        if (mounted) {
          setState(() {
            final existingMsg = _messages[existingIdx];
            // Jika ini pesan yang masuk kembali (duplicate), berarti sudah terkirim & diterima server
            final updatedAck = existingMsg.ack < 3 ? 3 : existingMsg.ack;
            if (existingMsg.ack != updatedAck) {
              _messages[existingIdx] = existingMsg.copyWith(
                ack: updatedAck,
                status: updatedAck >= 3
                    ? MessageStatus.delivered
                    : MessageStatus.sent,
              );
            }
          });
        }
        return;
      }

      // FIX: Jangan merakit objek Message secara manual karena akan menghilangkan semua attachment media (Voice Note, Gambar, dll).
      // Gunakan Message.fromJson agar semua parsing tipe pesan berjalan sempurna!
      final currentUserEmail = _currentUserEmail.isNotEmpty
          ? _currentUserEmail
          : (_authProvider?.currentUser ??
                (mounted
                    ? Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      ).currentUser
                    : '') ??
                '');

      try {
        // DEBUG: Log tipe pesan masuk via SignalR
        final incomingType =
            messageData['Type']?.toString() ??
            messageData['type']?.toString() ??
            messageData['BodyType']?.toString() ??
            '';
        final incomingMsg = messageData['Msg']?.toString() ?? '';
        if (incomingType.isNotEmpty && incomingType != '1') {
          debugPrint(
            '🔍 ChatDetail: SignalR message | Type=$incomingType | Msg="${incomingMsg.length > 100 ? incomingMsg.substring(0, 100) : incomingMsg}"',
          );
        }

        var parsedMessage = Message.fromJson(
          messageData,
          currentUserEmail,
          tenantId: _chatService.currentTenantId,
        );

        // Evaluasi isMe diserahkan ke model Message.fromJson()

        // SignalR messages from customers should always be read immediately when on this page
        Message newMessage = parsedMessage.copyWith(status: MessageStatus.read);

        // FIX: Populate missing reply content from local list untuk pesan realtime masuk
        if (newMessage.repliedMessage != null &&
            newMessage.repliedMessage!.content == 'Pesan terkait...') {
          final originalId = newMessage.repliedMessage!.id;
          try {
            final originalMsg = _messages.firstWhere(
              (m) => m.id == originalId || m.idAlias == originalId,
            );
            if (originalMsg.content.isNotEmpty) {
              newMessage = newMessage.copyWith(
                repliedMessage: newMessage.repliedMessage!.copyWith(
                  content: originalMsg.content,
                ),
              );
            }
          } catch (_) {}
        }

        // Incoming message verified for this room; proceed without blocking.

        if (mounted) {
          setState(() {
            // GUARD AKHIR ANTI-DUPLIKAT (Khusus pesan kita/keluar yang lolos dari pengecekan di atas)
            if (newMessage.isMe) {
              int matchIdx = _messages.indexWhere((m) {
                if (newMessage.id.isNotEmpty && m.id == newMessage.id) {
                  return true;
                }

                // UPDATE: Coba cocokkan jika ID lokal kosong ATAU berawalan 'temp_'
                if (m.isMe && (m.id.isEmpty || m.id.startsWith('temp_'))) {
                  // 1. Cocokkan berdasarkan teks eksak (bersihkan whitespace)
                  final cleanM = m.content.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    '',
                  );
                  final cleanNew = newMessage.content
                      .trim()
                      .toLowerCase()
                      .replaceAll(RegExp(r'\s+'), '');
                  if (cleanM.isNotEmpty &&
                      cleanNew.isNotEmpty &&
                      (cleanM == cleanNew ||
                          cleanNew.contains(cleanM) ||
                          cleanM.contains(cleanNew))) {
                    return true;
                  }

                  // 2. FIX: Untuk lampiran (Gambar, Dokumen, Voice Note), teks lokal ('📷 Photo')
                  // TIDAK AKAN COCOK dengan JSON/URL dari server. Cocokkan berdasarkan tipe media + waktu toleransi 2 detik.
                  if (newMessage.messageType != MessageType.text &&
                      m.messageType == newMessage.messageType) {
                    // FIX: Perluas toleransi waktu dari exact match menjadi 2 detik
                    if (m.rawTime.isNotEmpty && newMessage.rawTime.isNotEmpty) {
                      try {
                        final timeM = DateTime.parse(
                          m.rawTime.replaceAll('ZZ', 'Z'),
                        );
                        final timeNew = DateTime.parse(
                          newMessage.rawTime.replaceAll('ZZ', 'Z'),
                        );
                        if (timeNew.difference(timeM).inSeconds.abs() <= 2) {
                          return true;
                        }
                      } catch (_) {}
                    }
                    // Fallback: jika rawTime kosong, gunakan time (display time) dengan toleransi 2 detik
                    if (m.time.isNotEmpty && newMessage.time.isNotEmpty) {
                      try {
                        final timeM = DateTime.parse(
                          m.time.replaceAll('ZZ', 'Z'),
                        );
                        final timeNew = DateTime.parse(
                          newMessage.time.replaceAll('ZZ', 'Z'),
                        );
                        if (timeNew.difference(timeM).inSeconds.abs() <= 2) {
                          return true;
                        }
                      } catch (_) {}
                    }
                  }

                  // 3. FIX: Fallback waktu diperluas dari 60 ke 5 detik untuk pesan dengan tipe sama
                  if (m.messageType == newMessage.messageType &&
                      m.rawTime.isNotEmpty &&
                      newMessage.rawTime.isNotEmpty) {
                    try {
                      final timeM = DateTime.parse(
                        m.rawTime.replaceAll('ZZ', 'Z'),
                      );
                      final timeNew = DateTime.parse(
                        newMessage.rawTime.replaceAll('ZZ', 'Z'),
                      );
                      if (timeNew.difference(timeM).inSeconds.abs() <= 5) {
                        return true;
                      }
                    } catch (_) {}
                  }

                  // 4. Fallback tambahan: jika konten mirip (substring) dan tipe sama
                  if (m.messageType == newMessage.messageType) {
                    final contentM = m.content.trim().toLowerCase();
                    final contentNew = newMessage.content.trim().toLowerCase();
                    if (contentM.isNotEmpty &&
                        contentNew.isNotEmpty &&
                        (contentM.contains(contentNew) ||
                            contentNew.contains(contentM))) {
                      return true;
                    }
                  }
                }
                return false;
              });

              if (matchIdx == -1) {
                // LOG WHY IT FAILED
                debugPrint(
                  'TerimaPesan Guard: ❌ Failed to match local message for content: "${newMessage.content}"',
                );
                for (final m in _messages.where(
                  (m) => m.isMe && (m.id.isEmpty || m.id.startsWith('temp_')),
                )) {
                  final cleanM = m.content.trim().toLowerCase().replaceAll(
                    RegExp(r'\s+'),
                    '',
                  );
                  final cleanNew = newMessage.content
                      .trim()
                      .toLowerCase()
                      .replaceAll(RegExp(r'\s+'), '');
                  debugPrint('   -> Compared with local: "${m.content}"');
                  debugPrint('   -> Clean API: "$cleanNew"');
                  debugPrint('   -> Clean Local: "$cleanM"');
                }
              }
              if (matchIdx != -1) {
                debugPrint(
                  'SignalR: 🛑 Prevented duplicate isMe message at final add guard.',
                );

                final existingMsg = _messages[matchIdx];
                final updatedAck = (newMessage.ack >= 3)
                    ? newMessage.ack
                    : (existingMsg.ack < 3 ? 3 : existingMsg.ack);
                final updatedId = newMessage.id.isNotEmpty
                    ? newMessage.id
                    : existingMsg.id;

                _messages[matchIdx] = existingMsg.copyWith(
                  id: updatedId.isNotEmpty ? updatedId : null,
                  ack: updatedAck,
                  status: updatedAck >= 3
                      ? MessageStatus.delivered
                      : MessageStatus.sent,
                );

                if (chat.id.isNotEmpty &&
                    _localSentCache.containsKey(chat.id)) {
                  final cacheList = _localSentCache[chat.id]!;
                  final idxToRemove = cacheList.indexWhere(
                    (c) =>
                        c.message.content.trim() == newMessage.content.trim(),
                  );
                  if (idxToRemove != -1) cacheList.removeAt(idxToRemove);
                }
                return;
              }
            }

            _addMessageInOrder(newMessage);
            if (!_isNearBottom && !newMessage.isMe) {
              _unreadIncomingCountWhileScrolled++;
              if (_firstUnreadMessageId != null) {
                _initialUnreadCount++;
              }
            }
          });
          if (newMessage.isMe) {
            _scrollToBottom();
          } else if (_isNearBottom &&
              _unreadIncomingCountWhileScrolled == 0 &&
              _firstUnreadMessageId == null) {
            _scrollToBottom();
          } else {
            setState(() {
              _showScrollToBottomButton = true;
            });
          }
          _syncLastMessageToProvider();
        }
      } catch (e) {
        debugPrint('SignalR: ❌ Error parsing incoming message: $e');
      }

      // Tell server we've read this message
      try {
        final roomIdInt =
            int.tryParse(chat.id) ??
            int.tryParse(msgRoomId) ??
            int.tryParse(incomingRoomId);
        if (roomIdInt != null) {
          signalR.sendReadCount(roomIdInt);
        }
      } catch (e) {
        debugPrint('Error caught at _loadChatHistory (sendReadCount): $e');
      }
    });
  }

  /// Format time as "DD Mon, HH:mm" (e.g., "06 Jan, 12:29")
  String _formatFullTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  // FITUR: Scroll Otomatis ke Bawah
  // FUNGSI: Menganimasi daftar pesan secara instan ke pesan yang paling baru saat ada pesan masuk atau saat form dibuka.
  void _scrollToBottom({bool animate = true}) {
    _savePersistentMessages();
    if (_scrollController.hasClients) {
      // Jika sudah berada di bawah (offset <= 2.0 piksel pada reverse ListView),
      // tidak perlu memicu animasi berlebih agar tidak terjadi stutter/lag pada UI
      if (_scrollController.position.pixels <= 2.0) return;
      if (animate) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  // FITUR: Deteksi Pesan Belum Dibaca yang Terlewati Saat Scroll ke Bawah
  // FUNGSI: Mengurangi counter pada tombol scroll-to-bottom saat pesan unread dilewati ke bawah,
  //          dan mengunci angka agar tidak berkurang ketika user scroll kembali ke atas.
  void _checkUnreadMessagesPassed() {
    if (_firstUnreadMessageId == null || _firstUnreadMessageId!.isEmpty) return;
    if (!_scrollController.hasClients) return;

    final displayMessages = _messages.where((m) => !m.isSystemMessage).toList();
    final firstIdx = displayMessages.indexWhere(
      (m) =>
          m.id == _firstUnreadMessageId ||
          (m.idAlias != null && m.idAlias == _firstUnreadMessageId),
    );
    if (firstIdx == -1) return;

    final unreadList = <Message>[];
    for (int i = firstIdx; i < displayMessages.length; i++) {
      if (!displayMessages[i].isMe) {
        unreadList.add(displayMessages[i]);
      }
    }

    if (unreadList.isEmpty) return;

    final currentPixels = _scrollController.position.pixels;

    // Jika user sudah berada di bagian paling bawah obrolan (<= 30px),
    // tandai semua pesan unread sebagai sudah dilewati/terbaca.
    if (currentPixels <= 30.0) {
      _allInitialUnreadSeen = true;
      bool changed = false;
      for (final m in unreadList) {
        final effectiveId = m.id.isNotEmpty
            ? m.id
            : (m.idAlias ?? 'msg_${m.hashCode}');
        if (_passedUnreadMessageIds.add(effectiveId)) {
          changed = true;
        }
      }
      if (changed && mounted) {
        setState(() {});
      }
      return;
    }

    final listRenderBox =
        _messageListKey.currentContext?.findRenderObject() as RenderBox?;
    final listTop = (listRenderBox != null && listRenderBox.hasSize)
        ? listRenderBox.localToGlobal(Offset.zero).dy
        : null;
    final viewportHeight = (listRenderBox != null && listRenderBox.hasSize)
        ? listRenderBox.size.height
        : 600.0;

    // Titik fokus baca: Ketika bagian tengah pesan sudah naik melewati 35% atas layar obrolan
    final focusLine = listTop != null
        ? (listTop + (viewportHeight * 0.35).clamp(120.0, 220.0))
        : null;

    // Hitung juga berbasis rasio penurunan scroll offset dari posisi awal
    final totalDistance = _initialUnreadOffset > 30.0
        ? _initialUnreadOffset
        : 0.0;
    final scrolledDistance = totalDistance > 0
        ? (totalDistance - currentPixels).clamp(0.0, totalDistance)
        : 0.0;
    final slice = totalDistance > 0 ? (totalDistance / unreadList.length) : 0.0;

    bool hasChanges = false;

    for (int i = 0; i < unreadList.length; i++) {
      final msg = unreadList[i];
      final effectiveId = msg.id.isNotEmpty
          ? msg.id
          : (msg.idAlias ?? 'msg_${msg.hashCode}');
      if (_passedUnreadMessageIds.contains(effectiveId)) continue;

      bool passed = false;

      // 1. Cek posisi fisik gelembung pesan di layar
      final key = (i == 0) ? _firstUnreadKey : _unreadMessageKeys[effectiveId];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && focusLine != null && listTop != null) {
        final pos = box.localToGlobal(Offset.zero);
        final bubbleCenterY = pos.dy + (box.size.height * 0.5);
        final bubbleTopY = pos.dy;

        // Pesan dianggap sudah terbaca jika:
        // - Tengah pesan sudah melewati garis fokus baca (fokus bergeser ke pesan di bawahnya), ATAU
        // - Bagian atas pesan sudah mendekati batas atas layar obrolan (listTop + 40px)
        if (bubbleCenterY <= focusLine || bubbleTopY <= listTop + 40.0) {
          passed = true;
        }
      }

      // 2. Cek rasio progres scroll (fallback akurat jika widget belum/sudah keluar render tree)
      if (!passed && slice > 0) {
        if (scrolledDistance >= slice * (i + 0.5)) {
          passed = true;
        }
      }

      if (passed) {
        // Tandai pesan ini dan semua pesan sebelumnya sebagai sudah dilewati
        for (int j = 0; j <= i; j++) {
          final prior = unreadList[j];
          final priorId = prior.id.isNotEmpty
              ? prior.id
              : (prior.idAlias ?? 'msg_${prior.hashCode}');
          if (_passedUnreadMessageIds.add(priorId)) {
            hasChanges = true;
          }
        }
      }
    }

    if (_passedUnreadMessageIds.length >= unreadList.length) {
      _allInitialUnreadSeen = true;
    }

    if (hasChanges && mounted) {
      setState(() {});
    }
  }

  // FITUR: Scroll ke Pesan Terbaru (Paling Bawah)
  // FUNGSI: Saat membuka ruang obrolan, otomatis scroll ke pesan terbaru (bawah).
  //          Menandai semua pesan sebagai sudah dibaca dan menyembunyikan tombol scroll-to-bottom.
  void _handleInitialScroll() {
    if (!_scrollController.hasClients || _messages.isEmpty) return;
    if (_hasPositionedAtUnread) return;

    _hasPositionedAtUnread = true;
    setState(() {
      _allInitialUnreadSeen = true;
      _showScrollToBottomButton = false;
      _unreadIncomingCountWhileScrolled = 0;
      _firstUnreadMessageId = null;
      _firstUnreadDisplayIndex = null;
      _initialUnreadCount = 0;
      _initialUnreadOffset = 0.0;
      _passedUnreadMessageIds.clear();
      _unreadMessageKeys.clear();
    });

    // Scroll ke bawah (pesan terbaru) - animate: false untuk langsung di posisi
    _scrollToBottom(animate: false);

    // Pastikan posisi benar setelah layout selesai (frame kedua)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollToBottom(animate: false);
    });
  }

  // FITUR: Memuat Pesan Terdahulu (Pagination)
  // FUNGSI: Meminta data histori pesan yang lebih lama saat pengguna menggulir obrolan ke paling atas.
  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages || !_hasMoreMessages || chat.isArchived) return;

    setState(() => _isLoadingOlderMessages = true);

    final currentUserEmail = _currentUserEmail.isNotEmpty
        ? _currentUserEmail
        : (_authProvider?.currentUser ??
              (mounted
                  ? Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    ).currentUser
                  : '') ??
              '');

    final response = await _chatService.getMessageHistory(
      chat.id,
      currentUserEmail,
      skip: _messageSkip + _messagePageSize,
      take: _messagePageSize,
      contactId: chat.contactId,
      groupId: chat.groupId,
      ctRealId: chat.ctRealId,
    );

    if (mounted) {
      setState(() {
        _isLoadingOlderMessages = false;
        if (response.isError ||
            response.data == null ||
            response.data!.isEmpty) {
          _hasMoreMessages = false;
          debugPrint('ChatDetail: No more older messages');
        } else {
          final olderMessages = response.data!;
          debugPrint(
            'ChatDetail: Loaded ${olderMessages.length} older messages',
          );

          // Deduplicate by message ID
          final existingIds = _messages
              .map((m) => m.id)
              .where((id) => id.isNotEmpty)
              .toSet();
          final uniqueOlder = olderMessages
              .where(
                (m) =>
                    (m.id.isEmpty || !existingIds.contains(m.id)) &&
                    !_deletedMessageIds.contains(m.id),
              )
              .toList();

          // Prepend older messages. Server returns ASCENDING [oldest, older].
          // We can directly insert them at the start of _messages.
          _messages.insertAll(0, uniqueOlder);
          _messageSkip += _messagePageSize;
          _invalidateDisplayMessagesCache();

          // Inject local replies for the older messages
          _injectLocalReplies(uniqueOlder).then((_) {
            if (mounted) setState(() {});
          });

          if (olderMessages.length < _messagePageSize) {
            _hasMoreMessages = false;
          }
        }
      });
    }
  }

  // FITUR: Inisialisasi State Obrolan
  // FUNGSI: Mengonfigurasi parameter ruangan obrolan saat halaman pertama kali dibuka, serta memicu pemuatan pesan awal dan listener WebSocket.
  void _initializeChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.chat != null) {
        chat = widget.chat!;
      } else {
        chat = ModalRoute.of(context)!.settings.arguments as ChatModel;
      }
      _chatProvider ??= Provider.of<ChatProvider>(context, listen: false);
      // HANYA tandai arsip berdasarkan RoomId (dan status bawaan chat). Jangan
      // gunakan chat.contactId agar room BARU dengan kontak lama tidak ikut
      // terkunci/terarsip oleh status arsip percakapan lama kontak yang sama.
      if (_chatProvider != null && _chatProvider!.isRoomArchived(chat.id)) {
        chat = chat.copyWith(isArchived: true);
      }
      _authProvider ??= Provider.of<AuthProvider>(context, listen: false);
      if (_currentUserEmail.isEmpty) {
        _currentUserEmail = _authProvider?.currentUser ?? '';
      }
      _statusProvider = Provider.of<ChatStatusProvider>(context, listen: false);
      _loadInitialMessages();
      _subscribeToSignalR();
      SignalRService().joinConversation(chat.id);
      if (chat.contactId.isNotEmpty && chat.contactId != chat.id) {
        SignalRService().joinConversation(chat.contactId);
      }
      if (chat.ctRealId.isNotEmpty && chat.ctRealId != chat.id) {
        SignalRService().joinConversation(chat.ctRealId);
      }

      // Background refresh detail room agar AccountId, LinkId, ExtId, dan GroupId selalu yang terbaru dari database
      _chatService
          .getDetailRoom(chat.id)
          .then((resp) {
            if (!mounted || resp.isError || resp.data == null) return;
            final d = resp.data!;
            final chAccId = d['ChAccId']?.toString();
            final chAccNm = d['ChAcc']?.toString();
            final linkId = d['CtId']?.toString() ?? d['LinkId']?.toString();
            final extId = d['CtIdExt']?.toString() ?? d['ExtId']?.toString();

            final rMap = d['Room'] is Map
                ? Map<String, dynamic>.from(d['Room'] as Map)
                : d;
            final rawGrpId =
                (rMap['GrpId'] ??
                        rMap['grp_id'] ??
                        rMap['GroupId'] ??
                        rMap['groupId'] ??
                        rMap['IdGroup'])
                    ?.toString();
            final rawGrpNm =
                (rMap['Grp'] ??
                        rMap['GroupNm'] ??
                        rMap['GroupName'] ??
                        rMap['group_name'])
                    ?.toString();
            final rawCtReal = rMap['CtRealId']?.toString();
            final isGrpFlag =
                rMap['IsGrp'] == 1 ||
                rMap['IsGrp'] == true ||
                rMap['IsGroup'] == 1 ||
                rMap['IsGroup'] == true;

            final isGrp =
                chat.isGroup ||
                isGrpFlag ||
                (rawGrpId != null && rawGrpId.isNotEmpty && rawGrpId != '0') ||
                (rawGrpNm != null &&
                    rawGrpNm.isNotEmpty &&
                    rawGrpNm != 'null') ||
                (rawCtReal != null && rawCtReal.startsWith('-'));

            final resolvedGrpId =
                (rawGrpId != null && rawGrpId.isNotEmpty && rawGrpId != '0')
                ? rawGrpId
                : ((rawCtReal != null && rawCtReal.startsWith('-'))
                      ? rawCtReal
                      : chat.groupId);

            // FIX: Update data kontak (nama & foto profil) dari respons DetailRoom
            // agar header, avatar, dan Chat List ikut sinkron tanpa keluar-masuk halaman.
            final contactMap = (d['ContactReal'] is Map)
                ? Map<String, dynamic>.from(d['ContactReal'] as Map)
                : (d['Contact'] is Map)
                ? Map<String, dynamic>.from(d['Contact'] as Map)
                : <String, dynamic>{};
            final newSender =
                (rMap['CtRealNm']?.toString() ??
                        rMap['CtNm']?.toString() ??
                        d['CtRealNm']?.toString() ??
                        contactMap['Name']?.toString() ??
                        contactMap['Nm']?.toString())
                    ?.trim();
            final rawAvatar =
                contactMap['Photo']?.toString() ??
                rMap['CtImg']?.toString() ??
                rMap['LinkImg']?.toString() ??
                d['Photo']?.toString();
            String? newAvatar;
            if (rawAvatar != null &&
                rawAvatar.isNotEmpty &&
                rawAvatar != 'null') {
              newAvatar = rawAvatar.startsWith('http')
                  ? rawAvatar
                  : 'https://id.nobox.ai/upload/${rawAvatar.replaceAll('\\', '/')}';
            }

            setState(() {
              chat = chat.copyWith(
                accountId:
                    (chAccId != null && chAccId.isNotEmpty && chAccId != '0')
                    ? chAccId
                    : chat.accountId,
                channelName:
                    (chAccNm != null &&
                        chAccNm.isNotEmpty &&
                        chAccNm != 'Not Found')
                    ? chAccNm
                    : chat.channelName,
                contactId: isGrp
                    ? ''
                    : ((linkId != null && linkId.isNotEmpty && linkId != '0')
                          ? linkId
                          : chat.contactId),
                link: (linkId != null && linkId.isNotEmpty && linkId != '0')
                    ? linkId
                    : chat.link,
                extId: isGrp
                    ? ''
                    : ((extId != null && extId.isNotEmpty)
                          ? extId
                          : chat.extId),
                isGroup: isGrp,
                groupId:
                    (resolvedGrpId != null &&
                        resolvedGrpId.isNotEmpty &&
                        resolvedGrpId != '0')
                    ? resolvedGrpId
                    : chat.groupId,
                groupName:
                    (rawGrpNm != null &&
                        rawGrpNm.isNotEmpty &&
                        rawGrpNm != 'null')
                    ? rawGrpNm
                    : chat.groupName,
                sender:
                    (newSender != null &&
                        newSender.isNotEmpty &&
                        newSender != 'null')
                    ? newSender
                    : chat.sender,
                avatarUrl: (newAvatar != null && newAvatar.isNotEmpty)
                    ? newAvatar
                    : chat.avatarUrl,
              );
            });

            // Update nama & avatar ke ChatProvider agar daftar chat & header ikut sinkron.
            final chatProvForDetail = _chatProvider;
            if (chatProvForDetail != null) {
              final provIdx = chatProvForDetail.allChats.indexWhere(
                (c) => c.id == chat.id,
              );
              if (provIdx != -1) {
                final providerChat = chatProvForDetail.allChats[provIdx];
                chatProvForDetail.updateLocalChat(
                  providerChat.copyWith(
                    sender: chat.sender.isEmpty
                        ? providerChat.sender
                        : chat.sender,
                    avatarUrl: chat.avatarUrl ?? providerChat.avatarUrl,
                  ),
                );
              }
            }

            debugPrint(
              'ChatDetail: ✅ Refreshed room details: ChAccId=$chAccId, isGroup=$isGrp, GrpId=${chat.groupId}, GrpNm=${chat.groupName}',
            );
          })
          .catchError((e) {
            debugPrint('ChatDetail: ⚠️ Background getDetailRoom error: $e');
          });
      // Polling dimulai setelah _loadInitialMessages selesai (di dalam fungsinya)
      // _fetchQuickReplies hanya dipanggil saat user mengetik '/' (lazy)
    });
  }

  // FITUR: Hapus Semua Pesan (Clear Chat Lokal)
  // FUNGSI: Menampilkan dialog konfirmasi dan mengosongkan state pesan saat ini secara lokal di perangkat.
  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text(
          'Are you sure you want to delete all messages in this conversation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _messages.clear();
                _invalidateDisplayMessagesCache();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Chat cleared')));
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // FITUR: Kustomisasi Latar Belakang Chat (Wallpaper/Warna)
  // FUNGSI: Menampilkan modal bagi pengguna untuk mengubah tampilan latar belakang ruangan obrolan (warna solid atau gambar galeri).
  void _showBackgroundPicker() {
    final settings = Provider.of<ChatSettingsProvider>(context, listen: false);
    final colors = [
      null,
      Colors.blueGrey[50],
      Colors.green[50],
      Colors.purple[50],
      Colors.amber[50],
      Colors.red[50],
      Colors.blue[50],
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Background',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Solid colors row
            const Text(
              'Solid Colors',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: colors.length,
                itemBuilder: (context, index) {
                  final color = colors[index];
                  final isSelected =
                      settings.backgroundImagePath == null &&
                      settings.backgroundColor == color;

                  return GestureDetector(
                    onTap: () {
                      settings.setBackgroundColor(color);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: color ?? Colors.grey[200],
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.blue, width: 3)
                            : null,
                      ),
                      child: color == null
                          ? const Icon(Icons.block, size: 20)
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Wallpaper image option
            const Text(
              'Wallpaper',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final XFile? picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1920,
                      maxHeight: 1920,
                      imageQuality: 90,
                    );
                    if (picked != null) {
                      settings.setBackgroundImage(picked.path);
                    }
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: settings.backgroundImagePath != null
                          ? Border.all(color: Colors.blue, width: 3)
                          : null,
                    ),
                    child: const Icon(
                      Icons.image,
                      color: Colors.blue,
                      size: 24,
                    ),
                  ),
                ),
                if (settings.backgroundImagePath != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(settings.backgroundImagePath!),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Current',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isSending = false;

  // =====================================================================
  // [KATA KUNCI: Kirim Pesan Teks | Send Message | REST API | SignalR]
  // [FITUR: Pengiriman Pesan Teks Obrolan]
  // [RENTANG: Baris ~2665 - 2755]
  // [FUNGSI: Mengirimkan teks yang diinputkan pengguna ke server (menggunakan
  //          REST API atau SignalR). Menerapkan optimistic UI update (pesan
  //          langsung muncul di layar sebelum response server), menangani
  //          status terkirim/pending, serta membersihkan input bar.]
  // =====================================================================
  void _sendMessage() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final isArchived = chat.isArchived || chatProvider.isRoomArchived(chat.id);
    if (_isSending || isArchived)
      return; // Mencegah pengiriman ganda atau pada chat terarsip

    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final targetReplyMsg = _repliedMessage;
    final newMessage = Message(
      content: content,
      isMe: true,
      time: timeString,
      rawTime: now.toUtc().toIso8601String(),
      status: MessageStatus.sent,
      repliedMessage: targetReplyMsg,
      ack: 1,
    );

    setState(() {
      _messages.add(newMessage);
      _messageController.clear();
      _repliedMessage = null;
    });

    _scrollToBottom();

    // FIX: Optimistic update for Chat List preview so it appears instantly when returning to list
    chatProvider.updateLocalLastMessage(chat.id, content, isFromMe: true);

    final messageIndex = _messages.indexOf(newMessage);

    final isTelegram =
        chat.chId == '2' ||
        chat.channelType.toLowerCase().contains('telegram') ||
        chat.channelName.toLowerCase().contains('telegram');

    bool isSuccess = false;
    String? errorMsg;

    // WHATSAPP & TELEGRAM: Menggunakan SignalR (KirimPesan)
    // Berdasarkan sejarah, SignalR adalah satu-satunya jalur yang 100% masuk ke NoBox AI.

    String finalContent = content;
    String? finalReplyId;
    String? finalReplyMsg;
    String? finalReplyFrom;
    String? finalReplyType;

    if (targetReplyMsg != null) {
      if (chat.chId == '2' ||
          chat.channelType.toLowerCase().contains('telegram') ||
          chat.channelName.toLowerCase().contains('telegram')) {
        // TELEGRAM: Backend NoBox kemungkinan besar membutuhkan ID internal (Primary Key) untuk meresolve balasan Telegram
        finalReplyId = targetReplyMsg.id;
      } else {
        // WHATSAPP & LAINNYA: Prioritaskan idAlias (ID asli dari channel eksternal)
        finalReplyId =
            (targetReplyMsg.idAlias != null &&
                targetReplyMsg.idAlias!.isNotEmpty)
            ? targetReplyMsg.idAlias
            : targetReplyMsg.id;
      }

      finalReplyMsg = targetReplyMsg.content;
      finalReplyFrom = targetReplyMsg.fromId;
      if (finalReplyFrom == null || finalReplyFrom.isEmpty) {
        finalReplyFrom = chat.accountId.isNotEmpty && chat.accountId != '0'
            ? chat.accountId
            : "0";
      }
      finalReplyType = "0";
    }

    final sendError = await chatProvider.sendMessageViaSignalR(
      chat: chat,
      type: "1", // 1 is for Text as used in Aplikasi
      msg: finalContent,
      replyId: finalReplyId,
      replyMsg: finalReplyMsg,
      replyFrom: finalReplyFrom,
      replyType: finalReplyType,
    );

    isSuccess = (sendError == null);
    if (!isSuccess) errorMsg = sendError ?? 'Failed to send via SignalR';

    // FIX: Jika pengiriman via SignalR gagal (karena koneksi atau validasi ID), lakukan fallback ke REST API Inbox/Send
    if (!isSuccess) {
      debugPrint(
        'ChatDetail: ⚠️ SignalR send failed ($errorMsg), attempting fallback via REST API Inbox/Send...',
      );
      try {
        final isGroupChat =
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

        final resolvedGroupId = isGroupChat
            ? (chat.groupId.isNotEmpty && chat.groupId != '0'
                  ? chat.groupId
                  : (isTelegram && chat.ctRealId.startsWith('-')
                        ? chat.ctRealId
                        : (isTelegram && chat.link.startsWith('-')
                              ? chat.link
                              : (chat.id.startsWith('-') ? chat.id : null))))
            : null;

        final resp = await _chatService.sendMessage(
          MessageRequest(
            receiver: chat.id.isNotEmpty && chat.id != '0'
                ? chat.id
                : (chat.ctRealId.isNotEmpty ? chat.ctRealId : chat.contactId),
            content: finalContent,
            accountId: _getResolvedAccountId(chatProvider),
            contactId: isGroupChat
                ? null
                : (chat.contactId.isNotEmpty ? chat.contactId : chat.link),
            extId: isGroupChat
                ? null
                : (chat.extId.isNotEmpty
                      ? chat.extId
                      : (chat.sender.replaceAll(RegExp(r'[^0-9]'), '').length >=
                                9
                            ? chat.sender
                            : null)),
            channelId: chat.chId,
            groupId: resolvedGroupId,
          ),
        );
        if (!resp.isError) {
          isSuccess = true;
          errorMsg = null;
          debugPrint(
            'ChatDetail: ✅ Pesan berhasil terkirim via REST API fallback!',
          );
        } else {
          errorMsg = resp.error ?? 'Gagal mengirim via SignalR & REST API';
          debugPrint('ChatDetail: ❌ REST API fallback failed: $errorMsg');
        }
      } catch (restErr) {
        debugPrint('ChatDetail: ❌ REST API exception: $restErr');
      }
    }

    // Find message by reference or by content to survive modifications
    int currentIndex = _messages.indexOf(newMessage);
    if (currentIndex == -1) {
      currentIndex = _messages.indexWhere(
        (m) =>
            m.content == newMessage.content &&
            m.isMe &&
            m.time == newMessage.time,
      );
    }

    // CACHE DULU WALAU USER SUDAH KELUAR HALAMAN (mounted = false)
    if (isSuccess) {
      final updatedMessage = currentIndex != -1
          ? _messages[currentIndex].copyWith(
              status: MessageStatus.delivered,
              ack: 2,
            )
          : newMessage.copyWith(status: MessageStatus.delivered, ack: 2);

      _localSentCache.putIfAbsent(chat.id, () => []);
      _localSentCache[chat.id]!.add(
        _CachedSentMessage(updatedMessage, DateTime.now()),
      );
      _savePersistentMessages();
      debugPrint(
        'LocalCache: Pesan (Sukses) disimpan ke cache walau user pindah halaman. Total cache[${chat.id}]: ${_localSentCache[chat.id]!.length}',
      );
      chatProvider.recordRecentSentMessage(chat.id, content);
      chatProvider.updateLocalLastMessage(chat.id, content, isFromMe: true);
    }

    if (mounted && currentIndex != -1) {
      if (isSuccess) {
        setState(() {
          _messages[currentIndex] = _messages[currentIndex].copyWith(
            status: MessageStatus.delivered,
            ack: 2,
          );
          _isSending = false;
        });

        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).updateLocalLastMessage(chat.id, content, isFromMe: true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _startChatSyncPolling();
        });
      } else {
        setState(() {
          _messages[currentIndex] = _messages[currentIndex].copyWith(ack: 4);
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $errorMsg'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  // ─────────────────────────────────────────────
  //  ATTACHMENT PANEL TOGGLE
  // ─────────────────────────────────────────────

  // FITUR: Toggle Panel Lampiran
  // FUNGSI: Membuka atau menutup panel menu lampiran (attachment) yang berisi opsi Kamera, Galeri, Video, Lokasi, dll.
  void _toggleAttachmentPanel() {
    setState(() {
      _showAttachmentPanel = !_showAttachmentPanel;
    });
  }

  // =====================================================================
  // [KATA KUNCI: Kamera | Camera Picker | Ambil Foto | Lampiran Kamera]
  // [FITUR: Ambil Foto dari Kamera & Kirim]
  // [RENTANG: Baris ~2880 - 2975]
  // [FUNGSI: Membuka kamera bawaan perangkat untuk memotret foto, menampilkan
  //          layar pratinjau (FilePreviewScreen), mengunggah ke server, dan
  //          mengirimkannya sebagai pesan gambar ke obrolan.]
  // =====================================================================
  Future<void> _pickAndSendFromCamera() async {
    setState(() => _showAttachmentPanel = false);
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    // Show preview before sending
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewScreen(
          filePath: pickedFile.path,
          fileName: pickedFile.name,
          fileType: FilePreviewType.photo,
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    if (confirmed != true) return;

    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final newMessage = Message(
      content: '📷 Photo',
      isMe: true,
      time: timeString,
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imagePath: pickedFile.path,
    );

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    setState(() {
      _messages.add(newMessage);
    });

    _scrollToBottom();
    chatProvider.updateLocalLastMessage(chat.id, '📷 Photo', isFromMe: true);

    final messageIndex = _messages.indexOf(newMessage);

    final response = await _chatService.sendImageMessage(
      chat.id,
      pickedFile.path,
      accountId: _getResolvedAccountId(chatProvider),
      channelId: _isTelegramChat ? '2' : chat.chId,
      contactId:
          (chat.isGroup ||
              (_isTelegramChat &&
                  (chat.groupId.startsWith('-') ||
                      chat.ctRealId.startsWith('-'))))
          ? null
          : chat.contactId,
      link: chat.link,
      groupId: chat.groupId.isNotEmpty && chat.groupId != '0'
          ? chat.groupId
          : (_isTelegramChat && chat.ctRealId.startsWith('-')
                ? chat.ctRealId
                : null),
    );

    if (mounted && messageIndex < _messages.length) {
      if (!response.isError) {
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.delivered,
            imageUrl: response.data,
          );
        });
        Timer(const Duration(seconds: 2), () {
          if (mounted && messageIndex < _messages.length) {
            setState(() {
              _messages[messageIndex] = _messages[messageIndex].copyWith(
                status: MessageStatus.read,
              );
            });
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: ${response.error}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // =====================================================================
  // [KATA KUNCI: Video | Video Picker | Kirim Video | Lampiran Video]
  // [FITUR: Pilih Video dari Galeri & Kirim]
  // [RENTANG: Baris ~2980 - 3220]
  // [FUNGSI: Membuka galeri video perangkat dengan batas durasi maksimal 5 menit,
  //          menampilkan pratinjau, mengunggah video ke server NoBox, dan
  //          mengirimkannya sebagai pesan video.]
  // =====================================================================
  Future<void> _pickAndSendVideo() async {
    setState(() => _showAttachmentPanel = false);
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );

    if (pickedFile == null) return;

    // Show preview before sending
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewScreen(
          filePath: pickedFile.path,
          fileName: pickedFile.name,
          fileType: FilePreviewType.video,
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    if (confirmed != true) return;

    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final pLower = pickedFile.path.toLowerCase();
    final nLower = pickedFile.name.toLowerCase();
    final isStickerFile =
        pLower.endsWith('.webp') ||
        pLower.endsWith('.webm') ||
        pLower.endsWith('.tgs') ||
        pLower.endsWith('.gif') ||
        nLower.endsWith('.webp') ||
        nLower.endsWith('.webm') ||
        nLower.endsWith('.tgs') ||
        nLower.endsWith('.gif') ||
        nLower.contains('sticker') ||
        nLower.contains('stiker');

    final isAnimatedVideoSticker =
        pLower.endsWith('.webm') ||
        pLower.endsWith('.mp4') ||
        pLower.endsWith('.mov') ||
        nLower.endsWith('.webm') ||
        nLower.endsWith('.mp4') ||
        nLower.endsWith('.mov');

    final isTgsSticker = pLower.endsWith('.tgs') || nLower.endsWith('.tgs');

    // Static stickers: .webp, .png, .gif (non-animated)
    final isStaticSticker =
        isStickerFile && !isAnimatedVideoSticker && !isTgsSticker;

    final displayContent = isAnimatedVideoSticker
        ? '🎬 Sticker'
        : (isTgsSticker
              ? '🎬 Sticker'
              : (isStickerFile ? '🌟 Sticker' : '🎬 Video'));

    final newMessage = Message(
      content: displayContent,
      isMe: true,
      time: timeString,
      rawTime: now.toUtc().toIso8601String(), // Wajib ada ISO string agar urutan bubble stabil
      status: MessageStatus.sent,
      messageType: isStickerFile ? MessageType.sticker : MessageType.video,
      // Selalu pasang path lokal agar video dapat langsung di-preview.
      // imageUrl hanya untuk static sticker (.webp, .png, .gif) dan TGS.
      videoUrl: pickedFile.path,
      imageUrl: (isStaticSticker || isTgsSticker) ? pickedFile.path : null,
      ack: 1,
    );

    // Simpan pesan & waktu sebelumnya untuk rollback jika kirim video gagal
    final prevLastMessage = chat.lastMessage;
    final prevTime = chat.time;
    final prevLastMessageType = chat.lastMessageType;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    setState(() {
      _messages.add(newMessage);
    });

    _scrollToBottom();
    chatProvider.updateLocalLastMessage(
      chat.id,
      displayContent,
      lastMessageType: isStickerFile ? '16' : '4',
      isFromMe: true,
    );

    final messageIndex = _messages.indexOf(newMessage);

    final response = await _chatService.sendImageMessage(
      chat.id,
      pickedFile.path,
      accountId: _getResolvedAccountId(chatProvider),
      channelId: _isTelegramChat ? '2' : chat.chId,
      contactId:
          (chat.isGroup ||
              (_isTelegramChat &&
                  (chat.groupId.startsWith('-') ||
                      chat.ctRealId.startsWith('-'))))
          ? null
          : chat.contactId,
      link: chat.link,
      groupId: chat.groupId.isNotEmpty && chat.groupId != '0'
          ? chat.groupId
          : (_isTelegramChat && chat.ctRealId.startsWith('-')
                ? chat.ctRealId
                : null),
    );

    if (mounted && messageIndex < _messages.length) {
      if (!response.isError) {
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.delivered,
            videoUrl: response.data ?? pickedFile.path, // FIX: Simpan URL dari server
            ack: 2,
          );
        });
      } else {
        // GAGAL KIRIM: Update status pesan jadi ack 4
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(ack: 4);
        });

        // ROLLBACK POSISI DI CHAT LIST: Kembalikan waktu & pesan ke semula
        // agar obrolan TIDAK terlempar ke paling bawah daftar chat!
        chatProvider.updateLocalLastMessage(
          chat.id,
          prevLastMessage,
          overrideTime: prevTime,
          lastMessageType: prevLastMessageType,
          updateTimeAndPosition: false, // Pertahankan posisinya seperti sebelumnya
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to send video: ${response.error ?? "Upload error"}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 20, right: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  SEND PICKED IMAGE HELPER
  // ─────────────────────────────────────────────

  // FITUR: Mengirim Media Foto/Video (API Multipart)
  // FUNGSI: Mengunggah file (foto/video) menggunakan FormData (multipart/form-data) ke server, dan memperbarui status UI.
  Future<void> _sendPickedImage(XFile pickedFile) async {
    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final newMessage = Message(
      content: '📷 Photo',
      isMe: true,
      time: timeString,
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imagePath: pickedFile.path,
      ack: 1,
    );

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    setState(() {
      _messages.add(newMessage);
    });

    _scrollToBottom();
    chatProvider.updateLocalLastMessage(chat.id, '📷 Photo', isFromMe: true);

    final messageIndex = _messages.indexOf(newMessage);

    final response = await _chatService.sendImageMessage(
      chat.id,
      pickedFile.path,
      accountId: chat.accountId,
      channelId:
          (chat.chId == '2' ||
              chat.channelType.toLowerCase().contains('telegram') ||
              chat.channelName.toLowerCase().contains('telegram'))
          ? '2'
          : chat.chId,
      contactId: chat.contactId,
      link: chat.link,
      groupId: chat.groupId,
    );

    if (mounted && messageIndex < _messages.length) {
      if (!response.isError) {
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.delivered,
            imageUrl: response.data,
            ack: 2,
          );
        });
      } else {
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(ack: 4);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: ${response.error}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  PICK & SEND DOCUMENT
  // ─────────────────────────────────────────────

  // FITUR: Get Resolved AccountId
  // FUNGSI: Mengambil AccountId yang benar untuk Telegram/WhatsApp karena chat.accountId bisa saja kosong atau menunjuk ke bot lama yang tidak aktif.
  String _getResolvedAccountId(ChatProvider chatProvider) {
    String resolvedAccountId = chat.accountId;
    final chIdStr = chat.chId.toString().trim();
    final chTypeStr = chat.channelType.toLowerCase();
    final chNameStr = chat.channelName.toLowerCase();
    final isTelegram = chIdStr == '2' ||
        chTypeStr.contains('telegram') ||
        chTypeStr.contains('tg') ||
        chNameStr.contains('telegram') ||
        chNameStr.contains('tg');
    final isWa = chIdStr == '1' ||
        chIdStr == '1557' ||
        chIdStr == '1561' ||
        chTypeStr.contains('whatsapp') ||
        chTypeStr.contains('wa') ||
        chNameStr.contains('whatsapp') ||
        chNameStr.contains('wa');

    final accounts = chatProvider.cachedAccounts;
    bool isAccountActive(String id) {
      if (accounts == null || accounts.isEmpty) return true;
      final acc = accounts.where((a) => a['Id']?.toString() == id).firstOrNull;
      if (acc == null) return true;
      final status = acc['Status']?.toString();
      final condition = acc['Condition']?.toString();
      final note = (acc['NoteCondition']?.toString() ?? '').toLowerCase();
      return (status == '1' || status == 'true') &&
          (condition == '1' || condition == 'true' || note.contains('connect'));
    }

    if ((resolvedAccountId.isEmpty ||
            resolvedAccountId == '0' ||
            resolvedAccountId == 'null' ||
            !isAccountActive(resolvedAccountId)) &&
        accounts != null &&
        accounts.isNotEmpty) {
      try {
        final activeAcc = accounts.where((acc) {
          final status = acc['Status']?.toString();
          final condition = acc['Condition']?.toString();
          final note = (acc['NoteCondition']?.toString() ?? '').toLowerCase();
          final isConnected =
              (status == '1' || status == 'true') &&
              (condition == '1' ||
                  condition == 'true' ||
                  note.contains('connect'));
          if (!isConnected) return false;

          final ch = acc['Channel']?.toString() ?? '';
          final code = (acc['Code']?.toString() ?? '').toLowerCase();
          final accName = (acc['Name']?.toString() ?? '').toLowerCase();
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
        }
      } catch (e) {}
    }
    return resolvedAccountId;
  }

  // =====================================================================
  // [KATA KUNCI: Dokumen | File Picker | Kirim Dokumen | PDF | Lampiran File]
  // [FITUR: Pilih Dokumen & Kirim File]
  // [RENTANG: Baris ~3225 - 3350]
  // [FUNGSI: Menggunakan FilePicker untuk memilih dokumen dari memori perangkat
  //          (PDF, Word, Excel, ZIP, dsb.), menampilkan pratinjau dokumen,
  //          dan mengirimkannya sebagai lampiran file obrolan.]
  // =====================================================================
  Future<void> _pickAndSendDocument() async {
    setState(() => _showAttachmentPanel = false);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;

      final fileData = File(file.path!);
      final fileSize = await fileData.length();
      // Batasi 10 MB
      if (fileSize > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ukuran dokumen terlalu besar! Mohon pilih file di bawah 10 MB.',
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Show preview before sending
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _focusNode.unfocus();
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FilePreviewScreen(
            filePath: file.path!,
            fileName: file.name,
            fileType: FilePreviewType.document,
          ),
        ),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      _focusNode.unfocus();
      if (confirmed != true) return;

      final now = DateTime.now();
      final timeString = _formatFullTime(now);

      final newMessage = Message(
        content: '📄 ${file.name}',
        isMe: true,
        time: timeString,
        rawTime: now.toUtc().toIso8601String(),
        status: MessageStatus.sent,
        messageType: MessageType.document,
        documentName: file.name,
        ack: 1,
      );

      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      setState(() {
        _messages.add(newMessage);
      });

      _scrollToBottom();
      chatProvider.updateLocalLastMessage(
        chat.id,
        '📄 ${file.name}',
        isFromMe: true,
      );

      final messageIndex = _messages.indexOf(newMessage);

      final response = await _chatService.sendImageMessage(
        chat.id,
        file.path!,
        accountId: _getResolvedAccountId(chatProvider),
        channelId: _isTelegramChat ? '2' : chat.chId,
        contactId:
            (chat.isGroup ||
                (_isTelegramChat &&
                    (chat.groupId.startsWith('-') ||
                        chat.ctRealId.startsWith('-'))))
            ? null
            : chat.contactId,
        link: chat.link,
        groupId: chat.groupId.isNotEmpty && chat.groupId != '0'
            ? chat.groupId
            : (_isTelegramChat && chat.ctRealId.startsWith('-')
                  ? chat.ctRealId
                  : null),
        forceDocument: true,
      );

      if (!response.isError) {
        final updatedMsg = newMessage.copyWith(
          status: MessageStatus.delivered,
          documentUrl: response.data,
          ack: 2,
        );
        _localSentCache.putIfAbsent(chat.id, () => []);
        _localSentCache[chat.id]!.add(
          _CachedSentMessage(updatedMsg, DateTime.now()),
        );
        _savePersistentMessages();

        if (mounted && messageIndex < _messages.length) {
          setState(() {
            _messages[messageIndex] = updatedMsg;
          });
        }
      } else if (mounted && messageIndex < _messages.length) {
        setState(() {
          _messages[messageIndex] = _messages[messageIndex].copyWith(ack: 4);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal kirim dokumen: ${response.error}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().length > 60 ? '${e.toString().substring(0, 60)}...' : e}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // =====================================================================
  // [KATA KUNCI: Lokasi | Share Location | Bagikan Lokasi | Google Maps | GPS]
  // [FITUR: Bagikan Titik Lokasi / Maps]
  // [RENTANG: Baris ~3360 - 3450]
  // [FUNGSI: Membuka layar LocationPickerPage (peta) untuk memilih titik koordinat
  //          GPS, lalu mengirimkan tautan Google Maps beserta preview ke ruang chat.]
  // =====================================================================
  Future<void> _shareLocation() async {
    setState(() => _showAttachmentPanel = false);

    // Navigate to map picker
    final LatLng? pickedLocation = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (context) => const LocationPickerPage()),
    );

    if (pickedLocation == null || !mounted) return;

    final lat = pickedLocation.latitude;
    final lng = pickedLocation.longitude;
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final locationText = '📍 Lokasi saya\n$mapsUrl';

    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final newMessage = Message(
      content: locationText,
      isMe: true,
      time: timeString,
      rawTime: now.toUtc().toIso8601String(),
      status: MessageStatus.sent,
      ack: 1,
    );

    setState(() {
      _messages.add(newMessage);
    });

    _scrollToBottom();

    final messageIndex = _messages.indexOf(newMessage);

    final isTelegram =
        chat.chId == '2' ||
        chat.channelType.toLowerCase().contains('telegram') ||
        chat.channelName.toLowerCase().contains('telegram');
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    bool isSuccess = false;
    String? errorMsg;

    // 1. Coba kirim via SignalR terlebih dahulu
    // agar lokasi tercatat di database backend NoBox.
    final sendError = await chatProvider.sendMessageViaSignalR(
      chat: chat,
      type: "1", // Location is sent as text
      msg: locationText,
    );

    isSuccess = (sendError == null);
    if (!isSuccess) {
      errorMsg = sendError ?? 'Failed to send location via SignalR';
    }

    // 2. FALLBACK ke REST API jika SignalR gagal
    if (!isSuccess) {
      debugPrint(
        'ChatDetail: ⚠️ SignalR location send failed ($sendError). Mencoba fallback REST API...',
      );
      try {
        final isGroupChat =
            chat.isGroup ||
            (chat.groupId.isNotEmpty && chat.groupId != '0');

        final resolvedGroupId = isGroupChat ? chat.groupId : null;

        final resp = await _chatService.sendMessage(
          MessageRequest(
            receiver: chat.id.isNotEmpty && chat.id != '0'
                ? chat.id
                : chat.contactId,
            content: locationText,
            accountId: _getResolvedAccountId(chatProvider),
            contactId: isGroupChat
                ? null
                : (chat.contactId.isNotEmpty ? chat.contactId : chat.link),
            channelId: chat.chId,
            groupId: resolvedGroupId,
          ),
        );

        if (!resp.isError) {
          isSuccess = true;
          errorMsg = null;
          debugPrint(
            'ChatDetail: ✅ Lokasi berhasil terkirim via REST API fallback!',
          );
        } else {
          errorMsg = resp.error ?? 'Gagal mengirim lokasi';
        }
      } catch (restErr) {
        debugPrint(
          'ChatDetail: ❌ REST API location fallback exception: $restErr',
        );
        errorMsg = restErr.toString();
      }
    }

    if (isSuccess) {
      final updatedMsg = newMessage.copyWith(
        status: MessageStatus.delivered,
        ack: 2,
      );
      _localSentCache.putIfAbsent(chat.id, () => []);
      _localSentCache[chat.id]!.add(
        _CachedSentMessage(updatedMsg, DateTime.now()),
      );
      _savePersistentMessages();

      if (mounted && messageIndex < _messages.length) {
        setState(() {
          _messages[messageIndex] = updatedMsg;
        });
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).updateLocalLastMessage(
          chat.id,
          locationText,
          isFromMe: true,
        );
      }
    } else if (mounted && messageIndex < _messages.length) {
      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(ack: 4);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim lokasi: ${errorMsg ?? 'Unknown error'}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // =====================================================================
  // [KATA KUNCI: Foto | Galeri | Kirim Gambar | Image Picker | Lampiran Foto]
  // [FITUR: Pilih Foto dari Galeri & Kirim]
  // [RENTANG: Baris ~3460 - 3550]
  // [FUNGSI: Membuka galeri foto perangkat, menampilkan pratinjau FilePreviewScreen,
  //          mengunggah foto ke server, dan mengirimkannya sebagai pesan gambar.]
  // =====================================================================
  Future<void> _pickAndSendImage() async {
    setState(() => _showAttachmentPanel = false);
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    // Show preview before sending
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewScreen(
          filePath: pickedFile.path,
          fileName: pickedFile.name,
          fileType: FilePreviewType.photo,
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    if (confirmed != true) return;

    final now = DateTime.now();
    final timeString = _formatFullTime(now);

    final newMessage = Message(
      content: '📷 Photo',
      isMe: true,
      time: timeString,
      rawTime: now.toUtc().toIso8601String(),
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imagePath: pickedFile.path,
    );

    setState(() {
      _messages.add(newMessage);
    });

    _scrollToBottom();

    final messageIndex = _messages.indexOf(newMessage);

    final response = await _chatService.sendImageMessage(
      chat.id,
      pickedFile.path,
      accountId: _getResolvedAccountId(
        Provider.of<ChatProvider>(context, listen: false),
      ),
      channelId: _isTelegramChat ? '2' : chat.chId,
      contactId:
          (chat.isGroup ||
              (_isTelegramChat &&
                  (chat.groupId.startsWith('-') ||
                      chat.ctRealId.startsWith('-'))))
          ? null
          : chat.contactId,
      link: chat.link,
      groupId: chat.groupId.isNotEmpty && chat.groupId != '0'
          ? chat.groupId
          : (_isTelegramChat && chat.ctRealId.startsWith('-')
                ? chat.ctRealId
                : null),
    );

    if (!response.isError) {
      final updatedMsg = newMessage.copyWith(
        status: MessageStatus.delivered,
        imageUrl: response.data,
      );
      _localSentCache.putIfAbsent(chat.id, () => []);
      _localSentCache[chat.id]!.add(
        _CachedSentMessage(updatedMsg, DateTime.now()),
      );
      _savePersistentMessages();

      if (mounted && messageIndex < _messages.length) {
        setState(() {
          _messages[messageIndex] = updatedMsg;
        });
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).updateLocalLastMessage(chat.id, '📷 Photo', isFromMe: true);

        Timer(const Duration(seconds: 2), () {
          if (mounted && messageIndex < _messages.length) {
            setState(() {
              _messages[messageIndex] = _messages[messageIndex].copyWith(
                status: MessageStatus.read,
              );
            });
          }
        });
      }
    } else if (mounted && messageIndex < _messages.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send image: ${response.error}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  //  VOICE RECORDING
  // ─────────────────────────────────────────────

  // FITUR: Mulai Perekaman Suara (Voice Note)
  // FUNGSI: Mengecek izin mikrofon dan memulai proses perekaman audio langsung menggunakan library flutter_record.
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        debugPrint('Recording: Starting recording to $path');

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );

        debugPrint('Recording: Started successfully');

        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted && !_isRecordingPaused) {
            setState(() => _recordingSeconds++);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin mikrofon diperlukan untuk merekam suara'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  // FITUR: Kontrol Perekaman Suara
  // FUNGSI: Memberhentikan sementara proses perekaman audio tanpa menyimpannya.
  Future<void> _pauseRecording() async {
    try {
      await _audioRecorder.pause();
      setState(() => _isRecordingPaused = true);
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _audioRecorder.resume();
      setState(() => _isRecordingPaused = false);
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<String?> _finalizeRecording() async {
    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
          _recordedVoicePath = path;
          _recordedVoiceDuration = _recordingSeconds;
        });
      }
      return path;
    } catch (e) {
      debugPrint('Error finalizing recording: $e');
      setState(() {
        _isRecording = false;
        _isRecordingPaused = false;
      });
      return null;
    }
  }

  // FITUR: Kirim Voice Note (Audio API)
  // FUNGSI: Mengunggah file audio yang telah direkam ke server dan menambahkannya ke daftar pesan sebagai lampiran suara.
  Future<void> _sendVoiceNote(String path, int duration) async {
    try {
      final now = DateTime.now();
      final timeString = _formatFullTime(now);

      // Add voice message to chat immediately (with 'sent' status = uploading)
      final voiceMessage = Message(
        id: 'temp_voice_${DateTime.now().millisecondsSinceEpoch}',
        content: '',
        isMe: true,
        time: timeString,
        rawTime: now.toUtc().toIso8601String(),
        status: MessageStatus.sent,
        messageType: MessageType.voice,
        audioPath: path,
        audioDuration: duration,
      );
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      setState(() {
        _messages.add(voiceMessage);
      });
      _scrollToBottom();

      // FIX: Langsung beritahu daftar chat bahwa kita mengirim Voice Note sebelum proses upload dimulai
      // Sehingga kalau user langsung pencet tombol Back (keluar dari ruang obrolan), tulisan 'Voice Note' tetap muncul!
      chatProvider.updateLocalLastMessage(
        chat.id,
        '🎤 Pesan Suara',
        lastMessageType: '2',
        isFromMe: true,
      );

      final messageIndex = _messages.indexOf(voiceMessage);

      final response = await _chatService.sendImageMessage(
        chat.id,
        path,
        accountId: _getResolvedAccountId(chatProvider),
        channelId: _isTelegramChat ? '2' : chat.chId,
        contactId:
            (chat.isGroup ||
                (_isTelegramChat &&
                    (chat.groupId.startsWith('-') ||
                        chat.ctRealId.startsWith('-'))))
            ? null
            : chat.contactId,
        link: chat.link,
        groupId: chat.groupId.isNotEmpty && chat.groupId != '0'
            ? chat.groupId
            : (_isTelegramChat && chat.ctRealId.startsWith('-')
                  ? chat.ctRealId
                  : null),
      );

      if (!response.isError) {
        // Pertahankan file lokal asli yang ada di storage perangkat jika ada,
        // sehingga pemutaran audio instan tanpa perlu unduh ulang dari server (menghindari error 404/401)
        final localFileExists = path.isNotEmpty && File(path).existsSync();
        final updatedMsg = voiceMessage.copyWith(
          status: MessageStatus.delivered,
          audioPath: localFileExists ? path : response.data,
        );
        _localSentCache.putIfAbsent(chat.id, () => []);
        _localSentCache[chat.id]!.add(
          _CachedSentMessage(updatedMsg, DateTime.now()),
        );
        _savePersistentMessages();

        if (mounted && messageIndex < _messages.length) {
          setState(() {
            _messages[messageIndex] = updatedMsg;
          });

          Timer(const Duration(seconds: 2), () {
            if (mounted && messageIndex < _messages.length) {
              setState(() {
                _messages[messageIndex] = _messages[messageIndex].copyWith(
                  status: MessageStatus.read,
                );
              });
            }
          });
        }
      } else if (mounted && messageIndex < _messages.length) {
        debugPrint(
          '❌ Voice Note GAGAL: isError=${response.isError}, error=${response.error}, statusCode=${response.statusCode}',
        );
        debugPrint(
          '❌ chat.chId=${chat.chId}, chat.channelType=${chat.channelType}, chat.channelName=${chat.channelName}',
        );
        debugPrint(
          '❌ chat.link=${chat.link}, chat.contactId=${chat.contactId}, chat.accountId=${chat.accountId}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal kirim voice: ${response.error}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending voice note: $e');
    }
  }

  Future<void> _stopRecording() async {
    final path = await _finalizeRecording();
    if (path != null) {
      await _sendVoiceNote(path, _recordedVoiceDuration ?? 0);
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      if (mounted)
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
        });
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
      if (mounted)
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
        });
    }
  }

  // =====================================================================
  // [KATA KUNCI: Voice Note | Rekam Suara | Pesan Suara | Audio Recorder | Mic]
  // [FITUR: Rekam & Kirim Pesan Suara (Voice Note)]
  // [RENTANG: Baris ~3790 - 3860]
  // [FUNGSI: Membuka VoiceRecordingBottomSheet untuk merekam suara secara real-time,
  //          visualisasi waveform, pause/resume, playback, dan mengirimkan file audio ke obrolan.]
  // =====================================================================
  void _showVoiceBottomSheet() async {
    // Start recording first
    await _startRecording();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => VoiceRecordingBottomSheet(
        initialSeconds: _recordingSeconds,
        isRecording: _isRecording,
        isPaused: _isRecordingPaused,
        onPause: _pauseRecording,
        onResume: _resumeRecording,
        onStop: _finalizeRecording,
        onDelete: _cancelRecording,
        onReRecord: _startRecording,
        onSend: _sendVoiceNote,
        audioPlayer: _audioPlayer,
      ),
    );
  }

  // FITUR: Memutar Audio (Voice Note Player)
  // FUNGSI: Mengontrol pemutaran pesan suara (memutar, jeda, atau berpindah dari satu pesan suara ke pesan suara lainnya).
  Future<void> _togglePlayback(String path) async {
    try {
      final isUrl = path.startsWith('http');

      if (!isUrl) {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('Playback: FILE NOT FOUND: $path');
          return;
        }
      }

      if (_isPlaying && _currentlyPlayingPath == path) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.stop();
        setState(() {
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
        });

        if (isUrl) {
          await _audioPlayer.play(UrlSource(path));
        } else {
          await _audioPlayer.play(DeviceFileSource(path));
        }

        setState(() {
          _isPlaying = true;
          _currentlyPlayingPath = path;
        });
      }
    } catch (e) {
      debugPrint('Error toggling playback: $e');
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // FITUR: Emoji Keyboard Custom
  // FUNGSI: Menampilkan atau menyembunyikan panel emoji bawaan flutter, mengambil alih fokus dari keyboard sistem.
  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showEmojiPicker = true);
      });
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPos = selection.baseOffset >= 0
        ? selection.baseOffset
        : text.length;
    final newText =
        text.substring(0, cursorPos) + emoji.emoji + text.substring(cursorPos);
    final newCursorPos = cursorPos + emoji.emoji.length;
    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(
      offset: newCursorPos,
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────

  // FITUR: Merender Antarmuka Halaman Obrolan Utama
  // FUNGSI: Titik masuk utama untuk membangun UI Scaffold, AppBar (normal atau seleksi), Daftar Pesan, dan Area Input (termasuk banner jika diblokir/diarsipkan).
  @override
  Widget build(BuildContext context) {
    // OPTIMASI: Gunakan context.select hanya untuk status isBlocked agar perubahan pesan
    // atau chat lain di ChatProvider TIDAK memicu rebuild menyeluruh di halaman ini (menghilangkan lag)
    final bool isChatBlocked = context.select<ChatProvider, bool>((p) {
      try {
        return p.allChats.firstWhere((c) => c.id == chat.id).isBlocked;
      } catch (_) {
        return chat.isBlocked;
      }
    });

    final bool isChatArchived = context.select<ChatProvider, bool>((p) {
      return p.isRoomArchived(chat.id);
    });

    // FIX: Sinkronkan seluruh data kontak (nama, avatar, tags, funnel, deal, campaign,
    // agent, needReply) dari ChatProvider agar perubahan dari Edit Contact/Contact Info
    // maupun server/SignalR langsung ter-refleks di header & AppBar tanpa keluar-masuk halaman.
    final ChatModel? currentChat = context.select<ChatProvider, ChatModel?>((
      p,
    ) {
      try {
        return p.allChats.firstWhere((c) => c.id == chat.id);
      } catch (_) {
        return null;
      }
    });

    if (currentChat != null) {
      chat = chat.copyWith(
        sender: currentChat.sender,
        avatarUrl: currentChat.avatarUrl,
        tags: currentChat.tags,
        funnel: currentChat.funnel,
        deal: currentChat.deal,
        campaign: currentChat.campaign,
        agentName: currentChat.agentName,
        isBlocked: isChatBlocked,
        isArchived: isChatArchived || chat.isArchived,
        needReply: currentChat.needReply,
      );
    } else {
      chat = chat.copyWith(
        isBlocked: isChatBlocked,
        isArchived: isChatArchived || chat.isArchived,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvoked: (didPop) {
        if (!didPop && _isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedMessageKeys.clear();
          });
        }
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          if (_showEmojiPicker ||
              _showAttachmentPanel ||
              _isShowingQuickReply) {
            setState(() {
              _showEmojiPicker = false;
              _showAttachmentPanel = false;
              _isShowingQuickReply = false;
            });
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          appBar: _isSelectionMode
              ? _buildSelectionAppBar(isDark)
              : _buildAppBar(isDark),
          body: Consumer<ChatSettingsProvider>(
            builder: (context, settings, _) {
              return Container(
                decoration: BoxDecoration(
                  color: settings.backgroundImagePath == null
                      ? (settings.backgroundColor ??
                            (isDark
                                ? const Color(0xFF0B141A)
                                : const Color(0xFFF0F2F5)))
                      : null,
                  image: settings.backgroundImagePath != null
                      ? DecorationImage(
                          image: FileImage(File(settings.backgroundImagePath!)),
                          fit: BoxFit.cover,
                          colorFilter: isDark
                              ? ColorFilter.mode(
                                  Colors.black.withOpacity(0.4),
                                  BlendMode.darken,
                                )
                              : null,
                        )
                      : null,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          if (_showEmojiPicker ||
                              _showAttachmentPanel ||
                              _isShowingQuickReply) {
                            setState(() {
                              _showEmojiPicker = false;
                              _showAttachmentPanel = false;
                              _isShowingQuickReply = false;
                            });
                          }
                        },
                        behavior: HitTestBehavior.translucent,
                        child: Stack(
                          children: [
                            _buildMessageList(isDark),
                            // Tombol scroll-to-bottom dihilangkan
                            // if (_showScrollToBottomButton)
                            //   Positioned(
                            //     right: 16,
                            //     bottom: 12,
                            //     child: _buildScrollToBottomButton(isDark),
                            //   ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chat.isArchived || isChatArchived)
                            _buildArchivedBanner(isDark)
                          else if (!widget.isReadOnly) ...[
                            if (chat.isBlocked ||
                                chat.status.toLowerCase() == 'resolved')
                              const SizedBox.shrink()
                            else ...[
                              // state `_isShowingQuickReply` akan aktif dan memunculkan *overlay list* berisi template yang sudah di-cache.
                              if (_isShowingQuickReply &&
                                  _quickReplyTemplates.isNotEmpty)
                                _buildQuickReplyList(isDark),
                              if (_repliedMessage != null)
                                _buildReplyPreview(isDark),
                              _buildInputBar(isDark),
                              if (_showAttachmentPanel)
                                _buildAttachmentPanel(isDark),
                              if (_showEmojiPicker) _buildEmojiPicker(isDark),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Scroll Ke Bawah | Scroll To Bottom | Unread Badge | Floating Button]
  // [FITUR: Tombol Mengambang Pintasan Scroll ke Pesan Terbaru]
  // [RENTANG: Baris ~4040 - 4110]
  // [FUNGSI: Tombol melayang di pojok kanan bawah yang muncul saat pengguna scroll
  //          ke riwayat pesan lama di atas. Menampilkan badge jumlah pesan baru
  //          yang masuk dan mengembalikan posisi scroll ke bawah dalam satu ketukan.]
  // =====================================================================
  Widget _buildScrollToBottomButton(bool isDark) {
    final unreadBadgeCount = _remainingUnreadBadgeCount;

    return AnimatedScale(
      scale: _showScrollToBottomButton ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _allInitialUnreadSeen = true;
              _unreadIncomingCountWhileScrolled = 0;
              _firstUnreadMessageId = null;
              _firstUnreadDisplayIndex = null;
              _initialUnreadCount = 0;
              _initialUnreadOffset = 0.0;
              _passedUnreadMessageIds.clear();
              _unreadMessageKeys.clear();
            });
            _scrollToBottom();
          },
          borderRadius: BorderRadius.circular(25),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.grey.shade300,
                width: 0.8,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.keyboard_double_arrow_down_rounded,
                  size: 24,
                  color: isDark ? Colors.white : AppTheme.textPrimary,
                ),
                if (unreadBadgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Center(
                        child: Text(
                          '$unreadBadgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArchivedBanner(bool isDark) {
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF1F2C34) : Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              'This conversation has been archived.',
              style: TextStyle(
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedBanner(bool isDark) {
    return Container(
      width: double.infinity,
      color: Colors.red.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 20, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Text(
              'The contact is currently blocked.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolvedBanner(bool isDark) {
    // Warna hijau kebiruan (turquoise) persis seperti di dashboard web NoBox
    final Color resolvedColor = const Color(0xFF00C896);

    return Container(
      width: double.infinity,
      color: resolvedColor.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 20, color: resolvedColor),
            const SizedBox(width: 8),
            Text(
              'This conversation has been resolved.',
              style: TextStyle(
                color: resolvedColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  RESTORE ARCHIVED DIALOG
  // ─────────────────────────────────────────────

  // FITUR: Dialog Konfirmasi Buka Arsip
  // FUNGSI: Menampilkan popup konfirmasi untuk mengeluarkan obrolan ini dari folder arsip (unarchive).
  void _showRestoreArchivedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unarchive Conversation',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Are you sure you want to unarchive this conversation?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final chatProvider = Provider.of<ChatProvider>(
                context,
                listen: false,
              );
              await chatProvider.toggleArchive(chat.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Conversation unarchived successfully'),
                    backgroundColor: Colors.blue.shade700,
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Confirm', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  ARCHIVE CONVERSATION (from popup menu)
  // ─────────────────────────────────────────────

  // FITUR: Memproses Arsipkan Obrolan
  // FUNGSI: Menampilkan popup konfirmasi dan mengeksekusi API untuk memasukkan obrolan saat ini ke dalam daftar arsip.
  void _handleArchiveConversation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Archive Conversation',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Are you sure you want to archive this conversation?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx);

              // Show loading overlay
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => WillPopScope(
                  onWillPop: () async => false,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dialogBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(color: Colors.blue),
                          SizedBox(height: 16),
                          Text(
                            'Archiving conversation...',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              final chatProvider = Provider.of<ChatProvider>(
                context,
                listen: false,
              );
              await chatProvider.toggleArchive(chat.id);

              if (mounted) {
                Navigator.pop(context); // close loading overlay
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Conversation archived successfully'),
                      ],
                    ),
                    backgroundColor: Colors.blue.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
                Navigator.pop(context); // go back to chat list
              }
            },
            child: const Text('Confirm', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Status AppBar | Blocked | Resolved | Header Kontak Diblokir]
  // [FITUR: Header Status Obrolan (AppBar)]
  // [RENTANG: Baris ~4410 - 4550]
  // [FUNGSI: Menampilkan bilah header khusus ketika kontak berstatus Blocked
  //          atau percakapan telah diselesaikan (Resolved). Menyediakan teks
  //          status peringatan, tombol info kontak, dan menu opsi lanjutan.]
  // =====================================================================
  // FITUR: Buka Info Kontak
  // FUNGSI: Navigasi ke ContactInfoPage lalu refresh state halaman ini saat kembali,
  //          agar perubahan nama/avatar/tags/funnel/dll langsung ter-render realtime.
  Future<void> _openContactInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ContactInfoPage(chat: chat)),
    );
    if (mounted) {
      setState(() {});
    }
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    // ── STATUS APP BAR (Resolved / Blocked - Web Dashboard Style) ──
    final bool isResolved = chat.status.toLowerCase() == 'resolved';
    final bool isBlocked = chat.isBlocked;

    if (isResolved || isBlocked) {
      final Color statusColor = isBlocked
          ? const Color(0xFFE53935)
          : const Color(0xFF00C896);
      final String statusText = isBlocked
          ? 'This Contact has been blocked'
          : 'This conversation has been resolved.';

      final Color bgColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
      final Color iconColor = isDark ? Colors.white70 : Colors.black87;

      return AppBar(
        automaticallyImplyLeading: MediaQuery.of(context).size.width <= 800,
        backgroundColor: bgColor,
        surfaceTintColor: bgColor,
        iconTheme: IconThemeData(color: iconColor),
        leadingWidth: 30,
        titleSpacing: 12,
        title: Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Sidebar (Contact Info)
          IconButton(
            icon: CustomPaint(
              size: const Size(26, 22),
              painter: _SidebarIconPainter(color: iconColor),
            ),
            onPressed: () => _openContactInfo(),
          ),
          // =====================================================================
          // [KATA KUNCI: Menu Titik Tiga | Opsi Chat | Add Agent | Mark Resolved | Archive]
          // [FITUR: Menu Opsi Lanjutan Obrolan (Popup Menu)]
          // [RENTANG: Baris ~4465 - 4550]
          // [FUNGSI: Menu drop-down titik tiga di AppBar untuk menugaskan agen (Add Human Agent),
          //          menyelesaikan chat (Mark as Resolved), mengarsipkan (Archive), atau membuka bantuan.]
          // =====================================================================
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: iconColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'add_agent') {
                _showAddAgentDialog();
              } else if (value == 'mark_resolved') {
                _showResolveConfirmation();
              } else if (value == 'archive_conversation') {
                _handleArchiveConversation();
              } else if (value == 'help') {
                _openHelpUrl();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add_agent',
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt,
                      size: 24,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Add Human Agent',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mark_resolved',
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 24,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Mark as Resolved',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'archive_conversation',
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 24,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Archived Conversation',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'help',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 24, color: Colors.red),
                    const SizedBox(width: 16),
                    const Text(
                      'Help',
                      style: TextStyle(color: Colors.red, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    // =====================================================================
    // [KATA KUNCI: Archived AppBar | Chat Arsip | Restore Chat | Pulihkan Obrolan]
    // [FITUR: Header Percakapan Diarsipkan (AppBar)]
    // [RENTANG: Baris ~4560 - 4610]
    // [FUNGSI: Menampilkan bilah header saat obrolan berada di folder arsip.
    //          Menyediakan tombol pemulihan (restore) obrolan kembali ke daftar utama.]
    // =====================================================================
    if (chat.isArchived) {
      return AppBar(
        automaticallyImplyLeading: MediaQuery.of(context).size.width <= 800,
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue,
        surfaceTintColor: isDark ? AppTheme.darkSurface : Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
        leadingWidth: 30,
        titleSpacing: 12,
        title: const Text(
          'This conversation has been archived.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Sidebar (Contact Info)
          IconButton(
            icon: CustomPaint(
              size: const Size(26, 22),
              painter: _SidebarIconPainter(color: Colors.white),
            ),
            onPressed: () => _openContactInfo(),
          ),
          // Restore (styled as delete icon)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Restore Chat',
            onPressed: () => _showRestoreArchivedDialog(),
          ),
        ],
      );
    }

    // =====================================================================
    // [KATA KUNCI: Normal AppBar | Header Chat Utama | Profil Kontak | Channel Badge]
    // [FITUR: Header Obrolan Standar (AppBar)]
    // [RENTANG: Baris ~4610 - 4750]
    // [FUNGSI: Header utama ruang percakapan. Menampilkan avatar profil penerima,
    //          nama kontak, badge nomor/akun WhatsApp/Instagram, tombol profil
    //          kontak (sidebar), dan menu aksi titik tiga.]
    // =====================================================================
    return AppBar(
      automaticallyImplyLeading: MediaQuery.of(context).size.width <= 800,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue,
      surfaceTintColor: isDark ? AppTheme.darkSurface : Colors.blue,
      iconTheme: const IconThemeData(color: Colors.white),
      leadingWidth: 30,
      titleSpacing: 8,
      title: GestureDetector(
        onTap: () => _openContactInfo(),
        child: Row(
          children: [
            // Avatar
            Hero(
              tag: 'avatar_${chat.id}',
              child: AuthenticatedAvatar(
                imageUrl: chat.avatarUrl,
                size: 40,
                isGroup: chat.isGroup,
              ),
            ),
            const SizedBox(width: 10),
            // Name & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.sender,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Consumer<ChatStatusProvider>(
                    builder: (context, statusProvider, _) {
                      // Show WhatsApp icon + account name (channelName)
                      if (chat.channelName.isNotEmpty &&
                          chat.channelName != 'Not Found') {
                        return Row(
                          children: [
                            ChannelIcon(
                              chId: chat.chId,
                              channelName:
                                  '${chat.channelType} ${chat.channelName}',
                              size: 13,
                              isWhite: true,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                chat.channelName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: CustomPaint(
            size: const Size(26, 22),
            painter: _SidebarIconPainter(color: Colors.white),
          ),
          onPressed: () => _openContactInfo(),
        ),
        // FITUR: Menu Opsi Lanjutan (Titik Tiga Di Dalam Chat)
        // FUNGSI: Menampilkan dropdown menu di pojok kanan atas chat room untuk aksi tambahan pada tiket ini,
        // seperti menambahkan agen manusia, menandai selesai (Resolved), mengarsipkan chat, atau bantuan.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: (value) {
            if (value == 'add_agent') {
              _showAddAgentDialog();
            } else if (value == 'mark_resolved') {
              _showResolveConfirmation();
            } else if (value == 'archive_conversation') {
              _handleArchiveConversation();
            } else if (value == 'help') {
              _openHelpUrl();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'add_agent',
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_alt,
                    size: 24,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 16),
                  const Text('Add Human Agent', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'mark_resolved',
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 24,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Mark as Resolved',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'archive_conversation',
              child: Row(
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 24,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Archived Conversation',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'help',
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 24, color: Colors.red),
                  SizedBox(width: 16),
                  Text(
                    'Help',
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =====================================================================
  // [KATA KUNCI: Selection AppBar | Mode Seleksi Pesan | Multi Select | Reply | Forward | Copy | Delete]
  // [FITUR: Header Mode Seleksi Pesan (Selection AppBar)]
  // [RENTANG: Baris ~4800 - 4950]
  // [FUNGSI: Menampilkan bilah aksi atas ketika pengguna memilih satu atau beberapa
  //          pesan. Menyediakan tombol Balas (Reply), Teruskan (Forward), Salin (Copy),
  //          dan Hapus Pesan (Delete).]
  // =====================================================================
  PreferredSizeWidget _buildSelectionAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark
          ? AppTheme.darkSurface
          : const Color(
              0xFF1976D2,
            ), // Biru tua standar seperti di gambar referensi
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white),
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedMessageKeys.clear();
          });
        },
      ),
      title: Text(
        '${_selectedMessageKeys.length} selected',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      actions: [
        // Reply
        IconButton(
          icon: const Icon(Icons.reply, color: Colors.white),
          onPressed: () {
            if (_selectedMessageKeys.length == 1) {
              final targetKey = _selectedMessageKeys.first;
              final msg = _messages.firstWhere(
                (m) => _getMessageKey(m) == targetKey,
                orElse: () => _messages.first,
              );
              setState(() {
                _repliedMessage = msg;
                _isSelectionMode = false;
                _selectedMessageKeys.clear();
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pilih 1 pesan saja untuk reply')),
              );
            }
          },
        ),
        // Forward
        IconButton(
          icon: const Icon(Icons.forward, color: Colors.white),
          onPressed: () {
            _showForwardSelectedDialog();
          },
        ),
        // Copy / Salin
        IconButton(
          icon: const Icon(Icons.copy, color: Colors.white),
          onPressed: () {
            final buffer = StringBuffer();
            final selectedMsgs = _messages
                .where((m) => _selectedMessageKeys.contains(_getMessageKey(m)))
                .toList();
            for (final msg in selectedMsgs) {
              buffer.writeln(msg.content);
            }
            Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
            setState(() {
              _isSelectionMode = false;
              _selectedMessageKeys.clear();
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Pesan tersalin')));
          },
        ),

        // =====================================================================
        // [KATA KUNCI: Hapus Pesan | Delete Message | Dialog Hapus]
        // [FITUR: Dialog & Eksekusi Hapus Pesan Terpilih]
        // [RENTANG: Baris ~4885 - 4950]
        // [FUNGSI: Membuka dialog konfirmasi untuk menghapus semua pesan yang
        //          sedang diseleksi, memperbarui cache lokal, dan memanggil API backend.]
        // =====================================================================
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.white),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Message'),
                content: Text(
                  'Hapus ${_selectedMessageKeys.length} pesan yang dipilih untuk semua orang?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);

                      final selectedMsgs = _messages
                          .where(
                            (m) => _selectedMessageKeys.contains(
                              _getMessageKey(m),
                            ),
                          )
                          .toList();

                      // OPTIMISTIC UI UPDATE: Langsung sembunyikan pesan dari layar seketika tanpa loading!
                      final List<String> attemptingIds = [];
                      for (var m in selectedMsgs) {
                        if (m.id.isNotEmpty) attemptingIds.add(m.id);
                      }

                      setState(() {
                        _deletedMessageIds.addAll(attemptingIds);
                        _messages.removeWhere(
                          (m) =>
                              selectedMsgs.contains(m) ||
                              attemptingIds.contains(m.id),
                        );
                        if (_localSentCache[chat.id] != null) {
                          _localSentCache[chat.id]!.removeWhere(
                            (c) =>
                                selectedMsgs.contains(c.message) ||
                                attemptingIds.contains(c.message.id),
                          );
                        }
                        _isSelectionMode = false;
                        _selectedMessageKeys.clear();
                      });

                      // Sinkronkan data pesan yang dihapus ke ChatProvider SECARA INSTAN
                      final chatProv = Provider.of<ChatProvider>(
                        context,
                        listen: false,
                      );
                      for (var m in selectedMsgs) {
                        chatProv.recordDeletedMessage(
                          chat.id,
                          msgId: m.id,
                          content: m.content,
                          rawTime: m.rawTime,
                        );
                      }

                      _savePersistentMessages();

                      // Eksekusi penghapusan di latar belakang (Fire and Forget)
                      Future(() async {
                        bool hasError = false;
                        String errorMessage = '';

                        final futures = selectedMsgs.map((msg) async {
                          final msgId = msg.id;
                          if (msgId.isNotEmpty) {
                            try {
                              final resp = await _chatService.deleteMessage(
                                msgId,
                              );
                              if (resp.isError) {
                                final errText = resp.error ?? 'Unknown error';
                                if (!errText.contains('EntityNotFound') &&
                                    !errText.contains('Record not found')) {
                                  hasError = true;
                                  errorMessage = errText;
                                }
                              } else {
                                if (mounted) {
                                  Provider.of<ChatProvider>(
                                    context,
                                    listen: false,
                                  ).ignoreServerTime(chat.id, msg.rawTime);
                                }
                              }
                            } catch (e) {
                              hasError = true;
                              errorMessage = 'Error: $e';
                            }
                          }
                        });

                        await Future.wait(futures);

                        if (hasError && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Beberapa pesan gagal dihapus di server: $errorMessage',
                              ),
                            ),
                          );
                        }
                      });

                      // Update Last Message di Chat List (agar tidak menampilkan pesan yang sudah dihapus)
                      _syncLastMessageToProvider();
                      _showTopToast('Pesan dihapus', isError: false);
                    },
                    child: const Text(
                      'Hapus',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  ADD HUMAN AGENT DIALOG
  // ─────────────────────────────────────────────

  void _showAddAgentDialog() {
    showDialog(
      context: context,
      builder: (_) => AddAgentDialog(
        chatId: chat.id,
        contactId: chat.contactId,
        chId: chat.chId,
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  MARK AS RESOLVED
  // ─────────────────────────────────────────────

  void _showResolveConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Mark as Resolved',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.black,
            ),
          ),
          content: const Text(
            'Are you sure you want to mark this conversation as resolved? You won\'t be able to send messages after this.',
            style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
          ),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                _markAsResolved(); // Execute the actual function
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981), // Emerald/Green color
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Mark as Resolved',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        );
      },
    );
  }

  void _markAsResolved() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser ?? '';
    final currentAgentName = currentUser.isNotEmpty ? currentUser : 'Agent';

    debugPrint(
      '🔍 [DEBUG] _markAsResolved called with chat.id="${chat.id}", chat.contactId="${chat.contactId}", chat.ctRealId="${chat.ctRealId}", chat.link="${chat.link}"',
    );

    String resolveId = chat.id;
    if (resolveId.isEmpty ||
        resolveId == '0' ||
        resolveId == 'null' ||
        int.tryParse(resolveId.replaceAll(RegExp(r'[^0-9]'), '')) == null) {
      if (chat.contactId.isNotEmpty && chat.contactId != '0') {
        resolveId = chat.contactId;
      } else if (chat.link.isNotEmpty && chat.link != '0') {
        resolveId = chat.link;
      }
    }

    // Optimistic update pada state halaman detail dan ChatProvider agar
    // status "Resolved" beserta nama resolver langsung tampil tanpa menunggu
    // muat ulang dari server.
    setState(() {
      chat = chat.copyWith(status: 'Resolved', agentName: currentAgentName);
    });
    chatProvider.updateChatStatus(
      chat.id,
      'Resolved',
      agentName: currentAgentName,
    );
    if (resolveId != chat.id) {
      chatProvider.updateChatStatus(
        resolveId,
        'Resolved',
        agentName: currentAgentName,
      );
    }

    try {
      final response = await _chatService.resolveConversation(
        resolveId,
        accountId: chat.accountId,
      );
      if (mounted) {
        if (!response.isError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conversation marked as resolved')),
          );
          // Sinkronkan daftar chat di background tanpa memblokir
          chatProvider.refreshFirstPage(showLoading: false);
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: ${response.error}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ─────────────────────────────────────────────
  //  HELP ACTION
  // ─────────────────────────────────────────────

  void _openHelpUrl() async {
    final Uri url = Uri.parse(
      'https://ubig-co-1.gitbook.io/nobox-ai/real-base-ai-articles-english/menu/messages/inbox',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open help center page')),
        );
      }
    }
  }

  // =====================================================================
  // Cached filtered messages to avoid rebuilding list on every frame
  List<Message>? _cachedDisplayMessages;
  int _cachedMessagesHash = 0;

  void _invalidateDisplayMessagesCache() {
    _cachedDisplayMessages = null;
    _cachedMessagesHash = 0;
  }

  List<Message> get _displayMessages {
    final currentHash =
        (_messages.length * 31 +
                _messages.fold<int>(0, (h, m) => h + m.hashCode))
            as int;
    if (_cachedDisplayMessages != null && _cachedMessagesHash == currentHash) {
      return _cachedDisplayMessages!;
    }
    _cachedDisplayMessages = _messages
        .where((m) => !m.isSystemMessage)
        .toList();
    _cachedMessagesHash = currentHash;
    return _cachedDisplayMessages!;
  }

  // =====================================================================
  // [KATA KUNCI: Message List | Daftar Pesan | ListView Pesan | Bubble Chat | Riwayat Obrolan]
  // [FITUR: Daftar Tampilan Pesan Obrolan (Message List)]
  // [RENTANG: Baris ~5170 - 5330]
  // [FUNGSI: Merender daftar pesan dalam ruangan obrolan menggunakan ListView.builder
  //          (reverse: true). Menampilkan efek shimmer saat loading, status kosong
  //          jika belum ada pesan, pembatas tanggal otomatis, serta membungkus
  //          setiap pesan ke dalam widget MessageBubbleWidget.]
  // =====================================================================
  Widget _buildMessageList(bool isDark) {
    if (_isLoadingMessages) {
      return const MessageShimmerWidget();
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No conversation yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _debugApiState,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? Colors.orange.shade300
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final displayMessages = _displayMessages;

    // Status footer: shown at the bottom if archived or resolved
    final isResolved = chat.status.toLowerCase() == 'resolved';
    final hasStatusFooter = chat.isArchived || isResolved;
    final extraItems = 1 + (hasStatusFooter ? 1 : 0);
    final totalItems = displayMessages.length + extraItems;

    // Build a map for O(1) index lookup instead of O(n) indexOf
    final messageToIndex = <Message, int>{};
    for (int i = 0; i < displayMessages.length; i++) {
      messageToIndex[displayMessages[i]] = i;
    }

    // Align.topCenter + shrinkWrap ensures messages start from top when few,
    // while reverse: true keeps newest messages at bottom and auto-scroll works.
    // FIX: Always use shrinkWrap: false to enable ListView virtualization.
    // The Align(topCenter) handles "start from top when few messages" visually.
    return Align(
      key: _messageListKey,
      alignment: Alignment.topCenter,
      child: ListView.builder(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        reverse: true,
        shrinkWrap: false, // FIX: Disable shrinkWrap to enable virtualization
        addRepaintBoundaries: true,
        cacheExtent: 1000, // Increased cache for smoother fast scrolling
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          // With reverse: true, index 0 = bottom-most item

          // Index 0: Status footer (if applicable, positioned below the latest messages/day)
          if (hasStatusFooter && index == 0) {
            return RepaintBoundary(
              child: _buildStatusDivider(
                isResolved: isResolved && !chat.isArchived,
              ),
            );
          }

          // Adjust index for status footer offset
          final adjustedIndex = hasStatusFooter ? index - 1 : index;

          // Last index (top of screen): loading indicator or "No more messages"
          if (adjustedIndex == displayMessages.length) {
            return RepaintBoundary(child: _buildMessageListHeader());
          }

          // Map reversed index to message index (newest = index 0, oldest = last)
          final displayIndex = displayMessages.length - 1 - adjustedIndex;
          final message = displayMessages[displayIndex];
          // The message visually above this one (older) for date separator check
          final prevMessage = (displayIndex > 0)
              ? displayMessages[displayIndex - 1]
              : null;
          // Use O(1) map lookup instead of O(n) indexOf
          final realIndex = messageToIndex[message] ?? -1;

          // System message fallback
          if (message.isSystemMessage) {
            return RepaintBoundary(
              key: ValueKey('sys_${_getMessageKey(message)}'),
              child: _buildSystemMessage(message, isDark),
            );
          }

          // Date separator — show when this message has a different date from the one above it
          Widget? dateSeparator;
          if (prevMessage == null ||
              _shouldShowDateSeparator(prevMessage, message)) {
            dateSeparator = _buildDateSeparator(message, isDark);
          }

          // Normal chat bubble with swipe-to-reply + long-press selection
          final msgKey = _getMessageKey(message);
          final isSelected = _selectedMessageKeys.contains(msgKey);

          final isFirstUnread =
              (_firstUnreadMessageId != null &&
                  _firstUnreadMessageId!.isNotEmpty)
              ? (message.id == _firstUnreadMessageId ||
                    (message.idAlias != null &&
                        message.idAlias == _firstUnreadMessageId))
              : (_firstUnreadDisplayIndex != null &&
                    displayIndex == _firstUnreadDisplayIndex);

          final actualUnread = _actualUnreadCount;

          GlobalKey? unreadKey;
          if (isFirstUnread) {
            unreadKey = _firstUnreadKey;
          } else if (_firstUnreadMessageId != null && !message.isMe) {
            final effectiveId = message.id.isNotEmpty
                ? message.id
                : (message.idAlias ?? 'msg_${message.hashCode}');
            // Use existing key or create once - don't create during build
            unreadKey = _unreadMessageKeys[effectiveId];
            if (unreadKey == null) {
              unreadKey = GlobalKey();
              _unreadMessageKeys[effectiveId] = unreadKey;
            }
          }

          return RepaintBoundary(
            child: Column(
              key: ValueKey('col_$msgKey'),
              children: [
                if (dateSeparator != null) dateSeparator,
                // Divider "PESAN BELUM DIBACA" dihilangkan
                // if (isFirstUnread && actualUnread > 0)
                //   _buildUnreadMessagesDivider(actualUnread, isDark),
                Container(
                  key: unreadKey,
                  color: isSelected
                      ? (isDark
                            ? Colors.blue.withValues(alpha: 0.15)
                            : Colors.blue.withValues(alpha: 0.15))
                      : Colors.transparent,
                  child: MessageBubbleWidget(
                    key: ValueKey('bubble_$msgKey'),
                    message: message,
                    // FIX: Don't pass allMessages (huge list) to every bubble.
                    // Bubble only needs its own message data.
                    allMessages: null,
                    isSelected: isSelected,
                    onLongPress: () {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedMessageKeys.add(msgKey);
                      });
                    },
                    onTap: () {
                      if (_isSelectionMode) {
                        setState(() {
                          if (_selectedMessageKeys.contains(msgKey)) {
                            _selectedMessageKeys.remove(msgKey);
                            if (_selectedMessageKeys.isEmpty) {
                              _isSelectionMode = false;
                            }
                          } else {
                            _selectedMessageKeys.add(msgKey);
                          }
                        });
                      }
                    },
                    onReply: () {
                      setState(() => _repliedMessage = message);
                    },
                    onForward: () {
                      _showForwardDialog(message);
                    },
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied')),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Status Divider | Pembatas Status Chat | Resolved Divider | Archived Divider]
  // [FITUR: Garis Pembatas Status Percakapan]
  // [RENTANG: Baris ~5340 - 5390]
  // [FUNGSI: Menampilkan garis pemisah dan teks keterangan di bagian bawah daftar pesan
  //          apabila percakapan telah diselesaikan (Resolved) atau diarsipkan.]
  // =====================================================================
  Widget _buildStatusDivider({required bool isResolved}) {
    final textLabel = isResolved
        ? 'Percakapan ini telah diselesaikan'
        : 'Agent archived this conversation';
    final dateLabel = isResolved
        ? _formatBubbleTime(chat.time)
        : _archivedDateLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Divider(color: Colors.grey.shade400, thickness: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Text(
                      textLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (dateLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Divider(color: Colors.grey.shade400, thickness: 0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Date Separator | Pembatas Tanggal | Hari Ini | Kemarin]
  // [FITUR: Pembatas Tanggal Antar Pesan]
  // [RENTANG: Baris ~5395 - 5450]
  // [FUNGSI: Menentukan apakah harus menampilkan pembatas tanggal (misal: Hari ini,
  //          Kemarin, atau tanggal spesifik) di antara dua pesan yang dikirim pada hari berbeda.]
  // =====================================================================
  bool _shouldShowDateSeparator(Message prev, Message current) {
    final prevDate = _extractDate(prev.rawTime);
    final curDate = _extractDate(current.rawTime);
    if (prevDate == null || curDate == null) return false;
    return prevDate.day != curDate.day ||
        prevDate.month != curDate.month ||
        prevDate.year != curDate.year;
  }

  DateTime? _extractDate(String rawTime) {
    if (rawTime.isEmpty) return null;
    try {
      String iso = rawTime;
      if (!iso.endsWith('Z') && !iso.contains('+')) {
        iso += 'Z';
      }
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatBubbleTime(String rawTime) {
    if (rawTime.contains(', ')) {
      return rawTime.split(', ').last.trim();
    }
    return rawTime;
  }

  Widget _buildDateSeparator(Message message, bool isDark) {
    final date = _extractDate(message.rawTime);
    String label;
    if (date != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(date.year, date.month, date.day);
      final diff = today.difference(msgDay).inDays;
      if (diff == 0) {
        label = 'Today';
      } else if (diff == 1) {
        label = 'Kemarin';
      } else {
        final chatSettings = context.read<ChatSettingsProvider>();
        label = DateTimeHelper.formatDate(
          message.rawTime,
          chatSettings.dateFormat,
          fallback: message.time,
        );
      }
    } else {
      label = message.time;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.shade800.withOpacity(0.7)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  // FITUR: Pembatas Pesan Belum Dibaca (Unread Messages Divider)
  // FUNGSI: Menampilkan penanda visual dengan garis dan badge pill di atas pesan pertama yang belum dibaca
  Widget _buildUnreadMessagesDivider(int count, bool isDark) {
    final text = count > 1 ? '$count PESAN BELUM DIBACA' : 'PESAN BELUM DIBACA';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: isDark
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.blue.withOpacity(0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.blue.shade700.withOpacity(0.5)
                    : Colors.blue.shade200,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_unread_rounded,
                  size: 14,
                  color: isDark
                      ? Colors.blue.shade300
                      : const Color(0xFF2563EB),
                ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark
                        ? Colors.blue.shade300
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: isDark
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.blue.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  /// Swipe-to-reply gesture wrapper
  Widget _buildSwipeToReply({required Message message, required Widget child}) {
    double dragOffset = 0;
    bool triggered = false;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setLocalState(() {
              dragOffset = (dragOffset + details.delta.dx).clamp(0.0, 80.0);
              if (dragOffset >= 60 && !triggered) {
                triggered = true;
              }
            });
          },
          onHorizontalDragEnd: (details) {
            if (triggered) {
              setState(() => _repliedMessage = message);
            }
            setLocalState(() {
              dragOffset = 0;
              triggered = false;
            });
          },
          onHorizontalDragCancel: () {
            setLocalState(() {
              dragOffset = 0;
              triggered = false;
            });
          },
          child: Stack(
            children: [
              // Reply icon behind
              if (dragOffset > 0)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: AnimatedOpacity(
                        opacity: (dragOffset / 60).clamp(0.0, 1.0),
                        duration: const Duration(milliseconds: 50),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: triggered
                                ? Colors.blue
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.reply,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Chat bubble
              AnimatedContainer(
                duration: Duration(milliseconds: dragOffset == 0 ? 200 : 0),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(dragOffset, 0, 0),
                child: child,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bottom sheet with message options (Reply, Star)
  // =====================================================================
  // [KATA KUNCI: Opsi Pesan | Message Options | Balas | Bintang | Star | Salin | Teruskan]
  // [FITUR: Lembar Aksi Menu Pesan (Bottom Sheet Options)]
  // [RENTANG: Baris ~5560 - 5645]
  // [FUNGSI: Membuka bottom sheet aksi pesan saat pesan di-tap/dipilih:
  //          - Balas (Reply)
  //          - Tandai Bintang (Star/Unstar message)
  //          - Salin Teks (Copy to clipboard)
  //          - Teruskan (Forward to other chats)]
  // =====================================================================
  void _showMessageOptions(Message message) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final msgId = '${message.content.hashCode}_${message.time}';
    final starred = chatProvider.isStarred(msgId);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.blue),
                title: const Text('Balas'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _repliedMessage = message);
                },
              ),
              ListTile(
                leading: Icon(
                  starred ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                title: Text(starred ? 'Unstar' : 'Star'),
                onTap: () {
                  Navigator.pop(ctx);
                  chatProvider.toggleStar(
                    msgId,
                    content: message.content,
                    sender: message.isMe ? 'Saya' : chat.sender,
                    time: message.time,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        starred ? 'Bintang dihapus' : 'Pesan ditandai ⭐',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.teal),
                title: const Text('Salin'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pesan disalin'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward, color: Colors.deepPurple),
                title: const Text('Teruskan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showForwardDialog(message);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Teruskan Pesan | Forward Message | Dialog Teruskan]
  // [FITUR: Dialog Teruskan Pesan ke Kontak Lain]
  // [RENTANG: Baris ~5650 - 5840]
  // [FUNGSI: Menampilkan dialog daftar obrolan aktif untuk meneruskan isi pesan
  //          ke kontak lain yang dipilih.]
  // =====================================================================
  void _showForwardDialog(Message message) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final allChats = chatProvider.chats;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teruskan ke...'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: allChats.isEmpty
              ? const Center(child: Text('Tidak ada chat'))
              : ListView.builder(
                  itemCount: allChats.length,
                  itemBuilder: (builderCtx, index) {
                    final target = allChats[index];
                    if (target.id == chat.id) return const SizedBox.shrink();
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            target.sender.isNotEmpty
                                ? target.sender[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        title: Text(target.sender),
                        subtitle: Text(
                          target.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Meneruskan pesan ke ${target.sender}...',
                                ),
                              ),
                            );
                          }

                          int requestBodyType = 1;
                          String? attachmentStr;
                          if (message.messageType != MessageType.text) {
                            if (message.messageType == MessageType.voice)
                              requestBodyType = 2;
                            else if (message.messageType == MessageType.image)
                              requestBodyType = 3;
                            else if (message.messageType == MessageType.video)
                              requestBodyType = 4;
                            else if (message.messageType ==
                                MessageType.document)
                              requestBodyType = 5;

                            String? url =
                                message.imageUrl ??
                                message.documentUrl ??
                                message.videoUrl ??
                                message.audioPath;
                            if (url != null) {
                              String filename = url.split('/').last;
                              String originalName =
                                  message.documentName ?? filename;
                              final fileJsonObj = <String, dynamic>{
                                "Filename": filename,
                                "OriginalName": originalName,
                              };
                              if (message.messageType == MessageType.voice) {
                                fileJsonObj["Ptt"] = true;
                              }
                              attachmentStr = jsonEncode([fileJsonObj]);
                            }
                          }

                          final String finalContent =
                              (message.messageType != MessageType.text &&
                                  message.content == '📷 Photo')
                              ? ''
                              : message.content;
                          final sendError = await chatProvider
                              .sendMessageViaSignalR(
                                chat: target,
                                type: requestBodyType.toString(),
                                msg: finalContent,
                                fileJson: attachmentStr,
                              );
                          bool isError = (sendError != null);
                          String errorMessage =
                              sendError ?? 'SignalR delivery failed';

                          if (!isError) {
                            String displayContent = finalContent;
                            if (message.messageType == MessageType.image) {
                              displayContent = '📷 Photo';
                            } else if (message.messageType ==
                                MessageType.video) {
                              displayContent = '🎥 Video';
                            } else if (message.messageType ==
                                MessageType.voice) {
                              displayContent = '🎤 Pesan Suara';
                            } else if (message.messageType ==
                                MessageType.document) {
                              displayContent =
                                  '📄 ${message.documentName ?? 'Dokumen'}';
                            }
                            chatProvider.updateLocalLastMessage(
                              target.id,
                              displayContent,
                              lastMessageType: requestBodyType.toString(),
                              isFromMe: true,
                              updateTimeAndPosition: true,
                            );
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isError
                                      ? 'Gagal meneruskan pesan: $errorMessage'
                                      : 'Pesan berhasil diteruskan ke ${target.sender}',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  /// Forward multiple messages dialog
  void _showForwardSelectedDialog() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final allChats = chatProvider.chats;

    // Simpan list pesan yang di-select secara urut waktu
    final selectedMessages = _messages
        .where((m) => _selectedMessageKeys.contains(_getMessageKey(m)))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teruskan ke...'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: allChats.isEmpty
              ? const Center(child: Text('Tidak ada chat'))
              : ListView.builder(
                  itemCount: allChats.length,
                  itemBuilder: (builderCtx, index) {
                    final target = allChats[index];
                    if (target.id == chat.id) return const SizedBox.shrink();
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            target.sender.isNotEmpty
                                ? target.sender[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        title: Text(target.sender),
                        subtitle: Text(
                          target.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Meneruskan ${selectedMessages.length} pesan ke ${target.sender}...',
                                ),
                              ),
                            );
                          }

                          bool hasError = false;
                          for (final msg in selectedMessages) {
                            int requestBodyType = 1;
                            String? attachmentStr;
                            if (msg.messageType != MessageType.text) {
                              if (msg.messageType == MessageType.voice)
                                requestBodyType = 2;
                              else if (msg.messageType == MessageType.image)
                                requestBodyType = 3;
                              else if (msg.messageType == MessageType.video)
                                requestBodyType = 4;
                              else if (msg.messageType == MessageType.document)
                                requestBodyType = 5;

                              String? url =
                                  msg.imageUrl ??
                                  msg.documentUrl ??
                                  msg.videoUrl ??
                                  msg.audioPath;
                              if (url != null) {
                                String filename = url.split('/').last;
                                String originalName =
                                    msg.documentName ?? filename;
                                final fileJsonObj = <String, dynamic>{
                                  "Filename": filename,
                                  "OriginalName": originalName,
                                };
                                if (msg.messageType == MessageType.voice) {
                                  fileJsonObj["Ptt"] = true;
                                }
                                attachmentStr = jsonEncode([fileJsonObj]);
                              }
                            }

                            final String finalContent =
                                (msg.messageType != MessageType.text &&
                                    msg.content == '📷 Photo')
                                ? ''
                                : msg.content;

                            final sendError = await chatProvider
                                .sendMessageViaSignalR(
                                  chat: target,
                                  type: requestBodyType.toString(),
                                  msg: finalContent,
                                  fileJson: attachmentStr,
                                );
                            if (sendError != null) hasError = true;
                          }

                          if (!hasError && selectedMessages.isNotEmpty) {
                            final lastMsg = selectedMessages.last;
                            int lastType = 1;
                            if (lastMsg.messageType == MessageType.voice) {
                              lastType = 2;
                            } else if (lastMsg.messageType ==
                                MessageType.image) {
                              lastType = 3;
                            } else if (lastMsg.messageType ==
                                MessageType.video) {
                              lastType = 4;
                            } else if (lastMsg.messageType ==
                                MessageType.document) {
                              lastType = 5;
                            }

                            String displayContent =
                                (lastMsg.messageType != MessageType.text &&
                                    lastMsg.content == '📷 Photo')
                                ? ''
                                : lastMsg.content;
                            if (lastMsg.messageType == MessageType.image) {
                              displayContent = '📷 Photo';
                            } else if (lastMsg.messageType ==
                                MessageType.video) {
                              displayContent = '🎥 Video';
                            } else if (lastMsg.messageType ==
                                MessageType.voice) {
                              displayContent = '🎤 Pesan Suara';
                            } else if (lastMsg.messageType ==
                                MessageType.document) {
                              displayContent =
                                  '📄 ${lastMsg.documentName ?? 'Dokumen'}';
                            }

                            chatProvider.updateLocalLastMessage(
                              target.id,
                              displayContent,
                              lastMessageType: lastType.toString(),
                              isFromMe: true,
                              updateTimeAndPosition: true,
                            );
                          }

                          if (mounted) {
                            setState(() {
                              _isSelectionMode = false;
                              _selectedMessageKeys.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  hasError
                                      ? 'Beberapa pesan gagal diteruskan'
                                      : 'Pesan berhasil diteruskan ke ${target.sender}',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  "No more messages" header
  // ─────────────────────────────────────────────

  Widget _buildMessageListHeader() {
    if (_isLoadingOlderMessages) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Memuat pesan lama...',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (!_hasMoreMessages) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          'Tidak ada pesan lagi',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      );
    }

    // Has more but not loading yet — will auto-trigger via scroll listener
    return const SizedBox(height: 20);
  }

  // ─────────────────────────────────────────────
  //  System message (centered with dividers)
  // ─────────────────────────────────────────────

  Widget _buildSystemMessage(Message message, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[400], thickness: 0.5)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(child: Divider(color: Colors.grey[400], thickness: 0.5)),
            ],
          ),
          if (message.time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _formatBubbleTime(message.time),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Chat Bubble — matching screenshot style
  // ─────────────────────────────────────────────

  Widget _buildChatBubble(Message message, bool isDark) {
    final isMe = message.isMe;

    // Image message bubble
    if (message.messageType == MessageType.image) {
      return _buildImageBubble(message, isDark);
    }

    // Voice message bubble
    if (message.messageType == MessageType.voice) {
      return _buildVoiceBubble(message, isDark);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.blue
              : (isDark ? const Color(0xFF1F2C34) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe
                ? const Radius.circular(12)
                : const Radius.circular(2),
            bottomRight: isMe
                ? const Radius.circular(2)
                : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Quoted / reply
            if (message.repliedMessage != null) ...[
              _buildQuotedMessage(message.repliedMessage!, isMe),
              const SizedBox(height: 6),
            ],
            // Content
            Text(
              message.content,
              style: TextStyle(
                color: isMe
                    ? Colors.white
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 3),
            // Time + status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatBubbleTime(message.time),
                  style: TextStyle(
                    color: isMe
                        ? Colors.white70
                        : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    fontSize: 11,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _getStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  VOICE MESSAGE BUBBLE
  // ─────────────────────────────────────────────

  Widget _buildVoiceBubble(Message message, bool isDark) {
    final isMe = message.isMe;
    final isThisPlaying =
        _isPlaying && _currentlyPlayingPath == message.audioPath;
    final progress = _playbackDuration.inMilliseconds > 0 && isThisPlaying
        ? _playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds
        : 0.0;

    final totalSec = (isThisPlaying && _playbackDuration.inSeconds > 0)
        ? _playbackDuration.inSeconds
        : message.audioDuration;

    final displayDuration = isThisPlaying
        ? '${_formatDuration(_playbackPosition.inSeconds)} / ${_formatDuration(totalSec)}'
        : '0:00 / ${_formatDuration(message.audioDuration)}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.blue
              : (isDark ? const Color(0xFF1F2C34) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe
                ? const Radius.circular(12)
                : const Radius.circular(2),
            bottomRight: isMe
                ? const Radius.circular(2)
                : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play/Pause button
                GestureDetector(
                  onTap: message.audioPath != null
                      ? () => _togglePlayback(message.audioPath!)
                      : null,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isThisPlaying ? Icons.pause : Icons.play_arrow,
                      color: isMe ? Colors.white : Colors.blue,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Waveform / progress bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Simulated waveform bars
                      SizedBox(
                        height: 28,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(20, (i) {
                            final barProgress = (i + 1) / 20;
                            final isActive = progress >= barProgress;
                            // Pseudo-random heights for waveform look
                            final heights = [
                              0.4,
                              0.7,
                              0.5,
                              0.9,
                              0.6,
                              0.8,
                              0.3,
                              1.0,
                              0.5,
                              0.7,
                              0.6,
                              0.9,
                              0.4,
                              0.8,
                              0.5,
                              0.7,
                              0.3,
                              0.6,
                              0.8,
                              0.5,
                            ];
                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 0.5,
                                ),
                                height: 28 * heights[i],
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? (isMe ? Colors.white : Colors.blue)
                                      : (isMe
                                            ? Colors.white.withOpacity(0.3)
                                            : Colors.grey.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Mic icon
                Icon(
                  Icons.mic,
                  size: 18,
                  color: isMe ? Colors.white70 : Colors.grey[500],
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Duration + time + status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayDuration,
                  style: TextStyle(
                    color: isMe
                        ? Colors.white70
                        : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatBubbleTime(message.time),
                  style: TextStyle(
                    color: isMe
                        ? Colors.white70
                        : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    fontSize: 11,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _getStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  IMAGE MESSAGE BUBBLE
  // ─────────────────────────────────────────────

  Widget _buildImageBubble(Message message, bool isDark) {
    final isMe = message.isMe;

    Widget imageWidget;
    if (message.imagePath != null && File(message.imagePath!).existsSync()) {
      imageWidget = Image.file(
        File(message.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else if (message.imageUrl != null &&
        message.imageUrl!.startsWith('http')) {
      imageWidget = Image.network(
        message.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            height: 150,
            child: Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                    : null,
                color: isMe ? Colors.white : Colors.blue,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else {
      imageWidget = _buildImagePlaceholder();
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.blue
              : (isDark ? const Color(0xFF1F2C34) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe
                ? const Radius.circular(12)
                : const Radius.circular(2),
            bottomRight: isMe
                ? const Radius.circular(2)
                : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Image with rounded top corners
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  minHeight: 120,
                ),
                child: imageWidget,
              ),
            ),
            // Time + status row below image
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatBubbleTime(message.time),
                    style: TextStyle(
                      color: isMe
                          ? Colors.white70
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _getStatusIcon(message.status),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 48, color: Colors.grey[500]),
          const SizedBox(height: 4),
          Text(
            'Image',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Input Bar | Kolom Chat | TextField Pesan | Send Button | Tombol Mic]
  // [FITUR: Kolom Pengetikan Pesan Bawah (Input Bar)]
  // [RENTANG: Baris ~6485 - 6595]
  // [FUNGSI: Wadah utama interaksi pengetikan pesan di bagian bawah layar.
  //          Menyediakan tombol lampiran (attach file), TextField pengetikan,
  //          tombol toggle keyboard emoji, serta tombol kirim teks / mikrofon rekaman suara.]
  // =====================================================================
  Widget _buildInputBar(bool isDark) {
    // Attachment panel or spacing
    final bottomPadding = MediaQuery.of(context).padding.bottom + 8;

    return Container(
      key: const ValueKey('inputBar'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Attachment icon on the left (toggle panel)
          IconButton(
            icon: Icon(
              _showAttachmentPanel ? Icons.close : Icons.attach_file,
              color: Colors.blue,
              size: 26,
            ),
            onPressed: _toggleAttachmentPanel,
          ),
          // Text field with emoji suffix
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              autofocus: false,
              minLines: 1,
              maxLines: 3,
              onTap: () {
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                }
              },
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A3942)
                    : Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showEmojiPicker
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                    color: Colors.blue,
                    size: 26,
                  ),
                  onPressed: _toggleEmojiPicker,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Blue circular button: send (text) or hold-to-record (mic)
          _isComposing
              ? Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 22),
                    onPressed: _sendMessage,
                  ),
                )
              : GestureDetector(
                  onTap: _showVoiceBottomSheet,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 22),
                  ),
                ),
        ],
      ),
    );
  }

  // =====================================================================
  // [KATA KUNCI: Attachment Panel | Panel Lampiran | Menu Media | Kamera | Galeri | Video | Dokumen | Lokasi]
  // [FITUR: Panel Menu Lampiran Media (Attachment Panel)]
  // [RENTANG: Baris ~6600 - 6695]
  // [FUNGSI: Menampilkan menu pop-up animasi berisi pilihan jenis lampiran media
  //          (Kamera, Galeri Foto, Video, Dokumen, dan Berbagi Lokasi Google Maps).]
  // =====================================================================
  Widget _buildAttachmentPanel(bool isDark) {
    return AnimatedContainer(
      key: const ValueKey('attachmentPanel'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -1),
            blurRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachmentOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                onTap: _pickAndSendFromCamera,
              ),
              _buildAttachmentOption(
                icon: Icons.photo,
                label: 'Gallery',
                onTap: _pickAndSendImage,
              ),
              _buildAttachmentOption(
                icon: Icons.movie,
                label: 'Video',
                onTap: _pickAndSendVideo,
              ),
              _buildAttachmentOption(
                icon: Icons.insert_drive_file,
                label: 'Document',
                onTap: _pickAndSendDocument,
              ),
              _buildAttachmentOption(
                icon: Icons.location_on,
                label: 'Location',
                onTap: _shareLocation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlue = const Color(0xFF448AFF);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: isDark
                ? primaryBlue.withOpacity(0.2)
                : primaryBlue.withOpacity(0.1),
            child: Icon(icon, color: primaryBlue, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  RECORDING OVERLAY BAR
  // ─────────────────────────────────────────────

  // Removed _buildRecordingBar as it's replaced by VoiceRecordingBottomSheet

  // =====================================================================
  // [KATA KUNCI: Emoji Picker | Keyboard Emoji | Emoticon | Stiker]
  // [FITUR: Papan Tombol Emoji (Emoji Picker)]
  // [RENTANG: Baris ~6700 - 6780]
  // [FUNGSI: Menampilkan keyboard khusus emoji bergaya WhatsApp dengan fitur
  //          kategori emoji, pencarian emoji, dan tombol backspace.]
  // =====================================================================
  Widget _buildEmojiPicker(bool isDark) {
    return SizedBox(
      key: const ValueKey('emojiPicker'),
      height: 250,
      child: EmojiPicker(
        onEmojiSelected: _onEmojiSelected,
        onBackspacePressed: () {
          final text = _messageController.text;
          if (text.isNotEmpty) {
            // Handle multi-byte emoji characters properly
            final characters = text.characters.toList();
            characters.removeLast();
            _messageController.text = characters.join();
            _messageController.selection = TextSelection.collapsed(
              offset: _messageController.text.length,
            );
          }
        },
        config: Config(
          height: 250,
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 28,
            backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
            indicatorColor: Colors.blue,
            iconColorSelected: Colors.blue,
            iconColor: isDark ? Colors.grey[600]! : Colors.grey[400]!,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            showBackspaceButton: true,
            showSearchViewButton: true,
            backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue,
            buttonColor: isDark ? Colors.white70 : Colors.white,
            buttonIconColor: isDark ? Colors.white70 : Colors.white,
            customBottomActionBar: (config, state, showSearchView) {
              return Container(
                color: isDark ? AppTheme.darkSurface : Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: isDark ? Colors.white12 : Colors.white,
                      child: SearchButton(
                        config,
                        showSearchView,
                        isDark ? Colors.white70 : Colors.blue,
                      ),
                    ),
                    BackspaceButton(
                      config,
                      state.onBackspacePressed,
                      state.onBackspaceLongPressed,
                      isDark ? Colors.white70 : Colors.white,
                    ),
                  ],
                ),
              );
            },
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
            buttonIconColor: Colors.blue,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  Widget _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Colors.cyanAccent);
    }
  }

  // =====================================================================
  // [KATA KUNCI: Reply Preview | Balas Pesan | Pratinjau Balasan | Kutipan Pesan]
  // [FITUR: Kartu Pratinjau Balasan Pesan (Reply Preview)]
  // [RENTANG: Baris ~6795 - 6850]
  // [FUNGSI: Menampilkan bar kecil di atas kolom input yang berisi kutipan pesan
  //          yang sedang dibalas (nama pengirim, cuplikan isi pesan, dan tombol silang 'X' untuk membatalkan).]
  // =====================================================================
  Widget _buildReplyPreview(bool isDark) {
    return Container(
      key: const ValueKey('replyPreview'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A3942) : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: Colors.blue, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _repliedMessage!.isMe ? 'You' : chat.sender,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      if (_repliedMessage!.messageType == MessageType.voice)
                        Icon(
                          Icons.mic,
                          size: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      if (_repliedMessage!.messageType == MessageType.image)
                        Icon(
                          Icons.image,
                          size: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      if (_repliedMessage!.messageType == MessageType.document)
                        Icon(
                          Icons.insert_drive_file,
                          size: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      if (_repliedMessage!.messageType != MessageType.text)
                        const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _repliedMessage!.messageType == MessageType.voice
                              ? 'Voice note'
                              : (_repliedMessage!.content.isNotEmpty
                                    ? _repliedMessage!.content
                                    : _repliedMessage!.messageType
                                          .toString()
                                          .split('.')
                                          .last),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() => _repliedMessage = null),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Local Reply Cache (Backend Bypass)
  // ─────────────────────────────────────────────
  Future<void> _saveLocalReplyContext(
    String messageId,
    Message repliedMessage,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'local_reply_$messageId';
      final replyData = {
        'id': repliedMessage.id,
        'content': repliedMessage.content,
        'isMe': repliedMessage.isMe,
      };
      await prefs.setString(key, jsonEncode(replyData));
    } catch (e) {
      debugPrint('Error saving local reply context: $e');
    }
  }

  Future<void> _injectLocalReplies(List<Message> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg.id.isNotEmpty && msg.repliedMessage == null) {
          final key = 'local_reply_${msg.id}';
          final savedReply = prefs.getString(key);
          if (savedReply != null) {
            final data = jsonDecode(savedReply);
            messages[i] = msg.copyWith(
              repliedMessage: Message(
                id: data['id'] ?? '',
                content: data['content'] ?? '',
                isMe: data['isMe'] ?? false,
                time: '',
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error injecting local replies: $e');
    }
  }

  Widget _buildQuotedMessage(Message message, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.2)
            : (isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05)),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white70 : Colors.blue,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.isMe ? 'You' : chat.sender,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isMe ? Colors.white : Colors.blue,
              fontSize: 12,
            ),
          ),
          Text(
            message.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isMe
                  ? Colors.white70
                  : (isDark ? Colors.grey[300] : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Animated Chat Bubble
// ─────────────────────────────────────────────

class AnimatedChatBubble extends StatefulWidget {
  final Widget child;
  final bool isMe;

  const AnimatedChatBubble({
    super.key,
    required this.child,
    required this.isMe,
  });

  @override
  State<AnimatedChatBubble> createState() => _AnimatedChatBubbleState();
}

class _AnimatedChatBubbleState extends State<AnimatedChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

// ─────────────────────────────────────────────
//  Custom Painter for Sidebar Icon
// ─────────────────────────────────────────────

class _SidebarIconPainter extends CustomPainter {
  final Color color;
  _SidebarIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = 2.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeJoin = StrokeJoin.round;

    // Outer rounded rectangle – small radius like the target
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(rect, paint);

    // Vertical divider — roughly in the middle (45 %)
    final dividerX = size.width * 0.45;
    canvas.drawLine(
      Offset(dividerX, 1),
      Offset(dividerX, size.height - 1),
      paint,
    );

    // Three horizontal lines on the RIGHT panel
    final rightPanelLeft = dividerX + 4;
    final rightPanelRight = size.width - 4;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final lineSpacing = 4.0;

    // Middle line
    canvas.drawLine(
      Offset(rightPanelLeft, centerY),
      Offset(rightPanelRight, centerY),
      linePaint,
    );
    // Top line
    canvas.drawLine(
      Offset(rightPanelLeft, centerY - lineSpacing),
      Offset(rightPanelRight, centerY - lineSpacing),
      linePaint,
    );
    // Bottom line
    canvas.drawLine(
      Offset(rightPanelLeft, centerY + lineSpacing),
      Offset(rightPanelRight, centerY + lineSpacing),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
