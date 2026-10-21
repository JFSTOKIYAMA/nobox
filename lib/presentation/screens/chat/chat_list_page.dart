import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/searchable_dropdown.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/model/message.dart';
import '../../../core/model/api_response.dart';
import '../../../core/model/conversation.dart';
import '../../../core/model/message_request.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/utils/app_routes.dart';
import '../../../core/model/filter_data_item.dart';
import 'chat_detail_page.dart';
import 'archive_list_page.dart';
import '../profile/profile_page.dart' as profile;
import '../profile/user_profile_page.dart' as user_profile;
import '../about/about_page.dart' as about;
import '../../widgets/chat_list_skeleton.dart';
import '../../widgets/connection_status_banner.dart';
import '../../widgets/authenticated_avatar.dart';
import '../../widgets/channel_icon.dart';
import '../../widgets/top_notification.dart';
import '../../../core/utils/date_time_helper.dart';
import '../../../core/utils/string_helper.dart';
import '../../../core/providers/chat_settings_provider.dart';

// =====================================================================
// FITUR: Halaman Utama Daftar Chat (Inbox)
// FILE: lib/presentation/screens/chat/chat_list_page.dart
// FUNGSI: Menampilkan daftar seluruh percakapan aktif. Menyediakan fitur
//         pencarian, filter (unread, tag, dsb), serta indikator status
//         koneksi WebSocket secara real-time.
// =====================================================================

class ChatListPage extends StatefulWidget {
  final void Function(ChatModel)? onChatSelected;
  final String? selectedChatId;

  const ChatListPage({
    super.key,
    this.onChatSelected,
    this.selectedChatId,
  });

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All', 'Unassigned', 'Assigned', 'Resolved'];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedChats = {};

  // Infinite scroll
  final ScrollController _scrollController = ScrollController();

