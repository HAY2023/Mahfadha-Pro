import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/mars_theme.dart';

/// Custom title bar using [WindowCaption] from window_manager for proper
/// borderless window drag, minimize, and tray-hide behavior.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: MarsTheme.spaceNavy,
        border: Border(
          bottom: BorderSide(
            color: MarsTheme.cyanNeon.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          // ── WindowCaption: system-level drag + double-click maximize ──
          const WindowCaption(
            brightness: Brightness.dark,
            title: null, // We render our own branding below
          ),

          // ── Branding overlay (left side) ──
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.memory_rounded,
                      color: MarsTheme.cyanNeon,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mahfadha Pro',
                      style: GoogleFonts.inter(
                        color: MarsTheme.cyanNeon,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: MarsTheme.cyanNeon.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: MarsTheme.cyanNeon.withOpacity(0.15),
                        ),
                      ),
                      child: Text(
                        'Windows',
                        style: GoogleFonts.firaCode(
                          color: MarsTheme.cyanDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Custom window control buttons (right side) ──
          Positioned(
            top: 0,
            bottom: 0,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  tooltip: 'إرسال إلى الخلفية',
                  hoverColor: MarsTheme.error.withOpacity(0.15),
                  iconColor: MarsTheme.textSecondary,
                  iconHoverColor: MarsTheme.error,
                  onTap: () async {
                    // Hide to system tray — do NOT terminate the app
                    await windowManager.setSkipTaskbar(true);
                    await windowManager.hide();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
