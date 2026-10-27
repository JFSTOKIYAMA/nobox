import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/model/message.dart';
import '../../../core/providers/chat_provider.dart';
import 'edit_contact_page.dart';
import 'conversation_history_page.dart';
import '../../widgets/tag_selection_dialog.dart';
import '../../widgets/add_funnel_dialog.dart';
import '../../../core/services/filter_api_service.dart';
import '../../../core/model/filter_data_item.dart';
import '../../../core/model/api_response.dart';
import '../../widgets/searchable_dropdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/authenticated_avatar.dart';

// =====================================================================
// FITUR: Halaman Detail Kontak (Info)
// FILE: lib/presentation/screens/chat/contact_info_page.dart
// FUNGSI: Menampilkan dan mengelola informasi rinci dari kontak/chat room,
//         termasuk tag, funnel, note, status, dan data profil pengguna.
// =====================================================================

/// Contact Detail page matching the Nobox app design.
/// Sections: Contact, Conversation, Funnel, Message Tags, Notes,
/// Campaign, Deal, Form Template, Form Result, Human Agent.
class ContactInfoPage extends StatefulWidget {
  final ChatModel chat;
  const ContactInfoPage({super.key, required this.chat});

  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage> {
  late bool _needReply;
  late bool _muteAIAgent;
  late bool _isBlocked;
  late String _currentAccount;
  late String _currentFunnel;
  late List<String> _currentTags;
  late String _currentNotes;
  late String _currentCampaign;
  late String _currentPipeline;
  late String _currentStage;
  late String _currentDeal;
  late String _currentFormTemplate;
  late String _currentFormResult;
  String _agentEmail = '';
  String _currentAgentName = '';
  String _contactCountry = '';
  String _contactState = '';
  String _contactCity = '';
  String _currentContactName = '';
  String? _currentAvatarUrl;

  // Cached data from DetailRoom
  List<Map<String, dynamic>> _availableTagsFromServer = [];
  List<Map<String, dynamic>> _availableFunnelsFromServer = [];

  // Funnel inline dropdown state
  bool _isFunnelExpanded = false;
  final TextEditingController _funnelSearchController = TextEditingController();
  List<Map<String, String>> _cachedFunnelItems = [];
  bool _isLoadingFunnels = false;

  @override
  void initState() {
    super.initState();
    _needReply = widget.chat.needReply;
    _muteAIAgent = widget.chat.muteAiAgent;
    _isBlocked = Provider.of<ChatProvider>(
      context,
      listen: false,
    ).resolveIsBlocked(widget.chat.id, widget.chat.isBlocked);
    _currentAccount = 'Not Set';
    _currentFunnel = widget.chat.funnel;
    _currentTags = List.from(widget.chat.tags);
    _currentNotes = widget.chat.notes;
    // For now these are just local state, easily migratable to ChatModel if needed
    _currentCampaign = '';
    _currentPipeline = '';
    _currentStage = '';
    _currentDeal = '';
    _currentFormTemplate = '';
    _currentFormResult = '';
    _currentAgentName = widget.chat.agentName;
    _currentAvatarUrl = widget.chat.avatarUrl;
    _currentContactName =
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).getSavedContactName(widget.chat.id) ??
        widget.chat.sender;

    // Fetch latest data from server
    _loadDetailRoom();
  }

  @override
  void dispose() {
    _funnelSearchController.dispose();
    super.dispose();
  }

