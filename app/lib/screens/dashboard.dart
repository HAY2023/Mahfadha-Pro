import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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
  Timer? _telemetryTimer;

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

        // ── [V5] Start polling telemetry ──
        _telemetryTimer?.cancel();
        _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          _sendCommand({'cmd': 'get_telemetry'});
        });

        final reader = SerialPortReader(_port!);
        reader.stream.listen((data) {
          try {
            final message = utf8.decode(data).trim();
            if (message.isEmpty) return;

            // Handle potential multiple JSON objects in one burst
            final lines = message.split('\n');
            for (final line in lines) {
              if (line.isEmpty) continue;
              final json = jsonDecode(line);
              final appState = context.read<AppState>();
              
              if (json['status'] == 'telemetry') {
                final dataStr = json['data']?.toString() ?? '';
                appState.processTelemetry(dataStr);
                _checkThermalState(appState);
              } 
              else if (json['status'] == 'event') {
                final eventMessage = json['message']?.toString() ?? '';

                switch (eventMessage) {
                  case 'FINGERPRINT_VERIFIED':
                    setState(() => _status = 'تمت المصادقة الحيوية بنجاح ✓');
                    appState.onFingerprintVerified();
                    break;
                  case 'BIOMETRIC_UNLOCKED':
                    setState(() => _status = 'تمت المصادقة الحيوية بنجاح');
                    appState.onBiometricUnlocked();
                    break;
                  case 'FINGERPRINT_SCANNING':
                    setState(() => _status = 'جارٍ مسح البصمة...');
                    appState.onBiometricScanning();
                    break;
                  case 'FINGERPRINT_FAILED':
                    setState(() => _status = 'فشل التحقق من البصمة');
                    appState.onBiometricFailed();
                    break;
                  case 'BIOMETRIC_LOCKED':
                    setState(() => _status = 'وحدة التشفير متصلة وتنتظر التحقق الحيوي');
                    appState.lockBiometricVault();
                    break;
                }
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

  void _checkThermalState(AppState state) {
    if (state.isThermalEmergency) {
      _telemetryTimer?.cancel();
      _showThermalAlert();
      _sendCommand({'cmd': 'SHUTDOWN'});
      
      // Disconnect and route to ConnectionGate
      Future.delayed(const Duration(seconds: 4), () {
        if (_port?.isOpen ?? false) {
          _port!.close();
        }
        state.fullReset();
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
      });
    }
  }

  void _showThermalAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) => Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: MarsTheme.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: MarsTheme.error, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: MarsTheme.error.withOpacity(0.3),
                    blurRadius: 100,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_rounded, color: MarsTheme.error, size: 80),
                      const SizedBox(height: 20),
                      Text('!! تحذير حراري حرج !!', style: GoogleFonts.cairo(
                        color: MarsTheme.error, fontSize: 32, fontWeight: FontWeight.bold,
                      )),
                      const SizedBox(height: 16),
                      Text('درجة حرارة وحدة التشفير مرتفعة جداً (60°C أو أعلى). سيتم إيقاف التشغيل فوراً لحماية بياناتك ولتجنب تلف العتاد المادي.', 
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                        color: MarsTheme.textPrimary, fontSize: 16, height: 1.5,
                      )),
                      const SizedBox(height: 24),
                      CircularProgressIndicator(color: MarsTheme.error),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) {
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
              _inputField(phoneCtrl, 'جهات الاتصال الآمنة (فاصل: ,)', Icons.phone_android,
                hint: '+213xxxxxxxxx, +1xxxxxxxxxx'),
              const SizedBox(height: 10),
              _inputField(backupCtrl, 'أكواد احتياطية (فاصل: ,)', Icons.vpn_key,
                hint: 'XXXX-XXXX, YYYY-YYYY'),
              const SizedBox(height: 6),
              _buildInfoBanner(
                icon: Icons.security,
                color: MarsTheme.warning,
                text: 'هذه البيانات تُشفَّر وتُخزَّن حصرياً على وحدة التشفير المادية. لن تظهر '
                    'في التطبيق إلا بعد المصادقة الحيوية.',
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
                  label: const Text('تشفير وإرسال'),
                  onPressed: () {
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

  List<String> _parseCommaSeparated(String input) {
    if (input.trim().isEmpty) return [];
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

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
    _telemetryTimer?.cancel();
    if (_port?.isOpen ?? false) {
      _port!.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status.contains('متصل') || _status.contains('المصادقة');

    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          children: [
            _buildHeader(connected),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                children: [
                  // ── [V5] Telemetry Monitor ──
                  Consumer<AppState>(
                    builder: (context, state, _) {
                      return _buildPerformanceMonitor(state);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: MarsTheme.glassCard(borderRadius: 24),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عمليات وحدة التشفير المادية', style: GoogleFonts.cairo(
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

  Widget _buildPerformanceMonitor(AppState state) {
    return Container(
      decoration: MarsTheme.glassCard(borderRadius: 20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: MarsTheme.cyanNeon, size: 20),
              const SizedBox(width: 8),
              Text('حالة وحدة التشفير', style: GoogleFonts.cairo(
                color: MarsTheme.cyanNeon, fontSize: 16, fontWeight: FontWeight.bold,
              )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGauge(
                label: 'درجة الحرارة',
                value: state.temperature,
                maxValue: 80.0,
                unit: '°C',
                icon: Icons.thermostat_rounded,
                isTemperature: true,
              ),
              _buildGauge(
                label: 'المساحة المتوفرة',
                value: 100.0 - state.storageUsed,
                maxValue: 100.0,
                unit: '%',
                icon: Icons.storage_rounded,
                color: MarsTheme.cyanNeon,
              ),
              _buildGauge(
                label: 'استقرار النظام',
                value: state.systemLoad,
                maxValue: 100.0,
                unit: '%',
                icon: Icons.memory_rounded,
                color: MarsTheme.accent,
                invertColor: true, // Lower is better
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGauge({
    required String label,
    required double value,
    required double maxValue,
    required String unit,
    required IconData icon,
    Color? color,
    bool isTemperature = false,
    bool invertColor = false,
  }) {
    Color gaugeColor = color ?? MarsTheme.success;
    
    if (isTemperature) {
      if (value < 40) gaugeColor = MarsTheme.success;
      else if (value < 55) gaugeColor = MarsTheme.warning;
      else gaugeColor = MarsTheme.error;
    } else if (invertColor) {
      if (value > 80) gaugeColor = MarsTheme.error;
      else if (value > 60) gaugeColor = MarsTheme.warning;
      else gaugeColor = MarsTheme.success;
    }

    final double percentage = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: percentage,
                strokeWidth: 6,
                backgroundColor: gaugeColor.withOpacity(0.1),
                color: gaugeColor,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: gaugeColor, size: 16),
                const SizedBox(height: 2),
                Text(
                  '${value.toStringAsFixed(1)}$unit',
                  style: GoogleFonts.firaCode(
                    color: MarsTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: GoogleFonts.cairo(
            color: MarsTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
            Text('CipherVault Pro', style: GoogleFonts.inter(
              color: MarsTheme.cyanNeon, fontSize: 13, fontWeight: FontWeight.w700,
            )),
          ]),
        ),
        const SizedBox(width: 12),
        Text('لوحة التحكم', style: GoogleFonts.cairo(
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
              icon: Icons.shield_rounded, label: 'خزنة صفرية المعرفة',
              color: const Color(0xFFE879F9),
              onTap: () => context.read<AppState>().setCurrentPage(SidebarPage.accounts),
            ),
            _operationCard(
              icon: Icons.list_alt_rounded, label: 'سجل الحسابات',
              color: MarsTheme.accent,
              onTap: () => _sendCommand({'cmd': 'list_accounts'}),
            ),
            _operationCard(
              icon: Icons.upload_file_rounded, label: 'استيراد السجلات',
              color: MarsTheme.warning, onTap: _openCsvImporter,
            ),
            _operationCard(
              icon: Icons.download_done_rounded, label: 'نسخة احتياطية مشفرة',
              color: const Color(0xFF2DD4BF),
              onTap: () => _sendCommand({'cmd': 'export_backup'}),
            ),
            _operationCard(
              icon: Icons.refresh_rounded, label: 'تحديث النظام',
              color: MarsTheme.cyanGlow,
              onTap: () => context.read<AppState>().setCurrentPage(SidebarPage.updates),
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
