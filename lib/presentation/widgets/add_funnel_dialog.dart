import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/filter_api_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/providers/chat_provider.dart';

// =====================================================================
// FITUR: Dialog Ubah Status Funnel
// FILE: lib/presentation/widgets/add_funnel_dialog.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Menampilkan pop-up untuk memilih dan mengubah status pipeline/funnel pelanggan.
// =====================================================================
class AddFunnelDialog extends StatefulWidget {
  final String roomId;
  final String? initialFunnel;
  final Function(String funnelName, String funnelId) onSave;

  const AddFunnelDialog({
    super.key,
    required this.roomId,
    this.initialFunnel,
    required this.onSave,
  });

  @override
  State<AddFunnelDialog> createState() => _AddFunnelDialogState();
}

class _AddFunnelDialogState extends State<AddFunnelDialog> {
  final FilterApiService _filterApiService = FilterApiService();
  final ChatService _chatService = ChatService();

  List<Map<String, String>> _funnelOptions = [];
  String? _selectedFunnelId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  final TextEditingController _newFunnelController = TextEditingController();
  bool _isCreateMode = false; // Toggle antara pilih yang ada vs buat baru

  @override
  void initState() {
    super.initState();
    _fetchFunnels();
  }

  @override
  void dispose() {
    _newFunnelController.dispose();
    super.dispose();
  }

  Future<void> _fetchFunnels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _filterApiService.getFunnels();
      if (!mounted) return;

      if (!response.isError && response.data != null) {
        final List<Map<String, String>> parsed = [];
        for (final item in response.data!) {
          final String name =
              item['Name']?.toString() ?? item['Nm']?.toString() ?? '';
          final String id = item['Id']?.toString() ?? '';
          if (name.isNotEmpty && id.isNotEmpty) {
            parsed.add({'name': name, 'id': id});
          }
        }

        // Match initialFunnel to pre-select the correct dropdown value
        String? matchedId;
        if (widget.initialFunnel != null && widget.initialFunnel!.isNotEmpty) {
          for (final option in parsed) {
            if (option['name'] == widget.initialFunnel ||
                option['id'] == widget.initialFunnel) {
              matchedId = option['id'];
              break;
            }
          }
        }

        setState(() {
          _funnelOptions = parsed;
          _selectedFunnelId = matchedId;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Failed to load funnel stages';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AddFunnelDialog: Error fetching funnels: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred while loading funnel stages.';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSave() async {
    if (_selectedFunnelId == null || _isSaving) return;

    final selectedOption = _funnelOptions.firstWhere(
      (f) => f['id'] == _selectedFunnelId,
      orElse: () => <String, String>{},
    );

    if (selectedOption.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final response = await _chatService.updateContactFunnel(
        widget.roomId,
        _selectedFunnelId!,
      );
      if (!mounted) return;

      if (!response.isError && response.data == true) {
        if (!context.mounted) return;
        Navigator.pop(context);
        widget.onSave(selectedOption['name']!, selectedOption['id']!);

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'Funnel successfully make it',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.error ?? 'Failed to update funnel stage'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() => _isSaving = false);
      }
    } catch (e) {
      debugPrint('AddFunnelDialog: Error saving funnel: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Network error. Please try again.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  Future<void> _handleCreateNewFunnel() async {
    final newName = _newFunnelController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Masukkan nama funnel')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Panggil API NoBox Server untuk membuat Master Funnel baru
      final createRes = await _chatService.createFunnel(newName);
      if (!mounted) return;

      if (createRes.isError || createRes.data == null) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(createRes.error ?? 'Gagal membuat funnel baru'),
          ),
        );
        return;
      }

      final newFunnelId = createRes.data!['id']!.toString();
      final newFunnelName = createRes.data!['name']!.toString();

      // 2. Daftarkan ke ChatProvider cache
      Provider.of<ChatProvider>(
        context,
        listen: false,
      ).registerNewFunnel(id: newFunnelId, name: newFunnelName);

      // 3. Terapkan funnel baru ini ke kontak chatroom
      await _chatService.updateContactFunnel(widget.roomId, newFunnelId);

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSave(newFunnelName, newFunnelId);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Funnel successfully make it',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error creating funnel: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Terjadi kesalahan saat membuat funnel')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Set Funnel Stage',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildContent(isDark),
            const SizedBox(height: 24),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle button: pilih dari daftar vs buat baru
        TextButton.icon(
          onPressed: () {
            setState(() {
              _isCreateMode = !_isCreateMode;
            });
          },
          icon: Icon(_isCreateMode ? Icons.list : Icons.add, size: 18),
          label: Text(
            _isCreateMode ? 'Pilih dari daftar funnel' : '+ Buat Funnel Baru',
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.blue),
        ),
        const SizedBox(height: 12),
        if (_isCreateMode)
          // Mode: Buat Funnel Baru
          TextField(
            controller: _newFunnelController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Nama Funnel Baru',
              hintText: 'Contoh: Prospecting, Follow Up, Deal Closed',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.add_task, color: Colors.blue),
            ),
            autofocus: true,
          )
        else ...[
          // Mode: Pilih Funnel yang Ada
          if (_isLoading)
            const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _fetchFunnels,
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (_funnelOptions.isEmpty)
            const SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  'No funnel stages available.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedFunnelId,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: 'Funnel Stage',
                labelStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              items: _funnelOptions.map((funnel) {
                return DropdownMenuItem(
                  value: funnel['id'],
                  child: Text(
                    funnel['name']!,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              }).toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _selectedFunnelId = value;
                      });
                    },
            ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isCreateMode
                ? (_isSaving ? null : _handleCreateNewFunnel)
                : (_selectedFunnelId == null || _isLoading || _isSaving)
                ? null
                : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isCreateMode ? 'Buat & Terapkan' : 'Save',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}
