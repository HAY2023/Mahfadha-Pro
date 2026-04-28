import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Liquid Background Animation — [V6] Hardware Breathing Glow
///
///  Reacts dynamically to the device's HardwareGlowState:
///
///  • GHOST MODE (locked):
///    Deep quiet Space Navy (#0A0E14), very slow breathing opacity
///    animation with dim cyan blobs.
///
///  • UNLOCKED (fingerprint OK):
///    Cyan (#00FFFF) ripple effect from center, active glow,
///    faster blob movement with brighter accents.
///
///  • THERMAL / BREACH ALERT:
///    Fast-pulsing red (#FF0000) alarm state, all blobs turn red,
///    entire background flashes with urgent border glow.
/// ══════════════════════════════════════════════════════════════════════
class LiquidBackground extends StatefulWidget {
  final Widget child;

  const LiquidBackground({super.key, required this.child});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with TickerProviderStateMixin {
  late AnimationController _ctrl1;
  late AnimationController _ctrl2;
  late AnimationController _ctrl3;
  late AnimationController _breathCtrl;
  late AnimationController _rippleCtrl;
  late AnimationController _alertCtrl;

  HardwareGlowState _lastGlowState = HardwareGlowState.ghost;

  @override
  void initState() {
    super.initState();

    // ── Standard liquid blob animation ──
    _ctrl1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _ctrl2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _ctrl3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    // ── Slow breathing for Ghost Mode ──
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // ── Fast ripple for Unlock transition ──
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // ── Alert pulse — fast, aggressive ──
    _alertCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    _ctrl3.dispose();
    _breathCtrl.dispose();
    _rippleCtrl.dispose();
    _alertCtrl.dispose();
    super.dispose();
  }

  void _onGlowStateChanged(HardwareGlowState newState) {
    if (newState == _lastGlowState) return;
    _lastGlowState = newState;

    switch (newState) {
      case HardwareGlowState.ghost:
        _alertCtrl.stop();
        _rippleCtrl.stop();
        _breathCtrl.repeat(reverse: true);
        break;
      case HardwareGlowState.unlocked:
        _alertCtrl.stop();
        _rippleCtrl.forward(from: 0);
        _breathCtrl.stop();
        break;
      case HardwareGlowState.alert:
        _breathCtrl.stop();
        _rippleCtrl.stop();
        _alertCtrl.repeat(reverse: true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final glowState = appState.hardwareGlowState;
        _onGlowStateChanged(glowState);

        return AnimatedBuilder(
          animation: Listenable.merge([
            _ctrl1,
            _ctrl2,
            _ctrl3,
            _breathCtrl,
            _rippleCtrl,
            _alertCtrl,
          ]),
          builder: (context, _) => _buildBackground(glowState),
        );
      },
    );
  }

  Widget _buildBackground(HardwareGlowState glowState) {
    // ── Select color palette based on hardware state ──
    final Color blobColor;
    final Color bgColor;
    final double baseOpacity;
    final double breathMultiplier;

    switch (glowState) {
      case HardwareGlowState.ghost:
        blobColor = MarsTheme.cyanNeon;
        bgColor = MarsTheme.spaceNavy;
        baseOpacity = 0.03 + _breathCtrl.value * 0.03;
        breathMultiplier = 0.6;
        break;
      case HardwareGlowState.unlocked:
        blobColor = MarsTheme.cyanNeon;
        bgColor = MarsTheme.spaceNavy;
        baseOpacity = 0.06;
        breathMultiplier = 1.0;
        break;
      case HardwareGlowState.alert:
        blobColor = const Color(0xFFFF0000);
        bgColor = const Color(0xFF0A0408);
        baseOpacity = 0.08 + _alertCtrl.value * 0.06;
        breathMultiplier = 1.5;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Liquid blob 1 — large, slow ──
          _buildBlob(
            t1: _ctrl1.value,
            t2: _ctrl2.value,
            baseX: 0.7,
            baseY: 0.2,
            driftRadiusX: 0.15 * breathMultiplier,
            driftRadiusY: 0.1 * breathMultiplier,
            blobSize: 350,
            opacity: baseOpacity,
            blurRadius: 120,
            color: blobColor,
          ),

          // ── Liquid blob 2 — medium, mid-speed ──
          _buildBlob(
            t1: _ctrl2.value,
            t2: _ctrl3.value,
            baseX: 0.3,
            baseY: 0.6,
            driftRadiusX: 0.12 * breathMultiplier,
            driftRadiusY: 0.08 * breathMultiplier,
            blobSize: 280,
            opacity: baseOpacity * 0.85,
            blurRadius: 100,
            color: blobColor,
          ),

          // ── Liquid blob 3 — small accent ──
          _buildBlob(
            t1: _ctrl3.value,
            t2: _ctrl1.value,
            baseX: 0.5,
            baseY: 0.8,
            driftRadiusX: 0.1 * breathMultiplier,
            driftRadiusY: 0.12 * breathMultiplier,
            blobSize: 200,
            opacity: baseOpacity * 0.7,
            blurRadius: 80,
            color: blobColor,
          ),

          // ── [V6] Unlock Ripple Effect ──
          if (_rippleCtrl.isAnimating || _rippleCtrl.value > 0)
            _buildRipple(),

          // ── [V6] Alert border glow ──
          if (glowState == HardwareGlowState.alert)
            _buildAlertBorder(),

          // ── Vignette overlay for depth ──
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.3,
                  colors: [
                    Colors.transparent,
                    bgColor.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // ── [V6] BackdropFilter — subtle blur ──
          if (glowState == HardwareGlowState.ghost)
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: const SizedBox.expand(),
                ),
              ),
            ),

          // ── Child content ──
          widget.child,
        ],
      ),
    );
  }

  Widget _buildRipple() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;
        final maxRadius =
            math.sqrt(centerX * centerX + centerY * centerY) * 2;
        final currentRadius = _rippleCtrl.value * maxRadius;
        final opacity = (1.0 - _rippleCtrl.value) * 0.25;

        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RipplePainter(
                center: Offset(centerX, centerY),
                radius: currentRadius,
                color: MarsTheme.cyanNeon.withOpacity(opacity.clamp(0, 1)),
                strokeWidth: 3 + (1 - _rippleCtrl.value) * 8,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertBorder() {
    final opacity = 0.2 + _alertCtrl.value * 0.4;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFFF0000).withOpacity(opacity),
              width: 2 + _alertCtrl.value * 2,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(0xFFFF0000).withOpacity(opacity * 0.5),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlob({
    required double t1,
    required double t2,
    required double baseX,
    required double baseY,
    required double driftRadiusX,
    required double driftRadiusY,
    required double blobSize,
    required double opacity,
    required double blurRadius,
    required Color color,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        final dx = math.cos(t1 * 2 * math.pi) * w * driftRadiusX;
        final dy = math.sin(t2 * 2 * math.pi) * h * driftRadiusY;

        // Pulse size
        final pulse = 1.0 + math.sin(t1 * 4 * math.pi) * 0.08;
        final size = blobSize * pulse;

        return Positioned(
          left: w * baseX - size / 2 + dx,
          top: h * baseY - size / 2 + dy,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(opacity * 0.8),
                  blurRadius: blurRadius,
                  spreadRadius: blurRadius * 0.3,
                ),
              ],
              gradient: RadialGradient(
                colors: [
                  color.withOpacity(opacity),
                  color.withOpacity(opacity * 0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for the unlock ripple effect
class _RipplePainter extends CustomPainter {
  final Offset center;
  final double radius;
  final Color color;
  final double strokeWidth;

  _RipplePainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);

    // Inner glow ring
    final glowPaint = Paint()
      ..color = color.withOpacity(color.opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}
