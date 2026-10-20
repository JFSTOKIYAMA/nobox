import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/chat_provider.dart';

// =====================================================================
// FITUR: Daftar Pesan Berbintang
// FILE: lib/presentation/screens/chat/starred_messages_page.dart
// FUNGSI: Menampilkan kumpulan pesan yang ditandai bintang (bookmark)
//         dari berbagai percakapan untuk akses cepat.
// =====================================================================

/// Page that displays all starred/bookmarked messages
class StarredMessagesPage extends StatelessWidget {
  const StarredMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      // FITUR: Daftar List Berbintang (Membaca Provider)
      // FUNGSI: Mendengarkan perubahan data `starredMessages` dari ChatProvider dan me-rebuild UI ketika ada perubahan.
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          final starred = chatProvider.starredMessages;

          if (starred.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 80, color: Colors.amber.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No starred messages yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Long press a message and tap ⭐ to star it',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: starred.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final msg = starred[starred.length - 1 - index]; // newest first
              final content = msg['content'] ?? '';
              final sender = msg['sender'] ?? '';
              final time = msg['time'] ?? '';
              final msgId = msg['id'] ?? '';

              // FITUR: Hapus Bintang dengan Gestur Geser (Swipe to Unstar)
              // FUNGSI: Memungkinkan pengguna menghapus pesan dari daftar berbintang dengan menggesernya ke kiri.
              return Dismissible(
                key: Key(msgId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red.shade400,
                  child: const Icon(Icons.star_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  chatProvider.toggleStar(msgId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Star removed'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.shade100,
                      child: const Icon(Icons.star, color: Colors.amber, size: 20),
                    ),
                    title: Text(
                      sender.isNotEmpty ? sender : 'Me',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    trailing: Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