  // FITUR: Sinkronisasi Data Room & Kontak (API Call)
  // FUNGSI: Menarik data terbaru dari server mengenai obrolan ini, termasuk tag, funnel, notes, status bot, dsb.
  Future<void> _loadDetailRoom() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final data = await chatProvider.getDetailRoom(
      widget.chat.id,
      forceRefresh: true,
    );
    // DEBUG: Cetak semua field yang berkaitan dengan foto ke konsol Flutter
    if (data != null) {
      final roomData = data['Data'] ?? data;
      final room = roomData is Map ? (roomData['Room'] ?? {}) : {};
      final contact = roomData is Map
          ? (roomData['ContactReal'] ?? roomData['Contact'] ?? {})
          : {};
      debugPrint('=== AVATAR DEBUG (RoomId=${widget.chat.id}) ===');
      debugPrint('Room[CtImg]    = ${room['CtImg']}');
      debugPrint('Room[LinkImg]  = ${room['LinkImg']}');
      debugPrint('Room[Photo]    = ${room['Photo']}');
      debugPrint('Ct[Photo]      = ${contact['Photo']}');
      debugPrint('Ct[Img]        = ${contact['Img']}');
      debugPrint('Ct[AvatarUrl]  = ${contact['AvatarUrl']}');
      debugPrint('Ct[ProfilePic] = ${contact['ProfilePic']}');
      debugPrint('Ct[Picture]    = ${contact['Picture']}');
      debugPrint(
        'Room keys      = ${room is Map ? room.keys.toList() : "not a map"}',
      );
      debugPrint(
        'Contact keys   = ${contact is Map ? contact.keys.toList() : "not a map"}',
      );
      debugPrint('=== END AVATAR DEBUG ===');
    }
    debugPrint('ContactInfo: DetailRoom response keys: ${data?.keys.toList()}');
    if (data != null && mounted) {
      // Debug: print semua data untuk lihat field yang tersedia
      final roomData = data['Data'] ?? data;
      debugPrint(
        'ContactInfo: Data keys: ${roomData is Map ? roomData.keys.toList() : "not a map"}',
      );
      if (roomData is Map) {
        if (roomData['Room'] is Map) {
          debugPrint(
            'ContactInfo: Room keys: ${(roomData['Room'] as Map).keys.toList()}',
          );
        }
        if (roomData['ContactReal'] is Map) {
          debugPrint(
            'ContactInfo: ContactReal keys: ${(roomData['ContactReal'] as Map).keys.toList()}',
          );
          debugPrint(
            'ContactInfo: ContactReal data: ${roomData['ContactReal']}',
          );
        } else {
          debugPrint('ContactInfo: No ContactReal key found in Data');
        }
      }
      // PRE-FETCH MASTER TAGS SECARA UNCONDITIONAL
      // Agar _convertNamesToIds selalu memiliki akses ke seluruh daftar tag, bukan hanya tag yang ter-assign di chat ini.
      List<Map<String, dynamic>>? masterTagsFallback;
      try {
        final tagRes = await FilterApiService().getTags();
        if (!tagRes.isError && tagRes.data != null) {
          masterTagsFallback = tagRes.data!;
        }
      } catch (e) {
        debugPrint('ContactInfo: Gagal pre-fetch master tags: $e');
      }

      if (!mounted) return;

      // Pull variables outside so they are accessible across multiple setState blocks
      final room = roomData is Map ? (roomData['Room'] ?? {}) : {};

      setState(() {
        // Update nama kontak reaktif dari saved name lokal / server (CtRealNm)
        final savedLocalName = chatProvider.getSavedContactName(widget.chat.id);
        final serverName =
            room['CtRealNm']?.toString() ?? room['CtTmp']?.toString();
        if (savedLocalName != null && savedLocalName.isNotEmpty) {
          _currentContactName = savedLocalName;
        } else if (serverName != null && serverName.isNotEmpty) {
          _currentContactName = serverName;
        }

        // Funnel: dari Room → Fn atau FnId
        final fnName = room['Fn']?.toString() ?? room['FnNm']?.toString() ?? '';
        if (fnName.isNotEmpty) _currentFunnel = fnName;

        // Notes: dari Data → Notes (bisa list)
        final notesData = roomData is Map ? roomData['Notes'] : null;
        if (notesData is List && notesData.isNotEmpty) {
          // Ambil note terakhir

          final lastNote = notesData.last;
          _currentNotes =
              lastNote['Cnt']?.toString() ??
              lastNote['Content']?.toString() ??
              _currentNotes;
        } else if (notesData is String && notesData.isNotEmpty) {
          _currentNotes = notesData;
        }

        // Campaign: dari Data → Campaign atau Room
        final campaignData = roomData is Map ? roomData['Campaign'] : null;
        if (campaignData is Map) {
          _currentCampaign =
              campaignData['Name']?.toString() ??
              campaignData['Nm']?.toString() ??
              _currentCampaign;
        } else {
          final roomCampaign = room['Campaign']?.toString() ?? '';
          if (roomCampaign.isNotEmpty) _currentCampaign = roomCampaign;
        }

        // Deal: dari Data -> Deal atau Room
        final contactNode = (roomData is Map)
            ? (roomData['ContactReal'] ?? roomData['Contact'])
            : null;
        final dealData = roomData is Map
            ? (roomData['Deal'] ??
                  (contactNode is Map ? contactNode['Deal'] : null))
            : null;

        if (dealData is Map) {
          _currentDeal =
              dealData['Name']?.toString() ??
              dealData['Nm']?.toString() ??
              _currentDeal;
          final pipelineData =
              dealData['Pipeline']?.toString() ??
              dealData['PipelineName']?.toString() ??
              '';
          if (pipelineData.isNotEmpty) _currentPipeline = pipelineData;
          final stageData =
              dealData['Stage']?.toString() ??
              dealData['StageName']?.toString() ??
              '';
          if (stageData.isNotEmpty) _currentStage = stageData;
        } else {
          final roomDeal =
              room['Deal']?.toString() ??
              (contactNode is Map ? contactNode['Deal']?.toString() : null) ??
              '';
          if (roomDeal.isNotEmpty) _currentDeal = roomDeal;
          final roomPipeline =
              room['Pipeline']?.toString() ??
              (contactNode is Map
                  ? contactNode['Pipeline']?.toString()
                  : null) ??
              '';
          if (roomPipeline.isNotEmpty) _currentPipeline = roomPipeline;
          final roomStage =
              room['Stage']?.toString() ??
              (contactNode is Map ? contactNode['Stage']?.toString() : null) ??
              '';
          if (roomStage.isNotEmpty) _currentStage = roomStage;
        }

        // Form Template
        _currentFormTemplate =
            room['FormTemplateNm']?.toString() ??
            room['FormTemplateName']?.toString() ??
            data['FormTemplateNm']?.toString() ??
            data['FormTemplateName']?.toString() ??
            _currentFormTemplate;

        _currentFormResult =
            room['FormResultNm']?.toString() ??
            room['FormResultName']?.toString() ??
            data['FormResultNm']?.toString() ??
            data['FormResultName']?.toString() ??
            _currentFormResult;
      });

      // Jika nama template atau result kosong, coba mapping paksa dari ID-nya!
      final contactData = data['Contact'] ?? {};
      final formTemplateIdStr =
          room['FormTemplateId']?.toString() ??
          room['FormId']?.toString() ??
          data['FormTemplateId']?.toString() ??
          data['FormId']?.toString() ??
          contactData['FormTemplateId']?.toString() ??
          contactData['FormId']?.toString() ??
          '';
      final formResultIdStr =
          room['FormResultId']?.toString() ??
          data['FormResultId']?.toString() ??
          contactData['FormResultId']?.toString() ??
          '';

      if (formTemplateIdStr.isNotEmpty && _currentFormTemplate.isEmpty) {
        final templatesData = await chatProvider.getFormTemplates();
        if (templatesData != null) {
          for (final t in templatesData) {
            if (t['Id']?.toString() == formTemplateIdStr) {
              if (mounted)
                setState(() {
                  _currentFormTemplate =
                      t['Name']?.toString() ??
                      t['Nm']?.toString() ??
                      t['Title']?.toString() ??
                      '';
                });
              break;
            }
          }
        }
      }

      if (formResultIdStr.isNotEmpty && _currentFormResult.isEmpty) {
        final resultsData = await chatProvider.getFormResults();
        if (resultsData != null) {
          for (final r in resultsData) {
            if (r['Id']?.toString() == formResultIdStr) {
              if (mounted)
                setState(() {
                  _currentFormResult =
                      r['SenderNm']?.toString() ??
                      r['Phone']?.toString() ??
                      'Hasil Form #';
                });
              break;
            }
          }
        }
      }

      final contactNode2 = (roomData is Map)
          ? (roomData['ContactReal'] ?? roomData['Contact'])
          : null;
      final dealIdStr =
          room['DealId']?.toString() ??
          (contactNode2 is Map ? contactNode2['DealId']?.toString() : null) ??
          '';

      if (dealIdStr.isNotEmpty && _currentDeal.isEmpty) {
        try {
          final dealsResp = await chatProvider.getDealsResponse();
          if (!dealsResp.isError && dealsResp.data != null) {
            for (final d in dealsResp.data!) {
              if (d['Id']?.toString() == dealIdStr) {
                if (mounted)
                  setState(() {
                    _currentDeal =
                        d['Name']?.toString() ??
                        d['Nm']?.toString() ??
                        d['Title']?.toString() ??
                        dealIdStr;
                  });
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('Failed to fetch deal name: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        // Tags: dari Data → Tags (list of tag objects)
        final serverTags = roomData is Map ? roomData['Tags'] : null;
        debugPrint(
          'ContactInfo: Tags type=${serverTags.runtimeType}, data=$serverTags',
        );

        // SELALU utamakan masterTagsFallback karena berisi SEMUA tag,
        // sehingga fungsi _convertNamesToIds dapat memetakan nama ke ID dengan benar!
        if (masterTagsFallback != null && masterTagsFallback.isNotEmpty) {
          _availableTagsFromServer = masterTagsFallback;
          debugPrint(
            'ContactInfo: Saved ${_availableTagsFromServer.length} tags from masterTagsFallback',
          );
        } else if (serverTags is List && serverTags.isNotEmpty) {
          _availableTagsFromServer = serverTags
              .whereType<Map<String, dynamic>>()
              .toList();
          debugPrint(
            'ContactInfo: Saved ${_availableTagsFromServer.length} tags from serverTags',
          );
        }

        // Set current tags (yang sudah di-assign ke chat ini) dari Room atau ContactReal
        final ctReal = roomData is Map ? (roomData['ContactReal'] ?? {}) : {};
        dynamic rawTagsIdsData =
            room['TagsIds'] ?? room['tags_ids'] ?? room['tagsIds'];
        if (rawTagsIdsData == null ||
            rawTagsIdsData == '' ||
            rawTagsIdsData == 'null' ||
            rawTagsIdsData == '0') {
          if (ctReal is Map) {
            rawTagsIdsData =
                ctReal['TagsIds'] ?? ctReal['tags_ids'] ?? ctReal['tagsIds'];
          }
        }
        String roomTagsIds = '';
        if (rawTagsIdsData is List) {
          roomTagsIds = rawTagsIdsData
              .map(
                (e) =>
                    e.toString().replaceAll('[', '').replaceAll(']', '').trim(),
              )
              .join(',');
        } else if (rawTagsIdsData != null) {
          roomTagsIds = rawTagsIdsData
              .toString()
              .replaceAll('[', '')
              .replaceAll(']', '')
              .trim();
        }

        if (roomTagsIds.isNotEmpty &&
            roomTagsIds != 'null' &&
            roomTagsIds != '0') {
          final assignedIds = roomTagsIds
              .split(',')
              .map((t) => t.trim())
              .toSet();
          _currentTags = _availableTagsFromServer
              .where(
                (t) =>
                    assignedIds.contains(t['Id']?.toString()) ||
                    assignedIds.contains(t['id']?.toString()),
              )
              .map((t) => t['Name']?.toString() ?? t['Nm']?.toString() ?? '')
              .where((t) => t.isNotEmpty)
              .toList();
        } else {
          _currentTags = [];
        }

        // Update toggles dari Room
        if (room['IsMuteBot'] != null)
          _muteAIAgent =
              room['IsMuteBot'].toString() == 'true' ||
              room['IsMuteBot'].toString() == '1';
        if (room['IsNeedReply'] != null)
          _needReply =
              room['IsNeedReply'].toString() == 'true' ||
              room['IsNeedReply'].toString() == '1';

        final blockVal = room['CtIsBlock'] ?? room['IsBlock'];
        final rawBlock = blockVal != null
            ? (blockVal.toString() == 'true' || blockVal.toString() == '1')
            : widget.chat.isBlocked;
        _isBlocked = chatProvider.resolveIsBlocked(widget.chat.id, rawBlock);

        // Extract Agent info from RoomAgents if available
        try {
          if (roomData['RoomAgents'] != null &&
              roomData['RoomAgents'] is List &&
              (roomData['RoomAgents'] as List).isNotEmpty) {
            final firstAgent = (roomData['RoomAgents'] as List)[0];
            _agentEmail = firstAgent['UserEmail']?.toString() ?? '';
            final serverAgentName = firstAgent['DisplayName']?.toString() ?? '';
            if (serverAgentName.isNotEmpty) {
              _currentAgentName = serverAgentName;
            }
          }
          // Extract Account name from Account data
          if (roomData['Account'] != null && roomData['Account'] is Map) {
            final accountName = roomData['Account']['Name']?.toString() ?? '';
            if (accountName.isNotEmpty) {
              _currentAccount = accountName;
            }
          }
          // Extract Contact location data (Country, State, City)
          final contact =
              roomData['ContactReal'] ??
              roomData['Contact'] ??
              roomData['Room'] ??
              roomData;
          debugPrint(
            'ContactInfo: Trying contact source, type=${contact.runtimeType}',
          );
          if (contact is Map) {
            final country =
                contact['Country']?.toString() ??
                contact['Cntry']?.toString() ??
                '';
            final state =
                contact['State']?.toString() ??
                contact['Stt']?.toString() ??
                contact['Province']?.toString() ??
                '';
            final city =
                contact['City']?.toString() ?? contact['Cty']?.toString() ?? '';
            debugPrint(
              'ContactInfo: Parsed => Country="$country", State="$state", City="$city"',
            );
            if (country.isNotEmpty) _contactCountry = country;
            if (state.isNotEmpty) _contactState = state;
            if (city.isNotEmpty) _contactCity = city;

            final photo =
                contact['Photo']?.toString() ??
                room['CtImg']?.toString() ??
                room['LinkImg']?.toString() ??
                '';
            if (photo.isNotEmpty) {
              String resolvedPhoto = photo;
              if (!photo.startsWith('http')) {
                // Ganti backslash (Windows path) menjadi forward slash agar URL valid
                resolvedPhoto =
                    'https://id.nobox.ai/upload/${photo.replaceAll('\\', '/')}';
              }
              _currentAvatarUrl = resolvedPhoto;
              // SIMPAN ke cache ChatProvider agar bisa dipakai di halaman daftar chat
              chatProvider.saveCachedAvatarUrl(widget.chat.id, resolvedPhoto);
            }
          }

          // Override: gunakan data lokasi lokal (optimistic save) jika ada
          final localLocation = chatProvider.getSavedContactLocation(
            widget.chat.id,
          );
          if (localLocation != null) {
            if (localLocation['Country'] != null &&
                localLocation['Country']!.isNotEmpty) {
              _contactCountry = localLocation['Country']!;
            }
            if (localLocation['State'] != null &&
                localLocation['State']!.isNotEmpty) {
              _contactState = localLocation['State']!;
            }
            if (localLocation['City'] != null &&
                localLocation['City']!.isNotEmpty) {
              _contactCity = localLocation['City']!;
            }
          }
        } catch (e) {
          debugPrint('ContactInfo: Error extracting data: $e');
        }
      });

      // --- WORKAROUND LOCAL CACHE OVERRIDE ---
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedPipeline = prefs.getString(
          'deal_pipeline_${widget.chat.id}',
        );
        final cachedStage = prefs.getString('deal_stage_${widget.chat.id}');
        final cachedDeal = prefs.getString('deal_deal_${widget.chat.id}');

        if (cachedDeal != null && cachedDeal.isNotEmpty) {
          if (mounted) {
            setState(() {
              _currentPipeline = cachedPipeline ?? _currentPipeline;
              _currentStage = cachedStage ?? _currentStage;
              _currentDeal = cachedDeal;
            });
            debugPrint(
              'ContactInfo: Overrode Deal with local cache: $_currentDeal',
            );
          }
        }
      } catch (e) {
        debugPrint('Failed to load local deal cache: $e');
      }
    }
  }

  void _showAccountPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1F2C34)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final accounts = [
          'WhatsApp Business',
          'Instagram',
          'Facebook Messenger',
          'Telegram',
        ];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              ...accounts.map(
                (account) => ListTile(
                  title: Text(
                    account,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  trailing: _currentAccount == account
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    setState(() => _currentAccount = account);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Account changed to $account')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _toggleSetting(
    String name,
    bool currentValue,
    ValueChanged<bool> onSaved,
  ) async {
    // Show a quick loading snacbkar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updating $name...'),
        duration: const Duration(milliseconds: 500),
      ),
    );

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final newValue = !currentValue;

    bool isSuccess = false;
    if (name == 'Need Reply') {
      isSuccess = await chatProvider.toggleNeedReply(widget.chat.id, newValue);
    } else if (name == 'Mute AI Agent') {
      isSuccess = await chatProvider.toggleAiAgent(widget.chat.id, newValue);
    }

    if (isSuccess) {
      onSaved(newValue);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name is now ${newValue ? 'ON' : 'OFF'}'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update $name: ${chatProvider.error}'),
          ),
        );
      }
    }
  }

  void _showAddFunnelDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AddFunnelDialog(
          roomId: widget.chat.id,
          initialFunnel: _currentFunnel,
          onSave: (String funnelName, String funnelId) {
            if (mounted) {
              setState(() {
                _currentFunnel = funnelName;
              });
            }
          },
        );
      },
    );
  }

  Future<void> _toggleFunnelDropdown() async {
    if (_isFunnelExpanded) {
      setState(() {
        _isFunnelExpanded = false;
        _funnelSearchController.clear();
      });
      return;
    }

    setState(() {
      _isFunnelExpanded = true;
      if (_cachedFunnelItems.isEmpty) {
        _isLoadingFunnels = true;
      }
    });

    if (_cachedFunnelItems.isEmpty) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final funnelData = await chatProvider.getFunnels();
      if (!mounted) return;
      if (funnelData != null) {
        _cachedFunnelItems = funnelData
            .map((f) {
              final name = f['Name']?.toString() ?? f['Nm']?.toString() ?? '';
              final id = f['Id']?.toString() ?? '';
              return {'name': name, 'id': id};
            })
            .where((f) => f['name']!.isNotEmpty)
            .toList();
      }
      if (mounted) {
        setState(() {
          _isLoadingFunnels = false;
        });
      }
    }
  }

  void _showFunnelOverlay() {
    _toggleFunnelDropdown();
  }

  void _showFunnelList() {
    _toggleFunnelDropdown();
  }

  void _showRemoveFunnelConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.filter_alt_off,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Remove Funnel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Are you sure you want to remove the funnel from this contact?',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    if (mounted && _isFunnelExpanded) {
                      setState(() => _isFunnelExpanded = false);
                    }

                    // Call API to remove funnel
                    final chatProvider = Provider.of<ChatProvider>(
                      context,
                      listen: false,
                    );
                    final success = await chatProvider.updateContactFunnel(
                      widget.chat.id,
                      "",
                    );
                    if (success && mounted) {
                      setState(() => _currentFunnel = '');
                    }
                  },
                  child: const Text(
                    'Remove',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _convertNamesToIds(List<String> tagNames) {
    return tagNames.map((name) {
      final found = _availableTagsFromServer.firstWhere(
        (t) => (t['Name']?.toString() ?? t['Nm']?.toString() ?? '') == name,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) {
        return found['Id']?.toString() ?? name;
      }
      return name;
    }).toList();
  }

  void _showRemoveTagConfirmation(String tag) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.label_off,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Remove Tag',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Are you sure you want to remove the tag "$tag"?',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);

                    final newTagsList = List<String>.from(_currentTags)
                      ..remove(tag);
                    final tagIdsList = _convertNamesToIds(newTagsList);
                    final chatProvider = Provider.of<ChatProvider>(
                      context,
                      listen: false,
                    );
                    final success = await chatProvider.updateContactTags(
                      widget.chat.id,
                      tagIdsList,
                      tagNames: newTagsList,
                    );
                    if (success && mounted) {
                      setState(() => _currentTags.remove(tag));
                    }
                  },
                  child: const Text(
                    'Remove',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTagDialog() {
    final TextEditingController tagController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add Tag',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              InkWell(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.blue, size: 24),
              ),
            ],
          ),
          content: TextField(
            controller: tagController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Enter tag name...',
              hintStyle: TextStyle(
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            autofocus: true,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final newTag = tagController.text.trim();
                      if (newTag.isNotEmpty && !_currentTags.contains(newTag)) {
                        final newTagsList = List<String>.from(_currentTags)
                          ..add(newTag);
                        final tagIdsList = _convertNamesToIds(newTagsList);
                        final chatProvider = Provider.of<ChatProvider>(
                          context,
                          listen: false,
                        );
                        final success = await chatProvider.updateContactTags(
                          widget.chat.id,
                          tagIdsList,
                          tagNames: newTagsList,
                        );
                        if (success) {
                          setState(() => _currentTags = newTagsList);
                        } else {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to add tag')),
                            );
                        }
                      }
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showMessageTagsDialog() async {
    await showDialog(
      context: context,
      builder: (context) => TagSelectionDialog(
        roomId: widget.chat.id,
        initialSelectedTags: _currentTags,
        onSave: (List<String> updatedTags) {
          if (mounted) {
            setState(() {
              _currentTags = updatedTags;
            });
            final tagIdsList = _convertNamesToIds(updatedTags);
            Provider.of<ChatProvider>(
              context,
              listen: false,
            ).updateLocalContactTags(widget.chat.id, tagIdsList, updatedTags);
          }
        },
      ),
    );
  }

  void _showEditNoteDialog() {
    final TextEditingController noteController = TextEditingController(
      text: _currentNotes,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add Note',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              InkWell(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.blue, size: 24),
              ),
            ],
          ),
          content: TextField(
            controller: noteController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Enter your note...',
              hintStyle: TextStyle(
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            autofocus: true,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final newNotes = noteController.text.trim();
                      final chatProvider = Provider.of<ChatProvider>(
                        context,
                        listen: false,
                      );
                      final success = await chatProvider.updateContactNotes(
                        widget.chat.id,
                        newNotes,
                      );
                      if (success) {
                        setState(() => _currentNotes = newNotes);
                      } else {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to save notes')),
                          );
                      }
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showCampaignDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // API data
    List<CampaignItem> campaigns = [];
    bool isLoadingData = true;
    String? loadError;

    String selectedCampaignName = _currentCampaign;
    int? selectedCampaignId;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Fetch campaigns
            if (isLoadingData && campaigns.isEmpty && loadError == null) {
              Future.microtask(() async {
                try {
                  final resp = await chatProvider.getCampaignsResponse();
                  setDialogState(() {
                    isLoadingData = false;
                    if (!resp.isError && resp.data != null) {
                      campaigns = resp.data!
                          .map((e) => CampaignItem.fromJson(e))
                          .toList();
                      // find matching ID if we already have a name
                      if (selectedCampaignName.isNotEmpty) {
                        try {
                          final match = campaigns.firstWhere(
                            (c) =>
                                c.name.toLowerCase() ==
                                selectedCampaignName.toLowerCase(),
                          );
                          selectedCampaignId = int.tryParse(match.id);
                        } catch (_) {}
                      }
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

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.campaign,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Select Campaign',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campaign',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isLoadingData)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 50),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  else if (loadError != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error: $loadError',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (campaigns.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 50),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No campaigns available',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          hint: Text(
                            '--select campaign--',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade600,
                          ),
                          value: selectedCampaignId,
                          dropdownColor: isDark
                              ? const Color(0xFF1F2C34)
                              : Colors.white,
                          items: campaigns.map((c) {
                            return DropdownMenuItem<int>(
                              value: int.tryParse(c.id),
                              child: Text(
                                c.name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setDialogState(() {
                              selectedCampaignId = newValue;
                              try {
                                final c = campaigns.firstWhere(
                                  (c) => c.id == newValue.toString(),
                                );
                                selectedCampaignName = c.name;
                              } catch (_) {}
                            });
                          },
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (selectedCampaignId != null && !isLoadingData)
                            ? Colors.blue
                            : Colors.grey.shade300,
                        foregroundColor:
                            (selectedCampaignId != null && !isLoadingData)
                            ? Colors.white
                            : Colors.grey.shade500,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: (selectedCampaignId == null || isLoadingData)
                          ? null
                          : () async {
                              final success = await chatProvider.updateCampaign(
                                widget.chat.id,
                                selectedCampaignId,
                              );
                              if (success) {
                                if (mounted) {
                                  setState(() {
                                    _currentCampaign = selectedCampaignName;
                                  });
                                }
                              } else {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Failed to update campaign',
                                      ),
                                    ),
                                  );
                              }
                              if (mounted) Navigator.pop(context);
                            },
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDealDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    bool isLoading = true;
    String? loadError;

    List<Map<String, dynamic>> pipelines = [];
    List<Map<String, dynamic>> stages = [];
    List<Map<String, dynamic>> deals = [];

    String? selectedPipelineId;
    String? selectedStageId;
    String? selectedDealId;

    // We will show dialog first, then load pipelines, stages, and deals.
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Initial load of all data
            if (isLoading && pipelines.isEmpty && loadError == null) {
              Future.microtask(() async {
                try {
                  final pipeResp = await chatProvider.getPipelinesResponse();
                  final stageResp = await chatProvider.getStagesResponse();
                  final dealResp = await chatProvider.getDealsResponse();

                  setDialogState(() {
                    isLoading = false;
                    if (!pipeResp.isError && pipeResp.data != null) {
                      pipelines = pipeResp.data!;
                    } else {
                      loadError = 'Failed to load pipelines: ${pipeResp.error}';
                    }
                    if (!stageResp.isError && stageResp.data != null) {
                      stages = stageResp.data!;
                    }
                    if (!dealResp.isError && dealResp.data != null) {
                      deals = dealResp.data!;
                    }
                  });
                } catch (e) {
                  setDialogState(() {
                    isLoading = false;
                    loadError = e.toString();
                  });
                }
              });
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0B141A) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.handshake,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Select Deal',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLoading && pipelines.isEmpty)
                      const Center(child: CircularProgressIndicator())
                    else if (loadError != null)
                      Text(
                        loadError!,
                        style: const TextStyle(color: Colors.red),
                      )
                    else ...[
                      Text(
                        'Pipeline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SearchableDropdown<String>(
                        hint: '--select pipeline--',
                        value: selectedPipelineId,
                        options: pipelines
                            .map((p) => p['Id']?.toString() ?? '')
                            .toList(),
                        itemAsString: (id) {
                          final p = pipelines.firstWhere(
                            (p) => p['Id']?.toString() == id,
                            orElse: () => {},
                          );
                          return p['Nm']?.toString() ??
                              p['Name']?.toString() ??
                              p['Title']?.toString() ??
                              '';
                        },
                        onChanged: (newValue) {
                          setDialogState(() {
                            selectedPipelineId = newValue;
                            selectedStageId = null;
                            selectedDealId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Stage',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SearchableDropdown<String>(
                        hint: '--select stage--',
                        value: selectedStageId,
                        options: () {
                          if (selectedPipelineId == null) {
                            return ['empty_not_found'];
                          }
                          final filteredStages = stages
                              .where(
                                (s) =>
                                    selectedPipelineId == null ||
                                    s['DealpipelinesId']?.toString() ==
                                        selectedPipelineId ||
                                    s['DealPipelinesId']?.toString() ==
                                        selectedPipelineId ||
                                    s['PipelineId']?.toString() ==
                                        selectedPipelineId ||
                                    s['project_id']?.toString() ==
                                        selectedPipelineId ||
                                    s['ProjectId']?.toString() ==
                                        selectedPipelineId,
                              )
                              .map((s) => s['Id']?.toString() ?? '')
                              .toList();

                          if (filteredStages.isEmpty) {
                            return ['empty_not_found'];
                          }
                          return filteredStages;
                        }(),
                        itemAsString: (id) {
                          if (id == 'empty_not_found') return 'Not found';
                          final s = stages.firstWhere(
                            (s) => s['Id']?.toString() == id,
                            orElse: () => {},
                          );
                          return s['Name']?.toString() ??
                              s['Nm']?.toString() ??
                              s['Title']?.toString() ??
                              '';
                        },
                        onChanged: (newValue) {
                          if (newValue == 'empty_not_found') return;
                          setDialogState(() {
                            selectedStageId = newValue;
                            selectedDealId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Deal',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SearchableDropdown<String>(
                        hint: '--select deal--',
                        value: selectedDealId,
                        options: () {
                          if (selectedPipelineId == null) {
                            return ['empty_not_found'];
                          }

                          final filteredDeals = deals
                              .where((d) {
                                bool matchStage =
                                    selectedStageId == null ||
                                    d['piplinetypes']?.toString() ==
                                        selectedStageId ||
                                    d['DealpipelinetypesId']?.toString() ==
                                        selectedStageId ||
                                    d['DealPipelineTypesId']?.toString() ==
                                        selectedStageId ||
                                    d['StageId']?.toString() == selectedStageId;

                                bool matchPipeline =
                                    selectedPipelineId == null ||
                                    d['DealpipelinesId']?.toString() ==
                                        selectedPipelineId ||
                                    d['DealPipelinesId']?.toString() ==
                                        selectedPipelineId ||
                                    d['PipelineId']?.toString() ==
                                        selectedPipelineId ||
                                    d['project_id']?.toString() ==
                                        selectedPipelineId ||
                                    d['ProjectId']?.toString() ==
                                        selectedPipelineId;

                                if (selectedStageId != null) return matchStage;
                                if (selectedPipelineId != null)
                                  return matchPipeline;
                                return true;
                              })
                              .map((d) => d['Id']?.toString() ?? '')
                              .toList();

                          if (filteredDeals.isEmpty &&
                              (selectedStageId != null ||
                                  selectedPipelineId != null)) {
                            return ['empty_not_found'];
                          }

                          return filteredDeals;
                        }(),
                        itemAsString: (id) {
                          if (id == 'empty_not_found') return 'Not found';
                          final item = deals.firstWhere(
                            (d) => d['Id']?.toString() == id,
                            orElse: () => {},
                          );
                          return item['Name']?.toString() ??
                              item['Nm']?.toString() ??
                              item['Title']?.toString() ??
                              '';
                        },
                        onChanged: (newValue) {
                          if (newValue == 'empty_not_found') return;
                          setDialogState(() {
                            selectedDealId = newValue;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (!isLoading)
                            ? Colors.blue
                            : Colors.grey.shade300,
                        foregroundColor: (!isLoading)
                            ? Colors.white
                            : Colors.grey.shade500,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              setDialogState(() => isLoading = true);
                              final success = await chatProvider
                                  .updateContactDeal(
                                    widget.chat.id,
                                    selectedPipelineId ?? '',
                                    selectedStageId ?? '',
                                    selectedDealId ?? '',
                                  );
                              if (success) {
                                setState(() {
                                  // Find the names
                                  if (selectedPipelineId != null) {
                                    final p = pipelines.firstWhere(
                                      (e) =>
                                          e['Id']?.toString() ==
                                          selectedPipelineId,
                                      orElse: () => {},
                                    );
                                    _currentPipeline =
                                        p['Nm']?.toString() ??
                                        p['Name']?.toString() ??
                                        p['Title']?.toString() ??
                                        selectedPipelineId!;
                                  }
                                  if (selectedStageId != null) {
                                    final s = stages.firstWhere(
                                      (e) =>
                                          e['Id']?.toString() ==
                                          selectedStageId,
                                      orElse: () => {},
                                    );
                                    _currentStage =
                                        s['Name']?.toString() ??
                                        s['Nm']?.toString() ??
                                        s['Title']?.toString() ??
                                        selectedStageId!;
                                  } else {
                                    _currentStage = '';
                                  }
                                  if (selectedDealId != null) {
                                    final d = deals.firstWhere(
                                      (e) =>
                                          e['Id']?.toString() == selectedDealId,
                                      orElse: () => {},
                                    );
                                    _currentDeal =
                                        d['Name']?.toString() ??
                                        d['Nm']?.toString() ??
                                        d['Title']?.toString() ??
                                        selectedDealId!;
                                  } else {
                                    _currentDeal = '';
                                  }
                                });

                                // --- WORKAROUND LOCAL CACHE ---
                                SharedPreferences.getInstance()
                                    .then((prefs) {
                                      prefs.setString(
                                        'deal_pipeline_${widget.chat.id}',
                                        _currentPipeline,
                                      );
                                      prefs.setString(
                                        'deal_stage_${widget.chat.id}',
                                        _currentStage,
                                      );
                                      prefs.setString(
                                        'deal_deal_${widget.chat.id}',
                                        _currentDeal,
                                      );
                                    })
                                    .catchError((_) {});
                                // ------------------------------

                                // Dihapus _loadDetailRoom() di sini agar UI Deal tidak ter-reset
                                // (karena seringkali server terlambat sinkronisasi / cache)
                              } else {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to save deal'),
                                    ),
                                  );
                              }
                              if (mounted) {
                                setDialogState(() => isLoading = false);
                                Navigator.pop(context);
                              }
                            },
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFormTemplateDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Fetch form templates and form results from server
    final templatesData = await chatProvider.getFormTemplates();
    final resultsData = await chatProvider.getFormResults();

    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    // Parse templates into {id, name} maps
    final templates = <Map<String, String>>[];
    if (templatesData != null) {
      for (final t in templatesData) {
        final name =
            t['Name']?.toString() ??
            t['Nm']?.toString() ??
            t['Title']?.toString() ??
            '';
        final id = t['Id']?.toString() ?? '';
        if (name.isNotEmpty && id.isNotEmpty) {
          templates.add({'name': name, 'id': id});
        }
      }
    }

    // Parse results into {id, name} maps
    final results = <Map<String, String>>[];
    if (resultsData != null) {
      for (final r in resultsData) {
        // Pada Form Result (dari backend), nama pengirim ada di field "SenderNm" atau bisa juga "Phone"
        String name = r['SenderNm']?.toString() ?? r['Phone']?.toString() ?? '';
        if (name.isEmpty) {
          name = 'Hasil Form #${r['Id']}'; // Fallback
        }

        final id = r['Id']?.toString() ?? '';

        // Kita juga bisa memfilter agar hanya menampilkan Form Result untuk Template yang dipilih
        // Namun karena ini list default, kita ambil semua yang valid dulu.
        if (id.isNotEmpty) {
          results.add({
            'name': name,
            'id': id,
            'formId':
                r['FormId']?.toString() ??
                '', // Simpan FormId untuk keperluan filter jika perlu
          });
        }
      }
    }

    if (templates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada form template tersedia dari server'),
          ),
        );
      }
      return;
    }

    String selectedTemplateId = '';
    String selectedTemplateName = _currentFormTemplate;
    if (_currentFormTemplate.isNotEmpty) {
      try {
        selectedTemplateId =
            templates.firstWhere(
              (t) => t['name'] == _currentFormTemplate,
            )['id'] ??
            '';
      } catch (e) {
        selectedTemplateId = '';
      }
    }

    String selectedResultId = '';
    String selectedResultName = _currentFormResult;
    if (_currentFormResult.isNotEmpty) {
      try {
        selectedResultId =
            results.firstWhere((r) => r['name'] == _currentFormResult)['id'] ??
            '';
      } catch (e) {
        selectedResultId = '';
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isSaveEnabled = selectedTemplateId.isNotEmpty;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.description,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Form Template',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Form Template',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: Text(
                            '--select--',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade600,
                          ),
                          value: selectedTemplateId.isEmpty
                              ? null
                              : selectedTemplateId,
                          dropdownColor: isDark
                              ? const Color(0xFF1F2C34)
                              : Colors.white,
                          items: templates.map((t) {
                            return DropdownMenuItem<String>(
                              value: t['id']!,
                              child: Text(
                                t['name']!,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setDialogState(() {
                              selectedTemplateId = newValue!;
                              selectedTemplateName =
                                  templates.firstWhere(
                                    (t) => t['id'] == newValue,
                                  )['name'] ??
                                  '';
                              selectedResultId = '';
                              selectedResultName = '';
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Form Result',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: Text(
                            selectedTemplateId.isEmpty
                                ? '--select template first--'
                                : '--select--',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade600,
                          ),
                          value: selectedResultId.isEmpty
                              ? null
                              : selectedResultId,
                          dropdownColor: isDark
                              ? const Color(0xFF1F2C34)
                              : Colors.white,
                          items: selectedTemplateId.isEmpty
                              ? []
                              : () {
                                  final filteredResults = results
                                      .where(
                                        (r) =>
                                            r['formId'] == selectedTemplateId,
                                      )
                                      .toList();
                                  if (filteredResults.isEmpty) {
                                    return [
                                      DropdownMenuItem<String>(
                                        value: 'empty',
                                        child: Text(
                                          'Belum ada data (Kosong)',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    ];
                                  }
                                  return filteredResults.map((r) {
                                    return DropdownMenuItem<String>(
                                      value: r['id']!,
                                      child: Text(
                                        r['name']!,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    );
                                  }).toList();
                                }(),
                          onChanged: (newValue) {
                            if (newValue == 'empty') return;
                            setDialogState(() {
                              selectedResultId = newValue!;
                              selectedResultName =
                                  results.firstWhere(
                                    (r) => r['id'] == newValue,
                                    orElse: () => {'name': ''},
                                  )['name'] ??
                                  '';
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSaveEnabled
                            ? Colors.blue
                            : Colors.grey.shade300,
                        foregroundColor: isSaveEnabled
                            ? Colors.white
                            : Colors.grey.shade500,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: isSaveEnabled
                          ? () async {
                              final formTemplateId = int.tryParse(
                                selectedTemplateId,
                              );
                              final formResultId = selectedResultId.isNotEmpty
                                  ? int.tryParse(selectedResultId)
                                  : null;
                              final success = await chatProvider
                                  .updateFormTemplate(
                                    widget.chat.id,
                                    formTemplateId,
                                    formResultId: formResultId,
                                  );
                              if (success) {
                                setState(() {
                                  _currentFormTemplate = selectedTemplateName;
                                  _currentFormResult = selectedResultName;
                                });
                              } else {
                                if (mounted)
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to save form template',
                                      ),
                                    ),
                                  );
                              }
                              if (mounted) Navigator.pop(context);
                            }
                          : null,
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chat = widget.chat;
    final chatProvider = context.watch<ChatProvider>();
    final savedContactName = chatProvider.getSavedContactName(widget.chat.id);
    final contactName =
        (savedContactName != null && savedContactName.isNotEmpty)
        ? savedContactName
        : (_currentContactName.isNotEmpty
              ? _currentContactName
              : widget.chat.sender);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0B141A)
            : const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          elevation: 0.5,
          title: const Text(
            'Contact Detail',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // ── Avatar + Name ──
              Container(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    AuthenticatedAvatar(
                      imageUrl: _currentAvatarUrl,
                      size: 48,
                      isGroup: widget.chat.isGroup,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        contactName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Conversation History ──
              _buildListTile(
                isDark: isDark,
                title: 'Conversation History',
                trailing: Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                ),
                onTap: () {
                  // Read ctId from chatProvider's room matching the current room ID
                  final chatProvider = Provider.of<ChatProvider>(
                    context,
                    listen: false,
                  );
                  final allChats = chatProvider.chats;
                  String ctId = chat.contactId; // fallback
                  for (final room in allChats) {
                    if (room.id == chat.id) {
                      ctId = room.contactId;
                      break;
                    }
                  }
                  debugPrint(
                    'ConversationHistory: navigating with ctId=$ctId for roomId=${chat.id}',
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConversationHistoryPage(
                        contactId: ctId,
                        contactName: contactName,
                        contactImage: _currentAvatarUrl ?? chat.avatarUrl,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // ── Contact Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  _buildSectionHeader(
                    isDark: isDark,
                    title: 'Contact',
                    actions: [
                      IconButton(
                        icon: Icon(
                          Icons.block,
                          size: 20,
                          color: _isBlocked ? Colors.green : Colors.red,
                        ),
                        onPressed: () {
                          _showBlockDialog(context, isDark, contactName);
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 20,
                          color: Colors.blue,
                        ),
                        onPressed: () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditContactPage(
                                chat: chat.copyWith(sender: contactName),
                              ),
                            ),
                          );
                          if (result == true) {
                            // Refresh nama secara reaktif + data terbaru dari server
                            if (mounted) {
                              final provider = Provider.of<ChatProvider>(
                                context,
                                listen: false,
                              );
                              final updatedName = provider.getSavedContactName(
                                widget.chat.id,
                              );
                              if (updatedName != null &&
                                  updatedName.isNotEmpty) {
                                setState(
                                  () => _currentContactName = updatedName,
                                );
                              }
                              _loadDetailRoom();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  _buildKeyValueRow(
                    isDark: isDark,
                    label: 'Name',
                    value: contactName,
                  ),
                  if (_contactCountry.isNotEmpty)
                    _buildKeyValueRow(
                      isDark: isDark,
                      label: 'Country',
                      value: _contactCountry,
                      valueColor: isDark ? Colors.white : Colors.black,
                    ),
                  if (_contactState.isNotEmpty)
                    _buildKeyValueRow(
                      isDark: isDark,
                      label: 'State',
                      value: _contactState,
                      valueColor: isDark ? Colors.white : Colors.black,
                    ),
                  if (_contactCity.isNotEmpty)
                    _buildKeyValueRow(
                      isDark: isDark,
                      label: 'City',
                      value: _contactCity,
                      valueColor: isDark ? Colors.white : Colors.black,
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Conversation Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  _buildSectionHeader(isDark: isDark, title: 'Conversation'),
                  InkWell(
                    onTap: _showAccountPicker,
                    child: _buildStackedValueRow(
                      isDark: isDark,
                      label: 'Account',
                      value: _currentAccount,
                      valueColor: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSwitchRow(
                    isDark: isDark,
                    label: 'Need Reply',
                    value: _needReply,
                    onChanged: (val) => _toggleSetting(
                      'Need Reply',
                      _needReply,
                      (newVal) => setState(() => _needReply = newVal),
                    ),
                  ),
                  _buildSwitchRow(
                    isDark: isDark,
                    label: 'Mute AI Agent',
                    value: _muteAIAgent,
                    onChanged: (val) => _toggleSetting(
                      'Mute AI Agent',
                      _muteAIAgent,
                      (newVal) => setState(() => _muteAIAgent = newVal),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Funnel Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _toggleFunnelDropdown,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Funnel',
                      actions: [
                        IconButton(
                          icon: const Icon(
                            Icons.add,
                            size: 22,
                            color: Colors.lightBlue,
                          ),
                          onPressed: _showAddFunnelDialog,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isFunnelExpanded
                              ? Colors.blue.shade300
                              : (isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: _toggleFunnelDropdown,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentFunnel.isNotEmpty
                                          ? _currentFunnel
                                          : 'No funnel assigned',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: _currentFunnel.isNotEmpty
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                        color: _currentFunnel.isNotEmpty
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.black87)
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  if (_currentFunnel.isNotEmpty)
                                    GestureDetector(
                                      onTap: _showRemoveFunnelConfirmation,
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    _isFunnelExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    size: 22,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isFunnelExpanded) ...[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  controller: _funnelSearchController,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: isDark
                                            ? Colors.grey.shade600
                                            : Colors.blue.shade200,
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: isDark
                                            ? Colors.grey.shade600
                                            : Colors.blue.shade200,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                        color: Colors.blue,
                                        width: 1.5,
                                      ),
                                    ),
                                    hintText: 'Search...',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: _isLoadingFunnels
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : _cachedFunnelItems.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Tidak ada funnel',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    )
                                  : Builder(
                                      builder: (context) {
                                        final query = _funnelSearchController
                                            .text
                                            .toLowerCase();
                                        final filtered = _cachedFunnelItems
                                            .where((f) {
                                              return f['name']!
                                                  .toLowerCase()
                                                  .contains(query);
                                            })
                                            .toList();

                                        if (filtered.isEmpty) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(
                                              child: Text(
                                                'Funnel not found',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        return ListView.builder(
                                          shrinkWrap: true,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          itemCount: filtered.length,
                                          itemBuilder: (context, index) {
                                            final funnel = filtered[index];
                                            final isSelected =
                                                _currentFunnel ==
                                                funnel['name'];
                                            return InkWell(
                                              onTap: () async {
                                                setState(() {
                                                  _isFunnelExpanded = false;
                                                  _funnelSearchController
                                                      .clear();
                                                });
                                                final chatProvider =
                                                    Provider.of<ChatProvider>(
                                                      context,
                                                      listen: false,
                                                    );
                                                final success =
                                                    await chatProvider
                                                        .updateContactFunnel(
                                                          widget.chat.id,
                                                          funnel['id']!,
                                                          funnelName:
                                                              funnel['name']!,
                                                        );
                                                if (success && mounted) {
                                                  setState(
                                                    () => _currentFunnel =
                                                        funnel['name']!,
                                                  );
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? (isDark
                                                            ? Colors
                                                                  .blue
                                                                  .shade900
                                                                  .withOpacity(
                                                                    0.3,
                                                                  )
                                                            : const Color(
                                                                0xFFF0F3F6,
                                                              ))
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  funnel['name']!,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Message Tags Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showMessageTagsDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Message Tags',
                      actions: [
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            size: 22,
                            color: Colors.lightBlue,
                          ),
                          onPressed: _showAddTagDialog,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add,
                            size: 22,
                            color: Colors.lightBlue,
                          ),
                          onPressed: _showMessageTagsDialog,
                        ),
                      ],
                    ),
                  ),
                  if (_currentTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _currentTags.map((tag) {
                          return Chip(
                            label: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            backgroundColor: isDark
                                ? Colors.grey.shade800
                                : Colors.blue.shade50,
                            side: BorderSide.none,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _showRemoveTagConfirmation(tag),
                          );
                        }).toList(),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showMessageTagsDialog,
                      child: _buildPlaceholderRow(
                        isDark: isDark,
                        text: 'No tags added yet',
                        showIcon: false,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Notes Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showEditNoteDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Notes',
                      actions: [
                        IconButton(
                          icon: const Icon(
                            Icons.add,
                            size: 22,
                            color: Colors.lightBlue,
                          ),
                          onPressed: _showEditNoteDialog,
                        ),
                      ],
                    ),
                  ),
                  if (_currentNotes.isNotEmpty)
                    InkWell(
                      onTap: _showEditNoteDialog,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _currentNotes,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showEditNoteDialog,
                      child: _buildPlaceholderRow(
                        isDark: isDark,
                        text: 'No notes added yet',
                        showIcon: false,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Campaign Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showCampaignDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Campaign',
                      actions: [
                        IconButton(
                          icon: Icon(
                            Icons.open_in_new,
                            size: 20,
                            color: Colors.blue.shade400,
                          ),
                          onPressed: _showCampaignDialog,
                        ),
                      ],
                    ),
                  ),
                  if (_currentCampaign.isNotEmpty)
                    InkWell(
                      onTap: _showCampaignDialog,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _currentCampaign,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showCampaignDialog,
                      child: _buildPlaceholderValue(
                        isDark: isDark,
                        text: 'Not Set',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Deal Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showDealDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Deal',
                      actions: [
                        IconButton(
                          icon: Icon(
                            Icons.open_in_new,
                            size: 20,
                            color: Colors.blue.shade400,
                          ),
                          onPressed: _showDealDialog,
                        ),
                      ],
                    ),
                  ),
                  if (_currentPipeline.isNotEmpty ||
                      _currentStage.isNotEmpty ||
                      _currentDeal.isNotEmpty)
                    InkWell(
                      onTap: _showDealDialog,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_currentPipeline.isNotEmpty)
                              Text(
                                'Pipeline: $_currentPipeline',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            if (_currentPipeline.isNotEmpty)
                              const SizedBox(height: 2),
                            if (_currentStage.isNotEmpty)
                              Text(
                                'Stage: $_currentStage',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            if (_currentStage.isNotEmpty)
                              const SizedBox(height: 4),
                            if (_currentDeal.isNotEmpty)
                              Text(
                                _currentDeal,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showDealDialog,
                      child: _buildPlaceholderValue(
                        isDark: isDark,
                        text: 'Not Set',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Form Template Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showFormTemplateDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Form Template',
                      actions: [
                        IconButton(
                          icon: Icon(
                            Icons.open_in_new,
                            size: 20,
                            color: Colors.blue.shade400,
                          ),
                          onPressed: _showFormTemplateDialog,
                        ),
                      ],
                    ),
                  ),
                  if (_currentFormTemplate.isNotEmpty)
                    InkWell(
                      onTap: _showFormTemplateDialog,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _currentFormTemplate,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showFormTemplateDialog,
                      child: _buildPlaceholderValue(
                        isDark: isDark,
                        text: 'Not Set',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Form Result Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showFormTemplateDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Form Result',
                    ),
                  ),
                  if (_currentFormResult.isNotEmpty)
                    InkWell(
                      onTap: _showFormTemplateDialog,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          _currentFormResult,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showFormTemplateDialog,
                      child: _buildPlaceholderValue(
                        isDark: isDark,
                        text: 'Not Set',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Human Agent Section ──
              _buildSectionContainer(
                isDark: isDark,
                children: [
                  InkWell(
                    onTap: _showAgentDialog,
                    child: _buildSectionHeader(
                      isDark: isDark,
                      title: 'Human Agent',
                    ),
                  ),
                  if (_currentAgentName.isNotEmpty)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        onTap: _showAgentDialog,
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade200,
                          child: Icon(
                            Icons.person,
                            color: Colors.grey.shade500,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          _currentAgentName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: _agentEmail.isNotEmpty
                            ? Text(
                                _agentEmail,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              )
                            : null,
                        trailing: InkWell(
                          onTap: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Removing agent...'),
                              ),
                            );
                            final chatProvider = Provider.of<ChatProvider>(
                              context,
                              listen: false,
                            );
                            final success = await chatProvider.removeAgent(
                              widget.chat.id,
                            );
                            if (success) {
                              setState(() {
                                _currentAgentName = '';
                                _agentEmail = '';
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Agent removed')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to remove agent'),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _showAgentDialog,
                      child: _buildPlaceholderValue(
                        isDark: isDark,
                        text: 'Not Set',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HELPER WIDGETS
  // ─────────────────────────────────────────────

  Widget _buildListTile({
    required bool isDark,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF1F2C34) : Colors.white,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  Widget _buildSectionContainer({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF1F2C34) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildSectionHeader({
    required bool isDark,
    required String title,
    List<Widget>? actions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (actions != null) ...actions,
        ],
      ),
    );
  }

  Widget _buildKeyValueRow({
    required bool isDark,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? (isDark ? Colors.white : Colors.blue),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedValueRow({
    required bool isDark,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Colors.blue,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required bool isDark,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Colors.lightBlue,
            inactiveThumbColor: isDark ? Colors.white70 : Colors.grey.shade400,
            inactiveTrackColor: isDark
                ? Colors.grey.shade700
                : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderRow({
    required bool isDark,
    required String text,
    bool showIcon = true,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade400,
              ),
            ),
          ),
          if (showIcon)
            const Icon(Icons.add, size: 20, color: Colors.lightBlue),
        ],
      ),
    );
  }

  Widget _buildPlaceholderValue({required bool isDark, required String text}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[500] : Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  void _showBlockDialog(BuildContext context, bool isDark, String contactName) {
    final isCurrentlyBlocked = _isBlocked;
    final actionName = isCurrentlyBlocked ? 'Unblock' : 'Block';
    final actionDesc = isCurrentlyBlocked
        ? 'Are you sure you want to unblock this contact? You will receive messages from them.'
        : 'Are you sure you want to block this contact? You will not receive messages from them.';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isCurrentlyBlocked ? Colors.green : Colors.red)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.block,
                  color: isCurrentlyBlocked
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$actionName Contact',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          content: Text(
            actionDesc,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: isCurrentlyBlocked
                    ? Colors.green.shade600
                    : Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);

                // Show loading dialog (fast with SignalR)
                showDialog(
                  context: this.context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                final chatProvider = Provider.of<ChatProvider>(
                  this.context,
                  listen: false,
                );
                final newBlockedState = !isCurrentlyBlocked;
                final success = await chatProvider.toggleBlockContact(
                  widget.chat.id,
                  widget.chat.contactId,
                  newBlockedState,
                );

                if (!mounted) return;
                Navigator.pop(this.context); // hide loading

                if (success) {
                  // FIX Bug #4: Update local state so UI is reactive
                  setState(() {
                    _isBlocked = newBlockedState;
                  });
                  _showCenterSnackBar(
                    context: this.context,
                    message: isCurrentlyBlocked
                        ? 'Contact unblocked successfully'
                        : 'Contact blocked successfully',
                    backgroundColor: Colors.green.withOpacity(0.9),
                  );
                } else {
                  _showCenterSnackBar(
                    context: this.context,
                    message: 'Failed to $actionName contact',
                    backgroundColor: Colors.red.shade600,
                  );
                }
              },
              child: Text(
                actionName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAgentDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show a loading indicator first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final agents = await chatProvider.getAgents();

    if (!mounted) return;
    Navigator.pop(context); // hide loading

    if (agents == null || agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No agents found or failed to load')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Agent',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.close, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: agents.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final agent = agents[index];
                      final agentName =
                          agent['DisplayName']?.toString() ??
                          agent['Name']?.toString() ??
                          'Unknown Agent';
                      final agentUserId =
                          agent['UserId']?.toString() ??
                          agent['Id']?.toString() ??
                          '';

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.blue,
                          ),
                        ),
                        title: Text(
                          agentName,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          agent['Username']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Assigning to $agentName...'),
                            ),
                          );

                          final success = await chatProvider.assignAgent(
                            widget.chat.id,
                            agentUserId,
                            agentName,
                          );
                          if (success) {
                            if (mounted) {
                              setState(() {
                                _currentAgentName = agentName;
                                _agentEmail =
                                    agent['Email']?.toString() ??
                                    agent['Username']?.toString() ??
                                    '';
                              });
                            }
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Successfully assigned to $agentName',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Failed to assign agent')),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper: Show SnackBar di tengah layar (center)
  void _showCenterSnackBar({
    required BuildContext context,
    required String message,
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12,
          left: 24,
          right: 24,
          bottom:
              MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              80,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
        elevation: 8,
      ),
    );
  }
}
