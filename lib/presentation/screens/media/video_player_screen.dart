import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// =====================================================================
// FITUR: Pemutar Video Layar Penuh
// FILE: lib/presentation/screens/media/video_player_screen.dart
// BARIS AWAL: 9 (setelah komentar ini)
// FUNGSI: Menampilkan pemutar video kustom dengan kontrol play/pause, durasi, progress bar, dan fungsi mute.
// =====================================================================
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? caption;

  const VideoPlayerScreen({super.key, required this.videoUrl, this.caption});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideTimer;

  // For smooth progress tracking
  Timer? _progressTimer;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Animation for controls fade
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.value = 1.0; // start visible

    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _totalDuration = _controller.value.duration;
      });

      _controller.play();
      _startProgressTimer();
      _startHideTimer();

      _controller.addListener(_onPlayerUpdate);
    } catch (e) {
      debugPrint('Video Player Initialization Error: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    // Update when video completes
    if (!_controller.value.isPlaying &&
        _controller.value.position >= _controller.value.duration &&
        _controller.value.duration > Duration.zero) {
      _cancelHideTimer();
      _showControlsOverlay();
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _isInitialized) {
        setState(() {
          _currentPosition = _controller.value.position;
          _totalDuration = _controller.value.duration;
        });
      }
    });
  }

  void _startHideTimer() {
    _cancelHideTimer();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        _hideControlsOverlay();
      }
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _showControlsOverlay() {
    setState(() => _showControls = true);
    _fadeController.forward();
  }

  void _hideControlsOverlay() {
    _fadeController.reverse().then((_) {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onScreenTap() {
    if (_showControls) {
      _hideControlsOverlay();
    } else {
      _showControlsOverlay();
      if (_controller.value.isPlaying) {
        _startHideTimer();
      }
    }
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      _cancelHideTimer();
      _showControlsOverlay();
    } else {
      // If video ended, restart from beginning
      if (_controller.value.position >= _controller.value.duration &&
          _controller.value.duration > Duration.zero) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
      _startHideTimer();
    }
    setState(() {});
  }

  void _onSeekStart() {
    _cancelHideTimer();
  }

  void _onSeekEnd(double value) {
    final position = Duration(
      milliseconds: (value * _totalDuration.inMilliseconds).round(),
    );
    _controller.seekTo(position);
    if (_controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cancelHideTimer();
    _progressTimer?.cancel();
    _controller.removeListener(_onPlayerUpdate);
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // No AppBar — full-screen clean look
        body: GestureDetector(
          onTap: _onScreenTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── VIDEO ──
              Center(
                child: _hasError
                    ? _buildErrorWidget()
                    : _isInitialized
                    ? _buildVideoPlayer()
                    : _buildLoadingWidget(),
              ),

              // ── CONTROLS OVERLAY ──
              if (_showControls && _isInitialized)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Semi-transparent scrim
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.5),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                            stops: const [0.0, 0.2, 0.75, 1.0],
                          ),
                        ),
                      ),

                      // ── TOP: Back button + share ──
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                  onPressed: () {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    Navigator.pop(context);
                                  },
                                ),
                                const Expanded(
                                  child: Text(
                                    'Video',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.share,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    // Share action placeholder
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── CENTER: Play/Pause button ──
                      Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),

                      // ── BOTTOM: Progress bar + timestamps ──
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          top: false,
                          child: _buildBottomControls(),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── CAPTION (always visible at bottom when controls hidden) ──
              if (widget.caption != null &&
                  widget.caption!.isNotEmpty &&
                  !_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Text(
                        widget.caption!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the video player widget with proper rotation handling.
  /// Wraps VideoPlayer in FittedBox to handle camera rotation metadata
  /// (90°/270°) without distorting the video.
  Widget _buildVideoPlayer() {
    final value = _controller.value;
    final rotation = value.rotationCorrection;
    final isRotated = rotation == 90 || rotation == 270;
    final displayWidth = isRotated ? value.size.height : value.size.width;
    final displayHeight = isRotated ? value.size.width : value.size.height;
    final aspectRatio = displayHeight > 0 ? displayWidth / displayHeight : 1.0;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: value.size.width,
          height: value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final progress = _totalDuration.inMilliseconds > 0
        ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Caption (shown with controls)
        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              widget.caption!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Timestamps row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_currentPosition),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Mute button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.setVolume(
                      _controller.value.volume > 0 ? 0.0 : 1.0,
                    );
                  });
                },
                child: Icon(
                  _controller.value.volume > 0
                      ? Icons.volume_up
                      : Icons.volume_off,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(_totalDuration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 2),

        // Slim seek bar
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6,
                elevation: 2,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: progress,
              onChangeStart: (_) => _onSeekStart(),
              onChanged: (value) {
                final position = Duration(
                  milliseconds: (value * _totalDuration.inMilliseconds).round(),
                );
                setState(() => _currentPosition = position);
              },
              onChangeEnd: _onSeekEnd,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading video...',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
        const SizedBox(height: 16),
        const Text(
          'Gagal memuat video.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _hasError = false;
              _isInitialized = false;
            });
            _initializePlayer();
          },
          icon: const Icon(Icons.refresh, color: Colors.white),
          label: const Text('Coba lagi', style: TextStyle(color: Colors.white)),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        const SizedBox(height: 48),
        // Back button for error state
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
