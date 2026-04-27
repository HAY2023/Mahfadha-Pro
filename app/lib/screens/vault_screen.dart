import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Biometric-Gated Vault Screen
///  ZERO data is shown until ESP32 confirms fingerprint scan.
///  Includes: Accounts (with URL), Phone Numbers, Recovery Emails,
///  Backup Codes — all gated behind biometric verification.
/// ══════════════════════════════════════════════════════════════════════
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
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
                    : _buildLockedGate(),
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
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (state.isBiometricUnlocked ? MarsTheme.success : MarsTheme.warning)
              .withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (state.isBiometricUnlocked ? MarsTheme.success : MarsTheme.warning)
                .withOpacity(0.3),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            state.isBiometricUnlocked ? Icons.lock_open : Icons.fingerprint,
            size: 16,
            color: state.isBiometricUnlocked ? MarsTheme.success : MarsTheme.warning,
          ),
          const SizedBox(width: 8),
          Text(
            state.isBiometricUnlocked ? 'القبو مفتوح' : 'مطلوب بصمة',
            style: GoogleFonts.cairo(
              color: state.isBiometricUnlocked ? MarsTheme.success : MarsTheme.warning,
              fontSize: 12, fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildLockedGate() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 460, padding: const EdgeInsets.all(40),
            decoration: MarsTheme.glassCard(borderRadius: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) => Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: MarsTheme.warning.withOpacity(0.12 * _pulseCtrl.value),
                      blurRadius: 40, spreadRadius: 5,
                    )],
                  ),
                  child: child,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      MarsTheme.warning.withOpacity(0.12),
                      MarsTheme.cyanNeon.withOpacity(0.08),
                    ]),
                    border: Border.all(color: MarsTheme.warning.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.fingerprint, size: 56, color: MarsTheme.warning),
                ),
              ),
              const SizedBox(height: 28),
              Text('المصادقة الحيوية مطلوبة', style: GoogleFonts.cairo(
                color: MarsTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 12),
              Text(
                'ضع إصبعك على مستشعر البصمة في جهاز Mahfadha Pro.\n'
                'لن يتم فك تشفير أو عرض أي بيانات حتى تتم المصادقة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textSecondary, fontSize: 13, height: 1.8,
                ),
              ),
              const SizedBox(height: 20),
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
            ]),
          ),
        ),
      ),
    );
  }

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
        Row(children: [
          const Icon(Icons.account_circle, color: MarsTheme.cyanGlow, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(acc.name, style: GoogleFonts.cairo(
            color: MarsTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
          ))),
          if (acc.targetUrl.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MarsTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Auto-Login', style: GoogleFonts.firaCode(
                color: MarsTheme.success, fontSize: 9, fontWeight: FontWeight.w600,
              )),
            ),
        ]),
        const SizedBox(height: 8),
        _infoRow('المستخدم', acc.username),
        _infoRow('كلمة المرور', '••••••••'),
        if (acc.targetUrl.isNotEmpty) _infoRow('رابط الدخول', acc.targetUrl),
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
