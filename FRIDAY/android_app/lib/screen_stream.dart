// TARGET: Flutter 3.22+ | flutter_webrtc ^0.10.0
// JARVIS MODULE: Phone Screen Capture + WebRTC Stream

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenStreamService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _screenStream;
  RTCVideoRenderer? _localRenderer;

  final StreamController<RTCSessionDescription> _offerController =
      StreamController<RTCSessionDescription>.broadcast();

  Stream<RTCSessionDescription> get offerStream => _offerController.stream;

  // ── ICE CONFIG ─────────────────────────────────────────────────────────────
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // For LAN-only: no TURN needed
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── INIT SCREEN CAPTURE (Android MediaProjection) ──────────────────────────
  Future<void> startScreenCapture() async {
    try {
      // Request screen capture permission + stream
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'mandatory': {
            'minWidth': 1280,
            'minHeight': 720,
            'maxWidth': 1920,
            'maxHeight': 1080,
            'maxFrameRate': 30,
          },
          'facingMode': 'environment',
        },
        'audio': false, // Audio relay handled separately
      });

      _localRenderer = RTCVideoRenderer();
      await _localRenderer!.initialize();
      _localRenderer!.srcObject = _screenStream;

      await _initPeerConnection();
      debugPrint('[JARVIS-STREAM] Screen capture initiated ✓');
    } catch (e) {
      debugPrint('[JARVIS-STREAM] Screen capture error: $e');
      rethrow;
    }
  }

  // ── PEER CONNECTION ────────────────────────────────────────────────────────
  Future<void> _initPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceConfig);

    // Add screen tracks
    _screenStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _screenStream!);
    });

    // H.264 codec preference for low-latency
    _peerConnection!.onRenegotiationNeeded = () async {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': false,
        'offerToReceiveAudio': false,
      });

      // Prefer H.264 codec
      offer = RTCSessionDescription(
        _preferH264(offer.sdp!),
        offer.type,
      );

      await _peerConnection!.setLocalDescription(offer);
      _offerController.add(offer);
    };

    _peerConnection!.onIceCandidate = (candidate) {
      // Forward ICE candidates via WebSocket hub
      debugPrint('[JARVIS-STREAM] ICE candidate: ${candidate.candidate}');
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[JARVIS-STREAM] Connection state: $state');
    };
  }

  // ── H.264 SDP PREFERENCE ──────────────────────────────────────────────────
  String _preferH264(String sdp) {
    final lines = sdp.split('\n');
    final h264Pattern = RegExp(r'a=rtpmap:(\d+) H264/90000');

    String? h264PayloadType;
    for (final line in lines) {
      final match = h264Pattern.firstMatch(line);
      if (match != null) {
        h264PayloadType = match.group(1);
        break;
      }
    }

    if (h264PayloadType == null) return sdp;

    return lines.map((line) {
      if (line.startsWith('m=video')) {
        final parts = line.split(' ');
        final payloads = parts.sublist(3);
        payloads.remove(h264PayloadType);
        payloads.insert(0, h264PayloadType!);
        return '${parts.sublist(0, 3).join(' ')} ${payloads.join(' ')}';
      }
      return line;
    }).join('\n');
  }

  // ── HANDLE REMOTE ANSWER ───────────────────────────────────────────────────
  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    await _peerConnection?.setRemoteDescription(answer);
    debugPrint('[JARVIS-STREAM] Remote answer set ✓');
  }

  // ── ADAPTIVE BITRATE CONTROL ───────────────────────────────────────────────
  Future<void> setBitrate(int kbps) async {
    final senders = await _peerConnection?.getSenders();
    for (final sender in senders ?? []) {
      if (sender.track?.kind == 'video') {
        final params = await sender.getParameters();
        for (final encoding in params.encodings ?? []) {
          encoding.maxBitrate = kbps * 1000;
        }
        await sender.setParameters(params);
        debugPrint('[JARVIS-STREAM] Bitrate set to ${kbps}kbps');
      }
    }
  }

  Future<void> dispose() async {
    await _screenStream?.dispose();
    await _peerConnection?.close();
    _localRenderer?.dispose();
    _offerController.close();
  }
}

// ── MIRROR VIEW WIDGET (Desktop Renderer) ─────────────────────────────────
class MirrorViewWidget extends StatefulWidget {
  final RTCVideoRenderer renderer;

  const MirrorViewWidget({super.key, required this.renderer});

  @override
  State<MirrorViewWidget> createState() => _MirrorViewWidgetState();
}

class _MirrorViewWidgetState extends State<MirrorViewWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D4FF), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withOpacity(0.2),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: RTCVideoView(
        widget.renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        mirror: false,
        placeholderBuilder: (context) => Container(
          color: const Color(0xFF0D1117),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00D4FF)),
                SizedBox(height: 16),
                Text(
                  'AWAITING STREAM...',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}