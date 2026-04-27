import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Liquid Background Animation — Deep Space Navy with flowing
///  Cyan Neon liquid blobs that drift, pulse, and morph organically.
///  Designed for the Mahfadha Pro sidebar and main content area.
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

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    _ctrl3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarsTheme.spaceNavy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Liquid blob 1 — large, slow ──
          AnimatedBuilder(
            animation: Listenable.merge([_ctrl1, _ctrl2]),
            builder: (_, __) => _buildBlob(
              t1: _ctrl1.value,
              t2: _ctrl2.value,
              baseX: 0.7,
              baseY: 0.2,
              driftRadiusX: 0.15,
              driftRadiusY: 0.1,
              blobSize: 350,
              opacity: 0.06,
              blurRadius: 120,
            ),
          ),

          // ── Liquid blob 2 — medium, mid-speed ──
          AnimatedBuilder(
            animation: Listenable.merge([_ctrl2, _ctrl3]),
            builder: (_, __) => _buildBlob(
              t1: _ctrl2.value,
              t2: _ctrl3.value,
              baseX: 0.3,
              baseY: 0.6,
              driftRadiusX: 0.12,
              driftRadiusY: 0.08,
              blobSize: 280,
              opacity: 0.05,
              blurRadius: 100,
            ),
          ),

          // ── Liquid blob 3 — small accent ──
          AnimatedBuilder(
            animation: Listenable.merge([_ctrl3, _ctrl1]),
            builder: (_, __) => _buildBlob(
              t1: _ctrl3.value,
              t2: _ctrl1.value,
              baseX: 0.5,
              baseY: 0.8,
              driftRadiusX: 0.1,
              driftRadiusY: 0.12,
              blobSize: 200,
              opacity: 0.04,
              blurRadius: 80,
            ),
          ),

          // ── Vignette overlay for depth ──
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.3,
                  colors: [
                    Colors.transparent,
                    MarsTheme.spaceNavy.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // ── Child content ──
          widget.child,
        ],
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
                  color: MarsTheme.cyanNeon.withOpacity(opacity * 0.8),
                  blurRadius: blurRadius,
                  spreadRadius: blurRadius * 0.3,
                ),
              ],
              gradient: RadialGradient(
                colors: [
                  MarsTheme.cyanNeon.withOpacity(opacity),
                  MarsTheme.cyanNeon.withOpacity(opacity * 0.3),
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
