import 'message.dart';

// =====================================================================
// FITUR: Model Percakapan (Conversation/Chatroom)
// FILE: lib/core/model/conversation.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Class model untuk menampung data list chat/room di halaman utama chat
// =====================================================================
class Conversation {

  // DEBUG: Static log buffer for API analysis
  static final List<String> _debugApiLog = [];
  static void dumpDebugLog() {
    print(dumpDebugLogStr());
  }

  static String dumpDebugLogStr() {
    if (_debugApiLog.isEmpty) {
      return '=== API DEBUG LOG EMPTY ===';
    }
    final sb = StringBuffer();
    sb.writeln('=== API DEBUG LOG (${_debugApiLog.length} messages) ===');
    for (var log in _debugApiLog) {
      sb.writeln(log);
    }
    sb.writeln('===========================');
    return sb.toString();
  }

  final String id;
  final String contactId; // CtId dari Chatrooms/List — dibutuhkan untuk Inbox/Send dan Inbox/Get
  final String participantEmail;
  final String lastMessage;
  final String lastMessageTime;
  final int unreadCount;
  final String status;
  final String agentName;
  final List<String> tags;
  final String? avatarUrl;
  final String? lastMessageType;
  final String channelName;
  final String channelType;
  final bool isPinned;
  final String chId;
  final String funnel;
  final String tagsIds;
  final String funnelId;
  final bool isGroup;
  final bool isBlocked;
  final bool isLastMessageFromMe;
  final bool needReply;
  final String accountId;
  final String ctRealId;
  final String link;
  final String campaign;
  final String deal;
  final String groupName;
  final String groupId;
  final String sdrMsg; // "me" (agent), "you" (customer)
  final String extId; // CtIdExt / ExtId - Telegram user ID or phone number

  Conversation({
    required this.id,
    this.contactId = '',
    required this.participantEmail,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.status = 'Unassigned',
    this.agentName = '',
    this.tags = const [],
    this.avatarUrl,
    this.lastMessageType,
    this.channelName = '',
    this.channelType = '',
    this.isPinned = false,
    this.chId = '',
    this.funnel = '',
    this.tagsIds = '',
    this.funnelId = '',
    this.isGroup = false,
    this.isBlocked = false,
    this.isLastMessageFromMe = false,
    this.needReply = false,
    this.accountId = '',
    this.ctRealId = '',
    this.link = '',
    this.campaign = '',
    this.deal = '',
    this.groupName = '',
    this.groupId = '',
    this.sdrMsg = '',
    this.extId = '',
  });

