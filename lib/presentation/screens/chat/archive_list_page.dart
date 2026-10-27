import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/model/message.dart';
import '../../widgets/channel_icon.dart';
import 'chat_detail_page.dart';
import '../../widgets/authenticated_avatar.dart';

// =====================================================================
// FITUR: Halaman Daftar Arsip
// FILE: lib/presentation/screens/chat/archive_list_page.dart
// FUNGSI: Menampilkan daftar percakapan yang diarsipkan dengan fitur
//         pencarian dan filter yang serupa dengan halaman utama chat.
// =====================================================================

class ArchiveListPage extends StatefulWidget {
  const ArchiveListPage({super.key});

  @override
  State<ArchiveListPage> createState() => _ArchiveListPageState();
}

class _ArchiveListPageState extends State<ArchiveListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedChats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().syncArchivedConversations();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // FITUR: Appbar Mode Seleksi (Bulk Action)
  // FUNGSI: Menggantikan AppBar normal ketika pengguna memilih satu atau lebih chat, memungkinkan untuk unarchive secara massal.
  PreferredSizeWidget _buildSelectionAppBar(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    return AppBar(
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue.shade600,
      elevation: 0,
      toolbarHeight: 64,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => setState(() => _selectedChats.clear()),
      ),
      title: Text(
        '${_selectedChats.length} selected',
        style: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.unarchive, color: Colors.white),
          tooltip: 'Unarchive Selected',
          onPressed: () {
            final selectedCount = _selectedChats.length;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Unarchive Conversation',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Are you sure you want to unarchive $selectedCount conversation(s)?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      for (var id in _selectedChats) {
                        //toggleArchive() digunakan untuk mengembalikan obrolan yang diarsipkan ke daftar obrolan utama
                        await chatProvider.toggleArchive(id);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$selectedCount chat(s) unarchived'),
                            backgroundColor: Colors.blue.shade700,
                          ),
                        );
                        setState(() => _selectedChats.clear());
                      }
                    },
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontSize: 15),
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

  // FITUR: Appbar Mode Normal
  // FUNGSI: Menampilkan judul standar halaman ketika tidak ada percakapan yang sedang dipilih.
  PreferredSizeWidget _buildNormalAppBar(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    return AppBar(
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue,
      surfaceTintColor: isDark ? AppTheme.darkSurface : Colors.blue,
      iconTheme: const IconThemeData(color: Colors.white),
      elevation: 0,
      title: const Text(
        'Archived Conversation',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    // FITUR: Navigasi Kembali (PopScope)
    // FUNGSI: Mencegah tombol kembali (back) menutup halaman jika masih ada pesan yang terpilih, dan membersihkan seleksi tersebut alih-alih keluar.
    return PopScope(
      canPop: _selectedChats.isEmpty,
      onPopInvoked: (didPop) {
        if (!didPop && _selectedChats.isNotEmpty) {
          setState(() => _selectedChats.clear());
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF121B22)
            : const Color(0xFFF0F2F5),
        appBar: _selectedChats.isNotEmpty
            ? _buildSelectionAppBar(context)
            : _buildNormalAppBar(context),
        body: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
              ),
              // FITUR: Kolom Pencarian Arsip
              // FUNGSI: Input teks untuk memfilter daftar chat arsip secara lokal (berdasarkan nama pengirim atau isi pesan terakhir).
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Search conversation',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2C3940)
                      : const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // FITUR: Daftar Pesan Arsip
            // FUNGSI: Mengambil daftar percakapan arsip dari ChatProvider dan me-render list UI-nya beserta logika filter pencarian.
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, _) {
                  var chats = chatProvider.archivedChats;

                  if (_searchQuery.isNotEmpty) {
                    chats = chats
                        .where(
                          (chat) => chat.sender.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ),
                        )
                        .toList();
                  }

                  if (chats.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () => chatProvider.syncArchivedConversations(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 80,
                                    color: isDark
                                        ? Colors.grey.shade700
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'No archived chats'
                                        : 'No search results',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.grey.shade500
                                          : Colors.grey.shade600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => chatProvider.syncArchivedConversations(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        return _buildChatTile(
                          context,
                          chat,
                          chatProvider,
                          isDark,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FITUR: Format Waktu Relatif
  // FUNGSI: Mengonversi string waktu UTC dari server ke dalam format lokal (Tanggal Bulan, Jam:Menit) untuk ditampilkan di daftar.
  String _formatTime(String rawTime) {
    if (rawTime.isEmpty) return '';
    try {
      String timeString = rawTime;
      if (!timeString.endsWith('Z') &&
          !timeString.contains('+') &&
          timeString.length >= 19) {
        timeString += 'Z';
      }
      final dt = DateTime.parse(timeString).toLocal();
      final months = [
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
      return '${dt.day} ${months[dt.month - 1]}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawTime;
    }
  }

  // FITUR: Status Badge (Arsip)
  // FUNGSI: Menampilkan label status "Archived" bergaya abu-abu pada setiap item percakapan di daftar arsip.
  Widget _buildStatusBadge(String status, bool isDark) {
    // Untuk halaman arsip, kita paksa statusnya selalu "Archived"
    // dengan tampilan abu-abu yang lebih pas sesuai gambar referensi.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Archived',
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // FITUR: Preview Pesan Terakhir
  // FUNGSI: Merender baris preview teks pesan terakhir, dengan pengecekan khusus jika pesannya unsupported atau format attachment tertentu.
  Widget _buildLastMessageRow(ChatModel chat, bool isDark) {
    final messageColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    if (chat.lastMessageType != null && chat.lastMessageType!.isNotEmpty) {
      final isUnsupported = chat.lastMessageType!.toLowerCase().contains(
        'unsupported',
      );
      if (isUnsupported) {
        return Row(
          children: [
            Icon(Icons.block, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 4),
            Text(
              chat.lastMessageType!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade400,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      }

      String mappedType = chat.lastMessageType!;
      String icon = '🌟 ';

      switch (mappedType.toLowerCase()) {
        case '1':
        case 'text':
          mappedType = 'Text';
          break;
        case '2':
        case 'audio':
        case 'voice note':
          mappedType = 'Voice Message';
          icon = '🎤 ';
          break;
        case '3':
        case 'image':
        case 'photo':
          mappedType = 'Photo';
          icon = '📷 ';
          break;
        case '4':
        case 'video':
          mappedType = 'Video';
          icon = '🎬 ';
          break;
        case '5':
        case 'document':
        case 'file':
          mappedType = 'Document';
          icon = '📄 ';
          break;
        case '10':
        case '14':
        case 'contact':
          mappedType = 'Contact';
          icon = '👤 ';
          break;
        case '11':
        case '15':
        case 'location':
          mappedType = 'Location';
          icon = '📍 ';
          break;
        case '16':
        case '17':
        case 'sticker':
          mappedType = 'Sticker';
          icon = '🌟 ';
          break;
      }

      if (mappedType != 'Text') {
        return Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            Text(
              mappedType,
              style: TextStyle(
                fontSize: 13,
                color: messageColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      }
    }
    String displayMessage = chat.lastMessage;
    if (displayMessage.startsWith('{') &&
        displayMessage.contains('"Filename"')) {
      final lower = displayMessage.toLowerCase();
      if (lower.contains('"ptt":true') ||
          lower.contains('"ptt": true') ||
          lower.contains('.ogg') ||
          lower.contains('.mp3') ||
          lower.contains('voice note') ||
          lower.contains('pesan suara') ||
          lower.contains('voice_')) {
        displayMessage = '🎤 Voice Message';
      } else if (lower.contains('.jpg') ||
          lower.contains('.png') ||
          lower.contains('.jpeg') ||
          lower.contains('photo') ||
          lower.contains('foto')) {
        displayMessage = '📷 Photo';
      } else if (lower.contains('.mp4') || lower.contains('video')) {
        displayMessage = '🎬 Video';
      } else {
        displayMessage = '📎 Attachment';
      }
    }

    // Deteksi nama file mentah (non-JSON) berdasarkan ekstensi/pola nama
    bool isDocumentAlready = displayMessage.startsWith('📄');
    if (!displayMessage.startsWith('📷') &&
        !displayMessage.startsWith('🎬') &&
        !displayMessage.startsWith('🎤') &&
        !isDocumentAlready &&
        !displayMessage.startsWith('📎') &&
        !displayMessage.startsWith('📍') &&
        !displayMessage.startsWith('👤') &&
        !displayMessage.startsWith('🌟')) {
      final lower = displayMessage.toLowerCase().trim();
      if (['.webm', '.tgs', '.webp'].any((ext) => lower.endsWith(ext)) ||
          ['🌟 sticker', '🎬 sticker'].contains(lower)) {
        if (lower.endsWith('.webm') || lower.endsWith('.tgs')) {
          displayMessage = '🎬 Sticker';
        } else {
          displayMessage = '🌟 Sticker';
        }
      } else if ([
            '.jpg',
            '.jpeg',
            '.png',
            '.gif',
            '.bmp',
          ].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('img-') ||
          lower.startsWith('img_') ||
          lower.startsWith('photo')) {
        displayMessage = '📷 Photo';
      } else if ([
            '.mp4',
            '.avi',
            '.mov',
            '.3gp',
            '.mkv',
          ].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('vid-') ||
          lower.startsWith('vid_')) {
        displayMessage = '🎬 Video';
      } else if ([
            '.ogg',
            '.opus',
            '.mp3',
            '.wav',
            '.m4a',
            '.aac',
            '.amr',
            '.weba',
          ].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('voice_') ||
          lower.startsWith('ptt-') ||
          lower.startsWith('aud-')) {
        displayMessage = '🎤 Voice Message';
      } else if ([
        '.pdf',
        '.doc',
        '.docx',
        '.xls',
        '.xlsx',
        '.ppt',
        '.pptx',
        '.txt',
        '.csv',
        '.zip',
        '.rar',
      ].any((ext) => lower.endsWith(ext))) {
        displayMessage = '📄 Document';
      } else if (RegExp(r'\.[a-zA-Z0-9]{2,5}$').hasMatch(lower) &&
          !lower.contains(' ') &&
          lower.length < 100) {
        displayMessage = '📎 Attachment';
      }
    } else if (isDocumentAlready || displayMessage.startsWith('📎')) {
      final lower = displayMessage.toLowerCase().trim();
      if (isDocumentAlready &&
          (lower.contains('img-') ||
              lower.contains('vid-') ||
              lower.contains('wa00'))) {
        displayMessage = '📄 Document';
      } else if (displayMessage.startsWith('📎') &&
          (lower.contains('img-') || lower.contains('img_'))) {
        displayMessage = '📷 Photo';
      }
    }

    if (RegExp(
      r'^(📷|🖼️|🖼)\s*(Photo|Foto)',
      caseSensitive: false,
    ).hasMatch(displayMessage)) {
      String t = displayMessage
          .replaceAll('📷', '')
          .replaceAll('🖼️', '')
          .replaceAll('🖼', '')
          .trim();
      final match = RegExp(
        r'^(Photo|Foto)\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(t);
      if (match != null) {
        final desc = match.group(2)?.trim() ?? '';
        displayMessage = desc.isNotEmpty ? '📷 $desc' : '📷 Foto';
      }
    }

    return Text(
      displayMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: messageColor),
    );
  }

  // FITUR: Chat Tile Item (Daftar List)
  // FUNGSI: Merender UI utuh untuk satu baris chat, menangani transisi warna latar belakang saat chat dipilih, serta menampilkan avatar, info pengirim, dan trailing indicator.
  Widget _buildChatTile(
    BuildContext context,
    ChatModel chat,
    ChatProvider chatProvider,
    bool isDark,
  ) {
    final isSelected = _selectedChats.contains(chat.id);

    return Container(
      color: isSelected
          ? (isDark
                ? Colors.blue.shade900.withOpacity(0.3)
                : Colors.blue.shade50)
          : (isDark ? const Color(0xFF111B21) : Colors.white),
      child: Column(
        children: [
          InkWell(
            // FITUR: Tap Chat (Buka Room atau Pilih)
            // FUNGSI: Jika dalam mode seleksi massal, menambah/menghapus pilihan. Jika mode normal, menavigasi pengguna ke layar ChatDetailPage.
            onTap: () async {
              // Jika dalam mode pilih, ketuk chat menambah pilihan
              if (_selectedChats.isNotEmpty) {
                setState(() {
                  if (isSelected)
                    _selectedChats.remove(chat.id);
                  else
                    _selectedChats.add(chat.id);
                });
                return;
              }
              // Jika normal, pergi ke ruangan chat
              chatProvider.markAsRead(chat.id);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatDetailPage(chat: chat)),
              );

              if (mounted) {
                chatProvider.syncArchivedConversations();
              }
            },
            // FITUR: Long Press Chat (Aktifkan Mode Seleksi)
            // FUNGSI: Memulai mode seleksi massal saat pengguna menahan chat tile, yang mengubah AppBar ke mode unarchive.
            onLongPress: () {
              // Masuk ke Selectable Mode untuk Unarchive massal
              if (_selectedChats.isEmpty) {
                setState(() => _selectedChats.add(chat.id));
              } else {
                setState(() {
                  if (isSelected)
                    _selectedChats.remove(chat.id);
                  else
                    _selectedChats.add(chat.id);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Avatar ──
                    Align(
                      alignment: Alignment.topCenter,
                      child: _selectedChats.isNotEmpty
                          ? Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? Colors.blue.shade600
                                    : Colors.grey.shade400,
                                size: 28,
                              ),
                            )
                          : AuthenticatedAvatar(
                              imageUrl: chat.avatarUrl,
                              size: 48,
                              isGroup: chat.isGroup,
                            ),
                    ),
                    const SizedBox(width: 12),

                    // ── Content ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nama Pengirim
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chat.sender,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Last message
                          _buildLastMessageRow(chat, isDark),

                          // Tags & Funnel
                          if (chat.tags.isNotEmpty ||
                              chat.funnel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (chat.tags.isNotEmpty) ...[
                                  Icon(
                                    Icons.local_offer,
                                    size: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      chat.tags.join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                                if (chat.tags.isNotEmpty &&
                                    chat.funnel.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '|',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (chat.funnel.isNotEmpty) ...[
                                  Icon(
                                    Icons.filter_alt,
                                    size: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    chat.funnel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],

                          // Channel Icon and Name
                          if (chat.channelName.isNotEmpty &&
                              chat.channelName != 'Not Found') ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ChannelIcon(
                                  chId: chat.chId,
                                  channelName:
                                      '${chat.channelType} ${chat.channelName}',
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    chat.channelName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // ── Trailing Content (Sisi Kanan) ──
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Jam & Pin (Opsional untuk archived)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(chat.time),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade500,
                                  ),
                                ),
                                if (chat.isPinned) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: Colors.blue.shade400,
                                  ),
                                ],
                              ],
                            ),

                            // Badge Unread (Daftar Arsip juga menampilkan unread jika ada pesan baru)
                            if (chat.unreadCount > 0) ...[
                              const SizedBox(height: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  chat.unreadCount > 99
                                      ? '99+'
                                      : chat.unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Status badge
                        _buildStatusBadge(chat.status, isDark),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 0.5,
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}
