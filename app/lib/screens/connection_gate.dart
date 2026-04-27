import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/mars_theme.dart';
import '../providers/app_state.dart';

// ═══════════════════════════════════════════════════════════════════════
//  بوابة الاتصال — الدرع السيبراني
//  [FIX 1] لا جهاز = لا دخول. البوابة مقفلة حتى يرد الجهاز.
//  [FIX 5] حالة الإعداد تُقرأ من الجهاز مباشرة (ARE_YOU_SETUP?)
// ═══════════════════════════════════════════════════════════════════════

class ConnectionGateScreen extends StatefulWidget {
  const ConnectionGateScreen({super.key});
  @override
  State<ConnectionGateScreen> createState() => _ConnectionGateScreenState();
}

class _ConnectionGateScreenState extends State<ConnectionGateScreen>
    with SingleTickerProviderStateMixin {

  // ── حالات البوابة ──
  _GatePhase _phase = _GatePhase.scanning;
  String _statusText = 'جاري البحث عن الدرع السيبراني...';
  String? _connectedPort;
  List<String> _availablePorts = [];
  Timer? _scanTimer;
  SerialPort? _activePort;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _startPortScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _pulseController.dispose();
    _closePort();
    super.dispose();
  }

  void _closePort() {
    try {
      if (_activePort != null && _activePort!.isOpen) _activePort!.close();
    } catch (_) {}
    _activePort = null;
  }

  // ── المسح التلقائي للمنافذ كل 2 ثانية ──────────────────────────────
  void _startPortScan() {
    _scanPorts(); // أول مسح فوري
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_phase == _GatePhase.scanning) _scanPorts();
    });
  }

  void _scanPorts() {
    try {
      final ports = SerialPort.availablePorts;
      if (!mounted) return;
      setState(() => _availablePorts = ports);

      if (ports.isNotEmpty && _phase == _GatePhase.scanning) {
        // محاولة الاتصال بكل منفذ
        for (final portName in ports) {
          _tryHandshake(portName);
        }
      }
    } catch (e) {
      debugPrint('[GATE] خطأ في المسح: $e');
    }
  }

  // ── المصافحة مع الجهاز: إرسال ARE_YOU_SETUP? ───────────────────────
  Future<void> _tryHandshake(String portName) async {
    if (_phase != _GatePhase.scanning) return;

    setState(() {
      _phase = _GatePhase.handshaking;
      _statusText = 'جاري المصافحة مع $portName...';
    });

    SerialPort? port;
    try {
      port = SerialPort(portName);
      if (!port.openReadWrite()) {
        throw Exception('فشل فتح المنفذ');
      }

      _activePort = port;

      // إرسال سؤال الإعداد
      final command = '{"cmd":"ARE_YOU_SETUP?"}\n';
      port.write(Uint8List.fromList(utf8.encode(command)));

      // انتظار الرد (5 ثوانٍ كحد أقصى)
      final completer = Completer<String>();
      final reader = SerialPortReader(port);
      String buffer = '';

      final subscription = reader.stream.listen((data) {
        buffer += utf8.decode(data);
        if (buffer.contains('\n')) {
          if (!completer.isCompleted) completer.complete(buffer.trim());
        }
      });

      // مهلة 5 ثوانٍ
      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => '{"error":"TIMEOUT"}',
      );

      await subscription.cancel();

      _processHandshakeResponse(portName, response);

    } catch (e) {
      debugPrint('[GATE] فشل المصافحة مع $portName: $e');
      _closePort();
      if (mounted) {
        setState(() {
          _phase = _GatePhase.scanning;
          _statusText = 'لم يتم العثور على الدرع — جاري إعادة المسح...';
        });
      }
    }
  }

  // ── تحليل رد الجهاز ────────────────────────────────────────────────
  void _processHandshakeResponse(String portName, String rawResponse) {
    if (!mounted) return;

    try {
      final json = jsonDecode(rawResponse);
      final status = json['status']?.toString().toUpperCase() ?? '';

      if (status == 'YES' || status == 'READY' || status == 'SETUP_COMPLETE') {
        // [FIX 5] الجهاز مُعدّ → لوحة التحكم
        _scanTimer?.cancel();
        setState(() {
          _phase = _GatePhase.connected;
          _connectedPort = portName;
          _statusText = 'تم الاتصال بنجاح — الدرع جاهز';
        });

        // تحديث حالة التطبيق
        final appState = context.read<AppState>();
        appState.setDeviceConnected(true);
        appState.updateStatus('متصل بـ $portName');
        appState.setConnectedPort(portName);
        appState.markSetupComplete(); // [FIX 5] لا حلقة إعداد

        // انتقال بعد 1.5 ثانية
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        });

      } else if (status == 'NO' || status == 'NEEDS_SETUP') {
        // [FIX 5] الجهاز يحتاج إعداد → معالج الإعداد
        _scanTimer?.cancel();
        setState(() {
          _phase = _GatePhase.connected;
          _connectedPort = portName;
          _statusText = 'الجهاز يحتاج إعداداً أولياً...';
        });

        final appState = context.read<AppState>();
        appState.setDeviceConnected(true);
        appState.setConnectedPort(portName);

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/setup');
          }
        });

      } else {
        throw Exception('رد غير معروف: $rawResponse');
      }
    } catch (e) {
      debugPrint('[GATE] رد غير صالح: $e');
      _closePort();
      if (mounted) {
        setState(() {
          _phase = _GatePhase.scanning;
          _statusText = 'رد غير معروف من الجهاز — جاري إعادة المسح...';
        });
      }
    }
  }

  // ── اتصال يدوي عند الضغط على منفذ ──────────────────────────────────
  void _manualConnect(String portName) {
    if (_phase == _GatePhase.handshaking) return;
    setState(() => _phase = _GatePhase.scanning);
    _tryHandshake(portName);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  واجهة المستخدم — بوابة الدرع السيبراني
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── خلفية متحركة ──
          _buildAnimatedBackground(),
          // ── البوابة الزجاجية ──
          Center(child: _buildGateCard()),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                MarsTheme.cyanNeon.withOpacity(0.03 + _pulseController.value * 0.02),
                MarsTheme.spaceNavy,
              ],
              radius: 1.2 + _pulseController.value * 0.3,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGateCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _phase == _GatePhase.connected
                  ? MarsTheme.success.withOpacity(0.4)
                  : MarsTheme.cyanNeon.withOpacity(0.12),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: MarsTheme.cyanNeon.withOpacity(0.06),
                blurRadius: 80,
                spreadRadius: -20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── أيقونة الحالة ──
              _buildStatusIcon(),
              const SizedBox(height: 28),

              // ── العنوان ──
              Text(
                _getPhaseTitle(),
                style: GoogleFonts.cairo(
                  color: _phase == _GatePhase.connected
                      ? MarsTheme.success
                      : MarsTheme.cyanNeon,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ── الحالة ──
              Text(
                _statusText,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── مؤشر التقدم أو قائمة المنافذ ──
              if (_phase == _GatePhase.scanning || _phase == _GatePhase.handshaking)
                _buildScanSection(),

              if (_phase == _GatePhase.connected)
                _buildConnectedSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    double size = 72;

    switch (_phase) {
      case _GatePhase.scanning:
        icon = Icons.radar_rounded;
        color = MarsTheme.cyanNeon.withOpacity(0.6);
        break;
      case _GatePhase.handshaking:
        icon = Icons.handshake_outlined;
        color = MarsTheme.warning;
        break;
      case _GatePhase.connected:
        icon = Icons.verified_user_rounded;
        color = MarsTheme.success;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: AnimatedBuilder(
        key: ValueKey(_phase),
        animation: _pulseController,
        builder: (context, _) {
          return Container(
            width: size + 24,
            height: size + 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.15 + _pulseController.value * 0.15),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08 + _pulseController.value * 0.08),
                  blurRadius: 40,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Icon(icon, size: size, color: color),
          );
        },
      ),
    );
  }

  Widget _buildScanSection() {
    return Column(
      children: [
        // مؤشر تقدم
        SizedBox(
          width: 36, height: 36,
          child: CircularProgressIndicator(
            color: _phase == _GatePhase.handshaking
                ? MarsTheme.warning
                : MarsTheme.cyanNeon,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 24),

        // قائمة المنافذ المتاحة
        if (_availablePorts.isNotEmpty) ...[
          Text(
            'المنافذ المكتشفة:',
            style: GoogleFonts.cairo(
              color: MarsTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._availablePorts.map((port) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _manualConnect(port),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: MarsTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarsTheme.borderGlow),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.usb_rounded, color: MarsTheme.cyanNeon, size: 18),
                    const SizedBox(width: 10),
                    Text(port, style: GoogleFonts.firaCode(
                      color: MarsTheme.textPrimary, fontSize: 13)),
                    const Spacer(),
                    Text('اتصال', style: GoogleFonts.cairo(
                      color: MarsTheme.cyanDim, fontSize: 11)),
                  ],
                ),
              ),
            ),
          )),
        ],

        if (_availablePorts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MarsTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MarsTheme.error.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.usb_off, color: MarsTheme.error, size: 18),
                const SizedBox(width: 10),
                Text('لم يُكتشف أي جهاز — وصّل الدرع عبر USB',
                  style: GoogleFonts.cairo(color: MarsTheme.error, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConnectedSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MarsTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarsTheme.success.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: MarsTheme.success, size: 20),
          const SizedBox(width: 10),
          Text(
            'متصل بـ $_connectedPort',
            style: GoogleFonts.cairo(
              color: MarsTheme.success,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getPhaseTitle() {
    switch (_phase) {
      case _GatePhase.scanning:
        return 'بوابة الدرع السيبراني';
      case _GatePhase.handshaking:
        return 'جاري المصافحة الآمنة...';
      case _GatePhase.connected:
        return 'تم التحقق — الدرع جاهز';
    }
  }
}

/// مراحل البوابة
enum _GatePhase {
  scanning,
  handshaking,
  connected,
}