  // FITUR: Parse dari JSON
  // FUNGSI: Mengubah response JSON list chat API menjadi objek Conversation
  factory Conversation.fromJson(Map<String, dynamic> json) {
    // Parse tags dari JSON - Menangani tipe dinamis dengan aman (int, String, List)
    List<String> parsedTags = [];
    dynamic tagsData = json['Tags'] ?? json['tags'] ?? json['TagsNm'];
    String cleanTag(String s) => s
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');

    if (tagsData != null) {
      if (tagsData is List) {
        parsedTags = tagsData.map((e) => cleanTag(e.toString().trim())).where((e) => e.isNotEmpty).toList();
      } else if (tagsData is String && tagsData.isNotEmpty) {
        parsedTags = tagsData.split(',').map((e) => cleanTag(e.trim())).where((e) => e.isNotEmpty).toList();
      } else if (tagsData is int || tagsData is double) {
        parsedTags = [cleanTag(tagsData.toString())];
      }
    }
    // Kita secara eksplisit menghindari fallback ke TagsIds karena hanya berisi angka ID mentah, bukan nama.

    // Map St (integer) dari Chatrooms/List → string status yang bisa dibaca manusia
    // 1 = Unassigned, 2 = Assigned, 3 = Resolved
    String resolveStatus(dynamic stValue) {
      if (stValue == null) return 'Unassigned';
      if (stValue is String) {
        final lower = stValue.toLowerCase();
        if (lower == 'unassigned') return 'Unassigned';
        if (lower == 'assigned') return 'Assigned';
        if (lower == 'resolved') return 'Resolved';
        if (lower == 'archived') return 'Archived';
      }
      final st = stValue is int ? stValue : int.tryParse(stValue.toString());
      switch (st) {
        case 1: return 'Unassigned';
        case 2: return 'Assigned';
        case 3: return 'Resolved';
        case 4: return 'Archived';
        default: return 'Unassigned';
      }
    }

    // Helper pencarian (lookup) tidak peka huruf besar/kecil (Case-insensitive)
    dynamic getValue(List<String> keys) {
      for (final k in keys) {
        if (json.containsKey(k) && json[k] != null) return json[k];
      }
      return null;
    }

    // Coba beberapa kemungkinan nama kunci (key) untuk Tags dan Funnel IDs berdasarkan format backend
    // Parse TagsIds dengan aman karena nilainya bisa berupa int, String, atau List
    dynamic rawTagsIdsData = getValue(['TagsIds', 'tags_ids', 'tagsIds']);
    String rawTagsIds = '';
    if (rawTagsIdsData is List) {
      rawTagsIds = rawTagsIdsData.map((e) => e.toString()).join(',');
    } else if (rawTagsIdsData != null) {
      rawTagsIds = rawTagsIdsData.toString();
    }
    final rawFnId = getValue(['FnId', 'fn_id', 'fnId', 'FunnelId'])?.toString() ?? '';
    final rawFnName = getValue(['FnNm', 'fn_nm', 'Fn', 'fn'])?.toString() ?? '';

    // FIX: Prioritaskan LastMsg jika berisi teks pesan yang nyata (bukan placeholder media generik).
    // Category HANYA boleh digunakan jika LastMsg berupa placeholder kosong/generik
    // (misal: "document(empty)", "document", "voice note", "photo", "file", atau kosong),
    // sehingga media seperti Voice Note/Photo tidak berubah menjadi sekadar "Document" saat refresh,
    // DAN pesan teks baru dari bot/pengguna (seperti Muadzin Bot) TIDAK tertimpa oleh JSON media lama di Category!
    String resolveLastMessage(dynamic lastMsgData, dynamic categoryData) {
      final str1 = (lastMsgData?.toString() ?? '').trim();
      final str2 = (categoryData?.toString() ?? '').trim();

      // Jika str1 sendiri sudah berupa JSON (payload media terbaru), gunakan str1
      if (str1.startsWith('{') || str1.startsWith('[')) return str1;

      final lower1 = str1.toLowerCase();
      final isGenericPlaceholder = lower1.isEmpty ||
          lower1 == 'null' ||
          lower1 == 'document(empty)' ||
          lower1 == 'voice(empty)' ||
          lower1 == 'image(empty)' ||
          lower1 == 'video(empty)' ||
          lower1 == 'audio(empty)' ||
          lower1 == 'document' ||
          lower1 == 'file' ||
          lower1 == 'voice note' ||
          lower1 == 'voice' ||
          lower1 == 'audio' ||
          lower1 == 'photo' ||
          lower1 == 'foto' ||
          lower1 == 'image' ||
          lower1 == 'video' ||
          lower1 == 'attachment' ||
          lower1 == 'lampiran' ||
          lower1 == 'pesan suara' ||
          lower1 == '🎤 pesan suara';

      // Jika str1 adalah placeholder generik dan str2 memiliki payload JSON media, pakai str2
      if (isGenericPlaceholder && (str2.startsWith('{') || str2.startsWith('['))) {
        return str2;
      }

      // Jika str1 berisi teks nyata (seperti siaran Muadzin Bot atau obrolan pengguna),
      // SELALU prioritaskan str1! Jangan timpa dengan Category lama!
      if (str1.isNotEmpty && lower1 != 'null') {
        return str1;
      }

      return str2;
    }

    String finalLastMessage = resolveLastMessage(
      getValue(['LastMsg', 'last_message']),
      getValue(['Category'])
    );

    if (finalLastMessage.contains('[-{=||=}-]')) {
      finalLastMessage = '📍 Location';
    }

    // FIX: Normalisasi LastMessageType dan LastMessage agar Voice Note & Media tidak berubah menjadi "Lampiran" / Teks biasa
    String? rawLastMessageType = getValue(['LastMessageType', 'last_message_type'])?.toString();
    final lower = finalLastMessage.trim().toLowerCase();

    final isGenericMediaWord = lower.isEmpty ||
        lower == 'null' ||
        lower == 'document(empty)' ||
        lower == 'voice(empty)' ||
        lower == 'image(empty)' ||
        lower == 'video(empty)' ||
        lower == 'audio(empty)' ||
        lower == 'lampiran' ||
        lower == 'attachment' ||
        lower == 'document' ||
        lower == 'file' ||
        lower == 'voice' ||
        lower == 'voice note' ||
        lower == 'audio' ||
        lower == 'pesan suara' ||
        lower == 'photo' ||
        lower == 'foto' ||
        lower == 'image' ||
        lower == 'video';

    final isAudioLastMsg = lower.contains('🎤') ||
        lower.contains('pesan suara') ||
        lower.contains('voice note') ||
        lower.contains('.ogg') ||
        lower.contains('.opus') ||
        lower.contains('.mp3') ||
        lower.contains('.wav') ||
        lower.contains('.m4a') ||
        lower.contains('voice_') ||
        lower == 'voice(empty)';

    if (isAudioLastMsg || rawLastMessageType == '2' || rawLastMessageType == 'voice' || rawLastMessageType == 'audio') {
      rawLastMessageType = '2';
      if (isGenericMediaWord || finalLastMessage.isEmpty) {
        finalLastMessage = '🎤 Pesan Suara';
      }
    } else if (rawLastMessageType == '3' || rawLastMessageType == 'photo' || rawLastMessageType == 'image') {
      if (isGenericMediaWord || finalLastMessage.isEmpty) {
        finalLastMessage = '📷 Foto';
      }
    } else if (rawLastMessageType == '4' || rawLastMessageType == 'video') {
      if (isGenericMediaWord || finalLastMessage.isEmpty) {
        finalLastMessage = '🎬 Video';
      }
    } else if (rawLastMessageType == '16' || rawLastMessageType == '17' || rawLastMessageType == 'sticker') {
      if (isGenericMediaWord || finalLastMessage.isEmpty) {
        finalLastMessage = '🌟 Sticker';
      }
    } else if (rawLastMessageType == '5' || rawLastMessageType == 'document' || rawLastMessageType == 'file') {
      if (isGenericMediaWord || finalLastMessage.isEmpty) {
        finalLastMessage = '📄 Dokumen';
      }
    } else if (!finalLastMessage.startsWith('{') && !finalLastMessage.startsWith('[')) {
      // Hanya jika pesan adalah teks nyata (bukan kata generik seperti 'Lampiran' atau 'Document'),
      // kita perbaiki tipe jika server nyangkut di tipe media
      if (!isGenericMediaWord && lower.isNotEmpty) {
        if (rawLastMessageType != '1') {
          rawLastMessageType = '1';
        }
      }
    }

    // FIX (Issue 4): Pesan edit/protocol/document(empty)/file kosong → tampilkan placeholder Inggris
    // alih-alih "📎 Lampiran" / fallback Indonesia.
    if (isUnsupportedWhatsAppContent(finalLastMessage)) {
      finalLastMessage = kUnsupportedWhatsAppLabel;
      rawLastMessageType = '1';
    }

    // Helper untuk mendeteksi apakah obrolan benar-benar Group atau Private (individu)
    bool resolveIsGroup() {
      // 1. Cek flag IsGrp atau GrpId resmi dari server NoBox (Chatrooms/List)
      final grpFlag = getValue(['IsGrp', 'IsGroup', 'is_group', 'isGroup']);
      if (grpFlag != null && grpFlag.toString().isNotEmpty && grpFlag.toString() != 'null') {
        final strFlag = grpFlag.toString().trim().toLowerCase();
        if (strFlag == '1' || strFlag == 'true') return true;
        // JANGAN langsung return false jika strFlag == '0', karena server NoBox terkadang
        // mengembalikan IsGrp: 0 untuk grup Telegram dan menyimpan ID-nya di GrpId/CtRealId
      }

      final grpId = getValue(['GrpId', 'grp_id', 'GroupId', 'groupId', 'IdGroup', 'idGroup']);
      if (grpId != null) {
        final gInt = int.tryParse(grpId.toString().trim());
        // FIX: Di Telegram, ID grup bernilai NEGATIF (< 0, contoh -1001234567890).
        // Jangan batasi hanya gInt > 0!
        if (gInt != null && gInt != 0) return true;
        final gStr = grpId.toString().trim();
        if (gStr.isNotEmpty && gStr != '0' && gStr != 'null') {
          if (gStr.startsWith('-')) return true;
        }
      }

      // Cek apakah ada nama grup (Grp / GroupNm)
      final grpName = (getValue(['Grp', 'GroupNm', 'GroupName', 'group_name'])?.toString() ?? '').trim();
      if (grpName.isNotEmpty && grpName != 'null' && grpName != '0') {
        return true;
      }

      final chNm = (getValue(['ChNm', 'ChannelName', 'chnm', 'ChId', 'ch_id', 'Channel'])?.toString() ?? '').trim().toLowerCase();
      final idStr = (getValue(['Id', 'id', 'RoomId', 'room_id'])?.toString() ?? '').trim().toLowerCase();
      final contactStr = (getValue(['CtRealId', 'ct_real_id', 'CtId', 'ContactId', 'IdLink', 'LinkId', 'LinkTmp', 'Link', 'CtIdExt', 'ExtId', 'IdExt'])?.toString() ?? '').trim().toLowerCase();
      final combined = '$chNm $idStr $contactStr';

      // 2. ATURAN GROUP WHATSAPP: Pada channel WhatsApp, JID Grup berakhiran / mengandung '@g.us' atau '@group'.
      if (combined.contains('@g.us') || combined.contains('@group')) {
        return true;
      }

      // 3. ATURAN TELEGRAM: Di Telegram, Grup selalu ber-ID negatif (awalan tanda minus '-').
      final isTelegram = chNm.contains('telegram') || chNm.contains('tg') || chNm == '2' || combined.contains('telegram');
      if (isTelegram) {
        if (idStr.startsWith('-') ||
            contactStr.startsWith('-') ||
            (grpId != null && grpId.toString().trim().startsWith('-'))) {
          return true;
        }
      }

      // 4. ATURAN PRIVATE CHAT WHATSAPP
      if (combined.contains('@s.whatsapp.net') || combined.contains('@c.us')) {
        return false;
      }

      final chatType = (getValue(['ChatType', 'chat_type', 'Type', 'type'])?.toString() ?? '').trim().toLowerCase();
      if (chatType == 'group' || chatType == 'grup' || chatType == 'groupchat') return true;
      if (chatType == 'private' || chatType == 'personal' || chatType == 'user' || chatType == 'contact' || chatType == 'direct') return false;

      return false;
    }

    bool isLastFromMe = 
        getValue(['is_last_message_from_me', 'IsMeLast']) == true ||
        getValue(['is_last_message_from_me', 'IsMeLast']) == 1 ||
        getValue(['SdrMsg', 'sdr_msg', 'Sdr'])?.toString().toLowerCase() == 'me';

    int rawUc = int.tryParse(getValue(['Uc', 'uc', 'UC', 'unread_count', 'UnreadCount', 'Unread', 'unread', 'UnreadMsg', 'UnreadMsgs'])?.toString() ?? '') ?? 0;
    if (isLastFromMe) {
      rawUc = 0;
    }

    final conv = Conversation(
      id: getValue(['Id', 'id', 'RoomId', 'room_id'])?.toString() ?? '',
      // FIX: contactId harus HANYA berisi database ID (CtId, IdLink, LinkId), BUKAN phone number (ExtId) atau JID (IdAlias)
      // ExtId dan IdAlias adalah identitas di channel eksternal (WA/Telegram), bukan IdLink internal database
      contactId: getValue(['CtId', 'IdLink', 'LinkId', 'IdContact', 'ContactId'])?.toString() ?? '',
      participantEmail: getValue(['CtRealNm', 'CtNm', 'Nm', 'nm', 'Ct', 'Name', 'pushName', 'Title', 'participant_email', 'GroupNm', 'GroupName', 'group_name', 'Grp'])?.toString() ?? 'Unknown',
      lastMessage: finalLastMessage,
      lastMessageTime: getValue(['TimeMsg', 'In', 'last_message_time']) ?? '',
      unreadCount: rawUc,
      status: resolveStatus(json['St'] ?? getValue(['Status', 'status'])),
      agentName: getValue(['AssignedAgentName', 'AgentName', 'agent_name']) ?? '',
      tags: parsedTags,
      avatarUrl: _resolveAvatarUrl(json),
      lastMessageType: rawLastMessageType,
      channelName: _resolveChannelName(json),
      channelType: getValue(['ChNm', 'ChannelName', 'chnm'])?.toString() ?? '',
      isPinned: json['IsPin'] == 2 || json['is_pinned'] == true,
      chId: getValue(['ChId', 'ch_id'])?.toString() ?? '',
      accountId: getValue(['IdAccount', 'idAccount', 'AccId', 'acc_id', 'AccountId', 'accountId', 'ChAccId', 'ch_acc_id', 'To', 'to'])?.toString() ?? '',
      funnel: rawFnName,
      tagsIds: rawTagsIds,
      funnelId: rawFnId,
      isGroup: resolveIsGroup(),
      isBlocked: json['CtIsBlock'] == 1 || json['CtIsBlock'] == true,
      isLastMessageFromMe: isLastFromMe,
      needReply: isLastFromMe
          ? false
          : (json['NeedReply'] == 1 || 
              json['NeedReply'] == true || 
              json['IsNeedReply'] == 1 || 
              json['IsNeedReply'] == true ||
              json['isNeedReply'] == 1 ||
              json['isNeedReply'] == true),
      ctRealId: getValue(['CtRealId', 'ct_real_id'])?.toString() ?? '',
      link: getValue(['IdLink', 'LinkId', 'CtId', 'IdContact', 'CtIdExt', 'ExtId', 'IdAlias', 'LinkTmp', 'LinkNm', 'LinkName', 'link_name', 'Link'])?.toString() ?? '',
      campaign: getValue(['CmpNm', 'CampaignNm', 'CampaignName', 'campaign_name', 'Campaign'])?.toString() ?? '',
      deal: getValue(['DealNm', 'DealName', 'deal_name', 'Deal'])?.toString() ?? '',
      groupName: getValue(['Grp', 'GroupNm', 'GroupName', 'group_name'])?.toString() ?? '',
      groupId: () {
        final g = getValue(['GrpId', 'grp_id', 'GroupId', 'groupId', 'IdGroup', 'idGroup']);
        if (g != null && g.toString() != '0' && g.toString() != 'null') {
          final gInt = int.tryParse(g.toString().trim());
          // FIX: Telegram group IDs adalah angka negatif (gInt != 0, bukan gInt > 0)
          if (gInt != null && gInt != 0) return gInt.toString();
          final str = g.toString().trim();
          if (str.isNotEmpty && str != '0' && str != 'null') return str;
        }
        // Fallback untuk Telegram group: periksa apakah CtRealId, LinkTmp, ExtId, atau RoomId merupakan ID negatif
        final ctReal = getValue(['CtRealId', 'ct_real_id'])?.toString().trim() ?? '';
        if (ctReal.startsWith('-')) return ctReal;
        final linkVal = getValue(['LinkTmp', 'IdLink', 'LinkId', 'Link'])?.toString().trim() ?? '';
        if (linkVal.startsWith('-')) return linkVal;
        final extIdVal = getValue(['CtIdExt', 'ExtId', 'IdExt'])?.toString().trim() ?? '';
        if (extIdVal.startsWith('-')) return extIdVal;
        final roomIdVal = getValue(['Id', 'id', 'RoomId', 'room_id'])?.toString().trim() ?? '';
        if (roomIdVal.startsWith('-')) return roomIdVal;
        return '';
      }(),
      sdrMsg: getValue(['SdrMsg', 'sdr_msg', 'Sdr'])?.toString().trim() ?? '',
      extId: getValue(['CtIdExt', 'ExtId', 'IdExt', 'ct_id_ext', 'ctIdExt'])?.toString().trim() ?? '',
    );

    // DEBUG: Accumulate raw API values for analysis
    final _dbgName = getValue(['CtRealNm', 'CtNm', 'Nm', 'nm', 'Ct', 'Name'])?.toString() ?? '?';
    final _dbgIsMe = json['IsMe'];
    final _dbgLastIsMe = json['LastIsMe'];
    final _dbgSdrMsg = getValue(['SdrMsg', 'sdr_msg', 'Sdr']);
    final _dbgNeedReply = json['NeedReply'] ?? json['IsNeedReply'];
    final _dbgLastMsg = (conv.lastMessage.length > 20) ? conv.lastMessage.substring(0, 20) : conv.lastMessage;
    final line = 'CONV [$_dbgName] IsMe=$_dbgIsMe(${_dbgIsMe.runtimeType}) LastIsMe=$_dbgLastIsMe SdrMsg=$_dbgSdrMsg NeedReply=$_dbgNeedReply => fromMe=${conv.isLastMessageFromMe} | msg=$_dbgLastMsg';
    _debugApiLog.add(line);
    if (_debugApiLog.length > 200) _debugApiLog.removeAt(0); // Keep last 200

    return conv;
  }

