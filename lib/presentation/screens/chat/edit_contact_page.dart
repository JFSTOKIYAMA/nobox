import 'dart:io';
import 'package:flutter/material.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/model/message.dart';

// =====================================================================
// FITUR: Halaman Edit Kontak
// FILE: lib/presentation/screens/chat/edit_contact_page.dart
// FUNGSI: Formulir untuk mengubah data pelanggan (nama, alamat, lokasi)
//         dan foto profil kontak.
// =====================================================================

class EditContactPage extends StatefulWidget {
  final ChatModel chat;

  const EditContactPage({super.key, required this.chat});

  @override
  State<EditContactPage> createState() => _EditContactPageState();
}

class _EditContactPageState extends State<EditContactPage> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _postalCodeController;
  
  File? _profileImage;
  String? _currentAvatarUrl;
  final ImagePicker _imagePicker = ImagePicker();

  String _selectedCategory = 'WhatsAppBusiness';
  String? _selectedCountryName;
  String? _selectedCountryCode;
  String? _selectedStateName;
  String? _selectedStateCode;
  String? _selectedCityName;

  final List<String> _categories = ['General', 'WhatsAppBusiness'];

  // Cached data
  List<csc.Country> _countries = [];
  List<csc.State> _states = [];
  List<csc.City> _cities = [];
  bool _isLoadingCountries = true;
  bool _isLoadingContact = true;

  // Overlay state for category
  final GlobalKey _categoryKey = GlobalKey();
  OverlayEntry? _categoryOverlayEntry;
  final TextEditingController _categorySearchController = TextEditingController();
  List<String> _filteredCategories = [];

  // Overlay state for location details
  final GlobalKey _countryKey = GlobalKey();
  final GlobalKey _stateKey = GlobalKey();
  final GlobalKey _cityKey = GlobalKey();
  OverlayEntry? _locationOverlayEntry;
  GlobalKey? _activeLocationKey;
  final TextEditingController _locationSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredCategories = _categories;
    _currentAvatarUrl = widget.chat.avatarUrl;
    _nameController = TextEditingController(text: widget.chat.sender);
    _addressController = TextEditingController();
    _postalCodeController = TextEditingController();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _loadCountries(),
      _loadContactData(),
    ]);
    
    // FIX: Resolusi otomatis ISO Code berdasarkan nama Negara & Provinsi.
    // Tanpa ini, pengguna tidak bisa klik dropdown City (karena _selectedStateCode masih null).
    if (_selectedCountryName != null && _countries.isNotEmpty) {
      try {
        final country = _countries.firstWhere(
          (c) => c.name.toLowerCase() == _selectedCountryName!.toLowerCase()
        );
        _selectedCountryCode = country.isoCode;
        
        if (_selectedStateName != null) {
          await _loadStates(country.isoCode);
          try {
            final state = _states.firstWhere(
              (s) => s.name.toLowerCase() == _selectedStateName!.toLowerCase()
            );
            _selectedStateCode = state.isoCode;

            if (_selectedCityName != null) {
              await _loadCities(country.isoCode, state.isoCode);
            }
          } catch (_) {
            // Provinsi tidak ditemukan di database country_state_city
          }
        } else {
          await _loadStates(country.isoCode);
        }
      } catch (_) {
        // Negara tidak ditemukan di database country_state_city
      }
      if (mounted) setState(() {});
    }
  }

  // FITUR: Memuat Data Kontak (API Call)
  // FUNGSI: Mengambil detail data kontak dari server untuk mengisi form default sebelum diedit.
  Future<void> _loadContactData() async {
    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final data = await chatProvider.getDetailRoom(widget.chat.id);
      if (data != null && mounted) {
        // Data ada di data['Data']['Room'] dan data['Data']['ContactReal']
        final room = data['Data']?['Room'] ?? data;
        final contact = data['Data']?['ContactReal'] ?? data['Data']?['Contact'] ?? data;

        setState(() {
          // Pre-fill nama dari room
          final serverName = room['CtRealNm']?.toString() ?? room['CtTmp']?.toString() ?? contact['Name']?.toString() ?? contact['Nm']?.toString();
          if (serverName != null && serverName.isNotEmpty) {
            _nameController.text = serverName;
          }

          // Pre-fill data lokasi dari contact (server)
          final address = contact['Address']?.toString() ?? '';
          if (address.isNotEmpty) _addressController.text = address;

          final postalCode = contact['Postal']?.toString() ?? contact['PostalCode']?.toString() ?? '';
          if (postalCode.isNotEmpty) _postalCodeController.text = postalCode;

          final country = contact['Country']?.toString() ?? contact['Cntry']?.toString() ?? '';
          if (country.isNotEmpty) _selectedCountryName = country;

          final state = contact['State']?.toString() ?? contact['Stt']?.toString() ?? contact['Province']?.toString() ?? '';
          if (state.isNotEmpty) _selectedStateName = state;

          final city = contact['City']?.toString() ?? contact['Cty']?.toString() ?? '';
          if (city.isNotEmpty) _selectedCityName = city;

          final photo = contact['Photo']?.toString() ?? room['CtImg']?.toString() ?? room['LinkImg']?.toString() ?? '';
          if (photo.isNotEmpty) {
            if (photo.startsWith('http')) {
              _currentAvatarUrl = photo;
            } else {
              _currentAvatarUrl = 'https://id.nobox.ai/upload/$photo';
            }
          }

          // Override: gunakan data lokasi lokal (optimistic save) jika ada
          final localLocation = chatProvider.getSavedContactLocation(widget.chat.id);
          if (localLocation != null) {
            if (localLocation['Address'] != null && localLocation['Address']!.isNotEmpty) {
              _addressController.text = localLocation['Address']!;
            }
            if (localLocation['Postal'] != null && localLocation['Postal']!.isNotEmpty) {
              _postalCodeController.text = localLocation['Postal']!;
            }
            if (localLocation['Country'] != null && localLocation['Country']!.isNotEmpty) {
              _selectedCountryName = localLocation['Country']!;
            }
            if (localLocation['State'] != null && localLocation['State']!.isNotEmpty) {
              _selectedStateName = localLocation['State']!;
            }
            if (localLocation['City'] != null && localLocation['City']!.isNotEmpty) {
              _selectedCityName = localLocation['City']!;
            }
          }

          _isLoadingContact = false;
        });
      } else {
        // Server data kosong, coba dari lokal
        final chatProvider2 = Provider.of<ChatProvider>(context, listen: false);
        final localLocation = chatProvider2.getSavedContactLocation(widget.chat.id);
        if (localLocation != null && mounted) {
          setState(() {
            if (localLocation['Address'] != null) _addressController.text = localLocation['Address']!;
            if (localLocation['Postal'] != null) _postalCodeController.text = localLocation['Postal']!;
            if (localLocation['Country'] != null) _selectedCountryName = localLocation['Country'];
            if (localLocation['State'] != null) _selectedStateName = localLocation['State'];
            if (localLocation['City'] != null) _selectedCityName = localLocation['City'];
          });
        }
        if (mounted) setState(() => _isLoadingContact = false);
      }
    } catch (e) {
      debugPrint('EditContactPage: Error loading contact data: $e');
      // Fallback ke lokal jika terjadi error
      try {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        final localLocation = chatProvider.getSavedContactLocation(widget.chat.id);
        if (localLocation != null && mounted) {
          setState(() {
            if (localLocation['Address'] != null) _addressController.text = localLocation['Address']!;
            if (localLocation['Postal'] != null) _postalCodeController.text = localLocation['Postal']!;
            if (localLocation['Country'] != null) _selectedCountryName = localLocation['Country'];
            if (localLocation['State'] != null) _selectedStateName = localLocation['State'];
            if (localLocation['City'] != null) _selectedCityName = localLocation['City'];
          });
        }
      } catch (_) {}
      if (mounted) setState(() => _isLoadingContact = false);
    }
  }

  Future<void> _loadCountries() async {
    final countries = await csc.getAllCountries();
    if (mounted) {
      setState(() {
        _countries = countries;
        _isLoadingCountries = false;
      });
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() => _states = []);
    final states = await csc.getStatesOfCountry(countryCode);
    if (mounted) {
      setState(() => _states = states);
    }
  }

  Future<void> _loadCities(String countryCode, String stateCode) async {
    setState(() => _cities = []);
    final cities = await csc.getStateCities(countryCode, stateCode);
    if (mounted) {
      setState(() => _cities = cities);
    }
  }

  @override
  void dispose() {
    _removeCategoryOverlay();
    _removeLocationOverlay();
    _categorySearchController.dispose();
    _locationSearchController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = widget.chat.sender.isNotEmpty ? widget.chat.sender[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _removeCategoryOverlay();
        _removeLocationOverlay();
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFF5F8FA),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.blue,
          foregroundColor: Colors.white,
          title: const Text('Edit Contact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          centerTitle: false,
        actions: [
          // [ACTION: EDIT_CONTACT_INFO] - Eksekusi penyimpanan data profil kontak
          TextButton.icon(
            onPressed: () async {
              // Build the update payload
              final contactData = <String, dynamic>{
                "CtRealNm": _nameController.text.trim(),
              };
              if (_addressController.text.trim().isNotEmpty) {
                contactData["Address"] = _addressController.text.trim();
              }
              if (_postalCodeController.text.trim().isNotEmpty) {
                contactData["Postal"] = _postalCodeController.text.trim();
              }
              if (_selectedCountryName != null) {
                contactData["Country"] = _selectedCountryName;
              }
              if (_selectedStateName != null) {
                contactData["State"] = _selectedStateName;
              }
              if (_selectedCityName != null) {
                contactData["City"] = _selectedCityName;
              }
              
              // Show loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saving contact...')),
              );
              
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);

              if (_profileImage != null) {
                final imageUrl = await chatProvider.uploadImage(_profileImage!);
                if (imageUrl != null) {
                  contactData["Photo"] = imageUrl;
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to upload image: ${chatProvider.error ?? "Unknown error"}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }
              }

              final success = await chatProvider.updateContactInfo(widget.chat.id, contactData);
              
              if (success) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contact saved successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to save: ${chatProvider.error ?? "Unknown error"}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check, color: Colors.white, size: 20),
            label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ── Avatar Section ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                    GestureDetector(
                      onTap: () => _showChangePhotoBottomSheet(isDark),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.blue.shade400,
                            backgroundImage: _profileImage != null 
                                ? FileImage(_profileImage!) as ImageProvider
                                : (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty 
                                    ? CachedNetworkImageProvider(_currentAvatarUrl!) as ImageProvider 
                                    : null),
                            child: _profileImage == null && (_currentAvatarUrl == null || _currentAvatarUrl!.isEmpty)
                                ? Text(
                                    initial,
                                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Contact Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Basic Information Section ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
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
                        child: const Icon(Icons.person_outline, color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Basic Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  _buildLabel('Full Name', isDark),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _nameController,
                    icon: Icons.person_outline,
                    hintText: 'Enter full name',
                    isDark: isDark,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildLabel('Category', isDark),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      if (_categoryOverlayEntry != null) {
                        _removeCategoryOverlay();
                      } else {
                        _showCategoryOverlay();
                      }
                    },
                    child: Container(
                      key: _categoryKey,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _categoryOverlayEntry != null 
                              ? Colors.blue.shade600 
                              : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                          width: _categoryOverlayEntry != null ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.category, color: Colors.grey.shade400, size: 20),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _selectedCategory.isEmpty ? 'Select category' : _selectedCategory,
                              style: TextStyle(
                                color: _selectedCategory.isEmpty 
                                    ? Colors.grey.shade400 
                                    : (isDark ? Colors.white : Colors.black87),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            _categoryOverlayEntry != null ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Location Details Section ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
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
                        child: const Icon(Icons.location_on_outlined, color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Location Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  _buildLabel('Street Address', isDark),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _addressController,
                    icon: Icons.home_outlined,
                    hintText: 'Enter full address',
                    isDark: isDark,
                    maxLines: 3,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildLabel('Postal Code', isDark),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _postalCodeController,
                    icon: Icons.markunread_mailbox_outlined,
                    hintText: 'Enter postal code',
                    isDark: isDark,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // ── Country Picker ──
                  _buildLabel('Country', isDark),
                  const SizedBox(height: 8),
                  _buildSearchableSelector(
                    widgetKey: _countryKey,
                    icon: Icons.public,
                    value: _selectedCountryName,
                    hintText: _isLoadingCountries ? 'Loading countries...' : 'Select a country',
                    isDark: isDark,
                    onTap: _isLoadingCountries ? null : () => _showCountryPicker(isDark),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // ── State Picker ──
                  _buildLabel('State / Province', isDark),
                  const SizedBox(height: 8),
                  _buildSearchableSelector(
                    widgetKey: _stateKey,
                    icon: Icons.map_outlined,
                    value: _selectedStateName,
                    hintText: _selectedCountryName == null ? 'Select country first' : 'Select a state',
                    isDark: isDark,
                    onTap: _selectedCountryCode == null ? null : () => _showStatePicker(isDark),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // ── City Picker ──
                  _buildLabel('City', isDark),
                  const SizedBox(height: 8),
                  _buildSearchableSelector(
                    widgetKey: _cityKey,
                    icon: Icons.location_city,
                    value: _selectedCityName,
                    hintText: _selectedStateName == null ? 'Select state first' : 'Select a city',
                    isDark: isDark,
                    onTap: _selectedStateCode == null ? null : () => _showCityPicker(isDark),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ── Info Box ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Changes will be saved to the contact record',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
          // Loading overlay saat data contact sedang dimuat
          if (_isLoadingContact)
            Positioned.fill(
              child: Container(
                color: isDark ? Colors.black54 : Colors.white70,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blue),
                      SizedBox(height: 16),
                      Text(
                        'Loading contact data...',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  // ─────────────────────────────────────────────
  //  CATEGORY OVERLAY DROPDOWN
  // ─────────────────────────────────────────────
  
  void _removeCategoryOverlay() {
    _categoryOverlayEntry?.remove();
    _categoryOverlayEntry = null;
    if (mounted) setState(() {});
  }

  void _showCategoryOverlay() {
    final RenderBox renderBox = _categoryKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _categorySearchController.clear();
    _filteredCategories = List.from(_categories);

    _categoryOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removeCategoryOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              width: size.width,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                shadowColor: Colors.black26,
                child: StatefulBuilder(
                  builder: (context, setOverlayState) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: TextField(
                              controller: _categorySearchController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.blue),
                                ),
                              ),
                              onChanged: (text) {
                                setOverlayState(() {
                                  if (text.isEmpty) {
                                    _filteredCategories = List.from(_categories);
                                  } else {
                                    _filteredCategories = _categories.where((c) => c.toLowerCase().contains(text.toLowerCase())).toList();
                                  }
                                });
                              },
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: _filteredCategories.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child: Text(
                                        'No categories found',
                                        style: TextStyle(color: Colors.grey.shade500),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    shrinkWrap: true,
                                    itemCount: _filteredCategories.length,
                                    itemBuilder: (context, index) {
                                      final cat = _filteredCategories[index];
                                      return InkWell(
                                        onTap: () {
                                          if (mounted) {
                                            setState(() {
                                              _selectedCategory = cat;
                                            });
                                          }
                                          _removeCategoryOverlay();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Text(
                                            cat,
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_categoryOverlayEntry!);
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────
  //  CHANGE PROFILE PHOTO
  // ─────────────────────────────────────────────

  void _showChangePhotoBottomSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Change Profile Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(
                    Icons.camera_alt, 
                    color: isDark ? Colors.white : Colors.black87, 
                    size: 26,
                  ),
                  title: Text(
                    'Take Photo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(
                    Icons.photo_library, 
                    color: isDark ? Colors.white : Colors.black87, 
                    size: 26,
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (pickedFile != null && mounted) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  SEARCHABLE PICKERS
  // ─────────────────────────────────────────────

  void _showCountryPicker(bool isDark) {
    if (_locationOverlayEntry != null && _activeLocationKey == _countryKey) {
      _removeLocationOverlay();
      return;
    }
    _showLocationOverlay<csc.Country>(
      isDark: isDark,
      anchorKey: _countryKey,
      items: _countries,
      getName: (c) => c.name,
      onSelected: (country) {
        setState(() {
          _selectedCountryName = country.name;
          _selectedCountryCode = country.isoCode;
          _selectedStateName = null;
          _selectedStateCode = null;
          _selectedCityName = null;
          _states = [];
          _cities = [];
        });
        _loadStates(country.isoCode);
      },
    );
  }

  void _showStatePicker(bool isDark) {
    if (_locationOverlayEntry != null && _activeLocationKey == _stateKey) {
      _removeLocationOverlay();
      return;
    }
    if (_states.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading states, please wait...')),
      );
      return;
    }
    _showLocationOverlay<csc.State>(
      isDark: isDark,
      anchorKey: _stateKey,
      items: _states,
      getName: (s) => s.name,
      onSelected: (state) {
        setState(() {
          _selectedStateName = state.name;
          _selectedStateCode = state.isoCode;
          _selectedCityName = null;
          _cities = [];
        });
        _loadCities(_selectedCountryCode!, state.isoCode);
      },
    );
  }

  void _showCityPicker(bool isDark) {
    if (_locationOverlayEntry != null && _activeLocationKey == _cityKey) {
      _removeLocationOverlay();
      return;
    }
    if (_cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading cities, please wait...')),
      );
      return;
    }
    _showLocationOverlay<csc.City>(
      isDark: isDark,
      anchorKey: _cityKey,
      items: _cities,
      getName: (c) => c.name,
      onSelected: (city) {
        setState(() {
          _selectedCityName = city.name;
        });
      },
    );
  }

  void _removeLocationOverlay() {
    _locationOverlayEntry?.remove();
    _locationOverlayEntry = null;
    _activeLocationKey = null;
    if (mounted) setState(() {});
  }

  void _showLocationOverlay<T>({
    required bool isDark,
    required GlobalKey anchorKey,
    required List<T> items,
    required String Function(T) getName,
    required void Function(T) onSelected,
  }) {
    _removeLocationOverlay();
    
    final RenderBox renderBox = anchorKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _locationSearchController.clear();
    List<T> filteredItems = List.from(items);
    _activeLocationKey = anchorKey;

    _locationOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removeLocationOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              width: size.width,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                shadowColor: Colors.black26,
                child: StatefulBuilder(
                  builder: (context, setOverlayState) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: TextField(
                              controller: _locationSearchController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.blue),
                                ),
                              ),
                              onChanged: (text) {
                                setOverlayState(() {
                                  if (text.isEmpty) {
                                    filteredItems = List.from(items);
                                  } else {
                                    filteredItems = items.where((i) => getName(i).toLowerCase().contains(text.toLowerCase())).toList();
                                  }
                                });
                              },
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 250),
                            child: filteredItems.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child: Text(
                                        'No results found',
                                        style: TextStyle(color: Colors.grey.shade500),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    shrinkWrap: true,
                                    itemCount: filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final item = filteredItems[index];
                                      final name = getName(item);
                                      return InkWell(
                                        onTap: () {
                                          if (mounted) {
                                            onSelected(item);
                                            _removeLocationOverlay();
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_locationOverlayEntry!);
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────
  //  HELPER WIDGETS
  // ─────────────────────────────────────────────

  Widget _buildSearchableSelector({
    required GlobalKey widgetKey,
    required IconData icon,
    required String? value,
    required String hintText,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final isActive = _activeLocationKey == widgetKey && _locationOverlayEntry != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: widgetKey,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDisabled
              ? (isDark ? const Color(0xFF121B22) : const Color(0xFFF0F0F0))
              : (isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive 
                ? Colors.blue.shade600 
                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value ?? hintText,
                style: TextStyle(
                  color: value != null
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              isActive ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
              color: Colors.grey.shade500
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey.shade400 : Colors.blueGrey.shade600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    required bool isDark,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Icon(icon, color: Colors.grey.shade400, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        filled: true,
        fillColor: isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String? value,
    required IconData icon,
    required String hintText,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121B22) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Row(
            children: [
              Icon(icon, color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 16),
              Text(
                hintText,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
            ],
          ),
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade500),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Row(
                children: [
                  Icon(icon, color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 16),
                  Text(
                    item,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SEARCHABLE LIST WIDGET (Bottom Sheet)
// ─────────────────────────────────────────────

class _SearchableList<T> extends StatefulWidget {
  final bool isDark;
  final String title;
  final List<T> items;
  final String Function(T) getName;
  final String? Function(T) getSubtitle;
  final ValueChanged<T> onSelected;

  const _SearchableList({
    required this.isDark,
    required this.title,
    required this.items,
    required this.getName,
    required this.getSubtitle,
    required this.onSelected,
  });

  @override
  _SearchableListState<T> createState() => _SearchableListState<T>();
}

class _SearchableListState<T> extends State<_SearchableList<T>> {
  final TextEditingController _searchController = TextEditingController();
  List<T> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          return widget.getName(item).toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _filter,
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: widget.isDark ? const Color(0xFF121B22) : const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        'No results found',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final name = widget.getName(item);
                        final subtitle = widget.getSubtitle(item);
                        return ListTile(
                          title: Text(
                            name,
                            style: TextStyle(
                              color: widget.isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: subtitle != null
                              ? Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          onTap: () => widget.onSelected(item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
