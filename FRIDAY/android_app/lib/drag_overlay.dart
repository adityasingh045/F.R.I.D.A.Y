// TARGET: Flutter 3.22+ | file_picker ^8.0.0
// JARVIS MODULE: Bidirectional Drag & Drop Engine

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'websocket_service.dart';
import 'ai_classifier.dart';

enum DragPayloadType { file, text, image, video, code }

class DragPayload {
  final DragPayloadType type;
  final String? text;
  final String? filePath;
  final String? filename;
  final int? fileSize;
  final String? aiClassification;

  const DragPayload({
    required this.type,
    this.text,
    this.filePath,
    this.filename,
    this.fileSize,
    this.aiClassification,
  });
}

// ── PHONE DRAG OVERLAY ─────────────────────────────────────────────────────
class PhoneDragOverlay extends StatefulWidget {
  final WebSocketService wsService;
  final Widget child;

  const PhoneDragOverlay({
    super.key,
    required this.wsService,
    required this.child,
  });

  @override
  State<PhoneDragOverlay> createState() => _PhoneDragOverlayState();
}

class _PhoneDragOverlayState extends State<PhoneDragOverlay>
    with SingleTickerProviderStateMixin {
  bool _isDragTargetVisible = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  final AIClassifier _classifier = AIClassifier();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);

    // Listen for incoming drag events from desktop
    widget.wsService.messageStream.listen((message) {
      if (message['type'] == 'DRAG_INCOMING') {
        setState(() => _isDragTargetVisible = true);
        _animCtrl.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Original content
        widget.child,

        // Drag source — long press on screen elements
        Positioned.fill(
          child: DragTarget<DragPayload>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) async {
              final payload = details.data;
              await _handleIncomingDrop(payload);
            },
            builder: (context, candidateData, rejectedData) {
              return FadeTransition(
                opacity: _fadeAnim,
                child: _isDragTargetVisible
                    ? _DropZoneOverlay(
                        isActive: candidateData.isNotEmpty,
                        onDismiss: () {
                          _animCtrl.reverse();
                          setState(() => _isDragTargetVisible = false);
                        },
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),

        // Floating action: Pick & Drag to Desktop
        Positioned(
          right: 16,
          bottom: 100,
          child: _DragLaunchButton(
            onFilePicked: (result) => _sendFileToDesktop(result),
          ),
        ),
      ],
    );
  }

  Future<void> _handleIncomingDrop(DragPayload payload) async {
    switch (payload.type) {
      case DragPayloadType.text:
        // Write to clipboard
        debugPrint('[JARVIS-DRAG] Text received: ${payload.text}');
        break;
      case DragPayloadType.file:
      case DragPayloadType.image:
      case DragPayloadType.video:
        // Request file via HTTP/2
        await widget.wsService.requestFileTransfer(payload.filename!);
        break;
      case DragPayloadType.code:
        // Open in code viewer
        break;
    }
  }

  Future<void> _sendFileToDesktop(FilePickerResult result) async {
    for (final file in result.files) {
      if (file.path == null) continue;

      // AI classify before sending
      final classification = await _classifier.classify(file.path!);

      await widget.wsService.sendMessage({
        'type': 'DRAG_PAYLOAD',
        'payloadType': classification.name,
        'filename': file.name,
        'fileSize': file.size,
        'aiClassification': classification.name,
      });

      // Stream file via HTTP/2
      await widget.wsService.uploadFile(file.path!, file.name);
      debugPrint('[JARVIS-DRAG] Sent: ${file.name} (${classification.name})');
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }
}

// ── DROP ZONE UI ───────────────────────────────────────────────────────────
class _DropZoneOverlay extends StatelessWidget {
  final bool isActive;
  final VoidCallback onDismiss;

  const _DropZoneOverlay({required this.isActive, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? const Color(0xFF3FB950)
                : const Color(0xFF00D4FF),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.check_circle_outline : Icons.cloud_download_outlined,
              color: isActive
                  ? const Color(0xFF3FB950)
                  : const Color(0xFF00D4FF),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'DROP HERE' : 'AWAITING DROP',
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF3FB950)
                    : const Color(0xFF00D4FF),
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── DRAG LAUNCH BUTTON ─────────────────────────────────────────────────────
class _DragLaunchButton extends StatelessWidget {
  final Function(FilePickerResult) onFilePicked;

  const _DragLaunchButton({required this.onFilePicked});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.any,
        );
        if (result != null) onFilePicked(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4FF).withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'SEND TO DESKTOP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}