import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';
import 'csv_importer_and_health.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  SerialPort? _port;
  String _status = 'غير متصل';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      final portName = appState.connectedPort;
      if (portName != null) {
        _connectDevice(portName);
      } else {
        setState(() => _status = appState.deviceStatus);
      }
    });
  }

  void _connectDevice(String portName) {
    try {
      if (_port?.isOpen ?? false) {
        _port!.close();
      }

      _port = SerialPort(portName);
      if (_port!.openReadWrite()) {
        setState(() {
          _status = 'متصل عبر $portName — بانتظار المصادقة الحيوية';
        });

        final reader = SerialPortReader(_port!);
        reader.stream.listen((data) {
          try {
            final message = utf8.decode(data).trim();
            if (message.isEmpty) return;

            final json = jsonDecode(message);
            if (json['status'] == 'event') {
              if (json['message'] == 'BIOMETRIC_UNLOCKED') {
                setState(() => _status = 'تمت المصادقة الحيوية بنجاح');
              } else if (json['message'] == 'BIOMETRIC_LOCKED') {
                setState(() => _status = 'الجهاز متصل وينتظر التحقق الحيوي');
              }
            }
          } catch (_) {}
        });
      } else {
        setState(() => _status = 'تعذر فتح المنفذ $portName');
      }
    } catch (error) {
      setState(() => _status = 'خطأ اتصال: $error');
    }
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'وصّل جهاز Mahfadha Pro أولاً.',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
          ),
          backgroundColor: MarsTheme.error,
        ),
      );
      return;
    }

    try {
      final payload = '${jsonEncode(command)}\n';
      _port!.write(Uint8List.fromList(utf8.encode(payload)));
    } catch (error) {
      setState(() => _status = 'تعذر إرسال الأمر: $error');
    }
  }

  void _openCsvImporter() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const CsvImporterWidget(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_port?.isOpen ?? false) {
      _port!.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status.contains('متصل') || _status.contains('المصادقة');

    return Container(
      decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          children: [
            _buildHeader(connected),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: MarsTheme.glassCard(borderRadius: 24),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عمليات الجهاز',
                            style: GoogleFonts.cairo(
                              color: MarsTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Expanded(child: _buildOperationsGrid()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PasswordHealthDashboard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool connected) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: MarsTheme.surfaceLight.withOpacity(0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MarsTheme.borderGlow),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.memory_rounded, color: MarsTheme.cyanNeon, size: 18),
              const SizedBox(width: 8),
              Text(
                'Mahfadha Pro',
                style: GoogleFonts.inter(
                  color: MarsTheme.cyanNeon,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'لوحة التشغيل الآمنة',
          style: GoogleFonts.cairo(
            color: MarsTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: connected ? MarsTheme.success : MarsTheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                _status,
                style: GoogleFonts.cairo(
                  color: connected ? MarsTheme.success : MarsTheme.error,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperationsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 4 : 3;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: 1.45,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          children: [
            _operationCard(
              icon: Icons.sync_rounded,
              label: 'مزامنة الوقت',
              color: MarsTheme.cyan,
              onTap: () => _sendCommand({
                'cmd': 'sync_time',
                'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              }),
            ),
            _operationCard(
              icon: Icons.person_add_alt_1_rounded,
              label: 'إضافة سجل',
              color: MarsTheme.success,
              onTap: () => _sendCommand({
                'cmd': 'add_account',
                'name': 'جديد',
                'username': '',
                'password': '',
              }),
            ),
            _operationCard(
              icon: Icons.list_alt_rounded,
              label: 'عرض السجلات',
              color: MarsTheme.accent,
              onTap: () => _sendCommand({'cmd': 'list_accounts'}),
            ),
            _operationCard(
              icon: Icons.upload_file_rounded,
              label: 'استيراد CSV',
              color: MarsTheme.warning,
              onTap: _openCsvImporter,
            ),
            _operationCard(
              icon: Icons.download_done_rounded,
              label: 'نسخة احتياطية',
              color: const Color(0xFF2DD4BF),
              onTap: () => _sendCommand({'cmd': 'export_backup'}),
            ),
            _operationCard(
              icon: Icons.refresh_rounded,
              label: 'مركز التحديثات',
              color: MarsTheme.cyanGlow,
              onTap: () => Navigator.pushNamed(context, '/updates'),
            ),
            _operationCard(
              icon: Icons.delete_sweep_rounded,
              label: 'إعادة ضبط المصنع',
              color: MarsTheme.error,
              onTap: () => _sendCommand({'cmd': 'factory_reset'}),
            ),
          ],
        );
      },
    );
  }

  Widget _operationCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
