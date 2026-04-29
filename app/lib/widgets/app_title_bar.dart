import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Custom Title Bar — [V5 FIX] Window controls on LEFT (Windows standard)
///  1. Window dragging works on the ENTIRE title bar area
///  2. Close/Maximize/Minimize are ALWAYS clickable (on top of drag area)
///  3. Branding is visible on the right side (RTL layout)
///  4. Button order: Close | Maximize | Minimize (left to right)
/// ══════════════════════════════════════════════════════════════════════
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximizedState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _isMaximized = maximized;
      });
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  void onWindowRestore() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Stack(
        children: [
          // ── Layer 0: Background decoration ──
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: MarsTheme.spaceNavy,
                border: Border(
                  bottom: BorderSide(
                    color: MarsTheme.cyanNeon.withOpacity(0.08),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 1: Full-width drag area (GestureDetector) ──
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),

          // ── Layer 2: Branding (right side for RTL, non-interactive) ──
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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
                    const SizedBox(width: 6),
                    Text(
                      'CipherVault Pro',
                      style: GoogleFonts.inter(
                        color: MarsTheme.cyanNeon,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.memory_rounded,
                      color: MarsTheme.cyanNeon,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 3: Window control buttons (LEFT side, CLICKABLE) ──
          Positioned(
            top: 0,
            bottom: 0,
            left: 8,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TitleBarButton(
                    icon: Icons.close_rounded,
                    tooltip: 'إغلاق',
                    hoverColor: MarsTheme.error.withOpacity(0.15),
                    iconColor: MarsTheme.textSecondary,
                    iconHoverColor: MarsTheme.error,
                    onTap: () async {
                      // Hide to system tray — do NOT terminate the app
                      await windowManager.setSkipTaskbar(true);
                      await windowManager.hide();
                    },
                  ),
                  const SizedBox(width: 4),
                  _TitleBarButton(
                    icon: _isMaximized
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    tooltip: _isMaximized ? 'استعادة' : 'تكبير',
                    hoverColor: MarsTheme.cyanNeon.withOpacity(0.1),
                    iconColor: MarsTheme.textSecondary,
                    onTap: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  _TitleBarButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'تصغير',
                    hoverColor: MarsTheme.cyanNeon.withOpacity(0.1),
                    iconColor: MarsTheme.textSecondary,
                    onTap: () => windowManager.minimize(),
                  ),
                ],
              ),
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
