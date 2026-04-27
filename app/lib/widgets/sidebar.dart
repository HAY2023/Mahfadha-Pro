import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Sidebar Navigation — RTL Arabic with Cairo font
///  الرئيسية | الحسابات | أرقام الهاتف | مركز التحديثات | الإعدادات
/// ══════════════════════════════════════════════════════════════════════
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  static const List<_SidebarItem> _items = [
    _SidebarItem(
      page: SidebarPage.home,
      icon: Icons.dashboard_rounded,
      label: 'لوحة التحكم',
    ),
    _SidebarItem(
      page: SidebarPage.accounts,
      icon: Icons.key_rounded,
      label: 'سجل الحسابات',
    ),
    _SidebarItem(
      page: SidebarPage.phones,
      icon: Icons.phone_android_rounded,
      label: 'جهات الاتصال الآمنة',
    ),
    _SidebarItem(
      page: SidebarPage.updates,
      icon: Icons.system_update_alt_rounded,
      label: 'تحديث النظام',
    ),
    _SidebarItem(
      page: SidebarPage.settings,
      icon: Icons.settings_rounded,
      label: 'الإعدادات',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Container(
          width: 220,
          decoration: BoxDecoration(
            color: MarsTheme.deepSpace.withOpacity(0.6),
            border: Border(
              left: BorderSide(
                color: MarsTheme.cyanNeon.withOpacity(0.06),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // ── Device status badge ──
              FadeInRight(
                duration: const Duration(milliseconds: 400),
                child: _buildDeviceBadge(state),
              ),
              const SizedBox(height: 20),

              // ── Navigation items ──
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isActive = state.currentPage == item.page;
                    return FadeInRight(
                      delay: Duration(milliseconds: 80 * index),
                      duration: const Duration(milliseconds: 350),
                      child: _SidebarNavButton(
                        item: item,
                        isActive: isActive,
                        onTap: () => state.setCurrentPage(item.page),
                      ),
                    );
                  },
                ),
              ),

              // ── Biometric status at bottom ──
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                child: _buildBiometricIndicator(state),
              ),
              const SizedBox(height: 12),

              // ── Lock button ──
              if (state.isBiometricUnlocked)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FadeIn(
                    child: _buildLockButton(context, state),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceBadge(AppState state) {
    final connected = state.isDeviceConnected;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (connected ? MarsTheme.success : MarsTheme.error).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? MarsTheme.success : MarsTheme.error,
              boxShadow: [
                BoxShadow(
                  color: (connected ? MarsTheme.success : MarsTheme.error)
                      .withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected ? 'الجهاز متصل' : 'غير متصل',
              style: GoogleFonts.cairo(
                color: connected ? MarsTheme.success : MarsTheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricIndicator(AppState state) {
    final Color color;
    final IconData icon;
    final String label;

    if (state.isBiometricUnlocked) {
      color = MarsTheme.success;
      icon = Icons.lock_open_rounded;
      label = 'القبو مفتوح';
    } else {
      switch (state.biometricState) {
        case BiometricState.scanning:
          color = MarsTheme.cyanNeon;
          icon = Icons.fingerprint;
          label = 'جارٍ المسح...';
        case BiometricState.failed:
          color = MarsTheme.error;
          icon = Icons.error_outline;
          label = 'فشل التحقق';
        case BiometricState.waitingForFinger:
        case BiometricState.verified:
          color = MarsTheme.warning;
          icon = Icons.fingerprint;
          label = 'القبو مقفل';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.cairo(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockButton(BuildContext context, AppState state) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () => state.lockBiometricVault(),
        icon: const Icon(Icons.lock_rounded, size: 16),
        label: Text(
          'قفل القبو',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: MarsTheme.error,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem {
  final SidebarPage page;
  final IconData icon;
  final String label;

  const _SidebarItem({
    required this.page,
    required this.icon,
    required this.label,
  });
}

class _SidebarNavButton extends StatefulWidget {
  final _SidebarItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarNavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarNavButton> createState() => _SidebarNavButtonState();
}

class _SidebarNavButtonState extends State<_SidebarNavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final color = isActive ? MarsTheme.cyanNeon : MarsTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isActive
                  ? MarsTheme.cyanNeon.withOpacity(0.1)
                  : _isHovered
                      ? Colors.white.withOpacity(0.03)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(
                      color: MarsTheme.cyanNeon.withOpacity(0.15),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.item.label,
                  style: GoogleFonts.cairo(
                    color: isActive
                        ? MarsTheme.cyanNeon
                        : _isHovered
                            ? MarsTheme.textPrimary
                            : MarsTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: MarsTheme.cyanNeon,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: MarsTheme.cyanNeon.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
