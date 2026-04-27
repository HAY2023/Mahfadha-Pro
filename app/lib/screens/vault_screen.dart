import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Biometric-Gated Vault Screen [V3]
///  ZERO data is shown until ESP32 sends FINGERPRINT_VERIFIED.
///  Shows a Lottie fingerprint scanning animation while waiting.
///  Includes: Accounts (with URL + phone + backup codes),
///  Phone Numbers, Recovery Emails, Backup Codes — all gated
///  behind hardware biometric verification.
/// ══════════════════════════════════════════════════════════════════════
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _scanLineCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    // Scanning line animation for the fingerprint scanner effect
    _scanLineCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanLineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      return Container(
        decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, state),
              const SizedBox(height: 20),
              Expanded(
                child: state.isBiometricUnlocked
                    ? _buildUnlockedVault(state)
                    : _buildLockedGate(state),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildHeader(BuildContext context, AppState state) {
    return Row(children: [
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('رجوع'),
      ),
      const SizedBox(width: 14),
      Text('القبو الحساس', style: GoogleFonts.cairo(
        color: MarsTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700,
      )),
      const Spacer(),
      _buildBiometricStatusBadge(state),
    ]);
  }

  /// [V3] Status badge reflects BiometricState
  Widget _buildBiometricStatusBadge(AppState state) {
    final Color color;
    final IconData icon;
    final String label;

    if (state.isBiometricUnlocked) {
      color = MarsTheme.success;
      icon = Icons.lock_open;
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
          label = 'مطلوب بصمة';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.cairo(
          color: color, fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  LOCKED GATE — Lottie fingerprint animation + biometric state UI
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildLockedGate(AppState state) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 480, padding: const EdgeInsets.all(40),
            decoration: MarsTheme.gateGlassCard(borderRadius: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Fingerprint scanner visual ──
              _buildFingerprintScanner(state),
              const SizedBox(height: 28),

              // ── Title based on state ──
              Text(
                _getLockedTitle(state),
                style: GoogleFonts.cairo(
                  color: MarsTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),

              // ── Description ──
              Text(
                _getLockedDescription(state),
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textSecondary, fontSize: 13, height: 1.8,
                ),
              ),
              const SizedBox(height: 20),

              // ── Security notice ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MarsTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarsTheme.error.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.shield, color: MarsTheme.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'الحماية النشطة: البيانات مشفرة بالكامل ولا يمكن الوصول إليها بدون المصادقة الحيوية من الجهاز.',
                    style: GoogleFonts.cairo(color: MarsTheme.error, fontSize: 11),
                  )),
                ]),
              ),

              // ── Scanning/Failed state indicator ──
              if (state.biometricState == BiometricState.scanning) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Color(0xFF182133),
                    valueColor: AlwaysStoppedAnimation<Color>(MarsTheme.cyanNeon),
                  ),
                ),
              ],
              if (state.biometricState == BiometricState.failed) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: MarsTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'البصمة غير مطابقة — أعد المحاولة على الجهاز.',
                    style: GoogleFonts.cairo(
                      color: MarsTheme.error, fontSize: 12, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// [V3] Fingerprint scanner visual — uses Lottie animation with fallback
  Widget _buildFingerprintScanner(AppState state) {
    final Color glowColor;
    switch (state.biometricState) {
      case BiometricState.scanning:
        glowColor = MarsTheme.cyanNeon;
      case BiometricState.failed:
        glowColor = MarsTheme.error;
      case BiometricState.waitingForFinger:
      case BiometricState.verified:
        glowColor = MarsTheme.warning;
    }

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Container(
        width: 140, height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: glowColor.withOpacity(0.10 + _pulseCtrl.value * 0.12),
            blurRadius: 50 + _pulseCtrl.value * 20,
            spreadRadius: 2,
          )],
        ),
        child: child,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                glowColor.withOpacity(0.12),
                MarsTheme.cyanNeon.withOpacity(0.06),
              ]),
              border: Border.all(color: glowColor.withOpacity(0.3)),
            ),
          ),

          // Lottie fingerprint animation (network) with fallback
          SizedBox(
            width: 90, height: 90,
            child: Lottie.network(
              'https://lottie.host/b41c9e6e-fba7-4c63-b4f9-c2e0e4ed4b42/sIjCgigx1C.json',
              animate: state.biometricState == BiometricState.scanning ||
                       state.biometricState == BiometricState.waitingForFinger,
              repeat: true,
              errorBuilder: (context, error, stackTrace) {
                // Fallback: animated fingerprint icon
                return Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: glowColor,
                );
              },
              frameBuilder: (context, child, composition) {
                // Apply color tint matching the state
                return ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    glowColor.withOpacity(0.3),
                    BlendMode.srcATop,
                  ),
                  child: child,
                );
              },
            ),
          ),

          // Scanning line overlay (only during active scan)
          if (state.biometricState == BiometricState.scanning)
            AnimatedBuilder(
              animation: _scanLineCtrl,
              builder: (_, __) => Positioned(
                top: 10 + (_scanLineCtrl.value * 120),
                child: Container(
                  width: 100,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      MarsTheme.cyanNeon.withOpacity(0.8),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getLockedTitle(AppState state) {
    switch (state.biometricState) {
      case BiometricState.scanning:
        return 'جارٍ مسح البصمة...';
      case BiometricState.failed:
        return 'فشل التحقق من البصمة';
      case BiometricState.waitingForFinger:
      case BiometricState.verified:
        return 'المصادقة الحيوية مطلوبة';
    }
  }

  String _getLockedDescription(AppState state) {
    switch (state.biometricState) {
      case BiometricState.scanning:
        return 'لا ترفع إصبعك حتى يكتمل المسح.\n'
            'الجهاز يتحقق من بصمتك الآن.';
      case BiometricState.failed:
        return 'البصمة غير مطابقة. أعد المحاولة بوضع إصبعك المسجّل\n'
            'على مستشعر البصمة في جهاز Mahfadha Pro.';
      case BiometricState.waitingForFinger:
      case BiometricState.verified:
        return 'ضع إصبعك على مستشعر البصمة في جهاز Mahfadha Pro.\n'
            'لن يتم فك تشفير أو عرض أي بيانات حتى تتم المصادقة.';
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UNLOCKED VAULT — Full account + sensitive data display
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildUnlockedVault(AppState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Accounts list
        Expanded(flex: 3, child: _buildAccountsPanel(state)),
        const SizedBox(width: 16),
        // Right: Sensitive profiles
        Expanded(flex: 2, child: _buildSensitivePanel(state)),
      ],
    );
  }

  Widget _buildAccountsPanel(AppState state) {
    final accounts = state.vaultAccounts;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MarsTheme.glassCard(borderRadius: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.key_rounded, color: MarsTheme.cyanNeon, size: 20),
          const SizedBox(width: 10),
          Text('حسابات القبو', style: GoogleFonts.cairo(
            color: MarsTheme.cyanNeon, fontSize: 18, fontWeight: FontWeight.w700,
          )),
          const Spacer(),
          Text('${accounts.length} حساب', style: GoogleFonts.cairo(
            color: MarsTheme.textMuted, fontSize: 12,
          )),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: accounts.isEmpty
              ? Center(child: Text('لا توجد حسابات محفوظة', style: GoogleFonts.cairo(
                  color: MarsTheme.textMuted, fontSize: 14)))
              : ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (_, i) => _buildAccountTile(accounts[i]),
                ),
        ),
      ]),
    );
  }

  /// [V3] Account tile — shows targetUrl, phones, backup codes
  Widget _buildAccountTile(VaultAccount acc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarsTheme.borderGlow),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Account name + badges
        Row(children: [
          const Icon(Icons.account_circle, color: MarsTheme.cyanGlow, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(acc.name, style: GoogleFonts.cairo(
            color: MarsTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
          ))),
          if (acc.hasAutoLogin)
            _buildBadge('Auto-Login', MarsTheme.success),
          if (acc.sensitiveDataCount > 0) ...[
            const SizedBox(width: 6),
            _buildBadge('${acc.sensitiveDataCount} حساس', MarsTheme.warning),
          ],
        ]),
        const SizedBox(height: 8),

        // Core fields
        _infoRow('المستخدم', acc.username),
        _infoRow('كلمة المرور', '••••••••'),
        if (acc.targetUrl.isNotEmpty) _infoRow('رابط الدخول', acc.targetUrl),
        if (acc.totpSecret.isNotEmpty) _infoRow('TOTP', '••••••'),

        // [V3] Phone numbers
        if (acc.phoneNumbers.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildChipRow(
            icon: Icons.phone_android,
            color: MarsTheme.success,
            items: acc.phoneNumbers,
          ),
        ],

        // [V3] Backup codes
        if (acc.backupCodes.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildChipRow(
            icon: Icons.vpn_key,
            color: MarsTheme.error,
            items: acc.backupCodes,
          ),
        ],

        // [V3] Recovery emails
        if (acc.recoveryEmails.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildChipRow(
            icon: Icons.email_outlined,
            color: MarsTheme.warning,
            items: acc.recoveryEmails,
          ),
        ],

        // Legacy sensitive entries
        if (acc.sensitiveEntries.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: acc.sensitiveEntries.map((e) =>
            Chip(
              label: Text(e.label, style: GoogleFonts.cairo(fontSize: 10)),
              backgroundColor: MarsTheme.surfaceLight,
              side: BorderSide(color: MarsTheme.borderGlow),
              visualDensity: VisualDensity.compact,
            ),
          ).toList()),
        ],
      ]),
    );
  }

  /// Small colored badge widget
  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: GoogleFonts.firaCode(
        color: color, fontSize: 9, fontWeight: FontWeight.w600,
      )),
    );
  }

  /// [V3] Row of chips for list data (phones, codes, emails)
  Widget _buildChipRow({
    required IconData icon,
    required Color color,
    required List<String> items,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: items.map((item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Text(item, style: GoogleFonts.firaCode(
              color: MarsTheme.textSecondary, fontSize: 10,
            )),
          )).toList(),
        ),
      ),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: GoogleFonts.cairo(
          color: MarsTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600,
        ))),
        Expanded(child: Text(value, style: GoogleFonts.firaCode(
          color: MarsTheme.textSecondary, fontSize: 11,
        ), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _buildSensitivePanel(AppState state) {
    final entries = state.globalSensitiveEntries;
    final categoryIcons = <String, IconData>{
      'phone': Icons.phone_android,
      'email': Icons.email_outlined,
      'backup_code': Icons.vpn_key,
      'custom': Icons.lock_outline,
    };
    final categoryColors = <String, Color>{
      'phone': MarsTheme.success,
      'email': MarsTheme.warning,
      'backup_code': MarsTheme.error,
      'custom': MarsTheme.cyanDim,
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MarsTheme.glassCard(borderRadius: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_rounded, color: MarsTheme.warning, size: 20),
          const SizedBox(width: 10),
          Text('بيانات حساسة', style: GoogleFonts.cairo(
            color: MarsTheme.warning, fontSize: 18, fontWeight: FontWeight.w700,
          )),
        ]),
        const SizedBox(height: 6),
        Text('أرقام هواتف · بريد استرداد · أكواد احتياطية',
          style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 16),
        Expanded(
          child: entries.isEmpty
              ? Center(child: Text('لا توجد بيانات حساسة', style: GoogleFonts.cairo(
                  color: MarsTheme.textMuted, fontSize: 13)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final icon = categoryIcons[e.category] ?? Icons.lock_outline;
                    final color = categoryColors[e.category] ?? MarsTheme.cyanDim;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(0.18)),
                      ),
                      child: Row(children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.label, style: GoogleFonts.cairo(
                              color: MarsTheme.textPrimary, fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                            Text(e.value, style: GoogleFonts.firaCode(
                              color: MarsTheme.textSecondary, fontSize: 11,
                            )),
                          ],
                        )),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
