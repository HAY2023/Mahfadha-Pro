import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/esp32_serial_service.dart';
import '../theme/mars_theme.dart';
import 'csv_importer_and_health.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  Esp32SerialService? _serialService;
  String _status = 'غير متصل';
  Timer? _telemetryTimer;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

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
    _serialService?.dispose();
    _serialService = Esp32SerialService(portName: portName);
    
    _serialService!.onStatus.listen((status) {
      if (!mounted) return;
      setState(() {
        if (status == 'connected') {
          _status = 'متصل عبر $portName — بانتظار المصادقة الحيوية';
        } else {
          _status = status;
        }
      });
    });

    _serialService!.onData.listen((json) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      
      if (json['status'] == 'telemetry') {
        final dataStr = json['data']?.toString() ?? '';
        appState.processTelemetry(dataStr);
        _checkThermalState(appState);
      } else if (json['status'] == 'event') {
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
    });

    _serialService!.connect();

    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _serialService?.sendCommand({'cmd': 'get_telemetry'});
    });
  }

  void _checkThermalState(AppState state) {
    if (state.isThermalEmergency) {
      _telemetryTimer?.cancel();
      _showThermalAlert();
      _serialService?.sendCommand({'cmd': 'SHUTDOWN'});
      
      Future.delayed(const Duration(seconds: 4), () {
        _serialService?.dispose();
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
                  BoxShadow(color: MarsTheme.error.withOpacity(0.3), blurRadius: 100, spreadRadius: 10),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SingleChildScrollView(
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x990A0E14), Color(0xCC0D1117)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00FFFF).withOpacity(0.1), blurRadius: 40),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.person_add_alt_1, color: Color(0xFFD4AF37), size: 24),
                    const SizedBox(width: 10),
                    Text('إضافة حساب جديد', style: GoogleFonts.cairo(
                      color: const Color(0xFF00FFFF), fontSize: 20, fontWeight: FontWeight.w700,
                    )),
                  ]),
                  const SizedBox(height: 20),
                  _inputField(nameCtrl, 'اسم الحساب', Icons.label),
                  const SizedBox(height: 12),
                  _inputField(userCtrl, 'اسم المستخدم', Icons.person),
                  const SizedBox(height: 12),
                  _inputField(passCtrl, 'كلمة المرور', Icons.lock, obscure: true),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.security, size: 18),
                      label: const Text('تشفير وحفظ'),
                      onPressed: () {
                        _serialService?.sendCommand({
                          'cmd': 'add_account',
                          'name': nameCtrl.text,
                          'username': userCtrl.text,
                          'password': passCtrl.text,
                        });
                        Navigator.pop(ctx);
                      },
                    )),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.white54, fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF00FFFF), size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _serialService?.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status.contains('متصل') || _status.contains('المصادقة');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
        image: DecorationImage(
          image: AssetImage('assets/tray/bg_pattern.png'), // Subtle background texture if available
          fit: BoxFit.cover,
          opacity: 0.05,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
        child: Column(
          children: [
            _buildFuturisticHeader(connected),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Consumer<AppState>(
                      builder: (context, state, _) {
                        return _buildGlassmorphicMonitor(state);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildGlassmorphicOperations(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticHeader(bool connected) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00FFFF).withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF00FFFF).withOpacity(0.05), blurRadius: 20),
            ],
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withOpacity(_glowAnimation.value),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.security, color: Color(0xFF00FFFF), size: 24),
                  );
                },
              ),
              const SizedBox(width: 16),
              Text('CIPHER VAULT PRO', style: GoogleFonts.orbitron(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2,
              )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (connected ? const Color(0xFF34D399) : MarsTheme.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (connected ? const Color(0xFF34D399) : MarsTheme.error).withOpacity(0.5),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fiber_manual_record, size: 10,
                    color: connected ? const Color(0xFF34D399) : MarsTheme.error),
                  const SizedBox(width: 8),
                  Text(_status, style: GoogleFonts.cairo(
                    color: connected ? const Color(0xFF34D399) : MarsTheme.error,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  )),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassmorphicMonitor(AppState state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0x2A152033), Color(0x1A0D1117)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: Color(0xFFD4AF37), size: 22),
                  const SizedBox(width: 10),
                  Text('نظام المراقبة الحيوي', style: GoogleFonts.cairo(
                    color: const Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold,
                  )),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNeonGauge('الحرارة', state.temperature, 80.0, '°C', Icons.thermostat, const Color(0xFF00FFFF)),
                  _buildNeonGauge('المساحة', 100.0 - state.storageUsed, 100.0, '%', Icons.storage, const Color(0xFFD4AF37)),
                  _buildNeonGauge('الاستقرار', state.systemLoad, 100.0, '%', Icons.memory, const Color(0xFFB57EDC), invert: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeonGauge(String label, double value, double maxValue, String unit, IconData icon, Color neonColor, {bool invert = false}) {
    Color gaugeColor = neonColor;
    if (invert && value > 80) gaugeColor = MarsTheme.error;
    
    final percentage = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: gaugeColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
                ],
              ),
              child: CircularProgressIndicator(
                value: percentage,
                strokeWidth: 8,
                backgroundColor: gaugeColor.withOpacity(0.1),
                color: gaugeColor,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                Text('${value.toStringAsFixed(1)}$unit', style: GoogleFonts.firaCode(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(label, style: GoogleFonts.cairo(
          color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600,
        )),
      ],
    );
  }

  Widget _buildGlassmorphicOperations() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF00FFFF).withOpacity(0.15)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('العمليات المركزية', style: GoogleFonts.cairo(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: constraints.maxWidth >= 800 ? 4 : 3,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildNeonButton('مزامنة الوقت', Icons.sync, const Color(0xFF00FFFF), () => _serialService?.sendCommand({
                        'cmd': 'sync_time', 'time': DateTime.now().millisecondsSinceEpoch ~/ 1000
                      })),
                      _buildNeonButton('إضافة حساب', Icons.person_add, const Color(0xFF34D399), _showAddAccountDialog),
                      _buildNeonButton('الخزنة', Icons.shield, const Color(0xFFD4AF37), () => context.read<AppState>().setCurrentPage(SidebarPage.accounts)),
                      _buildNeonButton('استيراد', Icons.upload_file, const Color(0xFFB57EDC), _openCsvImporter),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeonButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.1), blurRadius: 15),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(label, style: GoogleFonts.cairo(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}
