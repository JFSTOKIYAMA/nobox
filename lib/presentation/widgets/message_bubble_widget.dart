 // =====================================================================
// FITUR 4: Detail Ruang Obrolan (Message Bubble Widget)
// TUJUAN: Mengelola antarmuka visual satu gelembung pesan, termasuk teks, media, jam pengiriman, dan indikator centang baca.
// CARA KERJA: Centang dipetakan berdasarkan status ack: 1 (Abu 1), 2 (Abu 2), 3 (Biru 2).
// =====================================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../../core/model/message.dart';
import '../../../core/providers/theme_provider.dart';
import '../screens/media/image_viewer_screen.dart';
import '../screens/media/image_gallery_viewer_screen.dart';
import '../screens/media/video_player_screen.dart';
import 'forward_dialog.dart';
import 'audio_player_widget.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/chat_settings_provider.dart';
import '../../../core/utils/date_time_helper.dart';

import '../../../core/theme/app_theme.dart';

// =====================================================================
// FITUR: Komponen Balon Chat
// FILE: lib/presentation/widgets/message_bubble_widget.dart
// BARIS AWAL: 23 (setelah komentar ini)
// FUNGSI: Widget utama yang merender setiap pesan di ruang obrolan (teks, gambar, video, dokumen).
// =====================================================================
class MessageBubbleWidget extends StatefulWidget {
  final Message message;
  final List<Message>? allMessages;
  final bool showSenderInfo;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  const MessageBubbleWidget({
    super.key,
    required this.message,
    this.allMessages,
    this.showSenderInfo = true,
    this.isSelected = false,
    this.onLongPress,
    this.onTap,
    this.onReply,
    this.onForward,
    this.onCopy,
    this.onDelete,
  });

  @override
  State<MessageBubbleWidget> createState() => _MessageBubbleWidgetState();
}

