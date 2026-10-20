import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/chat_provider.dart';

// =====================================================================
// FITUR: Dialog Tambah Agen
// FILE: lib/presentation/widgets/add_agent_dialog.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Menampilkan pop-up untuk menugaskan seorang agen/operator manusia ke dalam obrolan tertentu.
// =====================================================================
class AddAgentDialog extends StatefulWidget {
  final String chatId;
  final String contactId;
  final String chId;

  const AddAgentDialog({
    super.key,
    required this.chatId,
    required this.contactId,
    required this.chId,
  });

  @override
  State<AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<AddAgentDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allAgents = [];
  List<Map<String, dynamic>> _filteredAgents = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAgents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAgents() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final agents = await chatProvider.getAgents();

    if (mounted) {
      setState(() {
        _allAgents = agents ?? [];
        _filteredAgents = List.from(_allAgents);
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredAgents = List.from(_allAgents);
      } else {
        _filteredAgents = _allAgents.where((agent) {
          final name =
              (agent['Name'] ?? agent['FullName'] ?? agent['DisplayName'] ?? '')
                  .toString()
                  .toLowerCase();
          final email = (agent['Email'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();
          return name.contains(searchLower) || email.contains(searchLower);
        }).toList();
      }
    });
  }

  void _assignAgent(Map<String, dynamic> agent) async {
    final name =
        agent['Name'] ??
        agent['FullName'] ??
        agent['DisplayName'] ??
        'Unknown Agent';
    final id = agent['Id']?.toString() ?? agent['UserId']?.toString() ?? '';

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final success = await chatProvider.assignAgent(
      widget.chatId,
      id,
      name,
      chId: widget.chId,
      ctId: widget.contactId,
    );

    if (mounted) {
      // pop loading
      Navigator.pop(context);
      // pop dialog
      Navigator.pop(context);

      String errorMessage = chatProvider.error ?? "Gagal memproses ke server";
      if (errorMessage.contains('500') || errorMessage.contains('503') || errorMessage.contains('validateStatus')) {
        errorMessage = "Terjadi gangguan sementara pada server NoBox";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Agent "$name" assigned successfully'
                : 'Failed to assign agent: $errorMessage',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF3B82F6), // Main blue color
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Add Human Agent',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Search Box
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search agents...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                ),
              ),
            ),

            // Agent List
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: _filteredAgents.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Center(
                          child: Text(
                            'No agents found',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _filteredAgents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final agent = _filteredAgents[index];
                          final name =
                              (agent['Name'] ??
                                      agent['FullName'] ??
                                      agent['DisplayName'] ??
                                      'Agent')
                                  .toString();
                          final email = (agent['Email'] ?? '').toString();
                          final initial = name.isNotEmpty
                              ? name[0].toUpperCase()
                              : '?';

                          return InkWell(
                            onTap: () => _assignAgent(agent),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFE5F0FF),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Color(0xFF3B82F6),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (email.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.mail_outline,
                                                size: 14,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  email,
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.add_circle_outline,
                                    color: Color(0xFF3B82F6),
                                    size: 26,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFF9FAFB), // light grey
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Text(
                    '${_filteredAgents.length} agent${_filteredAgents.length == 1 ? '' : 's'} available',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
