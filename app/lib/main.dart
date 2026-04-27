import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/mars_theme.dart';
import 'providers/app_state.dart';
import 'screens/connection_gate.dart';
import 'screens/setup_wizard.dart';
import 'screens/dashboard.dart';
import 'widgets/auto_lock_wrapper.dart';
import 'widgets/cyber_title_bar.dart';

// ═══════════════════════════════════════════════════════════════════════
//  محفظة برو — القبو السيبراني المطلق
//  نقطة الدخول الرئيسية مع:
//    ✓ فرض نسخة واحدة (Single Instance)
//    ✓ شريط عنوان مخصص (إغلاق/تصغير)
//    ✓ عربي كامل RTL
//    ✓ بوابة مقفلة = لا جهاز = لا دخول
// ═══════════════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── [FIX 3] فرض نسخة واحدة — Single Instance Lock ─────────────────
  // نستخدم ملف قفل مؤقت في مجلد temp للتأكد من عدم فتح نسختين
  final lockFile = File('${Directory.systemTemp.path}/mahfadha_pro.lock');
  if (lockFile.existsSync()) {
    // محاولة قراءة PID القديم
    try {
      final oldPid = int.tryParse(lockFile.readAsStringSync().trim());
      if (oldPid != null && oldPid != pid) {
        // التحقق: هل العملية القديمة لا تزال تعمل؟
        // على Windows لا يمكن قتلها بسهولة، لكن نتحقق من الوجود
        try {
          Process.killPid(oldPid, ProcessSignal.sigterm);
          // إذا لم يرمي خطأ = العملية موجودة = نسخة أخرى تعمل
          debugPrint('[SINGLE-INSTANCE] نسخة أخرى تعمل بالفعل (PID: $oldPid). إغلاق.');
          exit(0);
        } catch (_) {
          // العملية القديمة ميتة — نكمل
          debugPrint('[SINGLE-INSTANCE] ملف قفل قديم وُجد لكن العملية ميتة. نستمر.');
        }
      }
    } catch (_) {
      // فشل القراءة — نحذف ونكمل
    }
  }
  // كتابة PID الحالي
  lockFile.writeAsStringSync(pid.toString());
  // حذف ملف القفل عند الإغلاق
  ProcessSignal.sigint.watch().listen((_) {
    lockFile.deleteSync();
    exit(0);
  });

  // ── تهيئة نافذة سطح المكتب ────────────────────────────────────────
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1100, 750),
    minimumSize: Size(900, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // [FIX 4] بلا شريط — سنصنع واحداً
    title: 'محفظة برو — القبو السيبراني',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MahfadhaApp(),
    ),
  );
}

class MahfadhaApp extends StatelessWidget {
  const MahfadhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'محفظة برو',
      theme: MarsTheme.darkTheme,

      // ── [FIX 2] فرض اللغة العربية RTL بالكامل ──────────────────────
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'AE'),
      ],
      locale: const Locale('ar', 'AE'),

      // ── [FIX 1] المسار الأولي = بوابة مقفلة دائماً ─────────────────
      initialRoute: '/',
      routes: {
        // البوابة: تمسح المنافذ → تسأل الجهاز → توجّه
        '/': (context) => const _AppShell(child: ConnectionGateScreen()),

        // لوحة التحكم: مع قفل تلقائي 3 دقائق
        '/dashboard': (context) => _AppShell(
          child: AutoLockWrapper(
            timeout: const Duration(seconds: 180),
            child: const DashboardScreen(),
          ),
        ),

        // معالج الإعداد الأول
        '/setup': (context) => const _AppShell(child: SetupWizard()),
      },
    );
  }
}

/// ── غلاف التطبيق مع شريط العنوان المخصص ──────────────────────────────
/// [FIX 4] يضع CyberTitleBar فوق كل شاشة
class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarsTheme.spaceNavy,
      body: Column(
        children: [
          const CyberTitleBar(), // شريط العنوان المخصص
          Expanded(child: child),
        ],
      ),
    );
  }
}
