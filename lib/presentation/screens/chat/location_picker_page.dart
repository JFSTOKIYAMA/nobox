import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

// =====================================================================
// FITUR: Pemilih Lokasi (Map)
// FILE: lib/presentation/screens/chat/location_picker_page.dart
// FUNGSI: Menampilkan peta interaktif yang dapat digeser untuk memilih
//         titik koordinat lokasi sebelum dikirim sebagai attachment.
// =====================================================================

/// WhatsApp-style location picker with draggable map.
/// Returns a LatLng when user confirms, or null if cancelled.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  LatLng _selectedLocation = const LatLng(-6.2088, 106.8456); // Jakarta default
  bool _isLoadingCurrentLocation = true;
  bool _isMapMoving = false;

  @override
  void initState() {
    super.initState();
    _goToCurrentLocation();
  }

  // FITUR: Ambil Lokasi Saat Ini (GPS)
  // FUNGSI: Mengecek izin akses GPS perangkat, mendapatkan koordinat lokasi pengguna saat ini, dan memindahkan pusat peta (map) ke titik tersebut.
  Future<void> _goToCurrentLocation() async {
    try {
      setState(() => _isLoadingCurrentLocation = true);

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoadingCurrentLocation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tolong aktifkan GPS (Location) di HP Anda.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _isLoadingCurrentLocation = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Izin lokasi ditolak.')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLoadingCurrentLocation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin lokasi diblokir permanen. Silakan ubah di Pengaturan HP.')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (mounted) {
        final currentLatLng = LatLng(position.latitude, position.longitude);
        setState(() {
          _selectedLocation = currentLatLng;
          _isLoadingCurrentLocation = false;
        });
        _mapController.move(currentLatLng, 16.0);
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        setState(() => _isLoadingCurrentLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sinyal GPS lemah atau timeout. Coba di luar ruangan.')),
        );
      }
    }
  }

  // FITUR: Deteksi Pergeseran Peta
  // FUNGSI: Memperbarui koordinat titik tengah (_selectedLocation) secara real-time saat pengguna menggeser peta.
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    setState(() {
      _selectedLocation = camera.center;
      _isMapMoving = hasGesture;
    });
  }

  // FITUR: Event Selesai Menggeser Peta
  // FUNGSI: Mendeteksi saat gesekan/pan pada peta berakhir untuk menghentikan animasi 'melayang' pada ikon pin di tengah layar.
  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      setState(() => _isMapMoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Send Location',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          // FITUR: UI Peta Interaktif
          // FUNGSI: Menampilkan komponen FlutterMap dengan TileLayer dari OpenStreetMap yang merender peta secara visual.
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 16.0,
              onPositionChanged: _onMapPositionChanged,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nobox.chat',
              ),
            ],
          ),

          // Center pin (fixed in center of map)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(
                  0,
                  _isMapMoving ? -10 : 0,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 48,
                      color: Colors.red.shade600,
                      shadows: const [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black38,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    // Pin shadow dot
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isMapMoving ? 8 : 6,
                      height: _isMapMoving ? 4 : 3,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading indicator
          if (_isLoadingCurrentLocation)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Mendapatkan lokasi...'),
                    ],
                  ),
                ),
              ),
            ),

          // My location FAB
          Positioned(
            right: 16,
            bottom: 140,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),

          // Bottom card with coordinates & send button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Location info row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.location_on, color: Colors.green.shade600, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send this location',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedLocation.latitude.toStringAsFixed(5)}, ${_selectedLocation.longitude.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // FITUR: Tombol Konfirmasi Lokasi
                  // FUNGSI: Menutup halaman dan mengirimkan koordinat (LatLng) yang terakhir kali dipilih kembali ke halaman pemanggil (chat).
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.send, size: 20),
                      label: const Text(
                        'Send Location',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        Navigator.pop(context, _selectedLocation);
                      },
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
}