  // Debounce for search
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().fetchChats();
    });
  }

  // FITUR: Infinite Scroll / Pagination
  // FUNGSI: Mendeteksi saat pengguna menggulir ke bawah daftar chat untuk memuat data tambahan (lazy loading).
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final isNearBottom = position.pixels >= position.maxScrollExtent - 200;

    final chatProvider = context.read<ChatProvider>();
    final isLoadingMore = chatProvider.isLoadingMore;
    final hasMore = chatProvider.hasMore;

    // fetchMoreChats() dipanggil untuk meminta data chat berikutnya dari server dengan parameter (kelipatan 20)
    if (isNearBottom && !isLoadingMore && hasMore) {
      chatProvider.fetchMoreChats();
    }
  }

  // FITUR: Filter Tab Chat (Semua, Belum Ditetapkan, dll)
  // FUNGSI: Mengubah filter daftar chat berdasarkan status tab yang dipilih oleh pengguna.
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (!mounted) return;
    final newFilter = _tabs[_tabController.index];
    context.read<ChatProvider>().setActiveFilter(newFilter);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // FITUR: Appbar Mode Seleksi (Bulk Action)
  // FUNGSI: Menampilkan AppBar khusus ketika pengguna memilih satu atau lebih chat, memungkinkan aksi massal seperti Archive atau Pin.
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
          icon: const Icon(Icons.push_pin, color: Colors.white),
          onPressed: () {
            final selected = List<String>.from(_selectedChats);
            final count = selected.length;
            setState(() => _selectedChats.clear());
            for (var id in selected) {
              chatProvider.togglePin(id);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  count == 1
                      ? 'Chat pin status updated'
                      : '$count chats pinned/updated',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
        // [ACTION: ARCHIVE_MASSAL] - Ikon untuk arsip masal / multi select
        IconButton(
          icon: const Icon(Icons.archive_outlined, color: Colors.white),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Archive Conversation',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Are you sure you want to archive ${_selectedChats.length} conversation(s)?',
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
                      // [ACTION: ARCHIVE_EXECUTE_MASSAL] - Perulangan untuk mengarsip pesan yang dipilih
                      final selected = List<String>.from(_selectedChats);
                      final count = selected.length;
                      setState(() => _selectedChats.clear());
                      for (var id in selected) {
                        await chatProvider.toggleArchive(id);
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$count chat(s) archived',
                            ),
                            backgroundColor: Colors.blue.shade700,
                          ),
                        );
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

  /// Mengubah pesan error mentah dari server/jaringan menjadi pesan yang ramah user.
  /// - Internet HP mati / DNS gagal      → "Tidak ada koneksi internet"
  /// - Server error (5xx) / server mati  → "Server sedang bermasalah..."
  /// - Selain itu                        → "Gagal memuat percakapan..."
  String _friendlyChatError(String error) {
    final e = error.toLowerCase();

    // 1. Perangkat tidak terhubung ke internet
    if (e.contains('failed host lookup') ||
        e.contains('no address associated with hostname') ||
        e.contains('network is unreachable') ||
        e.contains('no route to host') ||
        e.contains('xmlhttprequest error')) {
      return 'No internet connection';
    }

    // 2. Server error / server mati / tidak merespons
    if (RegExp(r'\b5\d\d\b').hasMatch(e) ||
        e.contains('server error') ||
        e.contains('internal server') ||
        e.contains('service unavailable') ||
        e.contains('bad gateway') ||
        e.contains('connection refused') ||
        e.contains('connection reset') ||
        e.contains('connection closed') ||
        e.contains('timeout') ||
        e.contains('timed out')) {
      return 'Server sedang bermasalah. Silakan coba lagi nanti.';
    }

    // 3. Error koneksi lain yang tidak spesifik → anggap tidak ada internet
    if (e.contains('socketexception') ||
        e.contains('connection error') ||
        e.contains('connection errored')) {
      return 'No internet connection';
    }

    return 'Failed to load conversations. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      // FITUR: Header AppBar (Normal / Mode Pencarian)
      // FUNGSI: Menampilkan judul dan tombol aksi di atas, serta berubah menjadi form input teks saat mode pencarian aktif.
      appBar: _selectedChats.isNotEmpty
          ? _buildSelectionAppBar(context)
          : AppBar(
              backgroundColor: isDark ? AppTheme.darkSurface : Colors.blue,
              surfaceTintColor: isDark ? AppTheme.darkSurface : Colors.blue,
              elevation: 0,
              toolbarHeight: 64,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: _isSearching
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isSearching = false;
                          _searchController.clear();
                          context.read<ChatProvider>().setSearchQuery('');
                        });
                      },
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset(
                        'assets/nobox.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
              title: _isSearching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                        ),
                        border: InputBorder.none,
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  context.read<ChatProvider>().setSearchQuery(
                                    '',
                                  );
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () {
                            if (mounted) {
                              context.read<ChatProvider>().setSearchQuery(
                                value,
                              );
                              setState(() {});
                            }
                          },
                        );
                      },
                    )
                  : const Text(
                      'NoBox Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
              actions: _isSearching
                  ? []
                  : [
                      IconButton(
                        icon: const Icon(
                          Icons.search,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.filter_alt,
                              color: Colors.white,
                              size: 27,
                            ),
                            padding: const EdgeInsets.all(8),
                            onPressed: () {
                              _showFilterDialog();
                            },
                          ),
                          if (context
                              .watch<ChatProvider>()
                              .hasActiveAdvancedFilters)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 28,
                        ),
                        onSelected: (value) {
                          if (value == 'user_profile') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const user_profile.UserProfilePage(),
                              ),
                            );
                          } else if (value == 'profile') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const profile.ProfilePage(),
                              ),
                            );
                          } else if (value == 'archived') {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.archivedChats,
                            );
                          } else if (value == 'help') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const about.AboutPage(),
                              ),
                            );
                          } else if (value == 'dark_mode') {
                            // Delay theme toggle to next frame so the popup menu
                            // fully closes before the widget tree rebuilds.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                themeProvider.toggleTheme(!isDark);
                              }
                            });
                          } else if (value == 'logout') {
                            _showLogoutDialog();
                          }
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: isDark ? const Color(0xFF2C3940) : Colors.white,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'user_profile',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_circle,
                                  size: 24,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'User Profile',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'dark_mode',
                            child: Row(
                              children: [
                                Icon(
                                  isDark ? Icons.light_mode : Icons.dark_mode,
                                  size: 24,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  isDark ? 'Light Mode' : 'Dark Mode',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'archived',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.archive,
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
                          PopupMenuItem(
                            value: 'help',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 24,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Help',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'profile', // Ini sebelumnya Profil NoBox.ai
                            child: Row(
                              children: [
                                Icon(
                                  Icons.help_outline,
                                  size: 24,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'About NoBox.ai',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 24, color: Colors.red),
                                SizedBox(width: 16),
                                Text(
                                  'Logout',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: Container(
                  color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    labelPadding: EdgeInsets.zero,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(color: Colors.blue, width: 3.0),
                      insets: EdgeInsets.only(bottom: 2.0),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 13,
                    ),
                    tabs: _buildTabsWithBadges(context),
                  ),
                ),
              ),
            ),
      body: Column(
        children: [
          const ConnectionStatusBanner(),
          // Banner kecil saat gagal memuat ulang, tetapi daftar chat lama masih tampil.
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              if (chatProvider.fetchError == null ||
                  chatProvider.chats.isEmpty ||
                  chatProvider.isLoading) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Failed to load conversations',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => chatProvider.fetchChats(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isLoading && chatProvider.chats.isEmpty) {
                  return const ChatListSkeleton();
                }

                final isSearching = chatProvider.searchQuery.isNotEmpty;
                final chats = chatProvider.chats;
                final serverContacts = isSearching
                    ? chatProvider.searchServerContacts(chatProvider.searchQuery)
                    : <Map<String, dynamic>>[];

                // Filter server contacts agar tidak menduplikasi obrolan aktif yang sudah tampil di atas
                final activeChatNames = chats
                    .map((c) => c.sender.trim().toLowerCase())
                    .toSet();
                final activeContactIds = chats
                    .map((c) => c.contactId)
                    .where((id) => id.isNotEmpty && id != '0')
                    .toSet();
                final otherContacts = serverContacts.where((contact) {
                  final cName = (contact['Name'] ?? contact['Nm'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
                  final cId =
                      (contact['Id'] ?? contact['id'] ?? '').toString();
                  if (activeChatNames.contains(cName)) return false;
                  if (cId.isNotEmpty && activeContactIds.contains(cId))
                    return false;
                  return true;
                }).toList();

                if (chats.isEmpty && (!isSearching || otherContacts.isEmpty)) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSearching
                              ? Icons.search_off
                              : Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isSearching
                              ? 'Contact not found'
                              : 'No conversation yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isSearching) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search keyword',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                        if (chatProvider.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _friendlyChatError(chatProvider.error!),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        // FITUR 2: Paging & Pengambilan Chat
                        // FUNGSI: fetchChats() digunakan untuk memanggil percakapan dari server.
                        if (chatProvider.error != null)
                          TextButton.icon(
                            onPressed: () => chatProvider.fetchChats(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          )
                        else if (isSearching)
                          TextButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              context.read<ChatProvider>().setSearchQuery('');
                              setState(() {
                                _isSearching = false;
                              });
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear Search'),
                          ),
                      ],
                    ),
                  );
                }

                if (isSearching) {
                  // Mode Pencarian: Tampilkan Obrolan Aktif + Kontak dari Server (Buku Alamat)
                  final List<Widget> searchItems = [];

                  if (chats.isNotEmpty) {
                    if (otherContacts.isNotEmpty) {
                      searchItems.add(
                        _buildSearchSectionHeader(
                          title: 'Active Chats',
                          count: chats.length,
                          icon: Icons.chat_bubble_outline,
                          isDark: isDark,
                        ),
                      );
                    }
                    for (final chat in chats) {
                      searchItems.add(
                        _buildChatTile(
                          context,
                          chat,
                          chatProvider,
                          isDark,
                        ),
                      );
                    }
                  }

                  if (otherContacts.isNotEmpty) {
                    searchItems.add(
                      _buildSearchSectionHeader(
                        title: 'Contacts from Address Book',
                        count: otherContacts.length,
                        icon: Icons.contacts_outlined,
                        isDark: isDark,
                      ),
                    );
                    for (final contact in otherContacts) {
                      searchItems.add(
                        _buildServerContactTile(
                          context,
                          contact,
                          chatProvider,
                          isDark,
                        ),
                      );
                    }
                  }

                  searchItems.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No more results',
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );

                  return ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    children: searchItems,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => chatProvider.fetchChats(),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    addRepaintBoundaries: true,
                    cacheExtent: 500,
                    // +1 for the bottom indicator (loading skeleton or end-of-list)
                    itemCount: chats.length + 1,
                    itemBuilder: (context, index) {
                      // Last item: show loading skeleton or end-of-list indicator
                      if (index == chats.length) {
                        if (chatProvider.isLoadingMore) {
                          return _buildLoadingMoreSkeleton(isDark);
                        } else if (!chatProvider.hasMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'All conversations displayed',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }

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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showNewConversationDialog();
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  List<Widget> _buildTabsWithBadges(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final counts = {
      'All': chatProvider.totalUnreadCount,
      'Unassigned': chatProvider.unassignedUnread,
      'Assigned': chatProvider.assignedUnread,
      'Resolved': chatProvider.resolvedUnread,
    };

    return List.generate(_tabs.length, (i) {
      final tabName = _tabs[i];
      final unreadCount = counts[tabName] ?? 0;

      return Tab(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tabName),
            if (unreadCount > 0 && tabName == 'Unassigned') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Center(
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  // FITUR: Header Bagian Pencarian
  // FUNGSI: Memberikan label pembatas visual antara Obrolan Aktif dan Kontak dari Buku Alamat NoBox
  Widget _buildSearchSectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? const Color(0xFF192229) : Colors.grey.shade100,
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FITUR: Tile Kontak Server (Buku Alamat)
  // FUNGSI: Menampilkan baris kontak dari direktori server yang belum memiliki obrolan aktif di inbox
  Widget _buildServerContactTile(
    BuildContext context,
    Map<String, dynamic> contact,
    ChatProvider chatProvider,
    bool isDark,
  ) {
    final name = (contact['Name'] ?? contact['Nm'] ?? 'Contact').toString();
    final phone = (contact['Phone'] ??
            contact['Hp'] ??
            contact['Mobile'] ??
            contact['Telp'] ??
            '')
        .toString();
    final photo = (contact['Photo'] ??
            contact['Img'] ??
            contact['AvatarUrl'] ??
            contact['Picture'] ??
            '')
        .toString();
    final contactId = (contact['Id'] ?? contact['id'] ?? '').toString();

    return InkWell(
      onTap: () {
        // Cek apakah kontak ini sudah memiliki obrolan aktif
        final allChats = chatProvider.allChats;
        ChatModel? existingChat;
        for (final c in allChats) {
          final isSameId = contactId.isNotEmpty &&
              (c.contactId == contactId || c.ctRealId == contactId);
          final isSameName = name.trim().toLowerCase() ==
              c.sender.trim().toLowerCase();
          if (isSameId || isSameName) {
            existingChat = c;
            break;
          }
        }

        if (existingChat != null) {
          if (widget.onChatSelected != null) {
            widget.onChatSelected!(existingChat);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailPage(chat: existingChat!),
              ),
            );
          }
        } else {
          // Buka form percakapan baru dengan kontak yang otomatis terpilih
          _showNewConversationDialog(
            initialContactName: name,
            initialContactId: contactId,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2C34) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade200,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            AuthenticatedAvatar(
              imageUrl: photo,
              size: 44,
              isGroup: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_outlined,
                        size: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          phone.isNotEmpty ? phone : 'Contact from server',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: Colors.blue.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.blue.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FITUR: Dialog Pencarian Bawaan (Cadangan)
  // FUNGSI: Menampilkan input text sederhana dalam sebuah dialog sebagai metode alternatif untuk mencari daftar obrolan aktif.
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(
          text: context.read<ChatProvider>().searchQuery,
        );
        return AlertDialog(
          title: const Text('Search'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search chats...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              context.read<ChatProvider>().setSearchQuery(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.read<ChatProvider>().setSearchQuery('');
                Navigator.pop(context);
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // Helper untuk membuat daftar nama tampilan yang unik dari data API
  List<String> _toUniqueNames(
    List<Map<String, dynamic>> items,
    List<String> keys,
  ) {
    final names = <String>[];
    final seen = <String, int>{};
    for (final item in items) {
      String name = 'Unknown';
      for (final key in keys) {
        final val = item[key]?.toString();
        if (val != null && val.isNotEmpty && val != 'null') {
          name = val;
          break;
        }
      }
      if (name == 'Unknown' || name.isEmpty) {
        for (final entry in item.entries) {
          final k = entry.key.toLowerCase();
          if (k != 'id' &&
              k != 'tenantid' &&
              k != 'chid' &&
              k != 'type' &&
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
      // Hilangkan duplikasi: tambahkan (2), (3), dst. untuk nama yang sama
      if (seen.containsKey(name)) {
        seen[name] = seen[name]! + 1;
        names.add('$name (${seen[name]})');
      } else {
        seen[name] = 1;
        names.add(name);
      }
    }
    return names;
  }

  // FITUR: Dialog Buat Percakapan Baru
  // FUNGSI: Menampilkan popup form (Channel, Akun, Kontak) untuk memulai obrolan baru dengan kontak tertentu atau manual.
  void _showNewConversationDialog({
    String? initialContactName,
    String? initialContactId,
  }) {
    String selectedChat = 'Private';
    String? selectedChannel;
    String? selectedAccount;
    String selectedTo = 'Contact'; // Contact, Link, Manual (or Group, Link, Manual)
    String? selectedContact;
    String? selectedGroup;
    String manualInput = '';
    String initialMessage = 'Hello';

    // API data
    List<Map<String, dynamic>> channels = [];
    List<Map<String, dynamic>> accounts = [];
    List<Map<String, dynamic>> contacts = [];
    List<Map<String, dynamic>> groups = [];
    bool isLoadingData = true;
    String? loadError;
    bool isCreatingRoom = false;

    final chatService = ChatService();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Tarik data saat widget pertama kali dirender
            if (isLoadingData && channels.isEmpty && loadError == null) {
              Future.microtask(() async {
                try {
                  final results = await Future.wait([
                    chatService.getChannels(),
                    chatService.getAccounts(),
                    chatService.getContacts(),
                    chatService.getGroups(),
                  ]);

                  final channelResp =
                      results[0] as ApiResponse<List<Map<String, dynamic>>>;
                  final accountResp =
                      results[1] as ApiResponse<List<Map<String, dynamic>>>;
                  final contactResp =
                      results[2] as ApiResponse<List<Map<String, dynamic>>>;
                  final groupResp =
                      results[3] as ApiResponse<List<Map<String, dynamic>>>;

                  setDialogState(() {
                    isLoadingData = false;
                    if (!channelResp.isError && channelResp.data != null) {
                      channels = channelResp.data!;
                    }
                    if (!accountResp.isError && accountResp.data != null) {
                      accounts = accountResp.data!;
                    }
                    if (!contactResp.isError && contactResp.data != null) {
                      contacts = contactResp.data!;
                      if (initialContactId != null ||
                          initialContactName != null) {
                        final cNames = _toUniqueNames(
                          contacts,
                          ['Name', 'Nm'],
                        );
                        for (int i = 0; i < contacts.length; i++) {
                          final cId = contacts[i]['Id']?.toString();
                          final cNm = (contacts[i]['Name'] ??
                                  contacts[i]['Nm'])
                              ?.toString() ??
                              '';
                          if ((initialContactId != null &&
                                  cId == initialContactId) ||
                              (initialContactName != null &&
                                  cNm.trim().toLowerCase() ==
                                      initialContactName
                                          .trim()
                                          .toLowerCase())) {
                            if (i < cNames.length) {
                              selectedContact = cNames[i];
                            }
                            break;
                          }
                        }
                      }
                    }
                    if (!groupResp.isError && groupResp.data != null) {
                      groups = groupResp.data!;
                    }
                  });
                } catch (e) {
                  setDialogState(() {
                    isLoadingData = false;
                    loadError = e.toString();
                  });
                }
              });
            }

            Widget buildDropdownRow(
              String label,
              String? value,
              List<String> options,
              ValueChanged<String?> onChanged, {
              bool enabled = true,
              String hintText = '--select--',
            }) {
              // Pastikan nilai yang dipilih ada di dalam daftar opsi, jika tidak kembalikan ke null
              final safeValue = (value != null && options.contains(value))
                  ? value
                  : null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Opacity(
                        opacity: enabled ? 1.0 : 0.5,
                        child: IgnorePointer(
                          ignoring: !enabled,
                          child: SearchableDropdown<String>(
                            value: safeValue,
                            hint: hintText,
                            options: options,
                            onChanged: onChanged,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Ekstrak nama unik dari data API untuk menu dropdown (dengan fallback key lengkap agar akun Telegram/platform lain terbaca)
            final channelNames = _toUniqueNames(channels, [
              'Nm',
              'Name',
              'ChannelName',
            ]);
            List<Map<String, dynamic>> filteredAccounts = accounts;
            String? selectedChannelId;
            bool isSelectedChannelTelegram = false;
            bool isSelectedChannelWhatsApp = false;

            if (selectedChannel != null) {
              final selectedChannelIndex = channelNames.indexOf(selectedChannel!);
              if (selectedChannelIndex != -1) {
                final channelObj = channels[selectedChannelIndex];
                selectedChannelId = channelObj['Id']?.toString() ?? channelObj['ChId']?.toString();
                final chNm = (channelObj['Nm'] ?? channelObj['Name'] ?? channelObj['ChannelName'] ?? selectedChannel!).toString().toLowerCase();
                isSelectedChannelTelegram = selectedChannelId == '2' || chNm.contains('telegram') || chNm.contains('tg');
                isSelectedChannelWhatsApp = selectedChannelId == '1' || selectedChannelId == '1557' || selectedChannelId == '1561' || chNm.contains('whatsapp') || chNm == 'wa' || chNm.startsWith('wa ') || chNm.endsWith(' wa');
                if (selectedChannelId != null) {
                  filteredAccounts = accounts.where((acc) {
                    final accChannel = acc['Channel']?.toString() ?? acc['ChId']?.toString() ?? acc['ChannelId']?.toString();
                    return accChannel == selectedChannelId;
                  }).toList();
                }
              }
            }

            // FILTER KHUSUS GRUP BERDASARKAN CHANNEL YANG DIPILIH:
            // Grup WA hanya untuk Channel WhatsApp, dan Grup Telegram hanya untuk Channel Telegram.
            List<Map<String, dynamic>> filteredGroups = [];
            if (selectedChannel != null) {
              final filteredAccountIds = filteredAccounts
                  .map((a) => (a['Id'] ?? a['id'] ?? a['AccountId'] ?? a['acc_id'])?.toString())
                  .where((id) => id != null && id.isNotEmpty)
                  .toSet();

              filteredGroups = groups.where((grp) {
                // 1. Cek Channel ID langsung dari data grup jika ada
                final grpChId = (grp['Channel'] ?? grp['ChId'] ?? grp['ChannelId'] ?? grp['channel_id'])?.toString();
                if (grpChId != null && grpChId.isNotEmpty && selectedChannelId != null) {
                  if (grpChId == selectedChannelId) return true;
                }

                // 2. Cek apakah grup terikat ke salah satu akun dari channel yang dipilih
                final grpAccId = (grp['AccountId'] ?? grp['Account'] ?? grp['AccId'] ?? grp['account_id'])?.toString();
                if (grpAccId != null && grpAccId.isNotEmpty && filteredAccountIds.isNotEmpty) {
                  if (filteredAccountIds.contains(grpAccId)) return true;
                }

                // 3. Cek pola unik identifier / LinkTmp / JID / GroupId / Nama
                final idStr = (grp['Id'] ?? grp['id'] ?? grp['GroupId'] ?? grp['grp_id'])?.toString() ?? '';
                final linkStr = (grp['LinkTmp'] ?? grp['Link'] ?? grp['link'] ?? grp['CtRealId'] ?? grp['Jid'] ?? '')?.toString().toLowerCase() ?? '';
                final grpName = (grp['Name'] ?? grp['DisplayName'] ?? grp['Title'] ?? grp['Nm'] ?? '')?.toString().toLowerCase() ?? '';
                final combined = '$idStr $linkStr $grpName';

                final isTelegramGroup = idStr.trim().startsWith('-') ||
                    linkStr.trim().startsWith('-') ||
                    linkStr.contains('t.me') ||
                    linkStr.contains('telegram') ||
                    grpName.contains('telegram') ||
                    grpChId == '2';

                final isWhatsAppGroup = combined.contains('@g.us') ||
                    combined.contains('@group') ||
                    linkStr.contains('whatsapp') ||
                    grpName.contains('whatsapp') ||
                    grpChId == '1' ||
                    grpChId == '1557' ||
                    grpChId == '1561';

                if (isSelectedChannelTelegram) {
                  if (isWhatsAppGroup) return false;
                  if (isTelegramGroup) return true;
                  return !combined.contains('@g.us');
                } else if (isSelectedChannelWhatsApp) {
                  if (isTelegramGroup) return false;
                  if (isWhatsAppGroup) return true;
                  return !idStr.trim().startsWith('-') && !linkStr.trim().startsWith('-');
                }

                if (selectedChannelId != null && grpChId != null) {
                  return grpChId == selectedChannelId;
                }

                return true;
              }).toList();
            }

            final accountNames = _toUniqueNames(filteredAccounts, [
              'Name',
              'AccountName',
              'Nm',
              'nm',
              'Title',
              'DisplayName',
              'Username',
              'AccNm',
              'Email',
              'Phone',
            ]);
            final contactNames = _toUniqueNames(contacts, [
              'Name',
              'CtNm',
              'CtRealNm',
              'Nm',
              'nm',
              'DisplayName',
            ]);
            final groupNames = _toUniqueNames(filteredGroups, [
              'Name',
              'DisplayName',
              'Title',
              'Nm',
              'nm',
              'GroupName',
            ]);

            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 40,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'New Conversation',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close, color: Colors.grey),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (isLoadingData)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Loading data...',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      else if (loadError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Failed to load: $loadError',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    isLoadingData = true;
                                    loadError = null;
                                    channels = [];
                                    accounts = [];
                                    contacts = [];
                                    groups = [];
                                  });
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // Dropdown pilihan jenis obrolan (Private/Group)
                        buildDropdownRow(
                          'Chat',
                          selectedChat,
                          ['Private', 'Group'],
                          (val) {
                            if (val != null && val != selectedChat) {
                              setDialogState(() {
                                selectedChat = val;
                                if (selectedChat == 'Group') {
                                  selectedTo = 'Group';
                                  selectedGroup = null;
                                } else {
                                  selectedTo = 'Contact';
                                  selectedContact = null;
                                }
                              });
                            }
                          },
                        ),

                        // Dropdown pilihan Channel (dari API)
                        buildDropdownRow(
                          'Channel',
                          selectedChannel,
                          channelNames,
                          (val) {
                            setDialogState(() {
                              selectedChannel = val;
                              selectedAccount = null;
                              selectedGroup = null;
                            });
                          },
                        ),

                        // Dropdown pilihan Akun (dari API)
                        buildDropdownRow(
                          'Account',
                          selectedAccount,
                          accountNames,
                          (val) {
                            setDialogState(() => selectedAccount = val);
                          },
                          enabled: selectedChannel != null,
                          hintText: selectedChannel != null ? '--select--' : 'Select Channel first',
                        ),

                        // Tombol Radio untuk Pilihan Tujuan (To)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                    'To',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 0,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Radio<String>(
                                            value: selectedChat == 'Group'
                                                ? 'Group'
                                                : 'Contact',
                                            groupValue: selectedTo,
                                            onChanged: (val) {
                                              if (val != null)
                                                setDialogState(
                                                  () => selectedTo = val,
                                                );
                                            },
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          Text(
                                            selectedChat == 'Group'
                                                ? 'Group'
                                                : 'Contact',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Radio<String>(
                                            value: 'Link',
                                            groupValue: selectedTo,
                                            onChanged: (val) {
                                              if (val != null)
                                                setDialogState(
                                                  () => selectedTo = val,
                                                );
                                            },
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          const Text(
                                            'Link',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Radio<String>(
                                            value: 'Manual',
                                            groupValue: selectedTo,
                                            onChanged: (val) {
                                              if (val != null)
                                                setDialogState(
                                                  () => selectedTo = val,
                                                );
                                            },
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          const Text(
                                            'Manual',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Dropdown pilihan Kontak / Grup (dari API) atau input angka secara Manual
                        if (selectedChat == 'Group' && selectedTo == 'Group')
                          buildDropdownRow(
                            'Group',
                            selectedGroup,
                            groupNames,
                            (val) {
                              setDialogState(() => selectedGroup = val);
                            },
                            enabled: selectedChannel != null,
                            hintText: selectedChannel == null
                                ? 'Select Channel first'
                                : (groupNames.isEmpty ? 'No groups for this channel' : '--select--'),
                          )
                        else if (selectedChat != 'Group' && selectedTo == 'Contact')
                          buildDropdownRow(
                            'Contact',
                            selectedContact,
                            contactNames,
                            (val) {
                              setDialogState(() => selectedContact = val);
                            },
                          )
                        else if (selectedTo == 'Manual')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 80,
                                  child: Text(
                                    'Number',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: selectedChat == 'Group'
                                          ? 'Enter group ID or number...'
                                          : 'Enter phone number...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    onChanged: (val) => manualInput = val,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (selectedTo == 'Link')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 80,
                                  child: Text(
                                    'Link',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: selectedChat == 'Group'
                                          ? 'Paste group link...'
                                          : 'Paste link...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    onChanged: (val) => manualInput = val,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Tombol Batal & Buat Pesan
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  side: const BorderSide(color: Colors.blue),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isCreatingRoom ? null : () async {
                                  void showValidationToast(
                                    String title,
                                    String msg,
                                  ) {
                                    debugPrint('ChatList: Validation Failed -> $title: $msg');
                                    TopNotification.show(
                                      dialogContext,
                                      title: title,
                                      message: msg,
                                      isError: true,
                                    );
                                  }

                                  debugPrint('ChatList: CREATE CLICKED. Channel: $selectedChannel, Account: $selectedAccount, To: $selectedTo, Contact: $selectedContact');
                                  // Validasi wajib isian sebelum proses pembuatan ruangan (New Conversation)
                                  if (selectedChannel == null ||
                                      selectedChannel!.trim().isEmpty) {
                                    showValidationToast(
                                      'Kolom Belum Lengkap!',
                                      'Silakan pilih Channel komunikasi terlebih dahulu.',
                                    );
                                    return;
                                  }
                                  if (selectedAccount == null ||
                                      selectedAccount!.trim().isEmpty) {
                                    showValidationToast(
                                      'Kolom Belum Lengkap!',
                                      'Silakan pilih Akun (Account) pengirim terlebih dahulu.',
                                    );
                                    return;
                                  }
                                  if (selectedChat == 'Group') {
                                    if (selectedTo == 'Group' &&
                                        (selectedGroup == null ||
                                            selectedGroup!.trim().isEmpty ||
                                            selectedGroup!.contains('No Groups') ||
                                            selectedGroup!.contains('Tidak ada grup'))) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Please select a Group from the available list.',
                                      );
                                      return;
                                    } else if (selectedTo == 'Manual' &&
                                        manualInput.trim().isEmpty) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Silakan masukkan nomor/ID grup tujuan secara manual.',
                                      );
                                      return;
                                    } else if (selectedTo == 'Link' &&
                                        manualInput.trim().isEmpty) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Silakan masukkan ID Tautan (Link) grup tujuan.',
                                      );
                                      return;
                                    }
                                  } else {
                                    if (selectedTo == 'Contact' &&
                                        (selectedContact == null ||
                                            selectedContact!.trim().isEmpty ||
                                            selectedContact!.contains(
                                              'No Contacts',
                                            ))) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Please select a Contact recipient from the available list.',
                                      );
                                      return;
                                    } else if (selectedTo == 'Manual' &&
                                        manualInput.trim().isEmpty) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Silakan masukkan nomor telepon tujuan secara manual.',
                                      );
                                      return;
                                    } else if (selectedTo == 'Link' &&
                                        manualInput.trim().isEmpty) {
                                      showValidationToast(
                                        'Kolom Belum Lengkap!',
                                        'Silakan masukkan ID Tautan (Link) tujuan.',
                                      );
                                      return;
                                    }
                                  }

                                  // Dapatkan Id akun yang dipilih dalam format integer
                                  int accountIdInt = 0;
                                  if (selectedAccount != null) {
                                    final idx = accountNames.indexOf(
                                      selectedAccount!,
                                    );
                                    if (idx >= 0 && idx < filteredAccounts.length) {
                                      accountIdInt =
                                          int.tryParse(
                                            (filteredAccounts[idx]['Id'] ?? filteredAccounts[idx]['id'])?.toString() ??
                                                '',
                                          ) ??
                                          0;
                                    }
                                  }

                                  // Dapatkan Id channel yang dipilih dalam format integer
                                  int channelIdInt = 1;
                                  if (selectedChannel != null) {
                                    final idx = channelNames.indexOf(
                                      selectedChannel!,
                                    );
                                    if (idx >= 0 && idx < channels.length) {
                                      channelIdInt =
                                          int.tryParse(
                                            (channels[idx]['Id'] ?? channels[idx]['id'])?.toString() ??
                                                '',
                                          ) ??
                                          1;
                                    }
                                  }

                                  // Temukan ID penerima berdasarkan opsi yang dipilih
                                  String? receiver;
                                  int? contactId;
                                  int? linkId;
                                  int? groupId;
                                  String? groupName;
                                  bool isGroup = selectedChat == 'Group';

                                  if (isGroup) {
                                    if (selectedTo == 'Group' && selectedGroup != null) {
                                      final idx = groupNames.indexOf(selectedGroup!);
                                      if (idx >= 0 && idx < filteredGroups.length) {
                                        final grp = filteredGroups[idx];
                                        debugPrint('ChatList: Selected Group RAW: $grp');
                                        final rawGrpId = (grp['Id'] ?? grp['id'] ?? grp['GroupId'] ?? grp['GrpId'])?.toString();
                                        groupId = int.tryParse(rawGrpId ?? '');
                                        groupName = (grp['Name'] ?? grp['DisplayName'] ?? grp['Title'] ?? grp['Nm'])?.toString();
                                        receiver = rawGrpId;
                                        debugPrint('ChatList: Receiver (GroupId): $receiver, Parsed GrpId: $groupId, GroupName: $groupName');
                                      }
                                    } else if (selectedTo == 'Manual' || selectedTo == 'Link') {
                                      receiver = manualInput;
                                      groupId = int.tryParse(manualInput);
                                      groupName = manualInput;
                                      if (selectedTo == 'Link') {
                                        linkId = int.tryParse(manualInput);
                                      }
                                    }
                                  } else {
                                    if (selectedTo == 'Contact' &&
                                        selectedContact != null) {
                                      final idx = contactNames.indexOf(
                                        selectedContact!,
                                      );
                                      if (idx >= 0 && idx < contacts.length) {
                                        final contact = contacts[idx];
                                        debugPrint('ChatList: Selected Contact RAW: $contact');
                                        receiver = (contact['Id'] ?? contact['id'])?.toString();
                                        contactId = int.tryParse(receiver ?? '');
                                        debugPrint('ChatList: Receiver (Id): $receiver, Parsed CtId: $contactId');

                                        // CARI LeadLink yang 100% cocok dengan Channel (misal 2 = Telegram) & Akun
                                        // agar obrolan yang dibuka memiliki riwayat pesan yang benar (tidak salah WA / tidak 0 pesan)!
                                        final leadLinks = contact['LeadLinks'];
                                        if (leadLinks is List &&
                                            leadLinks.isNotEmpty) {
                                          Map? targetLink;
                                          for (final l in leadLinks) {
                                            if (l is Map) {
                                              final lChId =
                                                  l['ChId']?.toString() ??
                                                  l['Ch']?.toString() ??
                                                  l['ChannelId']?.toString() ??
                                                  l['chId']?.toString() ??
                                                  '';
                                              final lAccId =
                                                  l['AccId']?.toString() ??
                                                  l['AccountId']?.toString() ??
                                                  l['IdAccount']?.toString() ??
                                                  l['accId']?.toString() ??
                                                  '';

                                              if (lChId ==
                                                  channelIdInt.toString()) {
                                                if (accountIdInt > 0 &&
                                                    lAccId ==
                                                        accountIdInt.toString()) {
                                                  targetLink = l;
                                                  break;
                                                } else if (targetLink == null) {
                                                  targetLink = l;
                                                }
                                              }
                                            }
                                          }
                                          targetLink ??= (leadLinks[0] is Map
                                              ? leadLinks[0]
                                              : null);
                                          if (targetLink != null) {
                                            linkId = int.tryParse(
                                              targetLink['Id']?.toString() ??
                                                  targetLink['id']?.toString() ??
                                                  '',
                                            );
                                          }
                                        }
                                      }
                                    } else if (selectedTo == 'Manual' ||
                                        selectedTo == 'Link') {
                                      receiver = manualInput;
                                      if (selectedTo == 'Link') {
                                        linkId = int.tryParse(manualInput);
                                      }
                                    }
                                  }

                                  if (receiver == null || receiver!.isEmpty) {
                                    showValidationToast(
                                      'Kolom Belum Lengkap!',
                                      'Silakan periksa kembali data ${isGroup ? "grup" : "penerima"} yang dipilih.',
                                    );
                                    return;
                                  }

                                  setDialogState(() => isCreatingRoom = true);

                                  // Buat ruang obrolan (room) melalui API baru alih-alih sekadar mengirim pesan
                                  final result = await chatService
                                      .createNewRoom(
                                        accountId: accountIdInt,
                                        channelId: channelIdInt,
                                        contactId: isGroup ? null : contactId,
                                        linkId: linkId,
                                        groupId: groupId,
                                        manualNumber: selectedTo == 'Manual'
                                            ? manualInput
                                            : null,
                                        isGroup: isGroup,
                                      );

                                  if (!mounted) return;
                                  setDialogState(() => isCreatingRoom = false);

                                  if (result['success'] == true) {
                                    Navigator.pop(dialogContext);

                                    // Muat ulang daftar chat dan navigasikan layar ke ruang chat yang baru dibuat
                                    if (mounted) {
                                      // Sesuai kode mentor: Jeda statis lalu fetch ulang paksa
                                      final isManual = manualInput.isNotEmpty;
                                      final delayDuration = isManual
                                          ? const Duration(seconds: 2)
                                          : const Duration(milliseconds: 1500);

                                      await Future.delayed(delayDuration);
                                      await context
                                          .read<ChatProvider>()
                                          .fetchChats();

                                      if (mounted &&
                                          _scrollController.hasClients) {
                                        _scrollController.animateTo(
                                          0,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeOut,
                                        );
                                      }

                                      final chats = context
                                          .read<ChatProvider>()
                                          .chats;
                                      
                                      // Cari chat yang sesuai dengan tujuan yang dipilih pengguna.
                                      String? newRoomIdStr = result['roomId']
                                          ?.toString();
                                      ChatModel? newChat;
                                      try {
                                        newChat = chats.firstWhere((c) {
                                          if (newRoomIdStr != null &&
                                              newRoomIdStr.isNotEmpty &&
                                              c.id == newRoomIdStr)
                                            return true;

                                          // Validasi agar tepat sasaran ke kamar channel yang dipilih
                                          bool isSameChannel =
                                              c.chId == channelIdInt.toString();
                                          if (!isSameChannel) return false;

                                          if (isGroup) {
                                            if (groupId != null &&
                                                groupId != 0 &&
                                                (c.groupId == groupId.toString() ||
                                                    c.ctRealId == groupId.toString())) {
                                              return true;
                                            }
                                            if (groupName != null &&
                                                groupName.isNotEmpty &&
                                                c.groupName.trim().toLowerCase() ==
                                                    groupName.trim().toLowerCase()) {
                                              return true;
                                            }
                                            return false;
                                          }

                                          if (linkId != null &&
                                              linkId! > 0 &&
                                              c.link == linkId.toString())
                                            return true;
                                          if (receiver != null &&
                                              receiver!.isNotEmpty &&
                                              (c.contactId == receiver ||
                                                  c.ctRealId == receiver))
                                            return true;
                                          if (selectedContact != null &&
                                              selectedContact!.isNotEmpty) {
                                            final rawTarget = selectedContact!
                                                .replaceAll(
                                                  RegExp(r'\s*\(\d+\)$'),
                                                  '',
                                                )
                                                .trim()
                                                .toLowerCase();
                                            if (rawTarget.isNotEmpty &&
                                                c.sender.trim().toLowerCase() ==
                                                    rawTarget) return true;
                                          }
                                          if (manualInput.isNotEmpty &&
                                              c.sender.trim().toLowerCase() ==
                                                  manualInput
                                                      .trim()
                                                      .toLowerCase())
                                            return true;
                                          return false;
                                        });
                                      } catch (e) {
                                        // Jika tidak ditemukan di 20 list pertama karena belum ada pesan (waktu masih null di server)
                                        String resolvedCtId =
                                            result['contactId']?.toString() ??
                                            (contactId?.toString() ?? '');
                                        String resolvedLinkId =
                                            result['linkId']?.toString() ??
                                            (linkId?.toString() ?? '');
                                        String resolvedAccId =
                                            result['accountId']?.toString() ??
                                            accountIdInt.toString();
                                        String resolvedCtRealId =
                                            result['ctRealId']?.toString() ??
                                            (receiver ?? '');
                                        String resolvedSender =
                                            selectedContact?.isNotEmpty == true
                                                ? selectedContact!
                                                : (manualInput.isNotEmpty
                                                    ? manualInput
                                                    : 'New Chat');

                                        // Jika ID masih kosong/tidak lengkap, ambil detail obrolan dari server menggunakan getDetailRoom
                                        if (newRoomIdStr != null &&
                                            newRoomIdStr.isNotEmpty &&
                                            (resolvedCtId.isEmpty ||
                                                resolvedCtId == '0')) {
                                          try {
                                            final detail = await context
                                                .read<ChatProvider>()
                                                .getDetailRoom(
                                                  newRoomIdStr,
                                                  forceRefresh: true,
                                                );
                                            if (detail != null) {
                                              final rData =
                                                  detail['Room'] ??
                                                  detail['Data']?['Room'] ??
                                                  detail;
                                              if (rData is Map) {
                                                final dCtId =
                                                    rData['CtId']?.toString() ??
                                                    rData['ContactId']
                                                        ?.toString();
                                                if (dCtId != null &&
                                                    dCtId.isNotEmpty &&
                                                    dCtId != '0')
                                                  resolvedCtId = dCtId;
                                                final dLinkId = rData['LinkTmp']
                                                        ?.toString() ??
                                                    rData['LinkId']?.toString();
                                                if (dLinkId != null &&
                                                    dLinkId.isNotEmpty &&
                                                    dLinkId != '0')
                                                  resolvedLinkId = dLinkId;
                                                final dAccId = rData['ChAccId']
                                                        ?.toString() ??
                                                    rData['AccId']?.toString();
                                                if (dAccId != null &&
                                                    dAccId.isNotEmpty &&
                                                    dAccId != '0')
                                                  resolvedAccId = dAccId;
                                                final dCtReal = rData['CtRealId']
                                                    ?.toString();
                                                if (dCtReal != null &&
                                                    dCtReal.isNotEmpty &&
                                                    dCtReal != '0')
                                                  resolvedCtRealId = dCtReal;
                                                final dSender = rData['CtRealNm']
                                                        ?.toString() ??
                                                    rData['ContactName']
                                                        ?.toString();
                                                if (dSender != null &&
                                                    dSender.isNotEmpty &&
                                                    dSender != 'null')
                                                  resolvedSender = dSender;
                                              }
                                            }
                                          } catch (err) {
                                            debugPrint(
                                              'ChatList: Gagal fetch getDetailRoom untuk New Chat: $err',
                                            );
                                          }
                                        }

                                        newChat = ChatModel(
                                          id: newRoomIdStr ?? '',
                                          contactId: isGroup
                                              ? ''
                                              : (resolvedCtId.isNotEmpty
                                                  ? resolvedCtId
                                                  : (receiver ?? '')),
                                          sender: isGroup
                                              ? (groupName?.isNotEmpty == true
                                                  ? groupName!
                                                  : (selectedGroup?.isNotEmpty == true
                                                      ? selectedGroup!
                                                      : (manualInput.isNotEmpty
                                                          ? manualInput
                                                          : 'Group')))
                                              : resolvedSender,
                                          lastMessage: '',
                                          time:
                                              DateTime.now().toIso8601String(),
                                          unreadCount: 0,
                                          status: 'Unassigned',
                                          agentName: '',
                                          tags: [],
                                          avatarUrl: null,
                                          lastMessageType: null,
                                          channelName:
                                              selectedAccount?.isNotEmpty == true
                                                  ? selectedAccount!
                                                  : (selectedChannel ?? ''),
                                          channelType: selectedChannel ?? '',
                                          isPinned: false,
                                          chId: channelIdInt.toString(),
                                          funnel: '',
                                          isGroup: isGroup,
                                          isBlocked: false,
                                          isLastMessageFromMe: true,
                                          needReply: false,
                                          accountId: resolvedAccId,
                                          ctRealId: resolvedCtRealId,
                                          link: resolvedLinkId,
                                          campaign: '',
                                          deal: '',
                                          groupName: isGroup
                                              ? (groupName?.isNotEmpty == true
                                                  ? groupName!
                                                  : (selectedGroup?.isNotEmpty == true
                                                      ? selectedGroup!
                                                      : (manualInput.isNotEmpty
                                                          ? manualInput
                                                          : 'Group')))
                                              : '',
                                          groupId:
                                              isGroup ? (groupId?.toString() ?? receiver ?? '') : '',
                                        );
                                        // Masukkan ke daftar lokal agar langsung terlihat
                                        context
                                            .read<ChatProvider>()
                                            .insertLocalChat(newChat);
                                      }

                                      if (widget.onChatSelected != null) {
                                        widget.onChatSelected!(newChat);
                                      } else {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ChatDetailPage(chat: newChat!),
                                          ),
                                        );
                                      }
                                      if (mounted) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            context
                                                .read<ChatProvider>()
                                                .refreshFirstPage();
                                          }
                                        });
                                      }
                                    }
                                  } else {
                                    showDialog(
                                      context: dialogContext,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Failed to Create Conversation'),
                                        content: Text('Terjadi kesalahan:\n\n${result['error']}\n\nPastikan konfigurasi channel di server sudah benar dan sedang online.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Tutup'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: isCreatingRoom
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Create'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // FITUR: Tile Akses Arsip
  // FUNGSI: Menampilkan baris di atas daftar chat untuk mengakses halaman Arsip, lengkap dengan jumlah (badge) chat yang saat ini diarsipkan.
  Widget _buildArchivedTile(BuildContext context, int count) {
    return ListTile(
      leading: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.archive_outlined, color: Colors.blue),
      ),
      title: const Text(
        'Diarsipkan',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Text(
        count.toString(),
        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ArchiveListPage()),
        );
      },
    );
  }

  // FITUR: Dialog Konfirmasi Keluar (Logout)
  // FUNGSI: Menampilkan popup peringatan dan menghapus cache lokal (provider) sebelum membawa pengguna kembali ke layar login.
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Confirmation'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Bersihkan cache (tags, funnels, chatrooms) sebelum logout agar tidak bocor ke sesi login akun berikutnya
              context.read<ChatProvider>().clearChatDataForAccountSwitch();
              context.read<AuthProvider>().logout();
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.login,
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Shimmer skeleton loading indicator for infinite scroll (3 items)
  // FITUR: Skeleton Loading (Pagination)
  // FUNGSI: Menampilkan animasi kerangka memuat (shimmer effect) di bagian bawah daftar chat saat aplikasi sedang menarik data halaman berikutnya.
  Widget _buildLoadingMoreSkeleton(bool isDark) {
    return _ShimmerLoadingWidget(isDark: isDark);
  }

  // FITUR: Status Badge (Assigned/Resolved/dll)
  // FUNGSI: Merender label kecil di kanan bawah chat tile berdasarkan status tiket obrolan, dengan warna yang disesuaikan.
  Widget _buildStatusBadge(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color color;
    switch (status) {
      case 'Resolved':
        color = const Color(0xFF2E7D32); // Green
        break;
      case 'Assigned':
        color = const Color(0xFF1565C0); // Blue
        break;
      case 'Unassigned':
        color = const Color(0xFFE65100); // Orange
        break;
      default:
        color = Colors.grey.shade700;
    }

    // Ini untuk membuat label Status Tag khusus ('Assigned', 'Resolved', dll) di kanan bawah
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.transparent
            : (status == 'Assigned' ? Colors.blue.shade50 : Colors.white),
        border: Border.all(
          color: status == 'Assigned'
              ? Colors.blue.shade400
              : color.withOpacity(0.5),
        ), // Border warna biru
        borderRadius: BorderRadius.circular(
          15,
        ), // Corner bulat persis 15 sesuai instruksi
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isDark
              ? (status == 'Assigned' ? Colors.blue.shade300 : color)
              : (status == 'Assigned' ? Colors.blue.shade700 : color),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChatTile(
    BuildContext context,
    ChatModel chat,
    ChatProvider chatProvider,
    bool isDark,
  ) {
    final chatSettings = context.watch<ChatSettingsProvider>();
    final isMultiSelected = _selectedChats.contains(chat.id);
    final isActiveMaster = widget.selectedChatId == chat.id;

    Color _getTileColor() {
      if (isMultiSelected) {
        return isDark
            ? Colors.blue.shade900.withOpacity(0.3)
            : Colors.blue.shade50;
      } else if (isActiveMaster) {
        return isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.grey.shade200;
      }
      return isDark ? const Color(0xFF1F2C34) : Colors.white;
    }

    return _SwipeableChatTile(
      key: ValueKey('swipe_${chat.id}'),
      chat: chat,
      chatProvider: chatProvider,
      isDark: isDark,
      child: Container(
        color: _getTileColor(),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              height: 0.5,
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey.shade300,
            ),
            InkWell(
              onTap: () async {
                if (_selectedChats.isNotEmpty) {
                  setState(() {
                    if (isMultiSelected)
                      _selectedChats.remove(chat.id);
                    else
                      _selectedChats.add(chat.id);
                  });
                  return;
                }
                chatProvider.markAsRead(chat.id);
                if (widget.onChatSelected != null) {
                  widget.onChatSelected!(chat);
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatDetailPage(chat: chat)),
                  );
                }

                // Kita hanya refresh jika onChatSelected null (mode mobile navigation)
                // Jalankan setelah animasi pop selesai agar tidak terjadi freeze / frame drop
                if (mounted && widget.onChatSelected == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      chatProvider.refreshFirstPage();
                    }
                  });
                }
              },
              onLongPress: () {
                if (_selectedChats.isEmpty) {
                  setState(() => _selectedChats.add(chat.id));
                } else {
                  _showChatOptions(context, chat, chatProvider);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                                  isMultiSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isMultiSelected
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
                            // Row 1: Name
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

                            // Row 2: Last message
                            _buildLastMessageRow(chat, isDark),

                            // Row 3: Tags & Funnel (inline)
                            Builder(
                              builder: (context) {
                                final validTags = chat.tags
                                    .map((t) => StringHelper.cleanApostrophe(t.trim()))
                                    .where((t) => t.isNotEmpty)
                                    .toList();
                                final hasFunnel = chat.funnel.trim().isNotEmpty;

                                if (validTags.isEmpty && !hasFunnel)
                                  return const SizedBox.shrink();

                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      if (validTags.isNotEmpty) ...[
                                        Icon(
                                          Icons.local_offer,
                                          size: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            validTags.join(', '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (validTags.isNotEmpty &&
                                          hasFunnel) ...[
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
                                      if (hasFunnel) ...[
                                        Icon(
                                          Icons.filter_alt,
                                          size: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          flex: validTags.isNotEmpty ? 2 : 1,
                                          child: Text(
                                            chat.funnel.trim(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),

                            // Row 4: Channel Icon and Name
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
                              // Jam & Pin (Row teratas sisi kanan)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(
                                      chat.time,
                                      dateFormat: chatSettings.dateFormat,
                                      timeFormat: chatSettings.timeFormat,
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  if (chat.isBlocked) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.person_off,
                                      size: 14,
                                      color: Colors.red,
                                    ),
                                  ],
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

                              // Badge Unread
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
                                    chat.unreadCount.toString(),
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
                          _buildStatusBadge(chat.status),
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
      ),
    );
  }

  // FITUR: Preview Pesan Terakhir (Indikator Warna & Tipe)
  // FUNGSI: Menampilkan cuplikan pesan terakhir di daftar chat, memberikan warna khusus (merah jika butuh balasan dari pelanggan), dan membedakan ikon lampiran.
  Widget _buildLastMessageRow(ChatModel chat, bool isDark) {
    // Logika warna berdasarkan status baca:
    // Jika unreadCount > 0 -> Ada pesan masuk baru yang belum dibaca -> Merah
    // Jika tidak -> Hitam/Warna Tema
    final bool hasUnread = chat.unreadCount > 0;
    // Aturan Resmi Backend NoBox:
    // 1. Teks pesan terakhir MERAH: SdrMsg == "you" dan IsNeedReply == 1 (atau unreadCount > 0)
    // 2. Balasan dari Agen (termasuk Telegram/Web/App): SdrMsg == "me" -> Teks normal (bukan merah)
    final bool isFromAgent = chat.sdrMsg.toLowerCase() == 'me' || chat.isLastMessageFromMe;
    final bool isCustomer = chat.sdrMsg.toLowerCase() == 'you' || (!isFromAgent && chat.sdrMsg.isEmpty);
    final bool isRedText = !isFromAgent && isCustomer && (chat.needReply || hasUnread);

    final Color messageColor = isRedText
        ? Colors.red
        : (isDark ? Colors.grey.shade400 : Colors.black87);

    String displayMessage = chat.lastMessage;
    bool isDeletedMessage = false;
    if (displayMessage.trim().toLowerCase() == 'document(empty)') {
      displayMessage = '';
    } else if (displayMessage.contains('Site.Inbox.DeletedMessage')) {
      displayMessage = '';
      isDeletedMessage = true;
    }
    final trimmedMsg = displayMessage.trim();
    bool parsedAsMedia = false;

    // FIX: Tangani label manual & audio terlebih dahulu sebelum JSON parsing.
    // Jika lastMessage diketik paksa secara lokal atau berupa nama file rekaman suara,
    // langsung atur ke Voice Note agar tidak tertimpa oleh chat.lastMessageType ("Document") yang usang.
    final lowerTrimmed = trimmedMsg.toLowerCase();

    bool isAudioMessage(String str) {
      if (str.isEmpty) return false;
      final lower = str.toLowerCase().trim();
      if (lower == '🎤 pesan suara' ||
          lower == 'pesan suara' ||
          lower == '🎵 voice note' ||
          lower == 'voice note' ||
          lower == 'voice' ||
          lower == 'audio' ||
          lower == 'voice(empty)' ||
          lower == 'voice (empty)' ||
          lower == 'audio(empty)' ||
          lower == 'audio (empty)') {
        return true;
      }
      if (lower.startsWith('voice_') ||
          lower.startsWith('aud-') ||
          lower.startsWith('ptt-') ||
          lower.contains('voice_') ||
          lower.contains('ptt-')) {
        return true;
      }
      return const [
        '.ogg',
        '.opus',
        '.mp3',
        '.wav',
        '.m4a',
        '.aac',
        '.weba',
        '.amr',
      ].any((ext) => lower.contains(ext));
    }

    String formatPhotoPreview(String text, {String? caption}) {
      final cap = (caption ?? '').trim();
      if (cap.isNotEmpty) {
        final cleanedCap = cap
            .replaceAll('📷', '')
            .replaceAll('🖼️', '')
            .replaceAll('🖼', '')
            .replaceAll(RegExp(r'^(Photo|Foto)\s*', caseSensitive: false), '')
            .trim();
        return cleanedCap.isNotEmpty ? '📷 $cleanedCap' : '📷 Photo';
      }

      String t = text.trim();
      t = t
          .replaceAll('📷', '')
          .replaceAll('🖼️', '')
          .replaceAll('🖼', '')
          .trim();
      final match = RegExp(r'^(Photo|Foto)\s*(.*)$', caseSensitive: false).firstMatch(t);
      if (match != null) {
        final desc = match.group(2)?.trim() ?? '';
        return desc.isNotEmpty ? '📷 $desc' : '📷 Photo';
      }
      if (t.isNotEmpty && t.toLowerCase() != 'photo' && t.toLowerCase() != 'foto') {
        return '📷 $t';
      }
      return '📷 Photo';
    }

    final isRawPhotoString = RegExp(r'^(📷|🖼️|🖼)\s*(Photo|Foto)', caseSensitive: false).hasMatch(trimmedMsg);
    final exactPhotoLabels = ['📷 photo', '📷 foto', '🖼 photo', '🖼 foto'];
    final exactVideoLabels = ['🎥 video', '🎬 video'];
    final exactStickerLabels = ['🌟 sticker', '🎬 sticker'];

    final isVoiceNote = chat.lastMessageType == '2' ||
        chat.lastMessageType?.toLowerCase() == 'voice note' ||
        chat.lastMessageType?.toLowerCase() == 'audio' ||
        isAudioMessage(trimmedMsg);

    if (isVoiceNote) {
      displayMessage = '🎤 Voice Message';
      parsedAsMedia = true;
    } else if (exactStickerLabels.contains(lowerTrimmed) || chat.lastMessageType == '16' || chat.lastMessageType == '17') {
      displayMessage = '🌟 Sticker';
      parsedAsMedia = true;
    } else if (isRawPhotoString ||
        exactPhotoLabels.contains(lowerTrimmed) ||
        chat.lastMessageType == '3' ||
        chat.lastMessageType?.toLowerCase() == 'photo' ||
        chat.lastMessageType?.toLowerCase() == 'image') {
      displayMessage = formatPhotoPreview(trimmedMsg);
      parsedAsMedia = true;
    } else if (exactVideoLabels.contains(lowerTrimmed) || chat.lastMessageType == '4') {
      displayMessage = '🎬 Video';
      parsedAsMedia = true;
    }

    // 1. Coba parse JSON terlebih dahulu (karena prioritas detail media dari JSON lebih akurat daripada lastMessageType)
    if (!parsedAsMedia &&
        (trimmedMsg.startsWith('{') || trimmedMsg.startsWith('['))) {
      try {
        final decoded = jsonDecode(trimmedMsg);
        final fileMap = decoded is List
            ? (decoded.isNotEmpty ? decoded.first : {})
            : decoded;

        if (fileMap is Map) {
          // EXTRACT NESTED MAP IF PRESENT (Some backend payloads wrap the file details)
          Map targetMap = fileMap;
          if (targetMap['File'] is String &&
              (targetMap['File'].toString().startsWith('{') ||
                  targetMap['File'].toString().startsWith('['))) {
            try {
              final decodedFile = jsonDecode(targetMap['File']);
              if (decodedFile is List && decodedFile.isNotEmpty)
                targetMap = decodedFile.first;
              else if (decodedFile is Map)
                targetMap = decodedFile;
            } catch (_) {}
          } else if (targetMap['Files'] is List &&
              (targetMap['Files'] as List).isNotEmpty) {
            final firstItem = targetMap['Files'].first;
            if (firstItem is Map) {
              targetMap = firstItem;
            } else if (firstItem is String) {
              // If it's just a string, it might be the filename itself!
              targetMap = {
                'File': firstItem,
                'Type':
                    targetMap['Type'] ?? targetMap['type'] ?? fileMap['Type'],
              };
            }
          } else if (targetMap['Files'] is String &&
              (targetMap['Files'].toString().startsWith('{') ||
                  targetMap['Files'].toString().startsWith('['))) {
            try {
              final decodedFiles = jsonDecode(targetMap['Files']);
              if (decodedFiles is List && decodedFiles.isNotEmpty)
                targetMap = decodedFiles.first;
              else if (decodedFiles is Map)
                targetMap = decodedFiles;
            } catch (_) {}
          } else if (targetMap['Msg'] is String &&
              (targetMap['Msg'].toString().startsWith('{') ||
                  targetMap['Msg'].toString().startsWith('['))) {
            try {
              final decodedMsg = jsonDecode(targetMap['Msg']);
              if (decodedMsg is List && decodedMsg.isNotEmpty)
                targetMap = decodedMsg.first;
              else if (decodedMsg is Map)
                targetMap = decodedMsg;
            } catch (_) {}
          }

          // FIX: Buat pengecekan key JSON menjadi case-insensitive dan tangani tipe string
          final typeVal =
              targetMap['Type']?.toString() ??
              targetMap['type']?.toString() ??
              fileMap['Type']?.toString() ??
              '';

          final isPtt =
              targetMap['Ptt'] == true ||
              targetMap['IsPtt'] == true ||
              targetMap['ptt'] == true ||
              targetMap['isPtt'] == true ||
              targetMap['Ptt']?.toString().toLowerCase() == 'true' ||
              targetMap['ptt']?.toString().toLowerCase() == 'true';

          final filename =
              targetMap['Filename']?.toString().toLowerCase() ??
              targetMap['filename']?.toString().toLowerCase() ??
              targetMap['File']?.toString().toLowerCase() ??
              targetMap['file']?.toString().toLowerCase() ??
              targetMap['url']?.toString().toLowerCase() ??
              targetMap['Url']?.toString().toLowerCase() ??
              '';

          final originalName =
              targetMap['OriginalName']?.toString().toLowerCase() ??
              targetMap['originalname']?.toString().toLowerCase() ??
              '';
          final caption =
              targetMap['Caption']?.toString() ??
              targetMap['caption']?.toString() ??
              '';

          final isDocument = typeVal == '5';

          bool _isWebLink(String str) {
            if (str.isEmpty) return false;
            final lower = str.toLowerCase();
            if (lower.startsWith('http')) return true;
            if (lower.startsWith('www.')) return true;
            if (lower.contains('tiktok.com') ||
                lower.contains('tiktok.co') ||
                lower.contains('instagram.com') ||
                lower.contains('youtube.com') ||
                lower.contains('youtu.be') ||
                lower.contains('shopee.co') ||
                lower.contains('tokopedia.com') ||
                lower.contains('facebook.com') ||
                lower.contains('twitter.com') ||
                lower.contains('x.com'))
              return true;
            if (RegExp(
              r'^[a-zA-Z0-9-]+\.(com|id|net|org|co|io|me|be|xyz)(\/|$)',
            ).hasMatch(lower))
              return true;
            return false;
          }

          final isWebLink =
              _isWebLink(filename) ||
              _isWebLink(originalName) ||
              _isWebLink(trimmedMsg);

          final isAudio =
              !isWebLink &&
              (isPtt ||
                  typeVal == '2' ||
                  [
                    '.ogg',
                    '.oga',
                    '.mp3',
                    '.wav',
                    '.m4a',
                    '.opus',
                    '.aac',
                    '.weba',
                    '.amr',
                  ].any(
                    (ext) =>
                        filename.contains(ext) ||
                        originalName.contains(ext),
                  ) ||
                  originalName.contains('voice note') ||
                  originalName.contains('pesan suara') ||
                  originalName.contains('voice_') ||
                  filename.contains('voice_') ||
                  filename.contains('ptt-') ||
                  originalName.contains('ptt-'));

          final isSticker =
              typeVal == '16' ||
              typeVal == '17' ||
              [
                '.webm',
                '.tgs',
                '.webp',
                '.ezgif',
              ].any(
                (s) =>
                    filename.contains(s) ||
                    originalName.contains(s) ||
                    caption.toLowerCase().contains(s) ||
                    trimmedMsg.toLowerCase().contains(s),
              );

          final isImage =
              !isSticker &&
              (typeVal == '3' ||
                  (!isDocument &&
                      ['.jpg', '.jpeg', '.png', '.gif', '.webp'].any(
                        (ext) =>
                            filename.contains(ext) ||
                            originalName.contains(ext),
                      )));

          final isVideo =
              !isSticker &&
              ((typeVal == '4' && !isSticker) ||
                  (!isDocument &&
                      !isSticker &&
                      ['.mp4', '.avi', '.mov', '.3gp', '.mkv'].any(
                        (ext) =>
                            filename.contains(ext) ||
                            originalName.contains(ext),
                      )));

          final isLocation =
              typeVal == '15' ||
              typeVal == '11' ||
              trimmedMsg.toLowerCase().contains('"lat":');
          final isContact = typeVal == '14' || typeVal == '10';

          if (isSticker) {
            if (typeVal == '17' ||
                ['.webm', '.tgs', '.mp4'].any((ext) =>
                    filename.contains(ext) ||
                    originalName.contains(ext) ||
                    trimmedMsg.toLowerCase().contains(ext)) ||
                displayMessage.contains('🎬')) {
              displayMessage = '🎬 Sticker';
            } else {
              displayMessage = '🌟 Sticker';
            }
            debugPrint('DEBUG STICKER JSON: isSticker=$isSticker, typeVal=$typeVal, filename=$filename, originalName=$originalName, msg=$trimmedMsg => result=$displayMessage');
            parsedAsMedia = true;
          } else if (isAudio) {
            displayMessage = '🎤 Voice Message';
            parsedAsMedia = true;
          } else if (isDocument && !isSticker) {
            String docName = 'Document';
            if (originalName.isNotEmpty) {
              docName =
                  targetMap['OriginalName']?.toString() ??
                  targetMap['originalname']?.toString() ??
                  'Document';
            } else if (filename.isNotEmpty) {
              docName =
                  (targetMap['Filename']?.toString() ??
                          targetMap['url']?.toString() ??
                          'Document')
                      .split('/')
                      .last;
            }
            if (caption.isNotEmpty &&
                !caption.startsWith('{') &&
                !caption.startsWith('[')) {
              displayMessage = '📎 $caption';
            } else {
              displayMessage = '📄 $docName';
            }
            parsedAsMedia = true;
          } else if (isImage) {
            displayMessage = formatPhotoPreview('', caption: caption);
            parsedAsMedia = true;
          } else if (isVideo) {
            displayMessage = '🎬 Video${caption.isNotEmpty ? ' $caption' : ''}';
            parsedAsMedia = true;
          } else if (isLocation) {
            displayMessage = '📍 Location';
            parsedAsMedia = true;
          } else if (isContact) {
            displayMessage = '👤 Contact';
            parsedAsMedia = true;
          } else if (filename.isNotEmpty || originalName.isNotEmpty) {
            // Cek apakah backend secara eksplisit memberitahu tipe media di lastMessageType
            final overrideType = chat.lastMessageType?.toLowerCase() ?? '';
            if (overrideType.contains('voice note') ||
                overrideType.contains('audio') ||
                overrideType == '2') {
              displayMessage = '🎤 Voice Message';
            } else if (overrideType.contains('image') ||
                overrideType.contains('photo') ||
                overrideType == '3') {
              displayMessage = formatPhotoPreview('', caption: caption);
            } else if (overrideType.contains('video')) {
              displayMessage =
                  '🎬 Video${caption.isNotEmpty ? ' $caption' : ''}';
            } else {
              String docName = 'Lampiran';
              if (originalName.isNotEmpty) {
                docName =
                    targetMap['OriginalName']?.toString() ??
                    targetMap['originalname']?.toString() ??
                    'Lampiran';
              } else if (filename.isNotEmpty) {
                docName =
                    (targetMap['Filename']?.toString() ??
                            targetMap['url']?.toString() ??
                            'Lampiran')
                        .split('/')
                        .last;
              }
              if (caption.isNotEmpty &&
                  !caption.startsWith('{') &&
                  !caption.startsWith('[')) {
                displayMessage = '📎 $caption';
              } else if (docName.toLowerCase().contains('document(empty)')) {
                final rawText =
                    targetMap['Msg']?.toString() ??
                    targetMap['Body']?.toString() ??
                    targetMap['Message']?.toString() ??
                    targetMap['Content']?.toString() ??
                    '';
                if (rawText.isNotEmpty &&
                    !rawText.startsWith('{') &&
                    !rawText.startsWith('[')) {
                  displayMessage = rawText;
                } else {
                  displayMessage = '📎 Lampiran';
                }
              } else {
                displayMessage = '📎 $docName';
              }
              parsedAsMedia = true;
            } // Close the `else` block from line 1495
            parsedAsMedia = true;
          } else {
            // Bukan media/file yang dikenal, coba ekstrak teks mentah (misal balasan Telegram/Bot yang dibungkus JSON)
            String rawText =
                targetMap['caption']?.toString() ??
                targetMap['Caption']?.toString() ??
                targetMap['text']?.toString() ??
                targetMap['Text']?.toString() ??
                targetMap['Msg']?.toString() ??
                targetMap['msg']?.toString() ??
                targetMap['Body']?.toString() ??
                targetMap['body']?.toString() ??
                targetMap['Message']?.toString() ??
                targetMap['Content']?.toString() ??
                targetMap['content']?.toString() ??
                '';

            // Cek jika dibungkus dalam objek nested "message"
            if (rawText.isEmpty && targetMap['message'] is Map) {
              final nested = targetMap['message'] as Map;
              rawText = nested['text']?.toString() ??
                  nested['caption']?.toString() ??
                  nested['Msg']?.toString() ??
                  '';
            }

            if (rawText.isNotEmpty &&
                !rawText.startsWith('{') &&
                !rawText.startsWith('[')) {
              displayMessage = rawText;
              parsedAsMedia = false; // Ini adalah teks biasa dari bot/user, bukan media!
            }
          }
        }
      } catch (_) {
        // Abaikan error parse, mungkin bukan JSON media
      }
    }

    // 2. Jika tidak berhasil diparse sebagai media JSON secara spesifik, cek lastMessageType dari backend
    final isLikelyPlainText =
        !trimmedMsg.startsWith('{') &&
        !trimmedMsg.startsWith('[') &&
        trimmedMsg.isNotEmpty &&
        !isAudioMessage(trimmedMsg) &&
        !exactPhotoLabels.contains(lowerTrimmed) &&
        !exactVideoLabels.contains(lowerTrimmed) &&
        !exactStickerLabels.contains(lowerTrimmed);
    if (!parsedAsMedia &&
        chat.lastMessageType != null &&
        chat.lastMessageType!.isNotEmpty) {
      final overrideType = chat.lastMessageType!.toLowerCase();

      if (overrideType.contains('voice note') ||
          overrideType.contains('audio') ||
          overrideType == '2' ||
          isAudioMessage(trimmedMsg)) {
        displayMessage = '🎤 Voice Message';
        parsedAsMedia = true;
      } else if (!isLikelyPlainText) {
        if (overrideType.contains('image') ||
            overrideType.contains('photo') ||
            overrideType == '3') {
          displayMessage = formatPhotoPreview(displayMessage);
        } else if (overrideType.contains('video') || overrideType == '4') {
          final cleaned = displayMessage
              .replaceAll('🎥', '')
              .replaceAll('📹', '')
              .replaceAll('🎬', '')
              .replaceAll('Video', '')
              .trim();
          if (displayMessage.toLowerCase().contains('.webm') ||
              displayMessage.toLowerCase().contains('.tgs') ||
              exactStickerLabels.contains(displayMessage.toLowerCase())) {
            displayMessage = '🎬 Sticker';
          } else {
            displayMessage = '🎬 Video${cleaned.isNotEmpty ? ' $cleaned' : ''}';
          }
        }
      } else if (overrideType == '16' || overrideType == '17' || overrideType.contains('sticker')) {
        if (overrideType == '17' ||
            displayMessage.toLowerCase().contains('.webm') ||
            displayMessage.toLowerCase().contains('.tgs') ||
            displayMessage.contains('🎬')) {
          displayMessage = '🎬 Sticker';
        } else {
          displayMessage = '🌟 Sticker';
        }
        debugPrint('DEBUG STICKER OVERRIDE: overrideType=$overrideType, displayMessage (original)=${chat.lastMessage} => result=$displayMessage');
      } else if (overrideType.contains('document') ||
          overrideType.contains('file') ||
          overrideType == '5') {
        if (displayMessage.contains('📎') ||
            displayMessage.contains('📁') ||
            displayMessage.contains('📄')) {
          // sudah ada emoji
        } else if (displayMessage.isEmpty) {
          displayMessage = '📎 Lampiran';
        } else {
          final preview = trimmedMsg.length > 35
              ? '${trimmedMsg.substring(0, 35)}...'
              : trimmedMsg;
          displayMessage = '📎 $preview';
        }
      } else if (overrideType == '15' ||
          overrideType == '11' ||
          overrideType.contains('location')) {
        displayMessage = '📍 Location';
      } else if (overrideType == '14' ||
          overrideType == '10' ||
          overrideType.contains('contact')) {
        displayMessage = '👤 Contact';
      } else if (overrideType.contains('unsupported')) {
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
      } else if (overrideType == '1' || overrideType == 'text') {
        // Teks biasa, abaikan
      } else {
        // Fallback untuk tipe lain yang tidak dikenal
        displayMessage =
            '🌟 ${chat.lastMessageType}${displayMessage.isNotEmpty ? ' $displayMessage' : ''}';
      }

      if (overrideType != '1' && overrideType != 'text') {
        parsedAsMedia = true;
      }
    }

    // 3. Fallback jika string kosong dan bukan media
    // FIX: Cek apakah lastMessage asli mengandung teks readable (pesan edit/ditetik)
    // sebelum fallback ke "Lampiran"
    final originalLastMsg = chat.lastMessage.trim();
    final hasReadableOriginalText = originalLastMsg.isNotEmpty &&
        !originalLastMsg.startsWith('{') &&
        !originalLastMsg.startsWith('[') &&
        !originalLastMsg.toLowerCase().contains('site.inbox.deletedmessage') &&
        !originalLastMsg.toLowerCase().contains('document(empty)') &&
        !originalLastMsg.toLowerCase().contains('voice(empty)') &&
        !originalLastMsg.toLowerCase().contains('image(empty)') &&
        !originalLastMsg.toLowerCase().contains('video(empty)') &&
        !originalLastMsg.toLowerCase().contains('audio(empty)');

    if (!parsedAsMedia && displayMessage.isEmpty && !isDeletedMessage) {
      if (hasReadableOriginalText) {
        // Gunakan teks asli jika readable (misal pesan edit WhatsApp)
        displayMessage = originalLastMsg;
      } else {
        displayMessage = '📎 Lampiran';
      }
    }

    if (!parsedAsMedia &&
        (displayMessage == 'Document' ||
            displayMessage == '📄 Document' ||
            displayMessage == '📄 File' ||
            displayMessage == '📎 Lampiran')) {
      if (hasReadableOriginalText) {
        displayMessage = originalLastMsg;
      } else {
        displayMessage = '📎 Lampiran';
      }
    }

    // 4. Deteksi nama file mentah (non-JSON) berdasarkan ekstensi/pola nama
    bool isGenericAttachment =
        displayMessage.startsWith('📎') ||
        displayMessage == 'Lampiran' ||
        displayMessage.contains('RAW:');
    bool isDocumentAlready = displayMessage.startsWith('📄');

    if (!parsedAsMedia || isGenericAttachment || isDocumentAlready) {
      final lower = displayMessage
          .toLowerCase()
          .replaceAll('📎', '')
          .replaceAll('📄', '')
          .replaceAll('raw:', '')
          .trim();

      // Deteksi ekstensi audio/voice note terlebih dahulu (server sering menganggap rekaman audio sebagai Dokumen)
      if ([
            '.ogg',
            '.opus',
            '.mp3',
            '.wav',
            '.m4a',
            '.aac',
            '.amr',
            '.weba',
          ].any((ext) => lower.contains(ext)) ||
          lower.startsWith('voice_') ||
          lower.contains('voice_') ||
          lower.startsWith('ptt-') ||
          lower.contains('ptt-') ||
          lower.startsWith('aud-') ||
          lower == 'voice note' ||
          lower == 'pesan suara' ||
          chat.lastMessageType == '2' ||
          chat.lastMessageType?.toLowerCase() == 'voice note' ||
          chat.lastMessageType?.toLowerCase() == 'audio') {
        displayMessage = '🎤 Voice Message';
        parsedAsMedia = true;
      }
      // Jika sudah ditandai sebagai dokumen (📄), TETAP jadikan Dokumen terlepas dari ekstensinya!
      else if (isDocumentAlready) {
        // Tampilkan nama aslinya jika ada (tapi dibersihkan), atau cukup "Dokumen" jika berantakan
        if (lower.contains('img-') ||
            lower.contains('vid-') ||
            lower.contains('wa00')) {
          displayMessage = '📄 Dokumen';
        } else {
          // Pertahankan nama file asli jika dirasa rapi (misal: "📄 Laporan.pdf")
          displayMessage = displayMessage;
        }
        parsedAsMedia = true;
      }
      // Deteksi ekstensi gambar
      else if ([
            '.jpg',
            '.jpeg',
            '.png',
            '.gif',
            '.bmp',
          ].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('img-') ||
          lower.startsWith('img_') ||
          lower.startsWith('photo')) {
        displayMessage = formatPhotoPreview(displayMessage);
        parsedAsMedia = true;
      }
      // Deteksi stiker (WhatsApp webp, atau animasi webm/tgs)
      else if (['.webp', '.webm', '.tgs'].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('stk-')) {
        if (lower.endsWith('.webm') || lower.endsWith('.tgs')) {
          displayMessage = '🎬 Sticker';
        } else {
          displayMessage = '🌟 Sticker';
        }
        parsedAsMedia = true;
      }
      // Deteksi ekstensi video
      else if ([
            '.mp4',
            '.avi',
            '.mov',
            '.3gp',
            '.mkv',
          ].any((ext) => lower.endsWith(ext)) ||
          lower.startsWith('vid-') ||
          lower.startsWith('vid_')) {
        displayMessage = '🎬 Video';
        parsedAsMedia = true;
      }
      // Deteksi ekstensi dokumen
      else if ([
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
        displayMessage = '📄 Dokumen';
        parsedAsMedia = true;
      }
      // Jika ada ekstensi file apapun (generic file detection)
      else if (RegExp(r'\.[a-zA-Z0-9]{2,5}$').hasMatch(lower) &&
          !lower.contains(' ') &&
          !lower.contains('@') &&
          !lower.startsWith('http') &&
          lower.length < 100) {
        displayMessage = '📎 Lampiran';
        parsedAsMedia = true;
      }
    }

    if (RegExp(r'^(📷|🖼️|🖼)\s*(Photo|Foto)', caseSensitive: false).hasMatch(displayMessage)) {
      displayMessage = formatPhotoPreview(displayMessage);
    }

    return Text(
      displayMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: messageColor),
    );
  }

  // FITUR: Format Waktu Relatif / Format Sesuai Preferensi User
  // FUNGSI: Mengonversi waktu standar UTC dari server menjadi format string yang ramah pembaca sesuai preferensi User (DateFormat & TimeFormat).
  String _formatTime(String rawTime, {String? dateFormat, String? timeFormat}) {
    if (rawTime.isEmpty) return '';
    return DateTimeHelper.formatChatTimestamp(
      rawTime,
      dateFormat: dateFormat,
      timeFormat: timeFormat,
    );
  }

  // FITUR: Dialog Filter Lanjutan (Advanced Filter)
  // FUNGSI: Membuka modal popup besar yang memuat API Master Data (Campaign, Funnel, Label, dll) untuk memfilter daftar obrolan secara presisi.
  void _showFilterDialog() {
    final provider = context.read<ChatProvider>();
    final chatService =
        ChatService(); // Create locally for services not exposed through provider

    // Local state for dropdowns synchronized with provider
    String? selectedStatus = provider.activeFilter == 'All'
        ? null
        : provider.activeFilter;
    if (!['Assigned', 'Unassigned', 'Resolved'].contains(selectedStatus)) {
      selectedStatus = null;
    }
    String? selectedMuteAi = provider.filterMuteAi;
    String? selectedReadStatus = provider.filterReadStatus;
    String? selectedChannel = provider.filterChannel;
    String? selectedChat = provider.filterChatType;
    List<String> selectedAccountIds = List.from(provider.filterAccountIds);
    String? selectedContactId = provider.filterContact;
    String? selectedLinkId = provider.filterLink;
    String? selectedGroupId = provider.filterGroup;
    String? selectedCampaignId = provider.filterCampaign;
    String? selectedFunnelId = provider.filterFunnel;
    String? selectedDealId = provider.filterDeal;
    String? selectedTagsId = provider.filterTags;
    String? selectedHumanAgentId = provider.filterHumanAgent;

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder(
          future: Future.wait([
            provider.getChannelsResponse(),
            provider.getAccountsResponse(),
            provider.getContactsResponse(),
            provider.getGroupsResponse(),
            provider.getCampaignsResponse(),
            provider.getFunnels(),
            provider.getDealsResponse(),
            provider.getTags(),
            provider.getAgents(),
            provider.getLinksResponse(),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Extract lists gracefully into Models
            final channelsRaw =
                snapshot.data?[0] as ApiResponse<List<Map<String, dynamic>>>?;
            // FIXME: Jangan pakai Nm dari Master/Channel/List (misal: "SellerTokopedia.com")
            // karena channelType disimpan sebagai Account.Code (misal: "TokopediaCom").
            // Ambil opsi channel DARI Account list Code agar matching pasti benar.

            final accountsRaw =
                snapshot.data?[1] as ApiResponse<List<Map<String, dynamic>>>?;
            final accountList = accountsRaw?.data ?? [];

            // Derive unique channel codes from account list (e.g., 'WhatsApp', 'Telegram', 'TokopediaCom')
            // Also build a display name map: Code -> prettier name
            final channelCodeToName = <String, String>{};
            for (final acc in accountList) {
              final code = acc['Code']?.toString() ?? '';
              if (code.isEmpty) continue;
              // Try to get a prettier name from Master/Channel/List via Kd matching
              final masterMatch = channelsRaw?.data?.firstWhere(
                (ch) => (ch['Kd']?.toString() ?? '') == code,
                orElse: () => <String, dynamic>{},
              );
              final displayName =
                  (masterMatch != null && masterMatch.isNotEmpty)
                  ? (masterMatch['Nm']?.toString() ?? code)
                  : code;
              channelCodeToName[code] = displayName;
            }
            // channels list = unique codes (used as filter value)
            final channels = channelCodeToName.keys.toList();

            final contactsRaw =
                snapshot.data?[2] as ApiResponse<List<Map<String, dynamic>>>?;
            final contacts =
                contactsRaw?.data
                    ?.map((e) => ContactItem.fromJson(e))
                    .toList() ??
                [];

            final groupsRaw =
                snapshot.data?[3] as ApiResponse<List<Map<String, dynamic>>>?;
            final groups =
                groupsRaw?.data?.map((e) => GroupItem.fromJson(e)).toList() ??
                [];

            final campaignsRaw =
                snapshot.data?[4] as ApiResponse<List<Map<String, dynamic>>>?;
            final campaigns =
                campaignsRaw?.data
                    ?.map((e) => CampaignItem.fromJson(e))
                    .toList() ??
                [];

            final funnelsRaw = snapshot.data?[5] as List<Map<String, dynamic>>?;
            final funnels =
                funnelsRaw?.map((e) => FunnelItem.fromJson(e)).toList() ?? [];

            final dealsRaw =
                snapshot.data?[6] as ApiResponse<List<Map<String, dynamic>>>?;
            final deals =
                dealsRaw?.data?.map((e) => DealItem.fromJson(e)).toList() ?? [];

            final tagsRaw = snapshot.data?[7] as List<Map<String, dynamic>>?;
            final tags =
                tagsRaw?.map((e) => TagItem.fromJson(e)).toList() ?? [];

            final agentsRaw = snapshot.data?[8] as List<Map<String, dynamic>>?;
            final agents =
                agentsRaw?.map((e) => HumanAgentItem.fromJson(e)).toList() ??
                [];

            final linksRaw =
                snapshot.data?[9] as ApiResponse<List<Map<String, dynamic>>>?;
            final links =
                linksRaw?.data?.map((e) => LinkItem.fromJson(e)).toList() ?? [];

            if (selectedChannel != null &&
                !channels.contains(selectedChannel) &&
                selectedChannel != '--select--')
              channels.add(selectedChannel!);

            return StatefulBuilder(
              builder: (context, setDialogState) {
                final themeProvider = Provider.of<ThemeProvider>(context);
                final isDark = themeProvider.isDarkMode;

                Widget buildDropdownRow<T>(
                  String label,
                  T? value,
                  List<T> options,
                  ValueChanged<T?> onChanged, {
                  String Function(T)? itemAsString,
                }) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : Colors.black,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SearchableDropdown<T>(
                            value: value,
                            options: options,
                            onChanged: onChanged,
                            itemAsString: itemAsString,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Dialog(
                  backgroundColor: isDark
                      ? AppTheme.darkBackground
                      : Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  insetPadding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.025,
                    vertical: MediaQuery.of(context).size.height * 0.1,
                  ),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.95,
                    height: MediaQuery.of(context).size.height * 0.8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Filter Conversation',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.primaryColor,
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(
                                  Icons.close,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.primaryColor,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Apply & Reset buttons
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Apply filter
                                  provider.setActiveFilter(
                                    selectedStatus ?? 'All',
                                  );
                                  provider.applyAdvancedFilters(
                                    muteAi: selectedMuteAi,
                                    readStatus: selectedReadStatus,
                                    channel: selectedChannel,
                                    chatType: selectedChat,
                                    accountIds: selectedAccountIds,
                                    contact: selectedContactId,
                                    link: selectedLinkId,
                                    group: selectedGroupId,
                                    campaign: selectedCampaignId,
                                    funnel: selectedFunnelId,
                                    deal: selectedDealId,
                                    tags: selectedTagsId,
                                    humanAgent: selectedHumanAgentId,
                                  );
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.filter_alt, size: 16),
                                label: const Text('Apply'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    selectedStatus = null;
                                    selectedMuteAi = null;
                                    selectedReadStatus = null;
                                    selectedChannel = null;
                                    selectedChat = null;
                                    selectedAccountIds = [];
                                    selectedContactId = null;
                                    selectedLinkId = null;
                                    selectedGroupId = null;
                                    selectedCampaignId = null;
                                    selectedFunnelId = null;
                                    selectedDealId = null;
                                    selectedTagsId = null;
                                    selectedHumanAgentId = null;
                                  });
                                  provider.resetFilters();
                                },
                                icon: Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.primaryColor,
                                ),
                                label: Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.primaryColor,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.primaryColor,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Scrollable filter rows
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  buildDropdownRow(
                                    'Status',
                                    selectedStatus,
                                    ['Assigned', 'Unassigned', 'Resolved'],
                                    (val) {
                                      setDialogState(
                                        () => selectedStatus = val,
                                      );
                                    },
                                  ),
                                  buildDropdownRow(
                                    'Is Mute Ai Agent',
                                    selectedMuteAi,
                                    ['Active', 'Inactive'],
                                    (val) {
                                      setDialogState(
                                        () => selectedMuteAi = val,
                                      );
                                    },
                                  ),
                                  buildDropdownRow(
                                    'Read Status',
                                    selectedReadStatus,
                                    ['Is Read', 'Unread'],
                                    (val) {
                                      setDialogState(
                                        () => selectedReadStatus = val,
                                      );
                                    },
                                  ),
                                  buildDropdownRow(
                                    'Channel',
                                    selectedChannel,
                                    channels.isEmpty
                                        ? [
                                            'WhatsApp',
                                            'Telegram',
                                            'TikTok',
                                            'Shopee',
                                            'Tokopedia',
                                          ]
                                        : channels,
                                    (val) {
                                      setDialogState(
                                        () => selectedChannel = val,
                                      );
                                    },
                                    itemAsString: (code) =>
                                        channelCodeToName[code] ?? code,
                                  ),
                                  buildDropdownRow(
                                    'Chat',
                                    selectedChat,
                                    ['Private', 'Group'],
                                    (val) {
                                      setDialogState(() => selectedChat = val);
                                    },
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            'Account',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? AppTheme.darkTextPrimary
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (ctx) {
                                                  return StatefulBuilder(
                                                    builder:
                                                        (
                                                          context,
                                                          setMultiSelectState,
                                                        ) {
                                                          return AlertDialog(
                                                            title: const Text(
                                                              'Pilih Akun',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            content:
                                                                accountList
                                                                    .isEmpty
                                                                ? const Padding(
                                                                    padding:
                                                                        EdgeInsets.all(
                                                                          16,
                                                                        ),
                                                                    child: Text(
                                                                      "No accounts available",
                                                                    ),
                                                                  )
                                                                : SingleChildScrollView(
                                                                    child: Column(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: accountList.map((
                                                                        account,
                                                                      ) {
                                                                        final id =
                                                                            account['Id']?.toString() ??
                                                                            '';
                                                                        final name =
                                                                            account['Name']?.toString() ??
                                                                            account['Nm']?.toString() ??
                                                                            'Unknown';
                                                                        final isChecked =
                                                                            selectedAccountIds.contains(
                                                                              id,
                                                                            );

                                                                        return CheckboxListTile(
                                                                          title: Text(
                                                                            name,
                                                                            style: const TextStyle(
                                                                              fontSize: 14,
                                                                            ),
                                                                          ),
                                                                          value:
                                                                              isChecked,
                                                                          controlAffinity:
                                                                              ListTileControlAffinity.leading,
                                                                          contentPadding:
                                                                              EdgeInsets.zero,
                                                                          visualDensity:
                                                                              VisualDensity.compact,
                                                                          onChanged:
                                                                              (
                                                                                bool?
                                                                                value,
                                                                              ) {
                                                                                setMultiSelectState(
                                                                                  () {
                                                                                    if (value ==
                                                                                        true) {
                                                                                      selectedAccountIds.add(
                                                                                        id,
                                                                                      );
                                                                                    } else {
                                                                                      selectedAccountIds.remove(
                                                                                        id,
                                                                                      );
                                                                                    }
                                                                                  },
                                                                                );
                                                                                setDialogState(
                                                                                  () {},
                                                                                );
                                                                              },
                                                                        );
                                                                      }).toList(),
                                                                    ),
                                                                  ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      ctx,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'Tutup',
                                                                    ),
                                                              ),
                                                            ],
                                                          );
                                                        },
                                                  );
                                                },
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.grey.shade700
                                                      : Colors.grey.shade300,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: isDark
                                                    ? AppTheme.darkSurface
                                                    : Colors.white,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      selectedAccountIds.isEmpty
                                                          ? '--select--'
                                                          : '${selectedAccountIds.length} Selected',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: isDark
                                                            ? AppTheme
                                                                  .darkTextPrimary
                                                            : Colors.black,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    color: isDark
                                                        ? AppTheme
                                                              .darkTextPrimary
                                                        : Colors.grey.shade600,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  buildDropdownRow<ContactItem>(
                                    'Contact',
                                    contacts
                                            .where(
                                              (e) => e.id == selectedContactId,
                                            )
                                            .isEmpty
                                        ? null
                                        : contacts.firstWhere(
                                            (e) => e.id == selectedContactId,
                                          ),
                                    contacts.isEmpty
                                        ? <ContactItem>[]
                                        : contacts,
                                    (val) => setDialogState(
                                      () => selectedContactId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<LinkItem>(
                                    'Link',
                                    links
                                            .where(
                                              (e) => e.id == selectedLinkId,
                                            )
                                            .isEmpty
                                        ? null
                                        : links.firstWhere(
                                            (e) => e.id == selectedLinkId,
                                          ),
                                    links.isEmpty ? <LinkItem>[] : links,
                                    (val) => setDialogState(
                                      () => selectedLinkId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<GroupItem>(
                                    'Group',
                                    groups
                                            .where(
                                              (e) => e.id == selectedGroupId,
                                            )
                                            .isEmpty
                                        ? null
                                        : groups.firstWhere(
                                            (e) => e.id == selectedGroupId,
                                          ),
                                    groups.isEmpty ? <GroupItem>[] : groups,
                                    (val) => setDialogState(
                                      () => selectedGroupId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<CampaignItem>(
                                    'Campaign',
                                    campaigns
                                            .where(
                                              (e) => e.id == selectedCampaignId,
                                            )
                                            .isEmpty
                                        ? null
                                        : campaigns.firstWhere(
                                            (e) => e.id == selectedCampaignId,
                                          ),
                                    campaigns.isEmpty
                                        ? <CampaignItem>[]
                                        : campaigns,
                                    (val) => setDialogState(
                                      () => selectedCampaignId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<FunnelItem>(
                                    'Funnel',
                                    funnels
                                            .where(
                                              (e) => e.id == selectedFunnelId,
                                            )
                                            .isEmpty
                                        ? null
                                        : funnels.firstWhere(
                                            (e) => e.id == selectedFunnelId,
                                          ),
                                    funnels.isEmpty ? <FunnelItem>[] : funnels,
                                    (val) => setDialogState(
                                      () => selectedFunnelId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<DealItem>(
                                    'Deal',
                                    deals
                                            .where(
                                              (e) => e.id == selectedDealId,
                                            )
                                            .isEmpty
                                        ? null
                                        : deals.firstWhere(
                                            (e) => e.id == selectedDealId,
                                          ),
                                    deals.isEmpty ? <DealItem>[] : deals,
                                    (val) => setDialogState(
                                      () => selectedDealId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<TagItem>(
                                    'Tags',
                                    tags
                                            .where(
                                              (e) => e.id == selectedTagsId,
                                            )
                                            .isEmpty
                                        ? null
                                        : tags.firstWhere(
                                            (e) => e.id == selectedTagsId,
                                          ),
                                    tags.isEmpty ? <TagItem>[] : tags,
                                    (val) => setDialogState(
                                      () => selectedTagsId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  buildDropdownRow<HumanAgentItem>(
                                    'Human Agents',
                                    agents
                                            .where(
                                              (e) =>
                                                  e.id == selectedHumanAgentId,
                                            )
                                            .isEmpty
                                        ? null
                                        : agents.firstWhere(
                                            (e) => e.id == selectedHumanAgentId,
                                          ),
                                    agents.isEmpty
                                        ? <HumanAgentItem>[]
                                        : agents,
                                    (val) => setDialogState(
                                      () => selectedHumanAgentId = val?.id,
                                    ),
                                    itemAsString: (item) => item.name,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // FITUR: Bottom Sheet Opsi Chat (Pin, Archive, Assign)
  // FUNGSI: Menampilkan menu pop-up di bawah layar ketika sebuah chat ditekan lama, memungkinkan agen untuk menyematkan, mengarsipkan, atau mengubah status tiket obrolan (Assign/Resolve).
  void _showChatOptions(
    BuildContext context,
    ChatModel chat,
    ChatProvider chatProvider,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
              chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              color: Colors.blue,
            ),
            title: Text(
              chat.isPinned ? 'Lepas Pin Chat' : 'Sematkan Chat (Pin)',
            ),
            onTap: () {
              final isPinned = chat.isPinned;
              final sender = chat.sender;
              final chatId = chat.id;
              Navigator.pop(context);
              chatProvider.togglePin(chatId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isPinned
                        ? 'Pin $sender dilepas'
                        : '$sender pinned to top',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          // [ACTION: ARCHIVE_SINGLE] - Di gunakan agar user ketika memencet log press akan muncul opo up dari
          // bawah layar lalu memilih opsi archive (arsipkan chat)
          ListTile(
            leading: const Icon(Icons.archive_outlined, color: Colors.blue),
            title: const Text('Arsipkan Chat'),
            onTap: () {
              Navigator.pop(context); // close bottom sheet first
              showDialog(
                context: this.context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'Archive Conversation',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  content: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Text(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 15),
                      ),
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
                        // [ACTION: ARCHIVE_EXECUTE_SINGLE] - Ketika pengguna memencet konformasi maka sistem akan mengeksekusi kode chatProvider.toggleArchive
                        await chatProvider.toggleArchive(chat.id);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${chat.sender} archived successfully',
                              ),
                              backgroundColor: Colors.blue.shade700,
                            ),
                          );
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
          // ── Assign / Resolve Actions ──
          if (chat.status != 'Assigned')
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: Colors.orange),
              title: const Text('Assign ke Saya'),
              onTap: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Mengassign chat...')),
                );
                final success = await chatProvider.assignChat(chat.id);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? '${chat.sender} berhasil di-assign!'
                            : 'Failed to assign chat',
                      ),
                    ),
                  );
                }
              },
            ),
          if (chat.status != 'Resolved')
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
              ),
              title: const Text('Selesaikan (Resolve)'),
              onTap: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Menyelesaikan chat...')),
                );
                String resolveId = chat.id;
                if (resolveId.isEmpty ||
                    resolveId == '0' ||
                    resolveId == 'null' ||
                    int.tryParse(resolveId.replaceAll(RegExp(r'[^0-9]'), '')) ==
                        null) {
                  if (int.tryParse(
                            chat.contactId.replaceAll(RegExp(r'[^0-9]'), ''),
                          ) !=
                          null &&
                      chat.contactId != '0') {
                    resolveId = chat.contactId;
                  } else if (int.tryParse(
                            chat.link.replaceAll(RegExp(r'[^0-9]'), ''),
                          ) !=
                          null &&
                      chat.link != '0') {
                    resolveId = chat.link;
                  }
                }
                final success = await chatProvider.resolveChat(
                  resolveId,
                  accountId: chat.accountId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(this.context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? '${chat.sender} berhasil diselesaikan!'
                            : 'Failed to resolve chat',
                      ),
                    ),
                  );
                }
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Swipeable Chat Tile Widget ──
// FITUR: Wrapper Widget Chat Tile
// FUNGSI: Membungkus chat tile individu. (Logika swipe sudah dinonaktifkan atas permintaan bisnis, namun widget tetap dipertahankan untuk kompatibilitas struktur).
class _SwipeableChatTile extends StatefulWidget {
  final ChatModel chat;
  final ChatProvider chatProvider;
  final bool isDark;
  final Widget child;

  const _SwipeableChatTile({
    super.key,
    required this.chat,
    required this.chatProvider,
    required this.isDark,
    required this.child,
  });

  @override
  State<_SwipeableChatTile> createState() => _SwipeableChatTileState();
}

class _SwipeableChatTileState extends State<_SwipeableChatTile> {
  @override
  Widget build(BuildContext context) {
    // Swipe-to-action has been removed per request. Returning child directly.
    return widget.child;
  }
}

// FITUR: Animasi Shimmer Loading
// FUNGSI: Menampilkan 3 kerangka (skeleton) berbentuk chat tile dengan efek mengkilap (shimmer) saat memuat daftar obrolan berikutnya via pagination (infinite scroll).
class _ShimmerLoadingWidget extends StatefulWidget {
  final bool isDark;
  const _ShimmerLoadingWidget({required this.isDark});

  @override
  State<_ShimmerLoadingWidget> createState() => _ShimmerLoadingWidgetState();
}

class _ShimmerLoadingWidgetState extends State<_ShimmerLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, _) {
        return _buildSkeletonItem();
      },
    );
  }

  Widget _buildSkeletonItem() {
    final isDark = widget.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CircleAvatar placeholder (radius 20 → diameter 40)
          _shimmerCircle(40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Name + timestamp
                Row(
                  children: [
                    // Name placeholder (width 120, height 14)
                    _shimmerBox(120, 14),
                    const Spacer(),
                    // Timestamp placeholder (width 50, height 10)
                    _shimmerBox(50, 10),
                  ],
                ),
                const SizedBox(height: 8),
                // Row 2: Message preview placeholder (width 200, height 12)
                _shimmerBox(200, 12),
                const SizedBox(height: 8),
                // Row 3: Agent name + badge
                Row(
                  children: [
                    _shimmerBox(80, 10),
                    const Spacer(),
                    // Badge placeholder (width 20, height 20, circle)
                    _shimmerCircle(20),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerCircle(double size) {
    final isDark = widget.isDark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment(_shimmerAnimation.value - 1, 0),
          end: Alignment(_shimmerAnimation.value + 1, 0),
          colors: isDark
              ? [
                  Colors.grey.shade800,
                  Colors.grey.shade700,
                  Colors.grey.shade800,
                ]
              : [
                  Colors.grey.shade300,
                  Colors.grey.shade100,
                  Colors.grey.shade300,
                ],
        ),
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double borderRadius = 4}) {
    final isDark = widget.isDark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(_shimmerAnimation.value - 1, 0),
          end: Alignment(_shimmerAnimation.value + 1, 0),
          colors: isDark
              ? [
                  Colors.grey.shade800,
                  Colors.grey.shade700,
                  Colors.grey.shade800,
                ]
              : [
                  Colors.grey.shade300,
                  Colors.grey.shade100,
                  Colors.grey.shade300,
                ],
        ),
      ),
    );
  }
}
