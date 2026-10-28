import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

// =====================================================================
// FITUR: Layar Pratinjau File
// FILE: lib/presentation/screens/chat/file_preview_screen.dart
// FUNGSI: Menampilkan pratinjau media (foto, video, dokumen) secara
//         full-screen sebelum file tersebut dikirim ke ruang obrolan.
// =====================================================================

/// Tipe file yang didukung oleh preview screen.
enum FilePreviewType { photo, video, document }

/// Full-screen preview sebelum mengirim file.
///
/// Menampilkan preview yang adaptif berdasarkan [fileType]:
/// - **photo**: Gambar full-screen dengan InteractiveViewer (pinch-to-zoom).
/// - **video**: Thumbnail dengan play button, tap untuk memutar video.
/// - **document**: Nama file, ukuran file, dan icon dokumen.
///
/// Return value: `true` jika user menekan Send, `false`/`null` jika Cancel.
class FilePreviewScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final FilePreviewType fileType;

  const FilePreviewScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.fileType,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  // Video preview state — Two states:
  //   Initial: thumbnail + play overlay + "Tap to preview" label
  //   Active:  full video player with controls (progress, volume, fullscreen)
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  bool _videoActiveMode = false; // false = Initial, true = Active
  Uint8List? _videoThumbnail;
  bool _isLoadingThumbnail = true;

  // Video controls state (Active mode only)
  bool _isMuted = false;
  bool _showControls = true;
  Timer? _controlsTimer;
  Duration _videoPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;

  // Document file size
  String _fileSizeLabel = '';

  @override
  void initState() {
    super.initState();
    if (widget.fileType == FilePreviewType.video) {
      _loadVideoThumbnail();
    } else if (widget.fileType == FilePreviewType.document) {
      _calculateFileSize();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    super.dispose();
  }

  // FITUR: Generate Thumbnail Video
  // FUNGSI: Menggunakan pustaka video_thumbnail untuk mengekstrak frame gambar pertama dari file video lokal agar bisa ditampilkan sebelum video diputar.
  Future<void> _loadVideoThumbnail() async {
    try {
      final thumbnailData = await vt.VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );
      if (mounted) {
        setState(() {
          _videoThumbnail = thumbnailData;
          _isLoadingThumbnail = false;
        });
      }
    } catch (e) {
      debugPrint('FilePreviewScreen: Error generating thumbnail: $e');
      if (mounted) {
        setState(() => _isLoadingThumbnail = false);
      }
    }
  }

  // FITUR: Inisialisasi Player Video
  // FUNGSI: Memulai instansiasi VideoPlayerController untuk membaca file video secara penuh saat pengguna menekan tombol play pertama kalinya.
  Future<void> _activateVideoPlayer() async {
    if (_videoActiveMode) return; // Already active

    _videoController = VideoPlayerController.file(File(widget.filePath));
    try {
      await _videoController?.initialize();
      _videoController?.addListener(_onVideoUpdate);
      await _videoController?.play();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoPlaying = true;
          _videoActiveMode = true;
          _videoDuration = _videoController?.value.duration ?? Duration.zero;
        });
        _startControlsAutoHide();
      }
    } catch (e) {
      debugPrint('FilePreviewScreen: Error initializing video: $e');
    }
  }

  // FITUR: Toggle Play/Pause Video
  // FUNGSI: Mengganti status putar dan jeda pada video controller yang aktif.
  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;
    if (_videoController?.value.isPlaying == true) {
      _videoController?.pause();
    } else {
      _videoController?.play();
    }
  }

  // FITUR: Listener Status Video (Durasi & Posisi)
  // FUNGSI: Memantau dan memperbarui UI berdasarkan posisi durasi video (progress bar) dan status 'isPlaying' secara real-time.
  void _onVideoUpdate() {
    if (!mounted || _videoController == null) return;
    final value = _videoController?.value;
    if (value == null) return;
    final playing = value.isPlaying;
    final pos = value.position;
    final dur = value.duration;
    if (playing != _isVideoPlaying ||
        pos != _videoPosition ||
        dur != _videoDuration) {
      setState(() {
        _isVideoPlaying = playing;
        _videoPosition = pos;
        _videoDuration = dur;
      });
    }
  }

  /// Auto-hide controls after 3 seconds of playback.
  void _startControlsAutoHide() {
    _controlsTimer?.cancel();
    if (_isVideoPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isVideoPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  /// Tap on video area toggles controls visibility.
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startControlsAutoHide();
    }
  }

  /// Toggle mute/unmute.
  void _toggleMute() {
    if (_videoController == null) return;
    setState(() => _isMuted = !_isMuted);
    _videoController?.setVolume(_isMuted ? 0.0 : 1.0);
  }

  /// Open fullscreen video player overlay.
  void _openFullscreen() {
    if (_videoController == null || !_isVideoInitialized) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenVideoOverlay(controller: _videoController!);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Format Duration as "mm:ss".
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Calculate and format file size for document preview.
  void _calculateFileSize() {
    try {
      final file = File(widget.filePath);
      final sizeBytes = file.lengthSync();
      if (sizeBytes < 1024) {
        _fileSizeLabel = '$sizeBytes B';
      } else if (sizeBytes < 1024 * 1024) {
        _fileSizeLabel = '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
      } else {
        _fileSizeLabel = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (e) {
      _fileSizeLabel = '';
    }
  }

  /// Label untuk AppBar title dan button text.
  String get _typeLabel {
    switch (widget.fileType) {
      case FilePreviewType.photo:
        return 'Photo';
      case FilePreviewType.video:
        return 'Video';
      case FilePreviewType.document:
        return 'Document';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          'Send $_typeLabel',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Preview Area ──
            Expanded(child: Center(child: _buildPreviewBody())),

            // ── Send Button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  label: Text(
                    'Send $_typeLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the main preview content based on file type.
  Widget _buildPreviewBody() {
    switch (widget.fileType) {
      case FilePreviewType.photo:
        return _buildPhotoPreview();
      case FilePreviewType.video:
        return _buildVideoPreview();
      case FilePreviewType.document:
        return _buildDocumentPreview();
    }
  }

  // ─────────────────────────────────────────────
  //  PHOTO PREVIEW
  // ─────────────────────────────────────────────

  Widget _buildPhotoPreview() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.file(
        File(widget.filePath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              const SizedBox(height: 12),
              Text(
                'Unable to load image',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  VIDEO PREVIEW
  // ─────────────────────────────────────────────

  /// Helper: calculate the true display aspect ratio accounting for
  /// camera rotation metadata (90°/270° swaps width and height).
  double _getVideoAspectRatio(VideoPlayerController? controller) {
    if (controller == null || !controller.value.isInitialized) return 16 / 9;
    final size = controller.value.size;
    final rotation = controller.value.rotationCorrection;
    if (size.width == 0 || size.height == 0) return 1.0;
    // If video is rotated 90° or 270° by phone camera metadata, swap width & height
    final isRotated = rotation == 90 || rotation == 270;
    final width = isRotated ? size.height : size.width;
    final height = isRotated ? size.width : size.height;
    return width / height;
  }

  Widget _buildVideoPreview() {
    // ── Initial State: thumbnail + play overlay ──
    if (!_videoActiveMode) {
      return _buildVideoInitialState();
    }
    // ── Active State: full video player with controls ──
    return _buildVideoActiveState();
  }

  /// Initial State — static thumbnail with play button and label.
  Widget _buildVideoInitialState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail area with play overlay — flexible aspect ratio
            GestureDetector(
              onTap: _activateVideoPlayer,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 450),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Thumbnail or placeholder — use BoxFit.contain to preserve original ratio
                    if (_videoThumbnail != null)
                      Image.memory(
                        _videoThumbnail!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      )
                    else
                      Container(height: 250, color: Colors.black),

                    // Loading spinner
                    if (_isLoadingThumbnail)
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),

                    // Play button overlay
                    if (!_isLoadingThumbnail)
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom info bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black,
              child: Row(
                children: [
                  Icon(Icons.movie, color: Colors.grey[400], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Video Preview',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to preview',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active State — full video player with controls overlay.
  Widget _buildVideoActiveState() {
    final totalMs = _videoDuration.inMilliseconds.toDouble();
    final currentMs = _videoPosition.inMilliseconds.toDouble().clamp(
      0.0,
      totalMs,
    );
    final aspect = _getVideoAspectRatio(_videoController);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspect,
          child: GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Video player — wrapped in FittedBox to handle rotation correction
                Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),

                // Controls overlay with fade animation
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showControls ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Column(
                        children: [
                          const Spacer(),

                          // Center play/pause button
                          GestureDetector(
                            onTap: () {
                              _togglePlayPause();
                              _startControlsAutoHide();
                            },
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isVideoPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Bottom control bar
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.7),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Progress slider
                                SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                    activeTrackColor: const Color(0xFF4A90E2),
                                    inactiveTrackColor: Colors.white.withValues(
                                      alpha: 0.3,
                                    ),
                                    thumbColor: const Color(0xFF4A90E2),
                                    overlayColor: const Color(
                                      0xFF4A90E2,
                                    ).withValues(alpha: 0.2),
                                  ),
                                  child: Slider(
                                    value: totalMs > 0
                                        ? currentMs / totalMs
                                        : 0.0,
                                    onChanged: (value) {
                                      _controlsTimer?.cancel();
                                      final newPosition = Duration(
                                        milliseconds: (value * totalMs).round(),
                                      );
                                      _videoController?.seekTo(newPosition);
                                    },
                                    onChangeEnd: (_) =>
                                        _startControlsAutoHide(),
                                  ),
                                ),

                                // Time labels + action buttons
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      // Current time
                                      Text(
                                        _formatDuration(_videoPosition),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '/',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Duration
                                      Text(
                                        _formatDuration(_videoDuration),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const Spacer(),
                                      // Volume toggle
                                      GestureDetector(
                                        onTap: _toggleMute,
                                        child: Icon(
                                          _isMuted
                                              ? Icons.volume_off
                                              : Icons.volume_up,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Fullscreen toggle
                                      GestureDetector(
                                        onTap: _openFullscreen,
                                        child: const Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DOCUMENT PREVIEW
  // ─────────────────────────────────────────────

  Widget _buildDocumentPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File info header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                children: [
                  Text(
                    widget.fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_fileSizeLabel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _fileSizeLabel,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),

            // Document icon area
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description,
                  color: Color(0xFF4A90E2),
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  FULLSCREEN VIDEO OVERLAY
// ═══════════════════════════════════════════════

/// Landscape fullscreen video overlay.
/// Reuses the existing [VideoPlayerController] from the parent — no re-initialization.
class _FullscreenVideoOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullscreenVideoOverlay({required this.controller});

  @override
  State<_FullscreenVideoOverlay> createState() =>
      _FullscreenVideoOverlayState();
}

class _FullscreenVideoOverlayState extends State<_FullscreenVideoOverlay> {
  bool _showControls = true;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    // Force landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.controller.addListener(_onUpdate);
    _startAutoHide();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    widget.controller.removeListener(_onUpdate);
    // Restore portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _startAutoHide() {
    _autoHideTimer?.cancel();
    if (widget.controller.value.isPlaying) {
      _autoHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && widget.controller.value.isPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final totalMs = value.duration.inMilliseconds.toDouble();
    final currentMs = value.position.inMilliseconds.toDouble().clamp(
      0.0,
      totalMs,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startAutoHide();
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 1.0,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: value.size.width,
                    height: value.size.height,
                    child: VideoPlayer(widget.controller),
                  ),
                ),
              ),
            ),

            // Controls
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    // Center play/pause
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (value.isPlaying) {
                            widget.controller.pause();
                          } else {
                            widget.controller.play();
                          }
                          _startAutoHide();
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),

                    // Top bar — exit fullscreen
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen_exit,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),

                    // Bottom progress bar
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Row(
                        children: [
                          Text(
                            _fmt(value.position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                activeTrackColor: const Color(0xFF4A90E2),
                                inactiveTrackColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                                thumbColor: const Color(0xFF4A90E2),
                              ),
                              child: Slider(
                                value: totalMs > 0 ? currentMs / totalMs : 0.0,
                                onChanged: (v) {
                                  _autoHideTimer?.cancel();
                                  widget.controller.seekTo(
                                    Duration(
                                      milliseconds: (v * totalMs).round(),
                                    ),
                                  );
                                },
                                onChangeEnd: (_) => _startAutoHide(),
                              ),
                            ),
                          ),
                          Text(
                            _fmt(value.duration),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