  // FITUR: Copy With (Duplikasi Object)
  // FUNGSI: Mengganti sebagian property dari object yang sudah ada tanpa merubah aslinya
  Conversation copyWith({
    String? id,
    String? contactId,
    String? participantEmail,
    String? lastMessage,
    String? lastMessageTime,
    int? unreadCount,
    String? status,
    String? agentName,
    List<String>? tags,
    String? avatarUrl,
    String? lastMessageType,
    String? channelName,
    String? channelType,
    bool? isPinned,
    String? chId,
    String? funnel,
    String? tagsIds,
    String? funnelId,
    // FIX: isGroup harus ikut di-copy, supaya tidak ter-reset ke false
    bool? isGroup,
    bool? isBlocked,
    bool? isLastMessageFromMe,
    bool? needReply,
    String? accountId,
    String? ctRealId,
    String? groupId,
    String? sdrMsg,
    String? link,
    String? campaign,
    String? deal,
    String? groupName,
    String? extId,
  }) {
    return Conversation(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      participantEmail: participantEmail ?? this.participantEmail,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      status: status ?? this.status,
      agentName: agentName ?? this.agentName,
      tags: tags ?? this.tags,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      channelName: channelName ?? this.channelName,
      channelType: channelType ?? this.channelType,
      isPinned: isPinned ?? this.isPinned,
      chId: chId ?? this.chId,
      funnel: funnel ?? this.funnel,
      tagsIds: tagsIds ?? this.tagsIds,
      funnelId: funnelId ?? this.funnelId,
      // FIX: Pastikan isGroup ikut dipertahankan saat copyWith dipanggil
      isGroup: isGroup ?? this.isGroup,
      isBlocked: isBlocked ?? this.isBlocked,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      needReply: needReply ?? this.needReply,
      accountId: accountId ?? this.accountId,
      ctRealId: ctRealId ?? this.ctRealId,
      groupId: groupId ?? this.groupId,
      sdrMsg: sdrMsg ?? this.sdrMsg,
      link: link ?? this.link,
      campaign: campaign ?? this.campaign,
      deal: deal ?? this.deal,
      groupName: groupName ?? this.groupName,
      extId: extId ?? this.extId,
    );
  }

