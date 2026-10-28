import 'dart:convert';
import 'package:flutter/foundation.dart';

// =====================================================================
// FITUR: Model Obrolan Utama (ChatModel)
// FILE: lib/core/model/message.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Class utama UI untuk data chat/room yang ditampilkan di screen utama
// =====================================================================
class ChatModel {
  final String id;
  final String contactId; // CtId — digunakan oleh Inbox/Send dan Inbox/Get
  final String sender;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isPinned;
  final bool isArchived;
  final bool isFavorite;
  final bool isGroup;
  final bool isBlocked;
  final String status; // "Selesai", "Ditugaskan", "Belum Ditugaskan"
  final String agentName;
  final List<String> tags;
  final String? avatarUrl;
  final String? lastMessageType; // "Sticker", "Pesan Tidak Didukung", dll.
  final bool needReply;
  final bool muteAiAgent;
  final String funnel;
  final String notes;
  final String channelName;
  final String channelType;
  final String chId;
  final String accountId;
  final String ctRealId;
  final bool isLastMessageFromMe;
  final String link;
  final String campaign;
  final String deal;
  final String groupName;
  final String groupId;
  final String sdrMsg; // "me" (agent), "you" (customer)
  final String extId; // CtIdExt / ExtId - Telegram user ID or phone number

  ChatModel({
    required this.id,
    this.contactId = '',
    required this.sender,
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isFavorite = false,
    this.isGroup = false,
    this.isBlocked = false,
    this.status = 'Unassigned',
    this.agentName = '',
    this.tags = const [],
    this.avatarUrl,
    this.lastMessageType,
    this.needReply = false,
    this.muteAiAgent = false,
    this.funnel = '',
    this.notes = '',
    this.channelName = '',
    this.channelType = '',
    this.chId = '',
    this.accountId = '',
    this.ctRealId = '',
    this.isLastMessageFromMe = false,
    this.link = '',
    this.campaign = '',
    this.deal = '',
    this.groupName = '',
    this.groupId = '',
    this.sdrMsg = '',
    this.extId = '',
  });

  // FITUR: Copy With (ChatModel)
  // FUNGSI: Meng-copy objek ChatModel untuk mempermudah perubahan state di provider
  ChatModel copyWith({
    String? id,
    String? contactId,
    String? sender,
    String? lastMessage,
    String? time,
    int? unreadCount,
    bool? isPinned,
    bool? isArchived,
    bool? isFavorite,
    bool? isGroup,
    bool? isBlocked,
    String? status,
    String? agentName,
    List<String>? tags,
    String? avatarUrl,
    String? lastMessageType,
    bool? needReply,
    bool? muteAiAgent,
    String? funnel,
    String? notes,
    String? channelName,
    String? channelType,
    String? chId,
    String? accountId,
    String? ctRealId,
    bool? isLastMessageFromMe,
    String? link,
    String? campaign,
    String? deal,
    String? groupName,
    String? groupId,
    String? sdrMsg,
    String? extId,
  }) {
    return ChatModel(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      sender: sender ?? this.sender,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isFavorite: isFavorite ?? this.isFavorite,
      isGroup: isGroup ?? this.isGroup,
      isBlocked: isBlocked ?? this.isBlocked,
      status: status ?? this.status,
      agentName: agentName ?? this.agentName,
      tags: tags ?? this.tags,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      needReply: needReply ?? this.needReply,
      muteAiAgent: muteAiAgent ?? this.muteAiAgent,
      funnel: funnel ?? this.funnel,
      notes: notes ?? this.notes,
      channelName: channelName ?? this.channelName,
      channelType: channelType ?? this.channelType,
      chId: chId ?? this.chId,
      accountId: accountId ?? this.accountId,
      ctRealId: ctRealId ?? this.ctRealId,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      link: link ?? this.link,
      campaign: campaign ?? this.campaign,
      deal: deal ?? this.deal,
      groupName: groupName ?? this.groupName,
      groupId: groupId ?? this.groupId,
      sdrMsg: sdrMsg ?? this.sdrMsg,
      extId: extId ?? this.extId,
    );
  }
}

enum MessageStatus { sent, delivered, read }
enum MessageType { text, voice, image, video, document, sticker }

/// Placeholder shown for WhatsApp messages that cannot be rendered in-app yet
/// (edited messages, protocol messages, and empty/unsupported media payloads).
const String kUnsupportedWhatsAppLabel =
    "This message can't be displayed here yet. Please open WhatsApp on your phone to view this message";

/// Returns true when [content] carries no readable text / media and should be
/// treated as an unsupported WhatsApp message (edited, protocol, or empty file).
bool isUnsupportedWhatsAppContent(String? content) {
  if (content == null) return false;
  final c = content.trim();
  if (c.isEmpty) return true;
  final lower = c.toLowerCase();
  if (lower == '{}' || lower == '[]' || lower == 'null') return true;
  if (lower == 'document(empty)' ||
      lower == 'voice(empty)' ||
      lower == 'image(empty)' ||
      lower == 'video(empty)' ||
      lower == 'audio(empty)') {
    return true;
  }
  // Server-side markers used for deleted / unsupported protocol payloads.
  if (lower.contains('site.inbox.deletedmessage')) return true;
  if (lower.contains('message.whatsapp') && !_hasReadableText(lower)) return true;
  return false;
}

bool _hasReadableText(String lower) {
  if (lower.startsWith('{') || lower.startsWith('[')) return false;
  return lower.replaceAll(RegExp(r'[^a-z0-9]'), '').isNotEmpty;
}

// =====================================================================
// FITUR: Model Pesan (Message)
// FILE: lib/core/model/message.dart
// BARIS AWAL: 165 (setelah komentar ini)
// FUNGSI: Class utama untuk menampung satu gelembung pesan (teks, gambar, audio) di ruang chat
// =====================================================================
class Message {
  final String id;
  final String? idAlias;
  final String content;
  final bool isMe;
  final String time;
  final String rawTime; // RAW ISO string for accurate sorting
  final MessageStatus status;
  final Message? repliedMessage;
  final bool isSystemMessage;
  final MessageType messageType;
  final String? audioPath;
  final int audioDuration; // dalam detik
  final String? imagePath;  // path file lokal
  final String? imageUrl;   // URL remote dari server
  final String? videoUrl;   // URL video remote dari server
  final String? documentName; // nama file asli untuk pesan dokumen
  final String? documentUrl;  // URL remote untuk unduh dokumen
  final int ack; // 1: pending, 2: terkirim, 3: diterima, 4: gagal, 5: dibaca
  final String? fromId;
  final String? toId;
  final String roomId;

