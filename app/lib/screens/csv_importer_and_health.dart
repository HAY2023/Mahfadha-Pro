import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/mars_theme.dart';
import '../providers/app_state.dart';
import 'dart:math';

// ═══════════════════════════════════════════════════════════════════════
//  CSV IMPORTER — معالج استيراد البيانات
//  كل البيانات في الذاكرة العشوائية فقط — صفر بقاء على القرص
// ═══════════════════════════════════════════════════════════════════════

class CsvImporterWidget extends StatefulWidget {
  const CsvImporterWidget({super.key});
  @override
  State<CsvImporterWidget> createState() => _CsvImporterWidgetState();
}

class _CsvImporterWidgetState extends State<CsvImporterWidget>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _parsedPasswords = [];
  bool _isScanning = false;
  bool _isSending = false;
  bool _sendComplete = false;
  String _statusMessage = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _wipeParsedData();
    super.dispose();
  }

  void _wipeParsedData() {
    for (var entry in _parsedPasswords) {
      entry.updateAll((key, value) => '');
    }
    _parsedPasswords.clear();
  }

  Future<void> _pickAndParseCsv() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'جاري فتح الملف...';
      _sendComplete = false;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'تم إلغاء الاستيراد';
        });
        return;
      }

      setState(() => _statusMessage = 'جاري مسح وتحليل البيانات...');
      await Future.delayed(const Duration(milliseconds: 800));

      final bytes = result.files.single.bytes!;
      final csvString = String.fromCharCodes(bytes);
      final rows = const CsvToListConverter().convert(csvString);

      if (rows.isEmpty) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'الملف فارغ';
        });
        return;
      }

      final headers = rows.first.map((e) => e.toString().toLowerCase()).toList();
      final parsed = <Map<String, dynamic>>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final entry = <String, dynamic>{};
        // Bitwarden format
        int nameIdx = headers.indexOf('name');
        int urlIdx = headers.indexOf('login_uri');
        int userIdx = headers.indexOf('login_username');
        int passIdx = headers.indexOf('login_password');
        // Chrome format fallback
        if (nameIdx == -1) nameIdx = headers.indexOf('name');
        if (urlIdx == -1) urlIdx = headers.indexOf('url');
        if (userIdx == -1) userIdx = headers.indexOf('username');
        if (passIdx == -1) passIdx = headers.indexOf('password');

        entry['name'] = nameIdx >= 0 && nameIdx < row.length ? row[nameIdx].toString() : '';
        entry['url'] = urlIdx >= 0 && urlIdx < row.length ? row[urlIdx].toString() : '';
        entry['username'] = userIdx >= 0 && userIdx < row.length ? row[userIdx].toString() : '';
        entry['password'] = passIdx >= 0 && passIdx < row.length ? row[passIdx].toString() : '';

        if (entry['password'].toString().isNotEmpty) {
          parsed.add(entry);
        }
      }

      setState(() {
        _parsedPasswords = parsed;
        _isScanning = false;
        _statusMessage = 'تم العثور على ${parsed.length} كلمة مرور. جاهزة للتشفير والإرسال.';
      });

      // حفظ مؤقت في AppState
      if (mounted) {
        context.read<AppState>().setTempPasswords(parsed);
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'خطأ في التحليل: $e';
      });
    }
  }

  Future<void> _sendToHardware() async {
    setState(() {
      _isSending = true;
      _statusMessage = 'جاري تشفير وإرسال البيانات إلى وحدة التشفير...';
    });

    // محاكاة إرسال كل إدخال إلى ESP32
    for (int i = 0; i < _parsedPasswords.length; i++) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (mounted) {
        setState(() {
          _statusMessage = 'إرسال ${i + 1}/${_parsedPasswords.length}...';
        });
      }
    }

    // ── مسح فوري من الذاكرة ──
    _wipeParsedData();
    if (mounted) {
      context.read<AppState>().clearPasswords();
    }

    setState(() {
      _isSending = false;
      _sendComplete = true;
      _statusMessage = 'تم الإرسال بنجاح! تم مسح جميع البيانات من الذاكرة.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: MarsTheme.glassCard(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // العنوان
              Row(children: [
                const Icon(Icons.upload_file_rounded, color: MarsTheme.cyanNeon, size: 26),
                const SizedBox(width: 10),
                Text('استيراد بيانات CSV', style: GoogleFonts.cairo(
                  color: MarsTheme.cyanNeon, fontSize: 20, fontWeight: FontWeight.w700,
                )),
              ]),
              const SizedBox(height: 6),
              Text('استيراد من Bitwarden أو Chrome مع معالجة مؤقتة داخل الذاكرة فقط',
                style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 24),

              // منطقة المسح / الرسوم المتحركة
              if (_isScanning || _isSending)
                _buildScanAnimation()
              else if (_sendComplete)
                _buildSuccessState()
              else if (_parsedPasswords.isNotEmpty)
                _buildSummary()
              else
                _buildIdleState(),

              const SizedBox(height: 20),

              // رسالة الحالة
              if (_statusMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MarsTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MarsTheme.borderGlow),
                  ),
                  child: Row(children: [
                    Icon(
                      _sendComplete ? Icons.check_circle : Icons.info_outline,
                      color: _sendComplete ? MarsTheme.success : MarsTheme.cyanDim,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusMessage, style: GoogleFonts.cairo(
                      color: MarsTheme.textSecondary, fontSize: 13,
                    ))),
                  ]),
                ),

              const SizedBox(height: 20),

              // أزرار التحكم
              Row(children: [
                if (_parsedPasswords.isEmpty && !_isSending && !_sendComplete)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isScanning ? null : _pickAndParseCsv,
                      icon: const Icon(Icons.folder_open, size: 20),
                      label: Text('اختيار ملف CSV', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (_parsedPasswords.isNotEmpty && !_isSending)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendToHardware,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      label: Text('إرسال إلى وحدة التشفير', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MarsTheme.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (_sendComplete)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _sendComplete = false;
                        _statusMessage = '';
                      }),
                      icon: const Icon(Icons.replay, size: 20),
                      label: Text('استيراد آخر', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleState() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarsTheme.borderGlow, width: 1),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_upload_outlined, color: MarsTheme.textMuted, size: 40),
          const SizedBox(height: 8),
          Text('اختر ملف CSV للبدء', style: GoogleFonts.cairo(
            color: MarsTheme.textMuted, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _buildScanAnimation() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          height: 120,
          decoration: BoxDecoration(
            color: MarsTheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: MarsTheme.cyanNeon.withOpacity(0.2 + _pulseController.value * 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: MarsTheme.cyanNeon.withOpacity(0.05 + _pulseController.value * 0.1),
                blurRadius: 30, spreadRadius: -5,
              ),
            ],
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(
                  color: MarsTheme.cyanNeon,
                  strokeWidth: 2.5,
                  value: _isSending ? null : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isSending ? 'جاري الإرسال المشفّر...' : 'جاري المسح الأمني...',
                style: GoogleFonts.cairo(color: MarsTheme.cyanGlow, fontSize: 14),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildSuccessState() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: MarsTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarsTheme.success.withOpacity(0.3)),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, color: MarsTheme.success, size: 44),
          const SizedBox(height: 8),
          Text('تم المسح من الذاكرة بالكامل ✓', style: GoogleFonts.cairo(
            color: MarsTheme.success, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.2)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.list_alt, color: MarsTheme.cyanNeon, size: 22),
          const SizedBox(width: 8),
          Text('${_parsedPasswords.length} كلمة مرور', style: GoogleFonts.cairo(
            color: MarsTheme.cyanNeon, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            itemCount: _parsedPasswords.length > 5 ? 5 : _parsedPasswords.length,
            itemBuilder: (_, i) {
              final entry = _parsedPasswords[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.key, color: MarsTheme.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(entry['name'] ?? '', style: GoogleFonts.cairo(
                    color: MarsTheme.textSecondary, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(entry['username'] ?? '', style: GoogleFonts.firaCode(
                    color: MarsTheme.textMuted, fontSize: 11)),
                ]),
              );
            },
          ),
        ),
        if (_parsedPasswords.length > 5)
          Text('... و ${_parsedPasswords.length - 5} إدخالات أخرى', style: GoogleFonts.cairo(
            color: MarsTheme.textMuted, fontSize: 11)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  لوحة صحة كلمات المرور — Password Health Dashboard
// ═══════════════════════════════════════════════════════════════════════

class PasswordHealthDashboard extends StatelessWidget {
  const PasswordHealthDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final passwords = appState.tempPasswords;
        final analysis = _analyzePasswords(passwords);

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: MarsTheme.glassCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Icon(Icons.health_and_safety, color: MarsTheme.cyanNeon, size: 24),
                    const SizedBox(width: 10),
                    Text('تحليل قوة كلمات المرور', style: GoogleFonts.cairo(
                      color: MarsTheme.cyanNeon, fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    passwords.isEmpty
                        ? 'لا توجد كلمات مرور للتحليل — قم بالاستيراد أولاً'
                        : 'تحليل ${passwords.length} كلمة مرور',
                    style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _HealthGauge(
                        label: 'كلمات ضعيفة',
                        value: analysis.weakPercent,
                        count: '${analysis.weakCount}',
                        color: MarsTheme.error,
                        icon: Icons.warning_amber_rounded,
                      ),
                      _HealthGauge(
                        label: 'مكررة',
                        value: analysis.reusedPercent,
                        count: '${analysis.reusedCount}',
                        color: MarsTheme.warning,
                        icon: Icons.copy_all,
                      ),
                      _HealthGauge(
                        label: 'التقييم العام',
                        value: analysis.overallScore / 100,
                        count: '${analysis.overallScore}%',
                        color: _scoreColor(analysis.overallScore),
                        icon: Icons.analytics_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Color _scoreColor(int score) {
    if (score >= 80) return MarsTheme.success;
    if (score >= 50) return MarsTheme.warning;
    return MarsTheme.error;
  }

  static _PasswordAnalysis _analyzePasswords(List<Map<String, dynamic>> passwords) {
    if (passwords.isEmpty) {
      return _PasswordAnalysis(weakCount: 0, reusedCount: 0, overallScore: 0,
          weakPercent: 0, reusedPercent: 0);
    }
    int weak = 0;
    final seen = <String, int>{};
    for (final entry in passwords) {
      final pass = entry['password']?.toString() ?? '';
      if (pass.length < 8 || !pass.contains(RegExp(r'[0-9]'))) weak++;
      seen[pass] = (seen[pass] ?? 0) + 1;
    }
    int reused = seen.values.where((c) => c > 1).fold(0, (a, b) => a + b);
    double weakPct = weak / passwords.length;
    double reusedPct = reused / passwords.length;
    int score = ((1 - (weakPct * 0.5 + reusedPct * 0.5)) * 100).round().clamp(0, 100);
    return _PasswordAnalysis(
      weakCount: weak, reusedCount: reused, overallScore: score,
      weakPercent: weakPct, reusedPercent: reusedPct,
    );
  }
}

class _PasswordAnalysis {
  final int weakCount, reusedCount, overallScore;
  final double weakPercent, reusedPercent;
  _PasswordAnalysis({
    required this.weakCount, required this.reusedCount, required this.overallScore,
    required this.weakPercent, required this.reusedPercent,
  });
}

class _HealthGauge extends StatefulWidget {
  final String label, count;
  final double value;
  final Color color;
  final IconData icon;
  const _HealthGauge({
    required this.label, required this.count, required this.value,
    required this.color, required this.icon,
  });
  @override
  State<_HealthGauge> createState() => _HealthGaugeState();
}

class _HealthGaugeState extends State<_HealthGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _animation = Tween<double>(begin: 0, end: widget.value)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(_HealthGauge old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _animation = Tween<double>(begin: _animation.value, end: widget.value)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 90, height: 90,
            child: CustomPaint(
              painter: _GaugePainter(value: _animation.value, color: widget.color),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.icon, color: widget.color, size: 20),
                  const SizedBox(height: 2),
                  Text(widget.count, style: GoogleFonts.firaCode(
                    color: widget.color, fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(widget.label, style: GoogleFonts.cairo(
            color: MarsTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, 2 * pi, false,
      Paint()..color = color.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // Value arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, 2 * pi * value.clamp(0.0, 1.0), false,
      Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}