  // FITUR: Resolve Avatar URL
  // FUNGSI: Menentukan sumber gambar profile (Avatar) prioritas tertinggi dari JSON
  static String? _resolveAvatarUrl(Map<String, dynamic> json) {
    // Coba beberapa field sumber avatar sesuai urutan prioritas.
    // PENTING: Kita harus mengecek satu per satu karena ?.toString() pada string
    // kosong "" mengembalikan "" (bukan null), yang akan memblokir fallback ?? 
    // dan mencegah penggunaan field selanjutnya seperti LinkImg.
    final candidates = [
      json['Photo'],      // Field utama untuk avatar contact (dari DetailRoom/API)
      json['photo'],
      json['CtImg'],      // Prioritas 2: Info Contact yang diupdate
      json['LinkImg'],    // Prioritas 3: Link Image bawaan channel / grup (sering dipakai backend)
      json['GrpImg'],     // Foto profil grup khusus
      json['GroupImg'],
      json['GroupPhoto'],
      json['Img'],
      json['AvatarUrl'],
      json['avatar_url'],
      json['ProfilePic'],
      json['profile_pic'],
      json['Picture'],
      json['picture'],
    ];

    String? raw;
    for (final val in candidates) {
      if (val == null) continue;
      final str = val.toString().trim();
      if (str.isNotEmpty && str != 'null') {
        final lowerStr = str.toLowerCase();
        if (lowerStr.contains('default') || lowerStr.contains('error:') || str.contains('{')) continue;
        raw = str;
        break;
      }
    }

    if (raw == null) return null;

    // BINGO: C# Backend sering mereturn Windows path backslash (\) seperti "80404711\Contacts\xxx.jpg"
    // Ganti semua backslash menjadi forward slash agar URL valid
    raw = raw.replaceAll('\\', '/');

    // Jika sudah berupa URL penuh, gunakan apa adanya
    if (raw.startsWith('http')) return raw;
    
    // Bersihkan slash di depan jika ada
    if (raw.startsWith('/')) raw = raw.substring(1);
    
    // Jika string dari server sudah mengandung path upload, jangan ditambahkan lagi
    if (raw.toLowerCase().startsWith('upload/')) {
       return 'https://id.nobox.ai/$raw';
    }
    
    // Tambahkan awalan base upload URL untuk path relatif
    return 'https://id.nobox.ai/upload/$raw';
  }

