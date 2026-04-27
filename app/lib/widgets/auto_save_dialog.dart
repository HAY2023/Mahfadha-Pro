import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Auto-Save Interceptor Dialog — Frosted Glass Overlay
///
///  Pops up on top of ALL windows when the background listener detects
///  new login credentials from the browser extension / native messaging.
///
///  Displays:  "اكتشاف تسجيل دخول جديد. هل تود تشفير البيانات وحفظها في وحدة التشفير المادية؟"
///  Buttons:   "تشفير وحفظ" + "تجاهل"
/// ══════════════════════════════════════════════════════════════════════

class AutoSaveDialog extends StatelessWidget {
  final InterceptedCredential credential;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const AutoSaveDialog({
    super.key,
    required this.credential,
    required this.onSave,
    required this.onDismiss,
  });

  /// Show the dialog as an overlay on top of the entire app.
  static Future<void> show(
    BuildContext context, {
    required InterceptedCredential credential,
    required VoidCallback onSave,
    required VoidCallback onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      barrierDismissible: false,
      builder: (_) => AutoSaveDialog(
        credential: credential,
        onSave: onSave,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeInUp(
        duration: const Duration(milliseconds: 400),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: MarsTheme.cyanNeon.withOpacity(0.15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: MarsTheme.cyanNeon.withOpacity(0.08),
                    blurRadius: 80,
                    spreadRadius: -10,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header with shield icon ──
                      _buildHeader(),
                      const SizedBox(height: 20),

                      // ── Question ──
                      Text(
                        'اكتشاف تسجيل دخول جديد. هل تود تشفير البيانات وحفظها في وحدة التشفير المادية؟',
                        style: GoogleFonts.cairo(
                          color: MarsTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Credential details ──
                      _buildCredentialCard(),
                      const SizedBox(height: 16),

                      // ── Security notice ──
                      _buildSecurityNotice(),
                      const SizedBox(height: 24),

                      // ── Action buttons ──
                      _buildActionButtons(),
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

  Widget _buildHeader() {
    return Row(
      children: [
        // Animated shield icon
        Pulse(
          infinite: true,
          duration: const Duration(seconds: 2),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MarsTheme.cyanNeon.withOpacity(0.15),
                  MarsTheme.cyanNeon.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MarsTheme.cyanNeon.withOpacity(0.2),
              ),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: MarsTheme.cyanNeon,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اعتراض بيانات دخول جديدة',
                style: GoogleFonts.cairo(
                  color: MarsTheme.cyanNeon,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Auto-Save Interceptor',
                style: GoogleFonts.firaCode(
                  color: MarsTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarsTheme.borderGlow),
      ),
      child: Column(
        children: [
          _credentialRow(
            icon: Icons.link_rounded,
            label: 'رابط الموقع',
            value: credential.targetUrl,
            color: MarsTheme.cyanNeon,
          ),
          const SizedBox(height: 12),
          _credentialRow(
            icon: Icons.person_outline_rounded,
            label: 'اسم المستخدم',
            value: credential.username,
            color: MarsTheme.success,
          ),
          const SizedBox(height: 12),
          _credentialRow(
            icon: Icons.lock_outline_rounded,
            label: 'كلمة المرور',
            value: '●' * (credential.password.length.clamp(6, 16)),
            color: MarsTheme.warning,
          ),
        ],
      ),
    );
  }

  Widget _credentialRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.cairo(
                color: MarsTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.firaCode(
                color: MarsTheme.textPrimary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecurityNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MarsTheme.cyanNeon.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: MarsTheme.cyanDim,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'عند الحفظ، ستُشفَّر البيانات بخوارزمية AES-256-GCM وتُرسَل حصرياً إلى وحدة التشفير المادية عبر USB. لن تُخزَّن على القرص مطلقاً.',
              style: GoogleFonts.cairo(
                color: MarsTheme.textSecondary,
                fontSize: 11,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // ── تجاهل (Dismiss) ──
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(
              'تجاهل',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: MarsTheme.textMuted,
              side: BorderSide(color: MarsTheme.textMuted.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // ── حفظ الآن (Save Now) ──
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.security_rounded, size: 18),
            label: Text(
              'تشفير وحفظ',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: MarsTheme.cyanNeon,
              foregroundColor: MarsTheme.spaceNavy,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