class _MessageBubbleWidgetState extends State<MessageBubbleWidget>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  static const double _maxDragDistance = 80.0;
  static const double _replyThreshold = 60.0;
  late AnimationController _resetAnimationController;
  late Animation<double> _resetAnimation;
  bool _hasTriggeredHaptic = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _resetAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _resetAnimation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _resetAnimationController,
        curve: Curves.easeOutCubic,
      ),
    )..addListener(() {
        setState(() {
          _dragPosition = _resetAnimation.value;
        });
      });
  }

  @override
  void dispose() {
    _resetAnimationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _resetAnimationController.stop();
    setState(() {
      _isDragging = true;
      _hasTriggeredHaptic = false;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    setState(() {
      double newPosition = _dragPosition + details.delta.dx;
      if (newPosition < 0) newPosition = 0;

      if (newPosition > _replyThreshold) {
        final excess = newPosition - _replyThreshold;
        final resistance =
            1 - (excess / (_maxDragDistance - _replyThreshold)) * 0.5;
        newPosition = _replyThreshold + (excess * resistance);
      }

      if (newPosition > _maxDragDistance) newPosition = _maxDragDistance;

      _dragPosition = newPosition;

      if (_dragPosition >= _replyThreshold && !_hasTriggeredHaptic) {
        HapticFeedback.lightImpact();
        _hasTriggeredHaptic = true;
      } else if (_dragPosition < _replyThreshold && _hasTriggeredHaptic) {
        _hasTriggeredHaptic = false;
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDragging = false;

    if (_dragPosition >= _replyThreshold && widget.onReply != null) {
      HapticFeedback.mediumImpact();
      widget.onReply!();
    }

    _resetAnimation = Tween<double>(
      begin: _dragPosition,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _resetAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _resetAnimationController.forward(from: 0);
    _hasTriggeredHaptic = false;
  }

  void _onHorizontalDragCancel() {
    _isDragging = false;
    _resetAnimation = Tween<double>(
      begin: _dragPosition,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _resetAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _resetAnimationController.forward(from: 0);
    _hasTriggeredHaptic = false;
  }

  String _cleanContent(String content) {
    return content.trim();
  }

  bool _isLocationMessage(String content) {
    return content.contains('Location:') ||
        content.contains('maps.google.com') ||
        content.contains('maps.app.goo.gl') ||
        content.contains('📍 Lokasi') ||
        content.contains('[-{=||=}-]');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    if (widget.message.isSystemMessage) {
      return _buildSystemMessage(context, isDarkMode);
    }

    final isMe = widget.message.isMe;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHorizontalDragStart:
          widget.onReply != null ? _onHorizontalDragStart : null,
      onHorizontalDragUpdate:
          widget.onReply != null ? _onHorizontalDragUpdate : null,
      onHorizontalDragEnd: widget.onReply != null ? _onHorizontalDragEnd : null,
      onHorizontalDragCancel:
          widget.onReply != null ? _onHorizontalDragCancel : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Stack(
          children: [
            if (_dragPosition > 5)
              Positioned(
                right: isMe ? null : 16,
                left: isMe ? 16 : null,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedScale(
                    scale: (_dragPosition / _maxDragDistance).clamp(0.5, 1.0),
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      opacity:
                          (_dragPosition / _replyThreshold).clamp(0.3, 1.0),
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_dragPosition >= _replyThreshold
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade500)
                              .withOpacity(
                                  _dragPosition >= _replyThreshold ? 0.25 : 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.reply_rounded,
                          color: _dragPosition >= _replyThreshold
                              ? AppTheme.primaryColor
                              : Colors.grey.shade600,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragPosition, 0, 0),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          child: Builder(
                            builder: (context) {
                              final isNoBubble = _isStickerMessage(widget.message);
                              final isMedia = !isNoBubble && (widget.message.messageType == MessageType.image || widget.message.messageType == MessageType.video || _hasVideoUrl(widget.message));
                              return Container(
                                padding: isNoBubble
                                    ? EdgeInsets.zero
                                    : (isMedia 
                                        ? const EdgeInsets.all(4) 
                                        : (widget.message.repliedMessage != null
                                            ? const EdgeInsets.only(top: 4, bottom: 6) 
                                            : const EdgeInsets.symmetric(horizontal: 10, vertical: 6))),
                                decoration: isNoBubble
                                    ? null
                                    : BoxDecoration(
                                        color: isMe
                                            ? (isDarkMode ? const Color(0xFF0B2641) : AppTheme.primaryColor)
                                            : (isDarkMode
                                                ? AppTheme.darkSurface
                                                : Colors.white),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(12),
                                          topRight: const Radius.circular(12),
                                          bottomLeft: Radius.circular(isMe ? 12 : 2),
                                          bottomRight: Radius.circular(isMe ? 2 : 12),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                                isDarkMode ? 0.3 : 0.08),
                                            blurRadius: 1,
                                            offset: const Offset(0, 0.5),
                                          ),
                                        ],
                                      ),
                                child: Builder(
                                  builder: (context) {
                                    final content = Column(
                                      crossAxisAlignment: widget.message.repliedMessage != null
                                          ? CrossAxisAlignment.stretch
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (widget.message.repliedMessage != null)
                                          _buildReplyPreview(context, isMe, isDarkMode),
                                        Padding(
                                          padding: (widget.message.repliedMessage != null && !isMedia)
                                              ? const EdgeInsets.symmetric(horizontal: 10)
                                              : EdgeInsets.zero,
                                          child: _buildMessageContent(context, isMe, isDarkMode),
                                        ),
                                      ],
                                    );
                                    
                                    if (widget.message.repliedMessage != null) {
                                      return IntrinsicWidth(child: content);
                                    }
                                    return content;
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context, bool isDarkMode) {
    final cleanMessage = _cleanContent(widget.message.content);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              height: 1,
              color: isDarkMode
                  ? Colors.white.withOpacity(0.2)
                  : Colors.grey.shade300,
            ),
          ),
          Flexible(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cleanMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? AppTheme.darkTextSecondary
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.message.time, // Using the formatted time directly
                    style: TextStyle(
                      fontSize: 10,
                      color: isDarkMode
                          ? AppTheme.darkTextSecondary.withOpacity(0.7)
                          : Colors.grey.shade400,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              height: 1,
              color: isDarkMode
                  ? Colors.white.withOpacity(0.2)
                  : Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestampRow(bool isMe) {
    final chatSettings = context.watch<ChatSettingsProvider>();
    final displayTime = DateTimeHelper.formatTime(
      widget.message.rawTime,
      chatSettings.timeFormat,
      fallback: widget.message.time,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          displayTime,
          style: TextStyle(
            fontSize: 11,
            color: isMe ? Colors.white70 : AppTheme.textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildAckIcon(),
        ],
      ],
    );
  }

  Widget _buildReplyPreview(BuildContext context, bool isMe, bool isDarkMode) {
    final repliedMsg = widget.message.repliedMessage;
    if (repliedMsg == null) return const SizedBox.shrink();

    final replyContent = _cleanContent(repliedMsg.content);
    
    // Cari pesan asli di daftar pesan untuk memastikan status isMe akurat
    Message? originalMsg;
    if (widget.allMessages != null) {
      try {
        originalMsg = widget.allMessages!.firstWhere((m) => m.id == repliedMsg.id);
      } catch (_) {}
    }
    
    final isRepliedMe = originalMsg?.isMe ?? repliedMsg.isMe;
    final replySender = isRepliedMe ? 'You' : 'Customer';

    return Container(
      margin: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      constraints: const BoxConstraints(minWidth: 140), // Mencegah kotak reply terlalu kecil/sempit
      decoration: BoxDecoration(
        color: isMe
            ? Colors.black.withOpacity(0.15) // Darker overlay for blue bubble
            : (isDarkMode
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(8),
        border: isMe 
            ? null
            : const Border(
                left: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 4),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.reply,
                size: 14,
                color: isMe
                    ? Colors.white.withOpacity(0.9)
                    : AppTheme.primaryColor,
              ),
              const SizedBox(width: 4),
              Text(
                'Reply to:',
                style: TextStyle(
                  fontSize: 11,
                  color: isMe
                      ? Colors.white.withOpacity(0.7)
                      : AppTheme.primaryColor.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            replySender,
            style: TextStyle(
              fontSize: 13,
              color: isMe
                  ? Colors.white
                  : AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            replyContent,
            style: TextStyle(
              fontSize: 13,
              color: isMe
                  ? Colors.white.withOpacity(0.9)
                  : (isDarkMode
                      ? AppTheme.darkTextPrimary
                      : Colors.black87),
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  bool _isStickerMessage(Message msg) {
    if (msg.messageType == MessageType.sticker) return true;
    final url = (msg.imageUrl ?? msg.videoUrl ?? msg.documentUrl ?? msg.imagePath ?? msg.documentName ?? '').toLowerCase();
    if (url.isNotEmpty && (url.contains('.webm') || url.contains('.tgs') || url.contains('.webp') || url.contains('.ezgif'))) {
      return true;
    }
    return false;
  }

  Widget _buildMessageContent(BuildContext context, bool isMe, bool isDarkMode) {
    if (_isLocationMessage(widget.message.content)) {
      return _buildLocationMessage(isMe, isDarkMode);
    }

    // Pengecekan stiker MUTLAK HARUS DIATAS pengecekan video
    if (_isStickerMessage(widget.message)) {
      return _buildStickerMessage(isMe, isDarkMode);
    }

    // Video detection: check content text, messageType, AND URL extension (tanpa .webm stiker)
    if (widget.message.content.contains('🎬 Video') ||
        widget.message.content.contains('🎬 Video') ||
        widget.message.content.contains('🎬 Video') ||
        widget.message.messageType == MessageType.video ||
        _hasVideoUrl(widget.message)) {
       return _buildVideoMessage(context, isMe, isDarkMode);
    }

    switch (widget.message.messageType) {
      case MessageType.text:
        return _buildTextMessage(isMe, isDarkMode);
      case MessageType.voice:
        return _buildAudioMessage(isMe, isDarkMode);
      case MessageType.image:
        return _buildImageMessage(context, isMe, isDarkMode);
      case MessageType.document:
        return _buildDocumentMessage(isMe, isDarkMode);
      case MessageType.sticker:
        return _buildStickerMessage(isMe, isDarkMode);
      default:
        return _buildTextMessage(isMe, isDarkMode);
    }
  }

  /// Check if the message has a video file URL (by extension), even if
  /// messageType was misdetected as image by the server.
  bool _hasVideoUrl(Message msg) {
    if (_isStickerMessage(msg)) return false;
    final url = (msg.imageUrl ?? msg.videoUrl ?? '').toLowerCase();
    if (url.isEmpty) return false;
    const videoExts = ['.mp4', '.mov', '.avi', '.mkv', '.3gp'];
    return videoExts.any((ext) => url.contains(ext));
  }

  Widget _buildTextMessage(bool isMe, bool isDarkMode) {
    final cleanMessage = _cleanContent(widget.message.content);
    final hasReply = widget.message.repliedMessage != null;

    final lines = cleanMessage.split('\n');
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(lines.length, (index) {
        final textToRender = lines[index].isEmpty ? '\u200B' : lines[index];
        return _buildTextWithLinks(
          textToRender,
          isMe,
          isDarkMode,
        );
      }),
    );

    if (hasReply) {
      return IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            textColumn,
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildTimestampRow(isMe),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2.0, bottom: 2.0, right: 4.0),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8.0, // Space between text and timestamp if on same line
        children: [
          textColumn,
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: _buildTimestampRow(isMe),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerMessage(bool isMe, bool isDarkMode) {
    final imageUrl = widget.message.imageUrl ?? widget.message.videoUrl ?? '';
    final lowerUrl = imageUrl.toLowerCase();
    final isAnimatedVideoSticker = lowerUrl.contains('.webm') || lowerUrl.contains('.mp4') || lowerUrl.contains('.mov');

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 180,
            maxHeight: 180,
          ),
          child: imageUrl.isNotEmpty
              ? (isAnimatedVideoSticker
                  ? AnimatedVideoSticker(url: imageUrl)
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(
                        width: 100,
                        height: 100,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.emoji_emotions_outlined, size: 48, color: Colors.grey),
                        ),
                      ),
                    ))
              : Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.emoji_emotions_outlined, size: 48, color: Colors.grey),
                  ),
                ),
        ),
        const SizedBox(height: 2),
        _buildTimestampRow(isMe),
      ],
    );
  }

  Widget _buildDocumentMessage(bool isMe, bool isDarkMode) {
    // Extract file name and extension from documentName or content
    final fileName = widget.message.documentName ??
        widget.message.content.replaceAll('📄 ', '').trim();
    final ext = fileName.contains('.')
        ? '.${fileName.split('.').last.toLowerCase()}'
        : '';
        
    final cleanMessage = _cleanContent(widget.message.content);
    // Jika content bukan nama file (alias pesan email/teks), kita tampilkan sebagai caption
    final hasCaption = cleanMessage.isNotEmpty && !cleanMessage.contains(fileName) && !cleanMessage.startsWith('📄 ');

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width * 0.65,
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.15)
                : (isDarkMode
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File icon container
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withOpacity(0.2)
                      : (isDarkMode
                          ? AppTheme.primaryColor.withOpacity(0.2)
                          : AppTheme.primaryColor.withOpacity(0.12)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.insert_drive_file,
                  color: isMe
                      ? Colors.white
                      : AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              // File name + extension
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        color: isMe
                            ? Colors.white
                            : (isDarkMode
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Document${ext.isNotEmpty ? ' • ${ext.toUpperCase().replaceAll('.', '')}' : ''}',
                      style: TextStyle(
                        color: isMe
                            ? Colors.white70
                            : (isDarkMode
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasCaption) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: _buildTextWithLinks(cleanMessage, isMe, isDarkMode),
          ),
        ],
        const SizedBox(height: 4),
        _buildTimestampRow(isMe),
      ],
    );
  }

  Widget _buildTextWithLinks(String text, bool isMe, bool isDarkMode, {Widget? trailing}) {
    final urlRegex =
        RegExp(r'https?://[^\s]+|www\.[^\s]+', caseSensitive: false);
    final matches = urlRegex.allMatches(text);

    final List<InlineSpan> spans = [];
    int currentIndex = 0;

    final defaultStyle = TextStyle(
      color: isMe
          ? Colors.white
          : (isDarkMode ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
      fontSize: 16,
      height: 1.3,
    );

    if (matches.isEmpty) {
      spans.add(TextSpan(text: text, style: defaultStyle));
    } else {

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
          style: TextStyle(
            color: isMe
                ? Colors.white
                : (isDarkMode
                    ? AppTheme.darkTextPrimary
                    : AppTheme.textPrimary),
            fontSize: 16,
            height: 1.3,
          ),
        ));
      }

      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: isMe ? Colors.white : Colors.blue,
          fontSize: 16,
          height: 1.3,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchURL(url),
      ));

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: defaultStyle,
      ));
    }
    }

    if (trailing != null) {
      // Tambahkan spasi kecil dan widget timestamp di akhir baris teks
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle, // Gunakan middle agar posisinya turun ke tengah baris
        child: Transform.translate(
          offset: const Offset(0, 2), // Tambahan sedikit ke bawah agar sejajar sempurna
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: trailing,
          ),
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Future<void> _launchURL(String url) async {
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    final uri = Uri.parse(finalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      print('Could not launch $finalUrl');
    }
  }

  Widget _buildImageMessage(BuildContext context, bool isMe, bool isDarkMode) {
    final imageUrl = widget.message.imageUrl;
    String caption = widget.message.content;
    if (caption == '📷 Photo') caption = '';
    
    final hasCaption = caption.isNotEmpty;
    final maxW = MediaQuery.of(context).size.width * 0.65; // 65% lebar layar
    final maxH = 400.0; // tinggi maksimal dinaikkan agar foto potret tidak gepeng/terpotong

    Widget _buildErrorImage(bool isMe, bool isDarkMode) {
      return Container(
        width: 200,
        height: 200,
        color: isMe
            ? Colors.white.withOpacity(0.2)
            : (isDarkMode ? Colors.grey[800] : Colors.grey.shade200),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image,
                size: 48,
                color: isMe ? Colors.white70 : Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Failed to load image',
              style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey,
                  fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final hasLocalPath = widget.message.imagePath != null && 
                         widget.message.imagePath!.isNotEmpty && 
                         File(widget.message.imagePath!).existsSync();

    if ((imageUrl == null || imageUrl.isEmpty) && !hasLocalPath) {
      return IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withOpacity(0.2)
                  : (isDarkMode ? Colors.grey[800] : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image,
                    size: 48, color: isMe ? Colors.white70 : Colors.grey),
                const SizedBox(height: 8),
                Text(
                  'Image not available',
                  style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildTimestampRow(isMe),
            ],
          ),
        ],
        ),
      );
    }

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ImageViewerScreen(
                    imageUrl: (imageUrl != null && imageUrl.isNotEmpty) 
                                ? imageUrl 
                                : widget.message.imagePath,
                    caption: hasCaption ? caption : null,
                  ),
                ),
              );
              FocusManager.instance.primaryFocus?.unfocus();
            },
            child: Hero(
              tag: imageUrl ?? widget.message.imagePath ?? 'image_${widget.message.id}',
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxW,
                  maxHeight: maxH,
                ),
                child: Builder(
                  builder: (context) {
                    final hasLocalPath = widget.message.imagePath != null && 
                                           widget.message.imagePath!.isNotEmpty && 
                                           File(widget.message.imagePath!).existsSync();
                      
                      if (hasLocalPath) {
                        return Image.file(
                          File(widget.message.imagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildErrorImage(isMe, isDarkMode),
                        );
                      }
                      
                      final pixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
                      final memW = (maxW * pixelRatio).round().clamp(100, 800);
                      return CachedNetworkImage(
                        imageUrl: imageUrl ?? '',
                        fit: BoxFit.cover,
                        memCacheWidth: memW,
                        maxWidthDiskCache: 800,
                        placeholder: (context, url) => SizedBox(
                          width: maxW * 0.6,
                          height: maxH * 0.6,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => _buildErrorImage(isMe, isDarkMode),
                      );
                    }
                  ),
                ),
              ),
            ),
          ),
        if (hasCaption) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: BoxConstraints(
              maxWidth: maxW,
            ),
            child: Text(
              _cleanContent(caption),
              style: TextStyle(
                color: isMe
                    ? Colors.white
                    : (isDarkMode
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary),
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4.0, bottom: 2.0),
              child: _buildTimestampRow(isMe),
            ),
          ],
        ),
      ],
      ),
    );
  }

  Widget _buildVideoMessage(BuildContext context, bool isMe, bool isDarkMode) {
    // Read from both imageUrl (locally sent) and videoUrl (server received)
    final videoUrl = widget.message.imageUrl ?? widget.message.videoUrl ?? '';
    final isSticker = _isStickerMessage(widget.message) || videoUrl.toLowerCase().contains('.webm') || videoUrl.toLowerCase().contains('.tgs') || videoUrl.toLowerCase().contains('.webp') || widget.message.content.toLowerCase().contains('animated sticker');
    if (isSticker) {
      return _buildStickerMessage(isMe, isDarkMode);
    }
    
    final caption = widget.message.content
        .replaceAll('📹 Video', '')
        .replaceAll('🎥 Video', '')
        .replaceAll('🎬 Video', '')
        .replaceAll('🌟 Sticker', '')
        .replaceAll('🎬 Sticker', '')
        .trim();
    final hasCaption = caption.isNotEmpty;
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final fixedHeight = maxWidth * 9 / 16; // Enforce 16:9 ratio


    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () async {
            if (videoUrl.isNotEmpty) {
              FocusManager.instance.primaryFocus?.unfocus();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    videoUrl: videoUrl,
                    caption: hasCaption ? caption : null,
                  ),
                ),
              );
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: maxWidth,
              height: fixedHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Dark placeholder background (no expensive thumbnail generation)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.grey.shade800,
                          Colors.grey.shade900,
                        ],
                      ),
                    ),
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  // Center play button
                  Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.play_arrow,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // 'Tap to play' pill — bottom left
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Tap to play',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // 'Video' pill — bottom right
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isSticker ? Icons.animation : Icons.movie, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            isSticker ? 'Sticker' : 'Video',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (hasCaption) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: BoxConstraints(
              maxWidth: maxWidth,
            ),
            child: Text(
              _cleanContent(caption),
              style: TextStyle(
                color: isMe ? Colors.white : (isDarkMode ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _buildTimestampRow(isMe),
      ],
    );
  }

  Widget _buildAudioMessage(bool isMe, bool isDarkMode) {
    final audioUrl = widget.message.audioPath;

    if (audioUrl == null || audioUrl.isEmpty) {
      return Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            width: 280,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withOpacity(0.2)
                  : (isDarkMode ? Colors.grey[800] : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 24,
                  color: isMe ? Colors.white70 : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice note not available',
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white70 : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _buildTimestampRow(isMe),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        AudioPlayerWidget(
          key: ValueKey('audio_${audioUrl.split('?').first.split('/').last}'),
          audioUrl: audioUrl,
          isMe: isMe,
          initialDuration: widget.message.audioDuration > 0
              ? Duration(seconds: widget.message.audioDuration)
              : null,
          caption: widget.message.content.trim().isNotEmpty == true
              ? widget.message.content
              : null,
        ),
        const SizedBox(height: 4),
        _buildTimestampRow(isMe),
      ],
    );
  }

  Widget _buildLocationMessage(bool isMe, bool isDarkMode) {
    final messageText = widget.message.content;

    double? latitude;
    double? longitude;
    String? mapsUrl;
    String? address;

    final locationRegex = RegExp(r'Location:\s*(-?\d+\.?\d*),\s*(-?\d+\.?\d*)', caseSensitive: false);
    final match = locationRegex.firstMatch(messageText);

    if (match != null) {
      latitude = double.tryParse(match.group(1)!);
      longitude = double.tryParse(match.group(2)!);
    } else if (messageText.contains('[-{=||=}-]')) {
      final parts = messageText.split('[-{=||=}-]');
      if (parts.length >= 2) {
        latitude = double.tryParse(parts[0].trim());
        longitude = double.tryParse(parts[1].trim());
      }
      if (parts.length >= 3) {
        final rawAddr = parts[2].trim();
        if (rawAddr.isNotEmpty && rawAddr != '-') {
          address = rawAddr;
        }
      }
    } else {
      final coordRegex = RegExp(r'(?:query|q)=(-?\d+\.?\d*),(-?\d+\.?\d*)');
      final coordMatch = coordRegex.firstMatch(messageText);
      if (coordMatch != null) {
        latitude = double.tryParse(coordMatch.group(1)!);
        longitude = double.tryParse(coordMatch.group(2)!);
      }
    }

    final urlRegex = RegExp(r'https?:\/\/(?:www\.)?(?:google\.com\/maps[^\s]+|maps\.google\.com[^\s]+|maps\.app\.goo\.gl[^\s]+)');
    final urlMatch = urlRegex.firstMatch(messageText);
    if (urlMatch != null) {
      mapsUrl = urlMatch.group(0);
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (mapsUrl != null) {
              _openInMaps(mapsUrl);
            } else if (latitude != null && longitude != null) {
              final url = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
              _openInMaps(url);
            }
          },
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withOpacity(0.2)
                  : (isDarkMode ? Colors.grey[800] : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMe
                    ? Colors.white.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 20,
                      color: isMe ? Colors.white : AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Location',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isMe
                            ? Colors.white
                            : (isDarkMode
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isMe
                          ? Colors.white
                          : (isDarkMode
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withOpacity(0.1)
                        : (isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMe
                          ? Colors.white.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        size: 48,
                        color: isMe ? Colors.white70 : AppTheme.textSecondary,
                      ),
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Tap to open in Maps',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (latitude != null && longitude != null)
                  Text(
                    'Lat: ${latitude.toStringAsFixed(6)}, Lng: ${longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white70 : AppTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withOpacity(0.2)
                        : AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMe
                          ? Colors.white.withOpacity(0.3)
                          : AppTheme.primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: isMe ? Colors.white : AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Open in Google Maps',
                        style: TextStyle(
                          fontSize: 14,
                          color: isMe ? Colors.white : AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildTimestampRow(isMe),
      ],
    );
  }

  void _openInMaps(String url) {
    try {
      launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Failed to open maps: $e');
    }
  }

  Widget _buildAckIcon() {
    IconData icon;
    Color color;

    switch (widget.message.ack) {
      case 1: // Pending
        icon = Icons.access_time;
        color = Colors.grey;
        break;
      case 2: // Sent
        icon = Icons.check;
        color = Colors.grey;
        break;
      case 3: // Delivered
        icon = Icons.done_all;
        color = Colors.grey; // Double gray checkmark
        break;
      case 4: // Failed
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      case 5: // Read
        icon = Icons.done_all;
        color = Colors.blue; // Double blue checkmark!
        break;
      default:
        icon = Icons.check;
        color = Colors.grey;
        break;
    }

    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }
}

class _VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoThumbnailWidget({required this.videoUrl});

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  Uint8List? _thumbnailData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );
      if (mounted) {
        setState(() {
          _thumbnailData = uint8list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating video thumbnail: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.grey.shade800,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        ),
      );
    }
    
    if (_thumbnailData != null) {
      return Image.memory(
        _thumbnailData!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    
    // Fallback if thumbnail generation fails
    return Container(
      color: Colors.grey.shade800,
      child: const Center(
        child: Icon(
          Icons.broken_image,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }
}

class AnimatedVideoSticker extends StatefulWidget {
  final String url;
  const AnimatedVideoSticker({super.key, required this.url});

  @override
  State<AnimatedVideoSticker> createState() => _AnimatedVideoStickerState();
}

class _AnimatedVideoStickerState extends State<AnimatedVideoSticker> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setVolume(0.0)
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
        }
      }).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox(
        width: 120,
        height: 120,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: 160,
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 1.0,
        child: VideoPlayer(_controller),
      ),
    );
  }
}