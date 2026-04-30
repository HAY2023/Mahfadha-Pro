import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';

import '../theme/mars_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  Settings Screen — [V4] Application settings & device management
/// ══════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInDown(
              duration: const Duration(milliseconds: 400),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: MarsTheme.surfaceLight.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: MarsTheme.borderGlow),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.settings_rounded,
                          color: MarsTheme.cyanNeon, size: 18),
                      const SizedBox(width: 8),
                      Text('الإعدادات',
                          style: GoogleFonts.cairo(
                            color: MarsTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          )),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // ── Device section ──
                    FadeInUp(
                      delay: const Duration(milliseconds: 100),
                      child: _buildSection(
                        title: 'إعدادات الجهاز',
                        icon: Icons.memory_rounded,
                        children: [
                          _settingsTile(
                            icon: Icons.timer_outlined,
                            title: 'مهلة القفل التلقائي',
                            subtitle: '3 دقائق من عدم النشاط',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: MarsTheme.cyanNeon.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('180 ثانية',
                                  style: GoogleFonts.firaCode(
                                    color: MarsTheme.cyanNeon,
                                    fontSize: 11,
                                  )),
                            ),
                          ),
                          _settingsTile(
                            icon: Icons.fingerprint,
                            title: 'المصادقة الحيوية',
                            subtitle: 'بصمة الإصبع عبر وحدة التشفير',
                            trailing: const Icon(Icons.check_circle,
                                color: MarsTheme.success, size: 20),
                          ),
                          _settingsTile(
                            icon: Icons.shield_rounded,
                            title: 'وضع الشبح (Ghost Mode)',
                            subtitle:
                                'يمنع الوصول إلى الجهاز عبر USB بدون مصادقة',
                            trailing: const Icon(Icons.check_circle,
                                color: MarsTheme.success, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Auto-Save section ──
                    FadeInUp(
                      delay: const Duration(milliseconds: 200),
                      child: _buildSection(
                        title: 'الحفظ التلقائي',
                        icon: Icons.auto_awesome_rounded,
                        children: [
                          _settingsTile(
                            icon: Icons.extension_rounded,
                            title: 'اعتراض بيانات الدخول',
                            subtitle:
                                'يستمع للبيانات من إضافة Chrome عبر Native Messaging',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: MarsTheme.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('نشط',
                                  style: GoogleFonts.cairo(
                                    color: MarsTheme.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          ),
                          _settingsTile(
                            icon: Icons.notifications_active_rounded,
                            title: 'إشعارات الاعتراض',
                            subtitle:
                                'عرض نافذة حفظ عند اكتشاف بيانات جديدة',
                            trailing: const Icon(Icons.check_circle,
                                color: MarsTheme.success, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Security section ──
                    FadeInUp(
                      delay: const Duration(milliseconds: 300),
                      child: _buildSection(
                        title: 'الأمان',
                        icon: Icons.security_rounded,
                        children: [
                          _settingsTile(
                            icon: Icons.enhanced_encryption_rounded,
                            title: 'خوارزمية التشفير',
                            subtitle: 'AES-256-GCM مع اشتقاق PBKDF2',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: MarsTheme.cyanNeon.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('ATECC608A',
                                  style: GoogleFonts.firaCode(
                                    color: MarsTheme.cyanNeon,
                                    fontSize: 10,
                                  )),
                            ),
                          ),
                          _settingsTile(
                            icon: Icons.edit_note,
                            title: 'تعديل البيانات',
                            subtitle: 'تعديل وتحديث بيانات الحسابات الحالية قبل إعادة تشفيرها',
                            trailing: ElevatedButton(
                              onPressed: () {
                                // Logic handled in TaskManager or via Dialog
                              },
                              child: Text('بدء التعديل', style: TextStyle(color: Colors.black)),
                              style: ElevatedButton.styleFrom(backgroundColor: MarsTheme.cyanNeon),
                            ),
                          ),
                          _settingsTile(
                            icon: Icons.delete_forever_rounded,
                            title: 'إعادة ضبط المصنع',
                            subtitle: 'مسح جميع البيانات من الجهاز نهائياً',
                            trailing: Icon(Icons.warning_amber_rounded,
                                color: MarsTheme.error.withOpacity(0.6),
                                size: 20),
                            color: MarsTheme.error,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── About section ──
                    FadeInUp(
                      delay: const Duration(milliseconds: 400),
                      child: _buildSection(
                        title: 'حول التطبيق',
                        icon: Icons.info_outline_rounded,
                        children: [
                          _settingsTile(
                            icon: Icons.code_rounded,
                            title: 'الإصدار',
                            subtitle: context.watch<AppState>().appVersion,
                          ),
                          _settingsTile(
                            icon: Icons.business_rounded,
                            title: 'المطوّر',
                            subtitle: 'HAY2023',
                          ),
                          _settingsTile(
                            icon: Icons.gavel_rounded,
                            title: 'الترخيص',
                            subtitle: 'MIT License',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MarsTheme.glassCard(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: MarsTheme.cyanNeon, size: 20),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.cairo(
                  color: MarsTheme.cyanNeon,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                )),
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? color,
  }) {
    final c = color ?? MarsTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MarsTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarsTheme.borderGlow),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: c.withOpacity(0.7), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.cairo(
                        color: c,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textMuted,
                        fontSize: 11,
                      )),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