  Message({
    this.id = '',
    this.idAlias,
    required this.content,
    required this.isMe,
    required this.time,
    this.rawTime = '',
    this.status = MessageStatus.sent,
    this.repliedMessage,
    this.isSystemMessage = false,
    this.messageType = MessageType.text,
    this.audioPath,
    this.audioDuration = 0,
    this.imagePath,
    this.imageUrl,
    this.videoUrl,
    this.documentName,
    this.documentUrl,
    this.ack = 0,
    this.fromId,
    this.toId,
    this.roomId = '',
  });

  /// Format ISO timestamp "2026-03-25T05:42:28.107" → "25 Mar, 05:42"
  static String _formatIsoTime(String raw) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    try {
      String timeString = raw;
      // Jika dari server tidak ada penanda zona waktu (Z atau +), paksa anggap sebagai UTC ('Z')
      if (!timeString.endsWith('Z') && !timeString.contains('+') && timeString.length >= 19) {
        timeString += 'Z';
      }
      final dt = DateTime.parse(timeString).toLocal();
      return "${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return raw; // Kembalikan apa adanya jika proses parse gagal
    }
  }

  /// Cek apakah nama file terlihat seperti gambar
  static bool _isImageFile(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
  }

  // FITUR: Parse Pesan dari JSON
  // FUNGSI: Mengubah response JSON list messages API menjadi objek Message
  factory Message.fromJson(Map<String, dynamic> json, String currentUserEmail, {String? tenantId, String? contactId}) {
    String id = json['Id']?.toString() ?? '';
    final rawIdAlias = json['IdAlias']?.toString() ?? '';
    final parsedIdAlias = (rawIdAlias.isNotEmpty && rawIdAlias != '0') ? rawIdAlias : null;

    if (id == '0' || id.isEmpty) {
      id = json['IdAlias']?.toString() ?? json['IdAccount']?.toString() ?? json['id']?.toString() ?? '';
    }

    bool isMe = false;
    
    // Deteksi Outbound NATIVE (Telegram dll) berdasarkan tujuan pesan
    // Jika pesan ditujukan KEPADA pelanggan ini (To == contactId), maka pesan itu PASTI dikirim oleh bisnis.
    bool isNativeOutbound = false;
    if (contactId != null && contactId.isNotEmpty && contactId != '0') {
      final extTo = json['To']?.toString() ?? json['ToId']?.toString() ?? '';
      if (extTo.isNotEmpty && extTo == contactId) {
        isNativeOutbound = true;
      }
    }

    if (json['IsMe'] == true || json['IsMe'] == 'true' || json['IsMe'] == 1) {
      isMe = true;
    } else if (isNativeOutbound) {
      // ✅ DETEKSI AKURAT: Jika `To` adalah Customer, ini adalah pesan KITA (Outbound).
      isMe = true;
    }

    if (id == '0' || id.isEmpty) {
      if (parsedIdAlias != null) {
        id = parsedIdAlias;
      } else {
        final timeStr = json['In']?.toString() ?? '';
        final contentStr = json['Msg']?.toString() ?? '';
        id = 'temp_${timeStr}_${contentStr.hashCode}';
      }
    }
    // ChatMessages/List menggunakan Type: 6 untuk pesan sistem, Type: 1/2 untuk pesan biasa
    final typeVal = json['Type']?.toString();

    // Tentukan konten pesan — ChatMessages/List menggunakan field 'Msg'
    // Tangani format String maupun Map untuk 'Msg'
    String content = '';
    final rawMsg = json['Msg'];
    if (rawMsg is String) {
      content = rawMsg;
    } else if (rawMsg is Map) {
      content = rawMsg['msg']?.toString() ??
          rawMsg['Msg']?.toString() ??
          rawMsg['text']?.toString() ??
          rawMsg['Text']?.toString() ??
          rawMsg['caption']?.toString() ??
          rawMsg['Caption']?.toString() ??
          rawMsg.toString();
    }
    
    // Jika content masih kosong atau hanya berupa string object/array kosong, coba ambil dari field lain
    if (content.isEmpty || content.trim() == '{}' || content.trim() == '[]' || content == 'null') {
      content = json['caption']?.toString() ??
          json['Caption']?.toString() ??
          json['text']?.toString() ??
          json['Text']?.toString() ??
          json['Body']?.toString() ??
          json['body']?.toString() ??
          json['Message']?.toString() ??
          json['message']?.toString() ??
          json['Content']?.toString() ??
          json['content']?.toString() ??
          '';
    }

    // Jika content adalah string JSON (misal bot response dari Telegram/WhatsApp), ekstrak teks aslinya
    if (content.startsWith('{') && !content.contains('"File"') && !content.contains('"Filename"')) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          final extracted = decoded['text']?.toString() ??
              decoded['Text']?.toString() ??
              decoded['caption']?.toString() ??
              decoded['Caption']?.toString() ??
              decoded['msg']?.toString() ??
              decoded['Msg']?.toString() ??
              decoded['body']?.toString() ??
              decoded['message']?.toString();
          if (extracted != null && extracted.isNotEmpty && !extracted.startsWith('{')) {
            content = extracted;
          }
        }
      } catch (_) {}
    }

    final isSystem = json['IsSystemMessage'] == true || 
                     typeVal?.toLowerCase() == 'system' ||
                     typeVal == '6' ||
                     content.contains('Site.Inbox.DeletedMessage') ||
                     content.contains('Percakapan di-assign') ||
                     content.contains('Percakapan diselesaikan');
    
    // Tangani anomali dari API: 'document(Empty)' atau 'voice(Empty)'
    if (content.trim().toLowerCase() == 'document(empty)' || content.trim().toLowerCase() == 'voice(empty)') {
      content = '';
    }

    // Pesan sistem (Type: 6) memiliki JSON di Msg seperti {"msg":"Site.Inbox.UnmuteBotByAgent",...}
    // Parse untuk menampilkan label yang mudah dibaca
    if (isSystem && (content.startsWith('{') || json['Msg'] is Map)) {
      try {
        dynamic decoded = json['Msg'];
        if (content.startsWith('{')) {
          decoded = jsonDecode(content);
        }
        final parsed = Map<String, dynamic>.from(
          decoded is Map ? decoded : (json['Msg'] is Map ? json['Msg'] : {}),
        );
        final msgKey = parsed['msg']?.toString() ?? parsed['Msg']?.toString() ?? parsed['text']?.toString() ?? '';
        // Ubah "Site.Inbox.UnmuteBotByAgent" -> "Bot diaktifkan"
        if (msgKey.contains('UnmuteBot')) {
          content = '🤖 Bot diaktifkan';
        } else if (msgKey.contains('MuteBot')) {
          content = '🤖 Bot dinonaktifkan';
        } else if (msgKey.contains('Assign') || msgKey.contains('assign') || msgKey.contains('Asign')) {
          content = '👤 Percakapan di-assign';
        } else if (msgKey.contains('Resolve') || msgKey.contains('resolve')) {
          content = '✅ Percakapan diselesaikan';
        } else if (msgKey.isNotEmpty) {
          final readableKey = msgKey.replaceAll("Site.Inbox.", "").replaceAll("_", " ");
          content = '📋 $readableKey';
        } else {
          content = '📋 Pemberitahuan sistem';
        }
      } catch (e) {
        if (content.trim().isEmpty || content.startsWith('{')) {
          content = '📋 Pemberitahuan sistem';
        }
      }
    }

    // Evaluasi isMe lanjutan (apabila tidak terdeteksi via isNativeOutbound/LastIsMe)
    if (!isMe && !isSystem) {
      final agentIdVal = json['AgentId'];
      final dirVal = json['Dir'] ?? json['Direction'] ?? json['dir'];
      final dirStr = dirVal?.toString().toLowerCase() ?? '';
      
      if (agentIdVal != null && agentIdVal != 0 && agentIdVal.toString() != '0') {
        // AgentId ada dan bukan 0 -> pesan dikirim oleh agen (kita)
        isMe = true;
      } else if (json['IsMe'] == true || json['IsOutbound'] == true || json['IsOutBound'] == true || json['Outbound'] == true || json['isOutbound'] == true) {
        isMe = true;
      } else if (json['IsNobox'] == 1 || json['IsNobox'] == true || json['IsNobox']?.toString() == '1') {
        // Dari log aktual, NoBox menandai pesan outbound channel dengan IsNobox: 1
        isMe = true;
      } else if (dirStr == '1' || dirStr == '2' || dirStr == 'out' || dirStr == 'outbound' || dirStr == 'true') {
        isMe = true;
      } else {
        // Deteksi kuat: Jika pengirim sama dengan ID Akun Channel (ChAccId), maka ini pesan dari KITA (agen/bisnis)
        final extFrom = json['From']?.toString() ?? json['FromId']?.toString() ?? json['IdAccount']?.toString() ?? '';
        final extChAccId = json['ChAccId']?.toString() ?? '';
        final extSenderId = json['SenderId']?.toString() ?? '';

        if (extFrom.isNotEmpty && extChAccId.isNotEmpty && extFrom == extChAccId) {
          isMe = true;
        } else if (extSenderId.isNotEmpty && extChAccId.isNotEmpty && extSenderId == extChAccId) {
          isMe = true;
        } else if (extSenderId.isNotEmpty && extFrom.isNotEmpty && extSenderId == extFrom && (dirStr == 'out' || dirStr == 'outbound' || dirStr == '1' || dirStr == '2')) {
          isMe = true;
        } else {
          // Fallback: cek kecocokan email
          final senderEmail = extSenderId.isNotEmpty ? extSenderId : (extFrom.isNotEmpty ? extFrom : (json['sender_email']?.toString() ?? ''));
          isMe = senderEmail.isNotEmpty && senderEmail == currentUserEmail;
        }
      }
    }

    // Parse file media — cek array Files terlebih dahulu, lalu field File, lalu fallback berdasarkan Type
    MessageType msgType = MessageType.text;
    String? imgUrl;
    String? audioPath;
    String? videoUrl;
    
    // Helper untuk mengecek apakah nama file adalah video
    bool isVideoFile(String fileName) {
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
      return ['mp4', 'avi', 'mov', 'mkv', '3gp', 'webm', 'ogg_video'].contains(ext);
    }
    
    // Helper untuk mengecek apakah nama file adalah file audio
    bool isAudioFile(String fileName) {
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
      return ['mp3', 'wav', 'ogg', 'oga', 'opus', 'm4a', 'aac', 'weba', 'amr'].contains(ext);
    }

    // Helper untuk mengecek string penanda Voice Note / Audio secara aman
    bool isVoiceNoteString(String str) {
      if (str.isEmpty) return false;
      final lower = str.toLowerCase();
      if (lower.contains('voice note') || lower.contains('pesan suara')) return true;
      if (lower.contains('voice_') && !lower.contains('invoice_')) return true;
      if (lower.contains('audio_')) return true;
      if (lower.contains('ptt-')) return true;
      return false;
    }

    // Helper untuk mengecek apakah string adalah web link / URL
    bool _isWebLink(String str) {
      if (str.isEmpty) return false;
      final lower = str.toLowerCase();
      if (lower.startsWith('http')) return true;
      if (lower.startsWith('www.')) return true;
      if (lower.contains('tiktok.com') || lower.contains('tiktok.co') || lower.contains('instagram.com') || lower.contains('youtube.com') || lower.contains('youtu.be') || lower.contains('shopee.co') || lower.contains('tokopedia.com') || lower.contains('facebook.com') || lower.contains('twitter.com') || lower.contains('x.com')) return true;
      if (RegExp(r'^[a-zA-Z0-9-]+\.(com|id|net|org|co|io|me|be|xyz)(\/|$)').hasMatch(lower)) return true;
      return false;
    }

    // Helper untuk mengecek flag Ptt:true (Voice Note marker dari WhatsApp/Telegram)
    bool _isPttFile(dynamic fileData) {
      if (fileData == null) return false;
      bool isTruthy(dynamic v) {
        if (v == null) return false;
        if (v is bool) return v;
        final s = v.toString().toLowerCase();
        return s == 'true' || s == '1';
      }

      bool isPttMap(Map map) {
        return isTruthy(map['Ptt']) ||
            isTruthy(map['ptt']) ||
            isTruthy(map['IsPtt']) ||
            isTruthy(map['isPtt']) ||
            isTruthy(map['IsAudio']) ||
            isTruthy(map['isAudio']) ||
            isTruthy(map['IsVoice']) ||
            isTruthy(map['isVoice']);
      }

      try {
        final decoded = fileData is String ? jsonDecode(fileData) : fileData;
        if (decoded is Map) {
          if (isPttMap(decoded)) return true;
        }
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          if (isPttMap(decoded.first as Map)) return true;
        }
      } catch (_) {}
      return false;
    }

    // Helper to check for IsDocument: true flag
    bool _isDocumentFlag(dynamic fileData) {
      if (fileData == null) return false;
      try {
        final decoded = fileData is String ? jsonDecode(fileData) : fileData;
        if (decoded is Map) return decoded['IsDocument'] == true;
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          return decoded.first['IsDocument'] == true;
        }
      } catch (_) {}
      return false;
    }

    // Debug: catat raw JSON untuk pesan terkait media
    if (typeVal == '2' || typeVal == '16' || typeVal == '3' || typeVal == '4' || typeVal == '5' ||
        json['Files'] != null || json['File'] != null) {
      assert(() {
        debugPrint('Message.fromJson MEDIA: Type=$typeVal, Files=${json['Files']}, File=${json['File']}, Id=${json['Id']}, IdAlias=${json['IdAlias']}, tenantId=$tenantId, Msg=${json['Msg']}');
        return true;
      }());
    }

    // Helper untuk mengekstrak path file dari array Files atau field File
    String extractFilePath(dynamic fileData) {
      String filePath = fileData.toString().replaceAll('\\', '/');
      
      // Perbaikan untuk bug serialisasi backend yang mengirimkan nama class alih-alih file
      if (filePath.contains('NoboxWhatsapp') || filePath.contains('MessageResponse')) {
        return '';
      }

      if (fileData is Map) {
        if (fileData['Filename'] != null) filePath = fileData['Filename'].toString();
        else if (fileData['url'] != null) filePath = fileData['url'].toString();
        else if (fileData['Url'] != null) filePath = fileData['Url'].toString();
        else if (fileData['URL'] != null) filePath = fileData['URL'].toString();
        else if (fileData['link'] != null) filePath = fileData['link'].toString();
        else if (fileData['Link'] != null) filePath = fileData['Link'].toString();
        else {
          for (var value in fileData.values) {
            final valStr = value?.toString().trim() ?? '';
            if (_isWebLink(valStr)) {
              filePath = valStr;
              break;
            }
          }
        }
      } else if (filePath.startsWith('{') || filePath.startsWith('[')) {
        try {
          final decoded = jsonDecode(filePath);
          final fileMap = decoded is List ? (decoded.isNotEmpty ? decoded.first : {}) : decoded;
          if (fileMap is Map) {
            if (fileMap['Filename'] != null) filePath = fileMap['Filename'].toString();
            else if (fileMap['url'] != null) filePath = fileMap['url'].toString();
            else if (fileMap['Url'] != null) filePath = fileMap['Url'].toString();
            else if (fileMap['URL'] != null) filePath = fileMap['URL'].toString();
            else if (fileMap['link'] != null) filePath = fileMap['link'].toString();
            else if (fileMap['Link'] != null) filePath = fileMap['Link'].toString();
            else {
              // Fallback: cari nilai apapun di dalam JSON yang terlihat seperti URL
              for (var value in fileMap.values) {
                final valStr = value?.toString().trim() ?? '';
                if (_isWebLink(valStr)) {
                  filePath = valStr;
                  break;
                }
              }
            }
          }
        } catch (_) {}
      }
      
      // Bersihkan tipe MIME atau parameter query (misal: .ogg; codecs=opus)
      if (filePath.contains(';')) {
        filePath = filePath.split(';').first;
      }
      if (filePath.contains('?')) {
        filePath = filePath.split('?').first;
      }
      return filePath.trim();
    }

    String formatMediaUrl(String path) {
      if (path.isEmpty) return path;
      var raw = path.replaceAll('\\', '/').trim();
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
      if (raw.startsWith('/')) raw = raw.substring(1);
      if (raw.toLowerCase().startsWith('upload/')) {
        return 'https://id.nobox.ai/$raw';
      }
      return 'https://id.nobox.ai/upload/$raw';
    }

    String extractOriginalName(dynamic fileData) {
      if (fileData is Map) {
        return fileData['OriginalName']?.toString() ?? '';
      } else if (fileData is String && (fileData.startsWith('{') || fileData.startsWith('['))) {
        try {
          final decoded = jsonDecode(fileData);
          final fileMap = decoded is List ? (decoded.isNotEmpty ? decoded.first : {}) : decoded;
          if (fileMap is Map) {
            return fileMap['OriginalName']?.toString() ?? '';
          }
        } catch (_) {}
      }
      return '';
    }

    bool isAbsoluteSticker(dynamic fileData, String? typeVal, String filePath, String originalName, String content) {
      if (isAudioFile(filePath) || isAudioFile(originalName) || isVoiceNoteString(filePath) || isVoiceNoteString(originalName)) {
        return false;
      }
      if (typeVal == '16' || typeVal == '17' || typeVal == '7') return true;
      final fLower = filePath.toLowerCase();
      final oLower = originalName.toLowerCase();
      final cLower = content.toLowerCase();
      if (fLower.contains('.webm') || oLower.contains('.webm') ||
          fLower.contains('.tgs') || oLower.contains('.tgs') ||
          fLower.contains('.webp') || oLower.contains('.webp') ||
          fLower.contains('.ezgif') || oLower.contains('.ezgif') ||
          fLower.contains('sticker') || oLower.contains('sticker') ||
          fLower.contains('stiker') || oLower.contains('stiker') ||
          cLower.contains('stiker bergerak')) {
        return true;
      }
      final jsonType = (json['Type'] ?? json['MessageType'] ?? '').toString().toLowerCase();
      if (jsonType == '16' || jsonType == '17' || jsonType == '7' || jsonType.contains('sticker') || jsonType.contains('stiker')) return true;

      // Cek metadata stiker dari WhatsApp / Baileys / WaaS / NoBox API
      try {
        final rawFileStr = fileData != null ? jsonEncode(fileData).toLowerCase() : '';
        final rawJsonStr = jsonEncode(json).toLowerCase();
        if (rawFileStr.contains('"issticker":true') ||
            rawFileStr.contains('"isanimated":true') ||
            rawFileStr.contains('"isanimatedsticker":true') ||
            rawFileStr.contains('"assticker":true') ||
            rawFileStr.contains('"mimetype":"image/webp"') ||
            rawFileStr.contains('image/webp') ||
            rawFileStr.contains('video/webm') ||
            rawFileStr.contains('application/x-tgsticker') ||
            rawFileStr.contains('animated') ||
            rawFileStr.contains('sticker') ||
            rawJsonStr.contains('"issticker":true') ||
            rawJsonStr.contains('"isanimated":true') ||
            rawJsonStr.contains('"isanimatedsticker":true') ||
            rawJsonStr.contains('"assticker":true') ||
            rawJsonStr.contains('"mimetype":"image/webp"') ||
            rawJsonStr.contains('stiker bergerak') ||
            rawJsonStr.contains('animated sticker') ||
            rawJsonStr.contains('video/webm') ||
            rawJsonStr.contains('application/x-tgsticker') ||
            rawJsonStr.contains('"sticker":')) {
          return true;
        }
      } catch (_) {}
      return false;
    }

    bool isAnimated(dynamic fileData, String filePath, String originalName, String content, String? typeVal) {
      if (typeVal == '17') return true;
      final fLower = filePath.toLowerCase();
      final oLower = originalName.toLowerCase();
      if (fLower.contains('.webm') || oLower.contains('.webm') || fLower.contains('.tgs') || oLower.contains('.tgs') || fLower.contains('.mp4') || oLower.contains('.mp4') || content.toLowerCase().contains('bergerak') || content.toLowerCase().contains('animated') || content.contains('🎬')) return true;
      try {
        final rawFileStr = fileData != null ? jsonEncode(fileData).toLowerCase() : '';
        final rawJsonStr = jsonEncode(json).toLowerCase();
        if (rawFileStr.contains('"isanimated":true') || rawFileStr.contains('"isanimatedsticker":true') || rawFileStr.contains('video/webm') || rawFileStr.contains('video/mp4') || rawFileStr.contains('animated') || rawJsonStr.contains('"isanimated":true') || rawJsonStr.contains('"isanimatedsticker":true') || rawJsonStr.contains('video/webm') || rawJsonStr.contains('video/mp4') || rawJsonStr.contains('animated sticker') || rawJsonStr.contains('stiker bergerak')) return true;
      } catch (_) {}
      return false;
    }

    String? docName;
    String? docUrl;

    final bool isLocation = content.contains('[-{=||=}-]') ||
        (json['Msg'] != null && json['Msg'].toString().contains('[-{=||=}-]')) ||
        (json['Content'] != null && json['Content'].toString().contains('[-{=||=}-]')) ||
        typeVal == '15' ||
        typeVal == '11' ||
        (json['Msg'] != null && json['Msg'].toString().toLowerCase().contains('"lat":'));

    if (isLocation) {
      msgType = MessageType.text;
      final rawCoord = (json['Msg']?.toString().contains('[-{=||=}-]') == true)
          ? json['Msg'].toString()
          : ((json['Content']?.toString().contains('[-{=||=}-]') == true)
              ? json['Content'].toString()
              : content);
      content = rawCoord;
    } else if (json['Files'] != null && json['Files'] is List && (json['Files'] as List).isNotEmpty) {
      final firstFile = (json['Files'] as List).first;
      final filePath = extractFilePath(firstFile);
      final originalName = extractOriginalName(firstFile);
      // Deteksi stiker MUTLAK PERTAMA — baik stiker diam maupun bergerak (.webm/.tgs/.webp) dari semua channel
      if (isAbsoluteSticker(firstFile, typeVal, filePath, originalName, content)) {
        msgType = MessageType.sticker;
        imgUrl = formatMediaUrl(filePath);
        content = isAnimated(firstFile, filePath, originalName, content, typeVal) ? '🎬 Sticker' : '🌟 Sticker';
      } else if (isAudioFile(filePath) || isAudioFile(originalName) || _isPttFile(firstFile) || isVoiceNoteString(originalName) || isVoiceNoteString(filePath)) {
        // Voice note: cek ekstensi audio ATAU flag Ptt:true ATAU nama file mengandung voice note — SEBELUM cek document (type 5)
        // Server NoBox kadang mengembalikan Type=5 untuk voice notes
        msgType = MessageType.voice;
        audioPath = formatMediaUrl(filePath);
        content = '';
      } else if (typeVal == '5' || _isDocumentFlag(firstFile)) {
        // Jika dari API diset sebagai Dokumen (5) atau ada flag IsDocument: true
        msgType = MessageType.document;
        docName = originalName.isNotEmpty ? originalName : filePath.split('/').last;
        docUrl = formatMediaUrl(filePath);
        if (content.isEmpty) content = '📄 $docName';
      } else if (isVideoFile(filePath) || isVideoFile(originalName)) {
        msgType = MessageType.video;
        videoUrl = formatMediaUrl(filePath);
        content = '🎬 Video';
      } else if (_isImageFile(filePath) || _isImageFile(originalName)) {
        msgType = MessageType.image;
        imgUrl = formatMediaUrl(filePath);
      } else if (typeVal == '2') {
        // Fallback berdasarkan API Type saat ekstensi tidak dikenali
        if (isVoiceNoteString(filePath) || content.contains('Voice Note') || content.contains('🎵') || (content.isEmpty && !_isWebLink(filePath))) {
          msgType = MessageType.voice;
          audioPath = formatMediaUrl(filePath);
          content = '';
        } else {
          msgType = MessageType.text; // Ignore buggy Type=2 if it's clearly a text message (like a link)
          if (content.isEmpty || content.startsWith('{') || content.startsWith('[')) {
            content = filePath; // Tampilkan isi link jika content kosong
          }
        }
      } else if (typeVal == '4') {
        msgType = MessageType.video;
        videoUrl = formatMediaUrl(filePath);
        content = '🎬 Video';
      } else if (typeVal == '3') {
        msgType = MessageType.image;
        imgUrl = formatMediaUrl(filePath);
      } else if (typeVal == '15' || typeVal == '11' || (json['Msg'] != null && json['Msg'].toString().toLowerCase().contains('"lat":'))) {
        msgType = MessageType.text;
        if (!content.contains('[-{=||=}-]')) {
          content = '📍 Location';
        }
      } else if (typeVal == '14' || typeVal == '10') {
        msgType = MessageType.text;
        content = '👤 Contact';
      } else if (filePath.isNotEmpty) {
        docName = originalName.isNotEmpty ? originalName : filePath.split('/').last;
        if (docName.toLowerCase().contains('document(empty)')) {
          msgType = MessageType.text;
          // Pertahankan text content aslinya (kemungkinan ini adalah Link / Caption / Teks lokasi)
          if (content.isEmpty || content.startsWith('{') || content.startsWith('[')) {
            content = '📍 Location';
          }
        } else {
          msgType = MessageType.document;
          docUrl = formatMediaUrl(filePath);
          if (content.isEmpty) content = '📄 $docName';
        }
      }
    } else if (json['File'] != null && json['File'].toString().isNotEmpty) {
      final filePath = extractFilePath(json['File']);
      final originalName = extractOriginalName(json['File']);
      // Deteksi stiker MUTLAK PERTAMA — baik stiker diam maupun bergerak (.webm/.tgs/.webp) dari semua channel
      if (isAbsoluteSticker(json['File'], typeVal, filePath, originalName, content)) {
        msgType = MessageType.sticker;
        imgUrl = formatMediaUrl(filePath);
        content = isAnimated(json['File'], filePath, originalName, content, typeVal) ? '🎬 Sticker' : '🌟 Sticker';
      } else if (typeVal == '2' || isAudioFile(filePath) || isAudioFile(originalName) || _isPttFile(json['File']) || isVoiceNoteString(originalName) || isVoiceNoteString(filePath)) {
        // Voice note: cek typeVal=='2', ekstensi audio, nama file, ATAU flag Ptt:true — sebelum cek document (type 5)
        if (isAudioFile(filePath) || isAudioFile(originalName) || _isPttFile(json['File']) || isVoiceNoteString(originalName) || isVoiceNoteString(filePath) || (content.trim().isEmpty && !_isWebLink(filePath) && filePath.isNotEmpty)) {
          msgType = MessageType.voice;
          audioPath = formatMediaUrl(filePath);
          content = '';
        } else {
          msgType = MessageType.text; // Ignore buggy Type=2 if it's clearly a text message (like a link)
          if (content.trim().isEmpty || content.startsWith('{') || content.startsWith('[')) {
            content = filePath.isNotEmpty ? filePath : 'Pesan tidak dapat ditampilkan';
          }
        }
      } else if (typeVal == '5' || _isDocumentFlag(json['File'])) {
        docName = originalName.isNotEmpty ? originalName : filePath.split('/').last;
        if (docName.toLowerCase().contains('document(empty)')) {
          msgType = MessageType.text;
          if (content.isEmpty || content.startsWith('{') || content.startsWith('[')) {
            content = '📍 Location';
          }
        } else {
          msgType = MessageType.document;
          docUrl = formatMediaUrl(filePath);
          if (content.isEmpty) content = '📄 $docName';
        }
      } else if (isVideoFile(filePath) || isVideoFile(originalName)) {
        msgType = MessageType.video;
        videoUrl = formatMediaUrl(filePath);
        content = '🎬 Video';
      } else if (_isImageFile(filePath) || _isImageFile(originalName)) {
        msgType = MessageType.image;
        imgUrl = formatMediaUrl(filePath);
      } else if (typeVal == '4') {
        msgType = MessageType.video;
        videoUrl = formatMediaUrl(filePath);
        content = '🎬 Video';
      } else if (typeVal == '3') {
        msgType = MessageType.image;
        imgUrl = formatMediaUrl(filePath);
      } else if (typeVal == '15' || typeVal == '11' || (json['Msg'] != null && json['Msg'].toString().toLowerCase().contains('"lat":'))) {
        msgType = MessageType.text;
        if (!content.contains('[-{=||=}-]')) {
          content = '📍 Location';
        }
      } else if (typeVal == '14' || typeVal == '10') {
        msgType = MessageType.text;
        content = '👤 Contact';
      } else if (filePath.isNotEmpty) {
        docName = originalName.isNotEmpty ? originalName : filePath.split('/').last;
        if (docName.toLowerCase().contains('document(empty)')) {
          msgType = MessageType.text;
          if (content.isEmpty || content.startsWith('{') || content.startsWith('[')) {
            content = '📍 Location';
          }
        } else {
          msgType = MessageType.document;
          docUrl = formatMediaUrl(filePath);
          if (content.isEmpty) content = '📄 $docName';
        }
      }
    } else if (typeVal == '2' || content.contains('🎵 Voice Note')) {
      // FIX BUG: Backend sering melabeli pesan berisi Link URL sebagai Type 2 (Voice Note)
      if (typeVal == '2' && !content.contains('🎵 Voice Note') && content.trim().isNotEmpty) {
        msgType = MessageType.text;
      } else {
        msgType = MessageType.voice;
        audioPath = '';
        content = '';
      }
    } else if ((typeVal == '16' || typeVal == '7' || content.contains('.webp') || content.contains('.tgs')) && content.trim().isNotEmpty && !content.startsWith('{') && !content.startsWith('[')) {
      // Fallback khusus stiker jika URL dikirim mentah di dalam field Msg
      msgType = MessageType.sticker;
      final cleanedPath = content.trim();
      imgUrl = formatMediaUrl(cleanedPath);
      content = '🌟 Sticker';
    } else if ((typeVal == '16' || typeVal == '3' || typeVal == '4' || typeVal == '5' || typeVal == '2') && (content.startsWith('{') || content.startsWith('['))) {
      // Fallback: API NoBox sering mengirim URL media di dalam field Msg bukan di Files/File
      final filePath = extractFilePath(content);
      if (filePath.isNotEmpty) {
        if (typeVal == '3' || _isImageFile(filePath)) {
          msgType = MessageType.image;
          imgUrl = formatMediaUrl(filePath);
          content = '';
        } else if (typeVal == '4' || isVideoFile(filePath)) {
          msgType = MessageType.video;
          videoUrl = formatMediaUrl(filePath);
          content = '🎬 Video';
        } else if (typeVal == '2' || isAudioFile(filePath) || isVoiceNoteString(filePath)) {
          msgType = MessageType.voice;
          audioPath = formatMediaUrl(filePath);
          content = '';
        } else if (typeVal == '5') {
          msgType = MessageType.document;
          docUrl = formatMediaUrl(filePath);
          docName = extractOriginalName(content);
          if (docName.isEmpty) docName = filePath.split('/').last;
          content = '📄 $docName';
        } else if (typeVal == '16') {
          msgType = MessageType.sticker;
          imgUrl = formatMediaUrl(filePath);
          content = '🌟 Sticker';
        }
      } else if (typeVal == '16' || typeVal == '3') {
        msgType = MessageType.text;
        // FIX: Untuk pesan edit WhatsApp atau tipe tidak dikenal, coba ekstrak teks dulu
        // Jika ada konten teks valid (bukan JSON kosong), gunakan itu
        final hasReadableText = content.isNotEmpty && 
            !content.startsWith('{') && 
            !content.startsWith('[') &&
            !content.toLowerCase().contains('site.inbox.deletedmessage');
        if (!hasReadableText) {
          content = kUnsupportedWhatsAppLabel;
        }
      }
    } else if (typeVal == '16' || typeVal == '3') {
      // No Files/File data available
      msgType = MessageType.text;
      // FIX: Coba ekstrak teks readable untuk pesan edit/unknown type
      final hasReadableText = content.isNotEmpty && 
          !content.startsWith('{') && 
          !content.startsWith('[') &&
          !content.toLowerCase().contains('site.inbox.deletedmessage');
      if (!hasReadableText) {
        content = kUnsupportedWhatsAppLabel;
      }
    } else if (typeVal == '15' || typeVal == '11') {
      msgType = MessageType.text;
      if (!content.contains('[-{=||=}-]')) {
        content = '📍 Location';
      }
    } else if (typeVal == '14' || typeVal == '10') {
      msgType = MessageType.text;
      content = '👤 Contact';
    } else if (typeVal != null && typeVal.isNotEmpty) {
      // FIX: Catch-all untuk tipe pesan tidak dikenal (misal pesan edit WhatsApp dengan type baru)
      // Coba ekstrak teks readable sebelum fallback ke error
      msgType = MessageType.text;
      final hasReadableText = content.isNotEmpty &&
          !content.startsWith('{') &&
          !content.startsWith('[') &&
          !content.toLowerCase().contains('site.inbox.deletedmessage');
      if (!hasReadableText) {
        content = kUnsupportedWhatsAppLabel;
      }
      debugPrint('⚠️ Message.fromJson: Unknown typeVal=$typeVal, content="${content.length > 50 ? content.substring(0, 50) : content}" -> treated as text');
    }

    // Fallback: if this is an image message but content is empty, set readable label
    if (msgType == MessageType.image && content.trim().isEmpty) {
      content = '📷 Photo';
    }
    
    // Format time — parse ISO timestamp to readable format
    final rawTime = json['In']?.toString() ?? json['timestamp']?.toString() ?? json['CreatedAt']?.toString() ?? '';
    final formattedTime = rawTime.contains('T') ? _formatIsoTime(rawTime) : rawTime;

    // Debug: log audio path for voice messages
    if (msgType == MessageType.voice) {
      debugPrint('🔊 Message.fromJson VOICE: id=$id, audioPath=$audioPath, Files=${json['Files']}, File=${json['File']}, Type=$typeVal');
    }

    int parsedAck = 2; // Default to sent if not present
    final ackVal = json['Ack'] ?? json['ack'] ?? json['ack_status'];
    if (ackVal != null) {
      if (ackVal is int) parsedAck = ackVal;
      else if (ackVal is String) parsedAck = int.tryParse(ackVal) ?? 2;
    } else {
      parsedAck = isSystem ? 0 : 2;
    }

    // FIX: Jika server mengirim Ack: 0 untuk pesan biasa (seperti Telegram/Forward), 
    // ubah menjadi 1 (Centang) karena pesan ini sudah ada di database server.
    // Jam (0) hanya untuk pesan yang belum sampai ke server sama sekali.
    if (parsedAck == 0 && !isSystem) {
      parsedAck = 1;
    }

    // FIX: Parse pesan balasan (Reply Context) agar tidak hilang saat keluar masuk halaman (atau saat via SignalR)
    Message? parsedRepliedMsg;
    final rawReplyMsg = json['ReplyMsg'] ?? json['replyMsg'];
    final rawReplyId = json['ReplyId'] ?? json['replyId'] ?? json['ReplyMsgId'] ?? json['replyMsgId'];
    final rawReplyFrom = json['ReplyFrom'] ?? json['replyFrom'];

    if ((rawReplyMsg != null && rawReplyMsg.toString().isNotEmpty) || (rawReplyId != null && rawReplyId.toString().isNotEmpty && rawReplyId.toString() != '0')) {
      parsedRepliedMsg = Message(
        id: rawReplyId?.toString() ?? '',
        content: rawReplyMsg?.toString().isNotEmpty == true ? rawReplyMsg.toString() : 'Pesan terkait...',
        isMe: rawReplyFrom?.toString() == currentUserEmail,
        time: '', // Waktu tidak dikirimkan oleh API untuk pesan balasan
        rawTime: '',
      );
    }

    // Parse audio duration (dalam detik) jika ini pesan suara
    int parsedAudioDuration = 0;
    if (msgType == MessageType.voice) {
      final d = json['Duration'] ?? json['duration'] ?? json['AudioDuration'] ?? json['audioDuration'] ?? json['Seconds'] ?? json['seconds'] ?? json['Length'] ?? json['length'];
      if (d != null) {
        if (d is num) {
          parsedAudioDuration = d.toInt();
        } else {
          parsedAudioDuration = int.tryParse(d.toString()) ?? (double.tryParse(d.toString())?.round() ?? 0);
        }
      }
      if (parsedAudioDuration == 0 && json['Files'] is List && (json['Files'] as List).isNotEmpty) {
        final f = (json['Files'] as List).first;
        if (f is Map) {
          final fd = f['Duration'] ?? f['duration'] ?? f['Seconds'] ?? f['seconds'] ?? f['Length'] ?? f['length'];
          if (fd != null) {
            if (fd is num) {
              parsedAudioDuration = fd.toInt();
            } else {
              parsedAudioDuration = int.tryParse(fd.toString()) ?? (double.tryParse(fd.toString())?.round() ?? 0);
            }
          }
        }
      }
      if (parsedAudioDuration == 0 && json['File'] != null) {
        if (json['File'] is Map) {
          final fd = json['File']['Duration'] ?? json['File']['duration'] ?? json['File']['Seconds'] ?? json['File']['seconds'];
          if (fd != null) {
            if (fd is num) {
              parsedAudioDuration = fd.toInt();
            } else {
              parsedAudioDuration = int.tryParse(fd.toString()) ?? (double.tryParse(fd.toString())?.round() ?? 0);
            }
          }
        } else if (json['File'] is String && (json['File'].toString().startsWith('{') || json['File'].toString().startsWith('['))) {
          try {
            final decoded = jsonDecode(json['File']);
            final fMap = decoded is List ? (decoded.isNotEmpty ? decoded.first : null) : decoded;
            if (fMap is Map) {
              final fd = fMap['Duration'] ?? fMap['duration'] ?? fMap['Seconds'] ?? fMap['seconds'];
              if (fd != null) {
                if (fd is num) {
                  parsedAudioDuration = fd.toInt();
                } else {
                  parsedAudioDuration = int.tryParse(fd.toString()) ?? (double.tryParse(fd.toString())?.round() ?? 0);
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    if (msgType == MessageType.text && content.trim().isEmpty) {
      content = "⚠️ Pesan gagal diproses oleh server.";
    }

    final parsedMsg = Message(
      id: id,
      idAlias: parsedIdAlias,
      content: content,
      isMe: isMe,
      time: formattedTime,
      rawTime: rawTime,
      status: MessageStatus.read,
      isSystemMessage: isSystem,
      messageType: msgType,
      imageUrl: imgUrl,
      audioPath: audioPath,
      audioDuration: parsedAudioDuration,
      videoUrl: videoUrl,
      documentName: docName,
      documentUrl: docUrl,
      ack: parsedAck,
      repliedMessage: parsedRepliedMsg,
      fromId: json['From']?.toString() ?? json['FromId']?.toString() ?? json['IdAccount']?.toString(),
      toId: json['To']?.toString() ?? json['ToId']?.toString() ?? json['ChAccId']?.toString(),
      roomId: json['RoomId']?.toString() ?? '',
    );

      return parsedMsg;
    }

  Message copyWith({
    String? id,
    String? content,
    bool? isMe,
    String? time,
    String? rawTime,
    MessageStatus? status,
    Message? repliedMessage,
    bool? isSystemMessage,
    MessageType? messageType,
    String? audioPath,
    int? audioDuration,
    String? imagePath,
    String? imageUrl,
    String? videoUrl,
    String? documentName,
    String? documentUrl,
    int? ack,
    String? fromId,
    String? toId,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      isMe: isMe ?? this.isMe,
      time: time ?? this.time,
      rawTime: rawTime ?? this.rawTime,
      status: status ?? this.status,
      repliedMessage: repliedMessage ?? this.repliedMessage,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      messageType: messageType ?? this.messageType,
      audioPath: audioPath ?? this.audioPath,
      audioDuration: audioDuration ?? this.audioDuration,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      documentName: documentName ?? this.documentName,
      documentUrl: documentUrl ?? this.documentUrl,
      ack: ack ?? this.ack,
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'isMe': isMe,
      'time': time,
      'rawTime': rawTime,
      'status': status.index,
      'repliedMessage': repliedMessage?.toMap(),
      'isSystemMessage': isSystemMessage,
      'messageType': messageType.index,
      'audioPath': audioPath,
      'audioDuration': audioDuration,
      'imagePath': imagePath,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'documentName': documentName,
      'documentUrl': documentUrl,
      'ack': ack,
      'fromId': fromId,
      'toId': toId,
      'roomId': roomId,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      isMe: map['isMe'] == true,
      time: map['time']?.toString() ?? '',
      rawTime: map['rawTime']?.toString() ?? '',
      status: (map['status'] != null && map['status'] is int && (map['status'] as int) < MessageStatus.values.length) 
          ? MessageStatus.values[map['status'] as int] 
          : MessageStatus.sent,
      repliedMessage: map['repliedMessage'] != null 
          ? Message.fromMap(Map<String, dynamic>.from(map['repliedMessage'] as Map)) 
          : null,
      isSystemMessage: map['isSystemMessage'] == true,
      messageType: (map['messageType'] != null && map['messageType'] is int && (map['messageType'] as int) < MessageType.values.length) 
          ? MessageType.values[map['messageType'] as int] 
          : MessageType.text,
      audioPath: map['audioPath']?.toString(),
      audioDuration: (map['audioDuration'] as num?)?.toInt() ?? 0,
      imagePath: map['imagePath']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      videoUrl: map['videoUrl']?.toString(),
      documentName: map['documentName']?.toString(),
      documentUrl: map['documentUrl']?.toString(),
      ack: (map['ack'] as num?)?.toInt() ?? 0,
      fromId: map['fromId']?.toString(),
      toId: map['toId']?.toString(),
      roomId: map['roomId']?.toString() ?? '',
    );
  }
}
