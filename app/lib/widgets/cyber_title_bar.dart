import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/mars_theme.dart';

// ═══════════════════════════════════════════════════════════════════════
//  شريط العنوان المخصص — Cyber Title Bar
//  [FIX 4] أزرار إغلاق وتصغير مخصصة للنافذة بلا إطار
// ═══════════════════════════════════════════════════════════════════════

class CyberTitleBar extends StatelessWidget {
  const CyberTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // السحب لتحريك النافذة
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: MarsTheme.spaceNavy,
          border: Border(
            bottom: BorderSide(
              color: MarsTheme.cyanNeon.withOpacity(0.06),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // ── الشعار ──
            const Icon(Icons.shield_rounded, color: MarsTheme.cyanNeon, size: 16),
            const SizedBox(width: 8),
            Text(
              'محفظة برو',
              style: GoogleFonts.cairo(
                color: MarsTheme.cyanNeon,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: MarsTheme.cyanNeon.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.15)),
              ),
              child: Text(
                'v2.0',
                style: GoogleFonts.firaCode(
                  color: MarsTheme.cyanDim,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const Spacer(),

            // ── أزرار التحكم ──
            _TitleBarButton(
              icon: Icons.remove_rounded,
              tooltip: 'تصغير',
              hoverColor: MarsTheme.cyanNeon.withOpacity(0.1),
              iconColor: MarsTheme.textSecondary,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 4),
            _TitleBarButton(
              icon: Icons.close_rounded,
              tooltip: 'إغلاق',
              hoverColor: MarsTheme.error.withOpacity(0.15),
              iconColor: MarsTheme.textSecondary,
              iconHoverColor: MarsTheme.error,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

/// زر شريط العنوان مع تأثير hover
class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color hoverColor;
  final Color iconColor;
  final Color? iconHoverColor;
  final VoidCallback onTap;

  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.iconColor,
    this.iconHoverColor,
    required this.onTap,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 28,
            decoration: BoxDecoration(
              color: _isHovered ? widget.hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovered
                  ? (widget.iconHoverColor ?? widget.iconColor)
                  : widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
