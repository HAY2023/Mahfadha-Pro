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

// ═══════════════════════════════════════════════════════════════════════════
//  CONNECTION GATE — Legendary Mars UI (Glassmorphism + Cyan Neon Glow)
//
//  ● Deep Space Navy (#0A0E14) background
//  ● Animated Cyan Neon (#00FFFF) glowing orb in background
//  ● Frosted-glass content card via BackdropFilter + ImageFilter.blur
//  ● Subtle white border on glass card
//  ● Dev skip button "تخطي حالياً (للاختبار)" at the bottom
// ═══════════════════════════════════════════════════════════════════════════

class ConnectionGateScreen extends StatefulWidget {
  const ConnectionGateScreen({super.key});

  @override
  State<ConnectionGateScreen> createState() => _ConnectionGateScreenState();
}

class _ConnectionGateScreenState extends State<ConnectionGateScreen>
    with TickerProviderStateMixin {
  _GatePhase _phase = _GatePhase.scanning;
  String _statusText = 'جارٍ التحقق من اتصال وحدة التشفير المادية عبر USB.';
  String? _connectedPort;
  List<String> _availablePorts = [];
  Timer? _scanTimer;
  SerialPort? _activePort;

  // ── Animation controllers ──
  late final AnimationController _glowController;
  late final AnimationController _orbitController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    // Glow pulsation for the neon orb & badge
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    // Slow orbit rotation for the neon orb
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Secondary pulse for the status badge ring
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _startPortScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _closePort();
    _glowController.dispose();
    _orbitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Serial port scanning & handshake (unchanged business logic)
  // ═══════════════════════════════════════════════════════════════════════

  void _startPortScan() {
    _scanPorts();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_phase == _GatePhase.scanning) {
        _scanPorts();
      }
    });
  }

  void _scanPorts() {
    try {
      final ports = SerialPort.availablePorts;
      if (!mounted) return;

      setState(() => _availablePorts = ports);

      if (ports.isNotEmpty && _phase == _GatePhase.scanning) {
        for (final portName in ports) {
          _tryHandshake(portName);
        }
      }
    } catch (error) {
      debugPrint('[ConnectionGate] Scan error: $error');
    }
  }

  Future<void> _tryHandshake(String portName) async {
    if (_phase != _GatePhase.scanning) return;

    setState(() {
      _phase = _GatePhase.handshaking;
      _statusText = 'جارٍ التحقق من استجابة الجهاز على المنفذ $portName.';
    });

    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        throw Exception('تعذر فتح المنفذ.');
      }

      _activePort = port;
      const command = '{"cmd":"ARE_YOU_SETUP?"}\n';
      port.write(Uint8List.fromList(utf8.encode(command)));

      final responseCompleter = Completer<String>();
      final reader = SerialPortReader(port);
      var buffer = '';

      final subscription = reader.stream.listen((data) {
        buffer += utf8.decode(data);
        if (buffer.contains('\n') && !responseCompleter.isCompleted) {
          responseCompleter.complete(buffer.trim());
        }
      });

      final response = await responseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => '{"error":"TIMEOUT"}',
      );

      await subscription.cancel();
      _processHandshakeResponse(portName, response);
    } catch (error) {
      debugPrint('[ConnectionGate] Handshake failed on $portName: $error');
      _closePort();
      if (!mounted) return;

      setState(() {
        _phase = _GatePhase.scanning;
        _statusText = 'لم يتم اعتماد هذا المنفذ. جارٍ متابعة البحث عن الجهاز.';
      });
    }
  }

  void _processHandshakeResponse(String portName, String rawResponse) {
    if (!mounted) return;

    try {
      final decoded = jsonDecode(rawResponse) as Map<String, dynamic>;
      final status = decoded['status']?.toString().toUpperCase() ?? '';
      final appState = context.read<AppState>();

      if (status == 'YES' ||
          status == 'READY' ||
          status == 'SETUP_COMPLETE') {
        _scanTimer?.cancel();
        setState(() {
          _phase = _GatePhase.connected;
          _connectedPort = portName;
          _statusText = 'تم اعتماد وحدة التشفير المادية وهي جاهزة للدخول.';
        });

        appState.setDeviceConnected(true);
        appState.setConnectedPort(portName);
        appState.updateStatus('متصل عبر $portName');
        appState.markSetupComplete();

        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          }
        });
        return;
      }

      if (status == 'NO' || status == 'NEEDS_SETUP') {
        _scanTimer?.cancel();
        setState(() {
          _phase = _GatePhase.connected;
          _connectedPort = portName;
          _statusText =
              'تم التعرف على الجهاز. يلزم تنفيذ التهيئة الأولية قبل المتابعة.';
        });

        appState.setDeviceConnected(true);
        appState.setConnectedPort(portName);
        appState.updateStatus('متصل ويتطلب تهيئة أولية');
        appState.markSetupNeeded();

        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/setup');
          }
        });
        return;
      }

      throw Exception('Unexpected response: $rawResponse');
    } catch (error) {
      debugPrint('[ConnectionGate] Invalid response: $error');
      _closePort();
      if (!mounted) return;

      setState(() {
        _phase = _GatePhase.scanning;
        _statusText = 'تم استلام رد غير صالح. جارٍ إعادة المحاولة تلقائياً.';
      });
    }
  }

  void _manualConnect(String portName) {
    if (_phase == _GatePhase.handshaking) return;
    setState(() => _phase = _GatePhase.scanning);
    _tryHandshake(portName);
  }

  /// Dev skip — bypass hardware waiting and go directly to the Dashboard
  Future<void> _skipForTesting() async {
    _scanTimer?.cancel();
    _closePort();

    final appState = context.read<AppState>();
    appState.setDeviceConnected(false);
    appState.setConnectedPort(null);
    appState.updateStatus('وضع الاختبار المحلي');
    appState.markSetupComplete();

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  void _closePort() {
    try {
      if (_activePort?.isOpen ?? false) {
        _activePort!.close();
      }
    } catch (_) {}
    _activePort = null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BUILD — Legendary Mars Glassmorphism UI
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0E14), // Deep Space Navy
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 0: Solid deep space background ──
          Container(color: const Color(0xFF0A0E14)),

          // ── Layer 1: Animated Cyan Neon glowing orb ──
          _buildNeonOrbBackground(),

          // ── Layer 2: Subtle grid / noise overlay for depth ──
          _buildSubtleNoiseOverlay(),

          // ── Layer 3: Centered frosted glass card ──
          Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 30 * (1 - value)),
                  child: child,
                ),
              ),
              child: _buildFrostedGlassCard(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── NEON ORB — glowing cyan circular blurred container ─────────────
  Widget _buildNeonOrbBackground() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowController, _orbitController]),
      builder: (context, _) {
        final glowVal = _glowController.value;
        final orbitVal = _orbitController.value;
        final size = MediaQuery.of(context).size;

        // Orb drifts in a subtle ellipse
        final dx = math.cos(orbitVal * 2 * math.pi) * 40;
        final dy = math.sin(orbitVal * 2 * math.pi) * 25;

        return Stack(
          children: [
            // Primary large glow
            Positioned(
              left: size.width * 0.5 - 200 + dx,
              top: size.height * 0.35 - 200 + dy,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFFF)
                          .withOpacity(0.08 + glowVal * 0.06),
                      blurRadius: 180 + glowVal * 40,
                      spreadRadius: 20 + glowVal * 15,
                    ),
                  ],
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00FFFF)
                          .withOpacity(0.07 + glowVal * 0.05),
                      const Color(0xFF00FFFF).withOpacity(0.02),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Secondary smaller accent glow (offset)
            Positioned(
              left: size.width * 0.65 - 80 - dx * 0.5,
              top: size.height * 0.55 - 80 - dy * 0.5,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00FFFF)
                          .withOpacity(0.04 + glowVal * 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Subtle noise/vignette for cinematic depth ──────────────────────
  Widget _buildSubtleNoiseOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.2,
            colors: [
              Colors.transparent,
              const Color(0xFF0A0E14).withOpacity(0.7),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  FROSTED GLASS CARD — BackdropFilter + ImageFilter.blur
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildFrostedGlassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            // Frosted glass fill
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(28),
            // Subtle white border for premium feel
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FFFF).withOpacity(0.05),
                blurRadius: 60,
                spreadRadius: -10,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              Center(child: _buildStatusBadge()),
              const SizedBox(height: 24),

              // Phase title
              Text(
                _phaseTitle,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              // Status text
              Text(
                _statusText,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textSecondary,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 24),

              // Phase-specific content
              if (_phase == _GatePhase.scanning ||
                  _phase == _GatePhase.handshaking)
                _buildScanSection(),
              if (_phase == _GatePhase.connected) _buildConnectedSection(),

              const SizedBox(height: 24),

              // ── Dev skip button ──
              Center(
                child: TextButton(
                  onPressed: _skipForTesting,
                  style: TextButton.styleFrom(
                    foregroundColor: MarsTheme.textMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.skip_next_rounded,
                        color: MarsTheme.textMuted.withOpacity(0.6),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'تخطي حالياً (للاختبار)',
                        style: GoogleFonts.cairo(
                          color: MarsTheme.textMuted.withOpacity(0.7),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header row ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      children: [
        // Device badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00FFFF).withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF00FFFF).withOpacity(0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.memory_rounded,
                color: Color(0xFF00FFFF),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'وحدة التشفير المادية',
                style: GoogleFonts.cairo(
                  color: const Color(0xFF00FFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          'فحص الاتصال',
          style: GoogleFonts.cairo(
            color: MarsTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─── Status badge — animated glowing ring ───────────────────────────
  Widget _buildStatusBadge() {
    final color = switch (_phase) {
      _GatePhase.scanning => const Color(0xFF00FFFF),
      _GatePhase.handshaking => MarsTheme.warning,
      _GatePhase.connected => MarsTheme.success,
    };

    final icon = switch (_phase) {
      _GatePhase.scanning => Icons.usb_rounded,
      _GatePhase.handshaking => Icons.settings_input_component_outlined,
      _GatePhase.connected => Icons.task_alt_rounded,
    };

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseVal = _pulseController.value;
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.15 + pulseVal * 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.06 + pulseVal * 0.1),
                blurRadius: 40 + pulseVal * 20,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(icon, color: color, size: 42),
          ),
        );
      },
    );
  }

  // ─── Scan section — progress + port list ────────────────────────────
  Widget _buildScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            backgroundColor: Colors.white.withOpacity(0.04),
            valueColor: AlwaysStoppedAnimation<Color>(
              _phase == _GatePhase.handshaking
                  ? MarsTheme.warning
                  : const Color(0xFF00FFFF),
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          _availablePorts.isEmpty
              ? 'لم يتم رصد أي منافذ متاحة حتى الآن.'
              : 'المنافذ المتاحة للتجربة اليدوية',
          style: GoogleFonts.cairo(
            color: MarsTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        if (_availablePorts.isEmpty)
          _buildInfoLine(
            icon: Icons.usb_off_rounded,
            color: MarsTheme.error,
            text: 'وصّل الجهاز عبر USB ثم اترك التطبيق يعيد المسح تلقائياً.',
          ),

        if (_availablePorts.isNotEmpty)
          ..._availablePorts.map(
            (port) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _manualConnect(port),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF00FFFF).withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.usb_rounded,
                        color: Color(0xFF00FFFF),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        port,
                        style: GoogleFonts.firaCode(
                          color: MarsTheme.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'تحقق يدوي',
                        style: GoogleFonts.cairo(
                          color: MarsTheme.cyanDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Connected section ──────────────────────────────────────────────
  Widget _buildConnectedSection() {
    return _buildInfoLine(
      icon: Icons.settings_ethernet_rounded,
      color: MarsTheme.success,
      text: _connectedPort == null
          ? 'تم اعتماد الاتصال.'
          : 'المنفذ المعتمد: $_connectedPort',
    );
  }

  // ─── Reusable info-line component ───────────────────────────────────
  Widget _buildInfoLine({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                color: color == MarsTheme.success
                    ? MarsTheme.textPrimary
                    : MarsTheme.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _phaseTitle {
    switch (_phase) {
      case _GatePhase.scanning:
        return 'التحقق من وحدة التشفير المادية';
      case _GatePhase.handshaking:
        return 'جارٍ اعتماد قناة الاتصال';
      case _GatePhase.connected:
        return 'تم اعتماد الاتصال';
    }
  }
}

enum _GatePhase {
  scanning,
  handshaking,
  connected,
}
