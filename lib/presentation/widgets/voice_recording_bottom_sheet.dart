import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

// =====================================================================
// FITUR: Perekam Suara Bawah (Voice Note)
// FILE: lib/presentation/widgets/voice_recording_bottom_sheet.dart
// BARIS AWAL: 6 (setelah komentar ini)
// FUNGSI: Menampilkan antarmuka untuk merekam, memutar ulang, dan mengirim voice note.
// =====================================================================
class VoiceRecordingBottomSheet extends StatefulWidget {
  final int initialSeconds;
  final bool isRecording;
  final bool isPaused;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final Future<String?> Function() onStop;
  final VoidCallback onDelete;
  final VoidCallback onReRecord;
  final Function(String path, int duration) onSend;
  final AudioPlayer audioPlayer;

  const VoiceRecordingBottomSheet({
    super.key,
    required this.initialSeconds,
    required this.isRecording,
    required this.isPaused,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onDelete,
    required this.onReRecord,
    required this.onSend,
    required this.audioPlayer,
  });

  @override
  State<VoiceRecordingBottomSheet> createState() =>
      _VoiceRecordingBottomSheetState();
}

class _VoiceRecordingBottomSheetState extends State<VoiceRecordingBottomSheet>
    with SingleTickerProviderStateMixin {
  late int _seconds;
  late bool _isRecording;
  late bool _isPaused;
  bool _isReady = false;
  String? _recordedPath;

  // Animation for pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Audio Player state for "Ready" state
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _compSub;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
    _isRecording = widget.isRecording;
    _isPaused = widget.isPaused;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Timer for UI sync
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isRecording && !_isPaused) {
        setState(() => _seconds++);
      }
    });

    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    widget.audioPlayer.setVolume(1.0);

    _posSub = widget.audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        if (_duration > Duration.zero && p >= _duration) {
          widget.audioPlayer.pause();
          setState(() {
            _position = Duration.zero;
            _isPlaying = false;
          });
          return;
        }
        setState(() => _position = p);
      }
    });
    _durSub = widget.audioPlayer.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) {
        Duration resolved = d;
        if (_seconds > 0) {
          final diffMs = (_seconds * 1000 - d.inMilliseconds).abs();
          if (diffMs <= 1500) {
            resolved = Duration(seconds: _seconds);
          }
        }
        setState(() => _duration = resolved);
      }
    });
    _compSub = widget.audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        if (_duration > const Duration(seconds: 2) &&
            _position < _duration - const Duration(milliseconds: 1000)) {
          return;
        }
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    _compSub?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _handleStop() async {
    final path = await widget.onStop();
    if (path != null) {
      setState(() {
        _isRecording = false;
        _isReady = true;
        _recordedPath = path;
        _duration = Duration(seconds: _seconds);
      });
    }
  }

  Future<void> _handlePlayPause() async {
    if (_recordedPath == null) return;
    if (_isPlaying) {
      await widget.audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await widget.audioPlayer.play(DeviceFileSource(_recordedPath!));
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C34) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(isDark),
          const SizedBox(height: 32),
          if (!_isReady)
            _buildRecordingState(isDark)
          else
            _buildReadyState(isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _isReady ? 'Voice Note Ready' : 'Recording Voice Note',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.grey.shade400 : Colors.grey,
          ),
          onPressed: () {
            widget.onDelete();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  // [ACTION: RECORD_VOICE] - Menampilkan animasi dan timer perekaman
  Widget _buildRecordingState(bool isDark) {
    return Column(
      children: [
        // Pulse Mic Container (sudah memiliki background merah transparan yang kontras)
        ScaleTransition(
          scale: _isPaused
              ? const AlwaysStoppedAnimation(1.0)
              : _pulseAnimation,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(_isPaused ? 0.3 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _formatDuration(_seconds),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: Icons.delete_outline,
              color: Colors.red,
              onPressed: () {
                widget.onDelete();
                Navigator.pop(context);
              },
            ),
            _buildActionButton(
              icon: _isPaused ? Icons.play_arrow : Icons.pause,
              color: Colors.amber,
              onPressed: () {
                if (_isPaused) {
                  widget.onResume();
                  setState(() => _isPaused = false);
                } else {
                  widget.onPause();
                  setState(() => _isPaused = true);
                }
              },
            ),
            _buildActionButton(
              icon: Icons.stop,
              color: isDark ? const Color(0xFF60A5FA) : Colors.blue,
              onPressed: _handleStop,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyState(bool isDark) {
    return Column(
      children: [
        // Audio Player Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.12)
                  : Colors.blue.withOpacity(0.1),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    color: isDark ? const Color(0xFF60A5FA) : Colors.blue,
                    onPressed: _handlePlayPause,
                  ),
                  Expanded(
                    child: Slider(
                      activeColor: isDark
                          ? const Color(0xFF60A5FA)
                          : Colors.blue,
                      inactiveColor: isDark
                          ? Colors.grey.shade700
                          : Colors.blue.shade100,
                      value: _position.inMilliseconds.toDouble().clamp(
                        0,
                        _duration.inMilliseconds.toDouble(),
                      ),
                      max: _duration.inMilliseconds.toDouble(),
                      onChanged: (v) async {
                        await widget.audioPlayer.seek(
                          Duration(milliseconds: v.toInt()),
                        );
                      },
                    ),
                  ),
                  Text(
                    _formatDuration(
                      ((_seconds > 0 ? _seconds : _duration.inSeconds) -
                              _position.inSeconds)
                          .clamp(0, 999),
                    ),
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _formatDuration(_seconds),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey.shade400 : Colors.grey,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF60A5FA) : Colors.blue,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  widget.onReRecord();
                  setState(() {
                    _isRecording = true;
                    _isReady = false;
                    _seconds = 0;
                    _isPaused = false;
                    _recordedPath = null;
                  });
                },
                child: Text(
                  'Re-record',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF60A5FA) : Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_recordedPath != null) {
                    widget.onSend(_recordedPath!, _seconds);
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  'Send',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
