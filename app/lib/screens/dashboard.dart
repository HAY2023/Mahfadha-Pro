import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/mars_theme.dart';
import '../providers/app_state.dart';
import 'csv_importer_and_health.dart';

// ═══════════════════════════════════════════════════════════════════════
//  لوحة التحكم الرئيسية — القبو السيبراني
//  [FIX 2] واجهة عربية بالكامل مع Mars Theme
// ═══════════════════════════════════════════════════════════════════════

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
    // اتصال تلقائي بالمنفذ المحفوظ من البوابة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final portName = context.read<AppState>().connectedPort;
      if (portName != null) _connectDevice(portName);
    });
  }

  void _connectDevice(String portName) {
    try {
      if (_port != null && _port!.isOpen) _port!.close();
      _port = SerialPort(portName);
      if (_port!.openReadWrite()) {
        setState(() => _status = 'متصل بـ $portName — في انتظار البصمة');
        final reader = SerialPortReader(_port!);
        reader.stream.listen((data) {
          try {
            String message = utf8.decode(data).trim();
            if (message.isNotEmpty) {
              final json = jsonDecode(message);
              if (json['status'] == 'event') {
                if (json['message'] == 'BIOMETRIC_UNLOCKED') {
                  setState(() => _status = 'متصل ومفتوح 🟢');
                } else if (json['message'] == 'BIOMETRIC_LOCKED') {
                  setState(() => _status = 'متصل ومقفل 🔴 — امسح بصمتك');
                }
              }
            }
          } catch (_) {}
        });
      } else {
        setState(() => _status = 'فشل فتح $portName');
      }
    } catch (e) {
      setState(() => _status = 'خطأ اتصال: $e');
    }
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('وصّل محفظة برو أولاً',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          backgroundColor: MarsTheme.error,
        ),
      );
      return;
    }
    try {
      String jsonString = '${jsonEncode(command)}\n';
      _port!.write(Uint8List.fromList(utf8.encode(jsonString)));
    } catch (e) {
      setState(() => _status = 'خطأ كتابة: $e');
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
    if (_port != null && _port!.isOpen) _port!.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status.contains('متصل');

    return Container(
      decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
      child: Column(children: [
        // ── شريط الحالة ──
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Row(children: [
            const Icon(Icons.shield_outlined, color: MarsTheme.cyan, size: 18),
            const SizedBox(width: 8),
            Text('القبو السيبراني', style: GoogleFonts.cairo(
              color: MarsTheme.cyan, fontSize: 14, fontWeight: FontWeight.w700,
            )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 7,
                  color: connected ? MarsTheme.success : MarsTheme.error),
                const SizedBox(width: 6),
                Text(_status, style: GoogleFonts.cairo(
                  color: connected ? MarsTheme.success : MarsTheme.error,
                  fontSize: 11, fontWeight: FontWeight.w600,
                )),
              ]),
            ),
          ]),
        ),

        // ── المحتوى الرئيسي ──
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Column(children: [
            // شبكة العمليات
            Expanded(child: Container(
              decoration: MarsTheme.glassCard(),
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('العمليات الآمنة', style: GoogleFonts.cairo(
                  color: MarsTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700,
                )),
                const SizedBox(height: 20),
                Expanded(child: GridView.count(
                  crossAxisCount: 3, childAspectRatio: 1.6,
                  crossAxisSpacing: 14, mainAxisSpacing: 14,
                  children: [
                    _opCard(Icons.sync, 'مزامنة الوقت', MarsTheme.cyan,
                      () => _sendCommand({'cmd': 'sync_time',
                        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000})),
                    _opCard(Icons.add_moderator, 'إضافة إدخال', MarsTheme.success,
                      () => _sendCommand({'cmd': 'add_account',
                        'name': 'جديد', 'username': '', 'password': ''})),
                    _opCard(Icons.list_alt, 'عرض الحسابات', MarsTheme.accent,
                      () => _sendCommand({'cmd': 'list_accounts'})),
                    _opCard(Icons.upload_file, 'استيراد CSV', MarsTheme.warning,
                      _openCsvImporter),
                    _opCard(Icons.save_alt, 'نسخة احتياطية', const Color(0xFF2DD4BF),
                      () => _sendCommand({'cmd': 'export_backup'})),
                    _opCard(Icons.delete_forever, 'مسح القبو', MarsTheme.error,
                      () => _sendCommand({'cmd': 'factory_reset'})),
                  ],
                )),
              ]),
            )),
            const SizedBox(height: 12),
            // لوحة صحة كلمات المرور
            const PasswordHealthDashboard(),
          ]),
        )),
      ]),
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
          Text(label, style: GoogleFonts.cairo(
            color: MarsTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
