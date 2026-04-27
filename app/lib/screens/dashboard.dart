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
              final appState = context.read<AppState>();
              final eventMessage = json['message']?.toString() ?? '';

              switch (eventMessage) {
                // ── [V3] Primary signal: FINGERPRINT_VERIFIED from ESP32 ──
                case 'FINGERPRINT_VERIFIED':
                  setState(() => _status = 'تمت المصادقة الحيوية بنجاح ✓');
                  appState.onFingerprintVerified();

                // ── [V2] Legacy support: BIOMETRIC_UNLOCKED ──
                case 'BIOMETRIC_UNLOCKED':
                  setState(() => _status = 'تمت المصادقة الحيوية بنجاح');
                  appState.onBiometricUnlocked();

                // ── [V3] Scanning in progress ──
                case 'FINGERPRINT_SCANNING':
                  setState(() => _status = 'جارٍ مسح البصمة...');
                  appState.onBiometricScanning();

                // ── [V3] Verification failed ──
                case 'FINGERPRINT_FAILED':
                  setState(() => _status = 'فشل التحقق من البصمة');
                  appState.onBiometricFailed();

                // ── Lock signals ──
                case 'BIOMETRIC_LOCKED':
                  setState(() => _status = 'الجهاز متصل وينتظر التحقق الحيوي');
                  appState.lockBiometricVault();
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

  /// [V3] Show add account dialog with targetUrl, phone, and backup codes
  void _showAddAccountDialog() {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final backupCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: SingleChildScrollView(
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(28),
            decoration: MarsTheme.glassCard(borderRadius: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Header ──
              Row(children: [
                const Icon(Icons.person_add_alt_1, color: MarsTheme.success, size: 24),
                const SizedBox(width: 10),
                Text('إضافة حساب جديد', style: GoogleFonts.cairo(
                  color: MarsTheme.cyanNeon, fontSize: 20, fontWeight: FontWeight.w700,
                )),
              ]),
              const SizedBox(height: 20),

              // ── Core fields ──
              _inputField(nameCtrl, 'اسم الحساب', Icons.label),
              const SizedBox(height: 12),
              _inputField(userCtrl, 'اسم المستخدم', Icons.person),
              const SizedBox(height: 12),
              _inputField(passCtrl, 'كلمة المرور', Icons.lock, obscure: true),
              const SizedBox(height: 16),

              // ── Auto-Login URL (Rubber Ducky) ──
              _buildSectionLabel(
                'الدخول التلقائي (Rubber Ducky)',
                Icons.keyboard_rounded,
                MarsTheme.success,
              ),
              const SizedBox(height: 8),
              _inputField(urlCtrl, 'رابط الدخول التلقائي (URL)', Icons.link,
                hint: 'https://facebook.com/login'),
              const SizedBox(height: 6),
              _buildInfoBanner(
                icon: Icons.keyboard,
                color: MarsTheme.success,
                text: 'الرابط سيُرسل إلى الجهاز ليقوم بفتحه تلقائياً عبر '
                    'Keystroke Injection (Rubber Ducky) ثم يكتب بيانات الدخول.',
              ),
              const SizedBox(height: 16),

              // ── Sensitive data section ──
              _buildSectionLabel(
                'بيانات حساسة (اختياري)',
                Icons.shield_outlined,
                MarsTheme.warning,
              ),
              const SizedBox(height: 8),
              _inputField(phoneCtrl, 'أرقام الهاتف (فاصل: ,)', Icons.phone_android,
                hint: '+213xxxxxxxxx, +1xxxxxxxxxx'),
              const SizedBox(height: 10),
              _inputField(backupCtrl, 'أكواد احتياطية (فاصل: ,)', Icons.vpn_key,
                hint: 'XXXX-XXXX, YYYY-YYYY'),
              const SizedBox(height: 6),
              _buildInfoBanner(
                icon: Icons.security,
                color: MarsTheme.warning,
                text: 'هذه البيانات تُشفَّر وتُخزَّن حصرياً على الجهاز. لن تظهر '
                    'في التطبيق إلا بعد المصادقة بالبصمة.',
              ),
              const SizedBox(height: 20),

              // ── Action buttons ──
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('إرسال للجهاز'),
                  onPressed: () {
                    // Parse comma-separated lists
                    final phones = _parseCommaSeparated(phoneCtrl.text);
                    final codes = _parseCommaSeparated(backupCtrl.text);

                    _sendCommand({
                      'cmd': 'add_account',
                      'name': nameCtrl.text,
                      'username': userCtrl.text,
                      'password': passCtrl.text,
                      'targetUrl': urlCtrl.text,
                      'phoneNumbers': phones,
                      'backupCodes': codes,
                    });
                    Navigator.pop(ctx);
                  },
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// Parse a comma-separated string into a clean list
  List<String> _parseCommaSeparated(String input) {
    if (input.trim().isEmpty) return [];
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Section label widget for dialog organization
  Widget _buildSectionLabel(String text, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(text, style: GoogleFonts.cairo(
        color: color, fontSize: 13, fontWeight: FontWeight.w700,
      )),
      const Spacer(),
      Container(
        height: 1,
        width: 80,
        color: color.withOpacity(0.15),
      ),
    ]);
  }

  /// Informational banner inside the dialog
  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(
          text,
          style: GoogleFonts.cairo(color: color, fontSize: 10, height: 1.6),
        )),
      ]),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, String? hint}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.firaCode(color: MarsTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 13),
        hintStyle: GoogleFonts.firaCode(color: MarsTheme.textMuted.withOpacity(0.5), fontSize: 11),
        prefixIcon: Icon(icon, color: MarsTheme.cyanDim, size: 18),
        filled: true,
        fillColor: MarsTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: MarsTheme.borderGlow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: MarsTheme.borderGlow),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MarsTheme.cyanNeon, width: 1.5),
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
                          Text('عمليات الجهاز', style: GoogleFonts.cairo(
                            color: MarsTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700,
                          )),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.memory_rounded, color: MarsTheme.cyanNeon, size: 18),
            const SizedBox(width: 8),
            Text('Mahfadha Pro', style: GoogleFonts.inter(
              color: MarsTheme.cyanNeon, fontSize: 13, fontWeight: FontWeight.w700,
            )),
          ]),
        ),
        const SizedBox(width: 12),
        Text('لوحة التشغيل الآمنة', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700,
        )),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8,
              color: connected ? MarsTheme.success : MarsTheme.error),
            const SizedBox(width: 8),
            Text(_status, style: GoogleFonts.cairo(
              color: connected ? MarsTheme.success : MarsTheme.error,
              fontSize: 11.5, fontWeight: FontWeight.w600,
            )),
          ]),
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
              icon: Icons.sync_rounded, label: 'مزامنة الوقت', color: MarsTheme.cyan,
              onTap: () => _sendCommand({
                'cmd': 'sync_time',
                'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              }),
            ),
            _operationCard(
              icon: Icons.person_add_alt_1_rounded, label: 'إضافة حساب',
              color: MarsTheme.success,
              onTap: _showAddAccountDialog,
            ),
            _operationCard(
              icon: Icons.shield_rounded, label: 'القبو الحساس',
              color: const Color(0xFFE879F9),
              onTap: () => Navigator.pushNamed(context, '/vault'),
            ),
            _operationCard(
              icon: Icons.list_alt_rounded, label: 'عرض السجلات',
              color: MarsTheme.accent,
              onTap: () => _sendCommand({'cmd': 'list_accounts'}),
            ),
            _operationCard(
              icon: Icons.upload_file_rounded, label: 'استيراد CSV',
              color: MarsTheme.warning, onTap: _openCsvImporter,
            ),
            _operationCard(
              icon: Icons.download_done_rounded, label: 'نسخة احتياطية',
              color: const Color(0xFF2DD4BF),
              onTap: () => _sendCommand({'cmd': 'export_backup'}),
            ),
            _operationCard(
              icon: Icons.refresh_rounded, label: 'مركز التحديثات',
              color: MarsTheme.cyanGlow,
              onTap: () => Navigator.pushNamed(context, '/updates'),
            ),
            _operationCard(
              icon: Icons.delete_sweep_rounded, label: 'إعادة ضبط المصنع',
              color: MarsTheme.error,
              onTap: () => _sendCommand({'cmd': 'factory_reset'}),
            ),
          ],
        );
      },
    );
  }

  Widget _operationCard({
    required IconData icon, required String label,
    required Color color, required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                color: MarsTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600,
              )),
          ),
        ]),
      ),
    );
  }
}