  // FITUR: Resolve Channel Name
  // FUNGSI: Menentukan nama channel yang dipakai (WhatsApp, IG, dll)
  static String _resolveChannelName(Map<String, dynamic> json) {
    final candidates = [
      json['AccNm'], json['ChNm'], json['ChAcc'], json['ChannelAccount'],
      json['accountName'], json['AccountName'], json['account_name']
    ];
    for (final val in candidates) {
      if (val != null && val.toString().isNotEmpty && val.toString() != 'Not Found') {
        return val.toString();
      }
    }
    return '';
  }

  // FITUR: Konversi ke ChatModel
  // FUNGSI: Mapping dari tipe Conversation (API Nobox) ke tipe ChatModel (UI Presentation)
  ChatModel toChatModel() {
    return ChatModel(
      id: id,
      contactId: contactId,
      sender: participantEmail,
      lastMessage: lastMessage,
      time: lastMessageTime,
      unreadCount: unreadCount,
      status: status,
      agentName: agentName,
      tags: tags,
      avatarUrl: avatarUrl,
      lastMessageType: lastMessageType,
      channelName: channelName,
      channelType: channelType,
      isPinned: isPinned,
      chId: chId,
      funnel: funnel,
      isGroup: isGroup,
      isBlocked: isBlocked,
      isLastMessageFromMe: isLastMessageFromMe,
      needReply: needReply,
      accountId: accountId,
      ctRealId: ctRealId,
      link: link,
      campaign: campaign,
      deal: deal,
      groupName: groupName,
      groupId: groupId,
      sdrMsg: sdrMsg,
      extId: extId,
      isArchived: status.toLowerCase() == 'archived' || status == '4',
    );
  }
}
