import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

class ConnectionGateScreen extends StatefulWidget {
  const ConnectionGateScreen({super.key});

  @override
  State<ConnectionGateScreen> createState() => _ConnectionGateScreenState();
}

class _ConnectionGateScreenState extends State<ConnectionGateScreen>
    with SingleTickerProviderStateMixin {
  _GatePhase _phase = _GatePhase.scanning;
  String _statusText = 'جارٍ التحقق من اتصال جهاز Mahfadha Pro عبر USB.';
  String? _connectedPort;
  List<String> _availablePorts = [];
  Timer? _scanTimer;
  SerialPort? _activePort;
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _startPortScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _closePort();
    _glowController.dispose();
    super.dispose();
  }

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
          _statusText = 'تم اعتماد جهاز Mahfadha Pro وهو جاهز للدخول.';
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackdrop(),
          Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 420),
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              ),
              child: _buildGateCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.15 + (_glowController.value * 0.25),
              colors: [
                MarsTheme.cyanNeon.withOpacity(0.06 + _glowController.value * 0.02),
                MarsTheme.deepSpace,
                MarsTheme.spaceNavy,
              ],
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(36),
          decoration: MarsTheme.glassCard(borderRadius: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              Center(child: _buildStatusBadge()),
              const SizedBox(height: 24),
              Text(
                _phaseTitle,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _statusText,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textSecondary,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 24),
              if (_phase == _GatePhase.scanning || _phase == _GatePhase.handshaking)
                _buildScanSection(),
              if (_phase == _GatePhase.connected) _buildConnectedSection(),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _skipForTesting,
                  style: TextButton.styleFrom(
                    foregroundColor: MarsTheme.textMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  ),
                  child: Text(
                    'تخطي حالياً (للاختبار)',
                    style: GoogleFonts.cairo(
                      color: MarsTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MarsTheme.surfaceLight.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MarsTheme.borderGlow),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.memory_rounded, color: MarsTheme.cyanNeon, size: 16),
              const SizedBox(width: 8),
              Text(
                'جهاز Mahfadha Pro',
                style: GoogleFonts.cairo(
                  color: MarsTheme.cyanNeon,
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

  Widget _buildStatusBadge() {
    final color = switch (_phase) {
      _GatePhase.scanning => MarsTheme.cyanNeon,
      _GatePhase.handshaking => MarsTheme.warning,
      _GatePhase.connected => MarsTheme.success,
    };

    final icon = switch (_phase) {
      _GatePhase.scanning => Icons.usb_rounded,
      _GatePhase.handshaking => Icons.settings_input_component_outlined,
      _GatePhase.connected => Icons.task_alt_rounded,
    };

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.2 + (_glowController.value * 0.2)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08 + (_glowController.value * 0.08)),
                blurRadius: 36,
                spreadRadius: -10,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 42),
        );
      },
    );
  }

  Widget _buildScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            backgroundColor: MarsTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(
              _phase == _GatePhase.handshaking
                  ? MarsTheme.warning
                  : MarsTheme.cyanNeon,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: MarsTheme.surfaceLight.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MarsTheme.borderGlow),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.usb_rounded,
                        color: MarsTheme.cyanNeon,
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

  Widget _buildConnectedSection() {
    return _buildInfoLine(
      icon: Icons.settings_ethernet_rounded,
      color: MarsTheme.success,
      text: _connectedPort == null
          ? 'تم اعتماد الاتصال.'
          : 'المنفذ المعتمد: $_connectedPort',
    );
  }

  Widget _buildInfoLine({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.24)),
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
        return 'التحقق من جهاز Mahfadha Pro';
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
