import 'package:flutter/material.dart';
import '../../core/services/filter_api_service.dart';
import '../../core/services/tag_service.dart';

// =====================================================================
// FITUR: Dialog Pemilihan Label (Tag)
// FILE: lib/presentation/widgets/tag_selection_dialog.dart
// BARIS AWAL: 5 (setelah komentar ini)
// FUNGSI: Menampilkan pop-up untuk menambahkan, menghapus, dan mencari label (tag) pada suatu obrolan/kontak.
// =====================================================================
class TagSelectionDialog extends StatefulWidget {
  final String roomId;
  final List<String> initialSelectedTags;
  final Function(List<String>)? onSave;

  const TagSelectionDialog({
    super.key,
    required this.roomId,
    required this.initialSelectedTags,
    this.onSave,
  });

  @override
  State<TagSelectionDialog> createState() => _TagSelectionDialogState();
}

class _TagSelectionDialogState extends State<TagSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FilterApiService _filterApiService = FilterApiService();
  final TagService _tagService = TagService();

  List<String> _selectedTags = [];
  List<Map<String, dynamic>> _allTags = [];
  List<Map<String, dynamic>> _filteredTags = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedTags = List.from(widget.initialSelectedTags);
    _fetchTags();

    _searchController.addListener(() {
      final query = _searchController.text.toLowerCase();
      setState(() {
        _filteredTags = _allTags
            .where((tag) => _getTagName(tag).toLowerCase().contains(query))
            .toList();
      });
    });
  }

  String _getTagId(Map<String, dynamic> tag) {
    return tag['Id']?.toString() ?? tag['id']?.toString() ?? '';
  }

  String _getTagName(Map<String, dynamic> tag) {
    final raw =
        tag['Nm']?.toString() ??
        tag['Name']?.toString() ??
        tag['name']?.toString() ??
        'Unknown';
    return raw
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
  }

  Future<void> _fetchTags() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _filterApiService.getTags();
      if (!mounted) return;

      if (!response.isError && response.data != null) {
        setState(() {
          _allTags = response.data!;
          _filteredTags = _allTags;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Failed to load tags';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('TagSelectionDialog: Error fetching tags: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred while loading tags.';
        _isLoading = false;
      });
    }
  }

  // [ACTION: ADD_TAG_CONTACT] - Menyimpan tag yang dipilih ke server
  Future<void> _handleSave() async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Ensure we are passing Tag IDs to the API, even if initialSelectedTags contained names.
      final List<String> tagIdsToSave = _selectedTags
          .map((selectedVal) {
            final foundByName = _allTags.firstWhere(
              (tag) => _getTagName(tag) == selectedVal,
              orElse: () => <String, dynamic>{},
            );
            if (foundByName.isNotEmpty) {
              return _getTagId(foundByName);
            }
            return selectedVal;
          })
          .toSet()
          .toList();

      final response = await _tagService.updateContactTags(
        widget.roomId,
        tagIdsToSave,
      );

      if (!mounted) return;

      if (!response.isError) {
        if (widget.onSave != null) {
          // FIX: Kembalikan NAMA tag, bukan ID, agar UI di ContactInfoPage menampilkan teks yang benar (bukan angka/ID)
          final List<String> tagNamesToSave = tagIdsToSave.map((id) {
            final foundById = _allTags.firstWhere(
              (tag) => _getTagId(tag) == id,
              orElse: () => <String, dynamic>{},
            );
            if (foundById.isNotEmpty) {
              return _getTagName(foundById);
            }
            // Fallback, barangkali itu nama tag baru
            return id;
          }).toList();

          widget.onSave!(tagNamesToSave);
        }
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.error ?? 'Failed to update tags')),
        );
        setState(() {
          _isSaving = false;
        });
      }
    } catch (e) {
      debugPrint('TagSelectionDialog: Error saving tags: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred while saving tags.')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Message Tags',
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
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search or create new tag...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
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
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              enabled: !_isLoading && !_isSaving,
            ),
            const SizedBox(height: 16),
            if (_selectedTags.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.withOpacity(0.15)
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_selectedTags.length} tag${_selectedTags.length > 1 ? 's' : ''} selected',
                    style: TextStyle(
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _buildContent()),
            const SizedBox(height: 16),
            Row(
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
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isLoading || _isSaving) ? null : _handleSave,
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
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Save${_selectedTags.isNotEmpty ? ' (${_selectedTags.length})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _fetchTags, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_filteredTags.isEmpty) {
      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No existing tags match "$query".',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    if (!_selectedTags.contains(query)) {
                      _selectedTags.add(query);
                    }
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add "$query" as tag'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('No tags found.'));
    }

    return ListView.builder(
      itemCount: _filteredTags.length,
      itemBuilder: (context, index) {
        final tag = _filteredTags[index];
        final tagId = _getTagId(tag);
        final tagName = _getTagName(tag);

        final isSelected =
            _selectedTags.contains(tagId) || _selectedTags.contains(tagName);

        return InkWell(
          onTap: _isSaving
              ? null
              : () {
                  setState(() {
                    if (!isSelected) {
                      _selectedTags.add(tagId);
                    } else {
                      _selectedTags.remove(tagId);
                      _selectedTags.remove(tagName);
                    }
                  });
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey.shade600
                                : Colors.grey.shade400),
                      width: isSelected ? 7 : 2,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tagName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: $tagId',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
