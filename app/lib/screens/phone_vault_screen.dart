import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Phone Vault Screen — [V4] Dedicated encrypted phone number storage
///  BLURRED/HIDDEN until ESP32 sends FINGERPRINT_OK signal.
///  All data gated behind biometric verification.
/// ══════════════════════════════════════════════════════════════════════
class PhoneVaultScreen extends StatefulWidget {
  const PhoneVaultScreen({super.key});

  @override
  State<PhoneVaultScreen> createState() => _PhoneVaultScreenState();
}

class _PhoneVaultScreenState extends State<PhoneVaultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _sendToDevice(Map<String, dynamic> command) {
    final appState = context.read<AppState>();
    final portName = appState.connectedPort;
    if (portName == null) {
      _showError('وصّل وحدة التشفير المادية أولاً.');
      return;
    }
    try {
      final port = SerialPort(portName);
      if (port.openReadWrite()) {
        final payload = '${jsonEncode(command)}\n';
        port.write(Uint8List.fromList(utf8.encode(payload)));
        port.close();
      }
    } catch (e) {
      _showError('تعذر إرسال الأمر: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: MarsTheme.error,
      ),
    );
  }

  void _showAddPhoneDialog() {
    final labelCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: MarsTheme.cyanNeon.withOpacity(0.06),
                    blurRadius: 60,
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        const Icon(Icons.phone_android_rounded,
                            color: MarsTheme.success, size: 24),
                        const SizedBox(width: 10),
                        Text('إضافة رقم هاتف جديد',
                            style: GoogleFonts.cairo(
                              color: MarsTheme.cyanNeon,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            )),
                      ]),
                      const SizedBox(height: 20),
                      _inputField(labelCtrl, 'التسمية', Icons.label_rounded,
                          hint: 'مثال: هاتفي الرئيسي'),
                      const SizedBox(height: 12),
                      _inputField(phoneCtrl, 'رقم الهاتف', Icons.dialpad_rounded,
                          hint: '+213xxxxxxxxx'),
                      const SizedBox(height: 12),
                      _inputField(notesCtrl, 'ملاحظات (اختياري)', Icons.note_rounded,
                          hint: 'ملاحظة اختيارية'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MarsTheme.success.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MarsTheme.success.withOpacity(0.15)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.security, color: MarsTheme.success, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الرقم سيُشفَّر بخوارزمية AES-256-GCM ويُخزَّن حصرياً داخل الشريحة الآمنة. لن يظهر إلا بعد المصادقة بالبصمة.',
                                style: GoogleFonts.cairo(
                                    color: MarsTheme.success, fontSize: 10, height: 1.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text('تشفير وإرسال'),
                            onPressed: () {
                              if (phoneCtrl.text.trim().isEmpty) return;
                              final appState = context.read<AppState>();
                              final id = appState.phoneVault.length;
                              final entry = PhoneVaultEntry(
                                id: id,
                                label: labelCtrl.text.trim(),
                                phoneNumber: phoneCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                              );
                              appState.addPhoneVaultEntry(entry);
                              _sendToDevice({
                                'cmd': 'add_phone',
                                'label': entry.label,
                                'phoneNumber': entry.phoneNumber,
                                'notes': entry.notes,
                              });
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ]),
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

  Widget _inputField(TextEditingController ctrl, String label, IconData icon,
      {String? hint}) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.firaCode(color: MarsTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 13),
        hintStyle: GoogleFonts.firaCode(
            color: MarsTheme.textMuted.withOpacity(0.5), fontSize: 11),
        prefixIcon: Icon(icon, color: MarsTheme.cyanDim, size: 18),
        filled: true,
        fillColor: MarsTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: MarsTheme.borderGlow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: MarsTheme.borderGlow),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MarsTheme.cyanNeon, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Container(
          decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(state),
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
      },
    );
  }

  Widget _buildHeader(AppState state) {
    return FadeInDown(
      duration: const Duration(milliseconds: 400),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MarsTheme.surfaceLight.withOpacity(0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MarsTheme.borderGlow),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.phone_android_rounded,
                  color: MarsTheme.success, size: 18),
              const SizedBox(width: 8),
              Text('جهات الاتصال الآمنة',
                  style: GoogleFonts.cairo(
                    color: MarsTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
            ]),
          ),
          const Spacer(),
          if (state.isBiometricUnlocked)
            ElevatedButton.icon(
              onPressed: _showAddPhoneDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('إضافة رقم',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildLockedGate() {
    return Center(
      child: FadeIn(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(40),
              decoration: MarsTheme.gateGlassCard(borderRadius: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing fingerprint
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, child) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: MarsTheme.warning
                                .withOpacity(0.08 + _pulseCtrl.value * 0.1),
                            blurRadius: 40 + _pulseCtrl.value * 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [
                          MarsTheme.warning.withOpacity(0.12),
                          MarsTheme.cyanNeon.withOpacity(0.06),
                        ]),
                        border: Border.all(
                            color: MarsTheme.warning.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.fingerprint,
                          size: 50, color: MarsTheme.warning),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('المصادقة الحيوية مطلوبة',
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 12),
                  Text(
                    'جهات الاتصال الآمنة مشفرة ومحمية. ضع إصبعك على مستشعر البصمة في وحدة التشفير المادية لفك التشفير.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      color: MarsTheme.textSecondary,
                      fontSize: 13,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockedVault(AppState state) {
    final phones = state.phoneVault;
    return FadeInUp(
      duration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MarsTheme.glassCard(borderRadius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.phone_locked_rounded,
                  color: MarsTheme.success, size: 20),
              const SizedBox(width: 10),
              Text('جهات الاتصال الآمنة المشفرة',
                  style: GoogleFonts.cairo(
                    color: MarsTheme.success,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text('${phones.length} رقم',
                  style: GoogleFonts.cairo(
                    color: MarsTheme.textMuted,
                    fontSize: 12,
                  )),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: phones.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_disabled_rounded,
                              color: MarsTheme.textMuted.withOpacity(0.4),
                              size: 48),
                          const SizedBox(height: 12),
                          Text('لا توجد أرقام محفوظة بعد',
                              style: GoogleFonts.cairo(
                                color: MarsTheme.textMuted,
                                fontSize: 14,
                              )),
                          const SizedBox(height: 8),
                          Text('اضغط "إضافة رقم" لتخزين رقم جديد في الشريحة الآمنة',
                              style: GoogleFonts.cairo(
                                color: MarsTheme.textMuted.withOpacity(0.6),
                                fontSize: 12,
                              )),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: phones.length,
                      itemBuilder: (_, i) {
                        final phone = phones[i];
                        return FadeInRight(
                          delay: Duration(milliseconds: 60 * i),
                          child: _buildPhoneTile(phone, state),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneTile(PhoneVaultEntry phone, AppState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarsTheme.borderGlow),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                MarsTheme.success.withOpacity(0.15),
                MarsTheme.cyanNeon.withOpacity(0.08),
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MarsTheme.success.withOpacity(0.2)),
            ),
            child: const Icon(Icons.phone_android,
                color: MarsTheme.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phone.label,
                    style: GoogleFonts.cairo(
                      color: MarsTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Text(phone.phoneNumber,
                    style: GoogleFonts.firaCode(
                      color: MarsTheme.cyanGlow,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    )),
                if (phone.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(phone.notes,
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textMuted,
                        fontSize: 11,
                      )),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              state.removePhoneVaultEntry(phone.id);
              _sendToDevice({
                'cmd': 'delete_phone',
                'id': phone.id,
              });
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: MarsTheme.error.withOpacity(0.6),
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }
}
