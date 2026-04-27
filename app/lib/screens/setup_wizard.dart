import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/mars_theme.dart';
import '../providers/app_state.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});
  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> with TickerProviderStateMixin {
  int _step = 0;
  final int _totalSteps = 5;

  // Step 3: PIN
  String _pin = '';
  // Step 4: Seed
  List<String> _seedWords = [];
  // Step 5: Progress
  double _progress = 0;
  String _progressLabel = 'جارٍ التهيئة...';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 2 && _pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز PIN مكوناً من 6 أرقام'), backgroundColor: Color(0xFFF87171)),
      );
      return;
    }
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      if (_step == 3) _generateSeed();
      if (_step == 4) _runInit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _generateSeed() {
    const words = [
      'abandon','ability','abstract','academy','access','accident','account','achieve',
      'acid','acoustic','acquire','adapt','adjust','admit','advance','advice',
      'afford','agent','ahead','alarm','album','alert','alien','alpha',
      'anchor','ancient','anger','animal','arena','armor','arrow','asset',
      'atomic','august','autumn','avenue','badge','bamboo','banner','barrel',
      'beacon','binary','blade','blast','blaze','border','breeze','bridge',
      'bronze','bullet','burden','cabin','camel','canal','canyon','carbon',
      'castle','catalog','cedar','cellar','cipher','citrus','claim','cliff',
      'cloud','cobalt','comet','coral','cosmic','crane','crater','credit',
      'cross','crown','cruise','crystal','cube','custom','cipher','dawn',
      'debris','decade','delta','denial','deploy','desert','device','diesel',
      'digital','domain','dragon','drift','eagle','echo','eclipse','elite',
      'ember','emerge','empire','enable','endure','enigma','epoch','equip',
      'erode','escape','ethics','evolve','exile','exotic','expire','export',
    ];
    final rng = Random.secure();
    _seedWords = List.generate(12, (_) => words[rng.nextInt(words.length)]);
  }

  Future<void> _runInit() async {
    final labels = [
      'إنشاء مفتاح AES-256 الرئيسي...',
      'كتابة المفتاح داخل الشريحة الآمنة ATECC608A...',
      'تسجيل البصمة الحيوية...',
      'تجهيز وحدة التشفير...',
      'تهيئة أقسام الذاكرة غير المتطايرة...',
      'إغلاق خطوات التهيئة...',
    ];
    for (int i = 0; i < labels.length; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        _progress = (i + 1) / labels.length;
        _progressLabel = labels[i];
      });
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    context.read<AppState>().markSetupComplete();
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarsTheme.background,
      body: Container(
        decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTitleBar(),
              _buildStepIndicator(),
              Expanded(child: _buildStepContent()),
              if (_step < 4) _buildNavButtons(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          const Icon(Icons.memory_rounded, color: MarsTheme.cyan, size: 20),
          const SizedBox(width: 8),
          Text('MAHFADHA PRO', style: GoogleFonts.inter(
            color: MarsTheme.cyan, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2,
          )),
          const Spacer(),
          Text('التهيئة الأولية', style: GoogleFonts.cairo(
            color: MarsTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5,
          )),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 24),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final active = i <= _step;
          return Expanded(
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active ? MarsTheme.cyanGradient : null,
                  color: active ? null : MarsTheme.surfaceLight,
                  border: Border.all(color: active ? MarsTheme.cyan : MarsTheme.borderGlow, width: 1.5),
                  boxShadow: active ? [BoxShadow(color: MarsTheme.cyan.withOpacity(0.3), blurRadius: 12)] : null,
                ),
                child: Center(child: Text(
                  '${i + 1}',
                  style: GoogleFonts.inter(
                    color: active ? MarsTheme.background : MarsTheme.textMuted,
                    fontSize: 12, fontWeight: FontWeight.w700,
                  ),
                )),
              ),
              if (i < _totalSteps - 1) Expanded(
                child: Container(
                  height: 2, margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i < _step ? MarsTheme.cyan.withOpacity(0.5) : MarsTheme.surfaceLight,
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _welcomeStep();
      case 1: return _fingerprintStep();
      case 2: return _pinStep();
      case 3: return _seedStep();
      case 4: return _initStep();
      default: return const SizedBox();
    }
  }

  // ── Step 0: Welcome ──────────────────────────────────────────────
  Widget _welcomeStep() {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Opacity(opacity: _pulseAnim.value, child: child),
          child: ShaderMask(
            shaderCallback: (rect) => MarsTheme.cyanGradient.createShader(rect),
            child: const Icon(Icons.verified_user_outlined, size: 80, color: Colors.white),
          ),
        ),
        const SizedBox(height: 32),
        Text('مرحباً بك في CipherVault Pro', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5,
        )),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (rect) => MarsTheme.cyanGradient.createShader(rect),
          child: Text('تهيئة وحدة التشفير الاحترافية', style: GoogleFonts.cairo(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500,
          )),
        ),
        const SizedBox(height: 24),
        Text(
          'سيتم الآن تهيئة الجهاز لحماية بياناتك داخل وحدة تشفير مخصصة.\nأكمل الخطوات التالية لتجهيز البيئة التشغيلية.',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(color: MarsTheme.textSecondary, fontSize: 14, height: 1.8),
        ),
      ]),
    ));
  }

  // ── Step 1: Fingerprint ──────────────────────────────────────────
  Widget _fingerprintStep() {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: MarsTheme.cyan.withOpacity(0.15 * _pulseAnim.value), blurRadius: 40, spreadRadius: 8)],
            ),
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [MarsTheme.cyan.withOpacity(0.12), MarsTheme.accent.withOpacity(0.08)],
              ),
              border: Border.all(color: MarsTheme.cyan.withOpacity(0.2)),
            ),
            child: const Icon(Icons.fingerprint, size: 60, color: MarsTheme.cyan),
          ),
        ),
        const SizedBox(height: 32),
        Text('تسجيل البصمة الحيوية', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 12),
        Text(
          'ضع إصبعك على المستشعر الحيوي في الجهاز.\nسيتم إرسال أمر التسجيل إلى الجسر المحلي تلقائياً.',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(color: MarsTheme.textSecondary, fontSize: 13, height: 1.8),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: MarsTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MarsTheme.borderGlow),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.terminal, size: 16, color: MarsTheme.cyan.withOpacity(0.7)),
            const SizedBox(width: 8),
            Text('bridge> {"cmd": "enroll_finger", "slot": 1}',
              style: GoogleFonts.firaCode(color: MarsTheme.cyan.withOpacity(0.7), fontSize: 11)),
          ]),
        ),
      ]),
    ));
  }

  // ── Step 2: Emergency PIN ────────────────────────────────────────
  Widget _pinStep() {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('تعيين رمز PIN احتياطي', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 8),
        Text('رمز مكوّن من 6 أرقام للاستخدام عند تعذر المصادقة الحيوية',
          style: GoogleFonts.cairo(color: MarsTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 28),
        // PIN Display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: filled ? MarsTheme.cyan.withOpacity(0.1) : MarsTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: filled ? MarsTheme.cyan : MarsTheme.borderGlow,
                  width: filled ? 1.5 : 1,
                ),
                boxShadow: filled ? [BoxShadow(color: MarsTheme.cyan.withOpacity(0.15), blurRadius: 12)] : null,
              ),
              child: Center(child: Text(
                filled ? '●' : '',
                style: TextStyle(color: MarsTheme.cyan, fontSize: 20),
              )),
            );
          }),
        ),
        const SizedBox(height: 28),
        // Numpad
        SizedBox(
          width: 280,
          child: Column(children: [
            for (var row in [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((key) {
                    if (key.isEmpty) return const SizedBox(width: 72, height: 52);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _onPinKey(key),
                          child: Container(
                            width: 72, height: 52,
                            decoration: BoxDecoration(
                              color: MarsTheme.surfaceLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: MarsTheme.borderGlow),
                            ),
                            child: Center(child: Text(key, style: GoogleFonts.inter(
                              color: key == '⌫' ? MarsTheme.error : MarsTheme.textPrimary,
                              fontSize: key == '⌫' ? 18 : 20, fontWeight: FontWeight.w600,
                            ))),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ]),
        ),
      ]),
    ));
  }

  void _onPinKey(String key) {
    setState(() {
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += key;
      }
    });
  }

  // ── Step 3: Recovery Seed ────────────────────────────────────────
  Widget _seedStep() {
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('عبارة الاستعادة', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MarsTheme.error.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MarsTheme.error.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: MarsTheme.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'دوّن هذه العبارة في وسيط آمن. لن تظهر مرة أخرى ولن تُحفظ على هذا الجهاز.',
              style: GoogleFonts.cairo(color: MarsTheme.warning, fontSize: 12, fontWeight: FontWeight.w500),
            )),
          ]),
        ),
        const SizedBox(height: 24),
        // 12-word grid (3 columns × 4 rows)
        Wrap(
          spacing: 10, runSpacing: 10,
          children: List.generate(12, (i) => Container(
            width: 180, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: MarsTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MarsTheme.borderGlow),
            ),
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: MarsTheme.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(child: Text('${i + 1}', style: GoogleFonts.inter(
                  color: MarsTheme.cyan, fontSize: 11, fontWeight: FontWeight.w700,
                ))),
              ),
              const SizedBox(width: 10),
              Text(_seedWords.isNotEmpty ? _seedWords[i] : '---', style: GoogleFonts.firaCode(
                color: MarsTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500,
              )),
            ]),
          )),
        ),
      ]),
    ));
  }

  // ── Step 4: Initialize ───────────────────────────────────────────
  Widget _initStep() {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 80),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: (_progress >= 1 ? MarsTheme.success : MarsTheme.cyan).withOpacity(0.2 * _pulseAnim.value),
                blurRadius: 30, spreadRadius: 5,
              )],
            ),
            child: Icon(
              _progress >= 1 ? Icons.check_circle_outline : Icons.memory,
              size: 56,
              color: _progress >= 1 ? MarsTheme.success : MarsTheme.cyan,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          _progress >= 1 ? 'اكتملت التهيئة' : 'جارٍ تجهيز وحدة التشفير...',
          style: GoogleFonts.cairo(color: MarsTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(_progressLabel, style: GoogleFonts.firaCode(color: MarsTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 32),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
            backgroundColor: MarsTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation(_progress >= 1 ? MarsTheme.success : MarsTheme.cyan),
          ),
        ),
        const SizedBox(height: 12),
        Text('${(_progress * 100).toInt()}%', style: GoogleFonts.inter(
          color: MarsTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600,
        )),
      ]),
    ));
  }

  // ── Navigation ───────────────────────────────────────────────────
  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(children: [
        if (_step > 0)
          OutlinedButton.icon(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('السابق'),
          ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _next,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text(_step == 3 ? 'تم التدوين' : 'متابعة'),
        ),
      ]),
    );
  }
}
