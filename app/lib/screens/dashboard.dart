import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/mars_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  SerialPort? _port;
  String _status = 'Disconnected';

  void _connectDevice(String portName) {
    try {
      if (_port != null && _port!.isOpen) _port!.close();
      _port = SerialPort(portName);
      if (_port!.openReadWrite()) {
        setState(() => _status = 'Connected to $portName (Awaiting Biometric Unlock)');
        final reader = SerialPortReader(_port!);
        reader.stream.listen((data) {
          try {
            String message = utf8.decode(data).trim();
            if (message.isNotEmpty) {
              final json = jsonDecode(message);
              if (json['status'] == 'event') {
                if (json['message'] == 'BIOMETRIC_UNLOCKED') {
                  setState(() => _status = 'Connected & UNLOCKED 🟢');
                } else if (json['message'] == 'BIOMETRIC_LOCKED') {
                  setState(() => _status = 'Connected & LOCKED 🔴 (Scan Finger)');
                }
              }
            }
          } catch (_) {}
        });
      } else {
        setState(() => _status = 'Failed to open $portName');
      }
    } catch (e) {
      setState(() => _status = 'Connection Error: $e');
    }
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to Mahfadha Pro first.')),
      );
      return;
    }
    try {
      String jsonString = '${jsonEncode(command)}\n';
      _port!.write(Uint8List.fromList(utf8.encode(jsonString)));
    } catch (e) {
      setState(() => _status = 'Write Error: $e');
    }
  }

  @override
  void dispose() {
    if (_port != null && _port!.isOpen) _port!.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<String> ports = [];
    try { ports = SerialPort.availablePorts; } catch (_) {}

    final connected = _status.contains('Connected');

    return Scaffold(
      backgroundColor: MarsTheme.background,
      body: Container(
        decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
        child: Column(children: [
          // Title bar
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Row(children: [
              const Icon(Icons.shield_outlined, color: MarsTheme.cyan, size: 20),
              const SizedBox(width: 8),
              Text('MAHFADHA PRO', style: GoogleFonts.inter(
                color: MarsTheme.cyan, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2,
              )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: connected ? MarsTheme.success : MarsTheme.error),
                  const SizedBox(width: 6),
                  Text(_status, style: GoogleFonts.inter(
                    color: connected ? MarsTheme.success : MarsTheme.error,
                    fontSize: 11, fontWeight: FontWeight.w600,
                  )),
                ]),
              ),
            ]),
          ),
          // Body
          Expanded(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              // Left: Ports
              SizedBox(
                width: 260,
                child: Container(
                  decoration: MarsTheme.glassCard(),
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('USB DEVICES', style: GoogleFonts.inter(
                      color: MarsTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2,
                    )),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ports.isEmpty
                        ? Center(child: Text('No devices found', style: GoogleFonts.inter(color: MarsTheme.textMuted, fontSize: 13)))
                        : ListView.separated(
                            itemCount: ports.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _connectDevice(ports[i]),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: MarsTheme.surfaceLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: MarsTheme.borderGlow),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.usb, color: MarsTheme.cyan, size: 18),
                                  const SizedBox(width: 10),
                                  Text(ports[i], style: GoogleFonts.firaCode(color: MarsTheme.textPrimary, fontSize: 13)),
                                ]),
                              ),
                            ),
                          ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 20),
              // Right: Operations grid
              Expanded(child: Container(
                decoration: MarsTheme.glassCard(),
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SECURE OPERATIONS', style: GoogleFonts.inter(
                    color: MarsTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2,
                  )),
                  const SizedBox(height: 20),
                  Expanded(child: GridView.count(
                    crossAxisCount: 3, childAspectRatio: 1.6,
                    crossAxisSpacing: 14, mainAxisSpacing: 14,
                    children: [
                      _opCard(Icons.sync, 'Sync Time', MarsTheme.cyan, () => _sendCommand({'cmd': 'sync_time', 'time': DateTime.now().millisecondsSinceEpoch ~/ 1000})),
                      _opCard(Icons.add_moderator, 'Add Entry', MarsTheme.success, () => _sendCommand({'cmd': 'add_account', 'name': 'New', 'username': '', 'password': ''})),
                      _opCard(Icons.list_alt, 'List Accounts', MarsTheme.accent, () => _sendCommand({'cmd': 'list_accounts'})),
                      _opCard(Icons.upload_file, 'Import CSV', MarsTheme.warning, () {}),
                      _opCard(Icons.save_alt, 'Export Backup', Color(0xFF2DD4BF), () => _sendCommand({'cmd': 'export_backup'})),
                      _opCard(Icons.delete_forever, 'Wipe Vault', MarsTheme.error, () => _sendCommand({'cmd': 'factory_reset'})),
                    ],
                  )),
                ]),
              )),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _opCard(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(label, style: GoogleFonts.inter(color: MarsTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
