// TARGET: Flutter 3.22+ | Dart 3.4+
// JARVIS MODULE: mDNS Discovery + QR Pairing Engine

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto.dart';

// ── DISCOVERED DEVICE MODEL ────────────────────────────────────────────────
class DiscoveredDevice {
  final String name;
  final String ip;
  final int port;
  final String deviceId;

  const DiscoveredDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.deviceId,
  });

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json) =>
      DiscoveredDevice(
        name: json['name'] ?? 'Unknown',
        ip: json['ip'],
        port: json['port'] ?? 8765,
        deviceId: json['deviceId'],
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'deviceId': deviceId,
  };
}

// ── DISCOVERY SERVICE ──────────────────────────────────────────────────────
class DiscoveryService {
  static const String _serviceType = '_multi-screen-collaborate._tcp';
  static const String _serviceName = 'multi-screen-collaborate';

  final StreamController<DiscoveredDevice> _deviceStream =
      StreamController<DiscoveredDevice>.broadcast();

  Stream<DiscoveredDevice> get deviceStream => _deviceStream.stream;

  MDnsClient? _client;
  bool _isScanning = false;

  // ── START mDNS SCAN ──────────────────────────────────────────────────────
  Future<void> startDiscovery() async {
    if (_isScanning) return;
    _isScanning = true;

    _client = MDnsClient(rawDatagramSocketFactory: (
      dynamic host,
      int port, {
      bool? reuseAddress,
      bool? reusePort,
      int? ttl,
    }) {
      return RawDatagramSocket.bind(host, port,
          reuseAddress: reuseAddress ?? true,
          reusePort: reusePort ?? true,
          ttl: ttl ?? 255);
    });

    await _client!.start();

    await for (final PtrResourceRecord ptr in _client!
        .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceType))) {
      await for (final SrvResourceRecord srv in _client!
          .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))) {
        await for (final IPAddressResourceRecord ip in _client!
            .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))) {
          final device = DiscoveredDevice(
            name: srv.target,
            ip: ip.address.address,
            port: srv.port,
            deviceId: ptr.domainName,
          );
          _deviceStream.add(device);
          debugPrint('[JARVIS-DISCOVERY] Found: ${device.name} @ ${device.ip}:${device.port}');
        }
      }
    }
  }

  Future<void> stopDiscovery() async {
    _isScanning = false;
    _client?.stop();
    _client = null;
  }

  void dispose() {
    stopDiscovery();
    _deviceStream.close();
  }
}

// ── QR PAIRING WIDGET ──────────────────────────────────────────────────────
class QRPairingWidget extends StatefulWidget {
  final String sessionKey;
  final Function(DiscoveredDevice) onPaired;

  const QRPairingWidget({
    super.key,
    required this.sessionKey,
    required this.onPaired,
  });

  @override
  State<QRPairingWidget> createState() => _QRPairingWidgetState();
}

class _QRPairingWidgetState extends State<QRPairingWidget> {
  String? _localIp;
  final DiscoveryService _discovery = DiscoveryService();

  @override
  void initState() {
    super.initState();
    _initPairing();
  }

  Future<void> _initPairing() async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    setState(() => _localIp = ip);

    _discovery.startDiscovery();
    _discovery.deviceStream.listen((device) {
      widget.onPaired(device);
      debugPrint('[JARVIS-PAIRING] Paired with: ${device.name}');
    });
  }

  String get _qrData {
    if (_localIp == null) return '';
    final payload = {
      'ip': _localIp,
      'port': 8765,
      'key': widget.sessionKey,
      'service': 'multi-screen-collaborate',
    };
    return jsonEncode(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00D4FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SCAN TO PAIR',
            style: TextStyle(
              color: Color(0xFF00D4FF),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          if (_localIp != null)
            QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0D1117),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0D1117),
              ),
            )
          else
            const CircularProgressIndicator(color: Color(0xFF00D4FF)),
          const SizedBox(height: 16),
          Text(
            'HOST: ${_localIp ?? "Resolving..."}:8765',
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulsingDot(),
              SizedBox(width: 8),
              Text(
                'Awaiting device...',
                style: TextStyle(color: Color(0xFF3FB950), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }
}

// ── PULSING INDICATOR ──────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF3FB950),
            shape: BoxShape.circle,
          ),
        ),
      );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}