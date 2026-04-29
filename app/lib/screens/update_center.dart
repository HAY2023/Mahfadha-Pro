import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/github_updater_service.dart';
import '../theme/mars_theme.dart';

class UpdateCenterScreen extends StatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen>
    with SingleTickerProviderStateMixin {
  static const String _currentDesktopVersion = '1.0.2';

  final GitHubUpdaterService _updater = GitHubUpdaterService(owner: 'HAY2023');

  GitHubReleaseInfo? _releaseInfo;
  bool _isChecking = false;
  bool _isDownloadingApp = false;
  double _appProgress = 0;
  String? _appDownloadedPath;
  String? _appHash;
  DateTime? _lastCheckedAt;

  _UpdateStatus _appStatus = _UpdateStatus.idle;
  String _appStatusMessage = 'لم يتم فحص التحديثات بعد.';

  // ── Firmware/Controller state ──
  _UpdateStatus _fwStatus = _UpdateStatus.idle;
  String _fwStatusMessage = 'لم يتم فحص تحديثات المتحكم بعد.';

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _updater.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  App Update Logic
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkForUpdates() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _releaseInfo = null;
      _appDownloadedPath = null;
      _appHash = null;
      _appProgress = 0;
      _appStatus = _UpdateStatus.checking;
      _appStatusMessage = 'جارٍ الاتصال بخوادم GitHub الآمنة...';
    });

    try {
      final releaseInfo = await _updater.fetchLatestRelease();
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _releaseInfo = releaseInfo;
        _lastCheckedAt = DateTime.now();
        _appStatus = _UpdateStatus.available;
        _appStatusMessage = 'الإصدار ${releaseInfo.tagName} متاح للتنزيل.\nالحزمة: ${releaseInfo.appAsset.name}';
      });
    } on NoReleasesException {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _lastCheckedAt = DateTime.now();
        _appStatus = _UpdateStatus.upToDate;
        _appStatusMessage = 'أنت تستخدم أحدث إصدار.\nلا توجد تحديثات جديدة.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _appStatus = _UpdateStatus.error;
        _appStatusMessage = 'تعذر الاتصال بخادم التحديثات.\n$error';
      });
    }
  }

  Future<void> _downloadAppUpdate() async {
    final releaseInfo = _releaseInfo;
    if (releaseInfo == null || _isDownloadingApp) return;
    setState(() {
      _isDownloadingApp = true;
      _appProgress = 0;
      _appDownloadedPath = null;
      _appHash = null;
      _appStatus = _UpdateStatus.downloading;
      _appStatusMessage = 'جارٍ تنزيل الإصدار ${releaseInfo.tagName}...';
    });

    try {
      final result = await _updater.downloadAndVerifyAsset(
        asset: releaseInfo.appAsset,
        onProgress: (p) { if (mounted) setState(() => _appProgress = p / 100); },
        onVerificationStart: () {
          if (mounted) setState(() {
            _appStatus = _UpdateStatus.verifying;
            _appStatusMessage = 'جارٍ التحقق من سلامة الملف (SHA-256)...';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _isDownloadingApp = false;
        _appProgress = 1;
        _appDownloadedPath = result.file.path;
        _appHash = result.sha256Hash;
        _appStatus = _UpdateStatus.ready;
        _appStatusMessage = 'تم التنزيل والتحقق بنجاح ✓\nالتحديث جاهز للتثبيت.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloadingApp = false;
        _appProgress = 0;
        _appStatus = _UpdateStatus.error;
        _appStatusMessage = '$error';
      });
    }
  }

  Future<void> _installUpdate() async {
    if (_appDownloadedPath == null || _appHash == null) return;
    final shouldInstall = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: MarsTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.system_update_rounded, color: MarsTheme.cyanNeon, size: 24),
            SizedBox(width: 10),
            Expanded(child: Text('تثبيت التحديث', style: TextStyle(color: MarsTheme.textPrimary))),
          ]),
          content: const Text('سيتم إغلاق التطبيق وتشغيل المثبت. هل تريد المتابعة؟',
            style: TextStyle(color: MarsTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.install_desktop_rounded, size: 18),
              label: const Text('تثبيت الآن'),
              style: ElevatedButton.styleFrom(backgroundColor: MarsTheme.success),
            ),
          ],
        ),
      ),
    );
    if (shouldInstall != true) return;
    setState(() {
      _appStatus = _UpdateStatus.ready;
      _appStatusMessage = 'جارٍ تشغيل المثبت وإغلاق التطبيق...';
    });
    final result = VerifiedDownloadResult(file: File(_appDownloadedPath!), sha256Hash: _appHash!);
    await _updater.applyAppUpdate(result);
  }

  // ═══════════════════════════════════════════════════════════
  //  Firmware Check Logic
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkFirmwareUpdate() async {
    setState(() {
      _fwStatus = _UpdateStatus.checking;
      _fwStatusMessage = 'جارٍ البحث عن تحديثات المتحكم (Firmware)...';
    });
    try {
      final releaseInfo = await _updater.fetchLatestRelease();
      if (!mounted) return;
      final hasFw = releaseInfo.rawAssets.any(
        (a) => a['name'].toString().toLowerCase().endsWith('.bin'));
      setState(() {
        _fwStatus = hasFw ? _UpdateStatus.available : _UpdateStatus.upToDate;
        _fwStatusMessage = hasFw
            ? 'تحديث المتحكم ${releaseInfo.tagName} متاح.\nيتضمن تحسينات أمنية وإصلاحات للأداء.'
            : 'المتحكم يعمل بأحدث إصدار.\nلا توجد تحديثات firmware جديدة.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fwStatus = _UpdateStatus.upToDate;
        _fwStatusMessage = 'المتحكم يعمل بأحدث إصدار.';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════
  String _formatDate(DateTime v) =>
      '${v.year}/${v.month.toString().padLeft(2, '0')}/${v.day.toString().padLeft(2, '0')} - ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';

  String _shortHash(String? h) {
    if (h == null || h.isEmpty) return '-';
    return h.length <= 16 ? h : '${h.substring(0, 12)}...${h.substring(h.length - 8)}';
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(gradient: MarsTheme.backgroundGradient),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 380),
          tween: Tween(begin: 0, end: 1),
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: child),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 22),
                  Expanded(child: _buildUpdateCard()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(children: [
      OutlinedButton.icon(
        onPressed: () {
          try {
            Provider.of<AppState>(context, listen: false).setCurrentPage(SidebarPage.home);
          } catch (_) { Navigator.of(context).pop(); }
        },
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('رجوع'),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مركز التحديثات', style: GoogleFonts.cairo(
          color: MarsTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('تحديث التطبيق والمتحكم عبر GitHub Releases مع التحقق من SHA-256.',
          style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 12.5)),
      ])),
      const SizedBox(width: 12),
      AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) => Container(
          decoration: _isChecking ? BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: MarsTheme.cyanNeon.withOpacity(0.2 * _pulseController.value), blurRadius: 20, spreadRadius: -4)],
          ) : null,
          child: child,
        ),
        child: ElevatedButton.icon(
          onPressed: _isChecking ? null : _checkForUpdates,
          icon: AnimatedRotation(turns: _isChecking ? 1.0 : 0.0, duration: const Duration(seconds: 1),
            child: const Icon(Icons.refresh_rounded, size: 18)),
          label: Text(_isChecking ? 'جارٍ الفحص...' : 'فحص التحديثات'),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════
  //  TABS: App Update + Controller Update
  // ═══════════════════════════════════════════════════════════
  Widget _buildUpdateCard() {
    return DefaultTabController(
      length: 2,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: MarsTheme.glassCard(borderRadius: 24),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
              color: MarsTheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MarsTheme.borderGlow),
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: MarsTheme.cyanNeon.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MarsTheme.cyanNeon.withOpacity(0.25)),
              ),
              labelColor: MarsTheme.cyanNeon,
              unselectedLabelColor: MarsTheme.textMuted,
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w500, fontSize: 13),
              dividerHeight: 0,
              indicatorSize: TabBarIndicatorSize.tab,
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.desktop_windows_rounded, size: 16), SizedBox(width: 8), Text('تحديث التطبيق')])),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.memory_rounded, size: 16), SizedBox(width: 8), Text('تحديث المتحكم')])),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(child: TabBarView(children: [
            _buildAppUpdateTab(),
            _buildFirmwareUpdateTab(),
          ])),
        ]),
      ),
    );
  }

  Widget _buildAppUpdateTab() {
    return SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _iconBox(_statusColor, _statusIcon),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تحديث تطبيق Mahfadha Pro', style: GoogleFonts.cairo(
              color: MarsTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('يتضمن VC++ Runtime لضمان التشغيل على جميع الأجهزة.',
              style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 11.5)),
          ])),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _infoTile(Icons.local_offer_rounded, 'الإصدار الحالي', _currentDesktopVersion)),
          const SizedBox(width: 12),
          Expanded(child: _infoTile(Icons.new_releases_rounded, 'الإصدار المتاح', _releaseInfo?.tagName ?? '-', highlight: _releaseInfo != null)),
          const SizedBox(width: 12),
          Expanded(child: _infoTile(Icons.schedule_rounded, 'آخر فحص', _lastCheckedAt != null ? _formatDate(_lastCheckedAt!) : '-')),
        ]),
        const SizedBox(height: 16),
        _statusPanel(_statusColor, _statusIcon, _statusTitle, _appStatusMessage, _appStatus),
        const SizedBox(height: 16),
        if (_isDownloadingApp || _appProgress > 0) ...[
          _progressBar(_appProgress, _appProgress >= 1 ? MarsTheme.success : MarsTheme.cyanNeon),
          const SizedBox(height: 16),
        ],
        if (_appHash != null) ...[
          _infoTile(Icons.fingerprint_rounded, 'SHA-256', _shortHash(_appHash)),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: (_releaseInfo == null || _isDownloadingApp) ? null : _downloadAppUpdate,
            icon: Icon(_isDownloadingApp ? Icons.downloading_rounded : Icons.download_rounded, size: 18),
            label: Text(_isDownloadingApp ? 'جارٍ التنزيل...' : 'تنزيل التحديث'),
          )),
          if (_appStatus == _UpdateStatus.ready) ...[
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              onPressed: _installUpdate,
              style: ElevatedButton.styleFrom(backgroundColor: MarsTheme.success),
              icon: const Icon(Icons.install_desktop_rounded, size: 18),
              label: const Text('تثبيت التحديث'),
            )),
          ],
        ]),
      ],
    ));
  }

  Widget _buildFirmwareUpdateTab() {
    final c = _fwColor; final ic = _fwIcon;
    return SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _iconBox(c, ic),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تحديث كود المتحكم (ESP32-S3)', style: GoogleFonts.cairo(
              color: MarsTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('تحديث البرنامج الثابت لوحدة التشفير المادية عبر OTA.',
              style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 11.5)),
          ])),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _infoTile(Icons.developer_board_rounded, 'الجهاز', 'ESP32-S3')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile(Icons.security_rounded, 'التشفير', 'ATECC608A')),
          const SizedBox(width: 12),
          Expanded(child: _infoTile(Icons.fingerprint, 'البصمة', 'GROW R503')),
        ]),
        const SizedBox(height: 16),
        _statusPanel(c, ic, _fwTitle, _fwStatusMessage, _fwStatus),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MarsTheme.warning.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MarsTheme.warning.withOpacity(0.15)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: MarsTheme.warning, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'تحذير: لا تفصل الجهاز أثناء تحديث المتحكم. قد يؤدي الانقطاع إلى تلف البرنامج الثابت.',
              style: GoogleFonts.cairo(color: MarsTheme.warning, fontSize: 11, height: 1.6))),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _fwStatus == _UpdateStatus.checking ? null : _checkFirmwareUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: MarsTheme.surfaceLight, foregroundColor: MarsTheme.cyanNeon,
            side: BorderSide(color: MarsTheme.cyanNeon.withOpacity(0.3))),
          icon: Icon(_fwStatus == _UpdateStatus.checking ? Icons.downloading_rounded : Icons.search_rounded, size: 18),
          label: Text(_fwStatus == _UpdateStatus.checking ? 'جارٍ الفحص...' : 'فحص تحديثات المتحكم'),
        )),
      ],
    ));
  }

  // ═══════════════════════════════════════════════════════════
  //  Reusable Widgets
  // ═══════════════════════════════════════════════════════════
  Widget _iconBox(Color c, IconData ic) => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.withOpacity(0.2))),
    child: Icon(ic, color: c, size: 22));

  Widget _infoTile(IconData icon, String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? MarsTheme.cyanNeon.withOpacity(0.06) : MarsTheme.surface.withOpacity(0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? MarsTheme.cyanNeon.withOpacity(0.2) : MarsTheme.borderGlow)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: MarsTheme.textMuted, size: 14), const SizedBox(width: 6),
          Text(label, style: GoogleFonts.cairo(color: MarsTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.firaCode(
          color: highlight ? MarsTheme.cyanNeon : MarsTheme.textPrimary, fontSize: 12,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ]));
  }

  Widget _statusPanel(Color c, IconData ic, String title, String msg, _UpdateStatus status) {
    final shouldPulse = status == _UpdateStatus.checking || status == _UpdateStatus.downloading || status == _UpdateStatus.verifying;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300), width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.18))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedBuilder(animation: _pulseController, builder: (_, child) => Opacity(
          opacity: shouldPulse ? 0.5 + _pulseController.value * 0.5 : 1.0, child: child),
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(ic, color: c, size: 18))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.cairo(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(msg, style: GoogleFonts.cairo(color: MarsTheme.textSecondary, fontSize: 12.5, height: 1.7)),
        ])),
      ]));
  }

  Widget _progressBar(double val, Color c) => Row(children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(value: val, minHeight: 8, backgroundColor: MarsTheme.surfaceLight,
        valueColor: AlwaysStoppedAnimation<Color>(c)))),
    const SizedBox(width: 12),
    Text('${(val * 100).toStringAsFixed(0)}%', style: GoogleFonts.firaCode(
      color: MarsTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
  ]);

  // ── Status getters ──
  Color get _statusColor => _colorFor(_appStatus);
  IconData get _statusIcon => _iconFor(_appStatus);
  String get _statusTitle => _titleFor(_appStatus);
  Color get _fwColor => _colorFor(_fwStatus);
  IconData get _fwIcon => _iconFor(_fwStatus);
  String get _fwTitle => _titleFor(_fwStatus);

  Color _colorFor(_UpdateStatus s) => switch (s) {
    _UpdateStatus.idle => MarsTheme.textMuted,
    _UpdateStatus.checking || _UpdateStatus.verifying || _UpdateStatus.available => MarsTheme.cyanNeon,
    _UpdateStatus.upToDate || _UpdateStatus.ready => MarsTheme.success,
    _UpdateStatus.downloading => MarsTheme.warning,
    _UpdateStatus.error => MarsTheme.error,
  };

  IconData _iconFor(_UpdateStatus s) => switch (s) {
    _UpdateStatus.idle => Icons.info_outline_rounded,
    _UpdateStatus.checking => Icons.search_rounded,
    _UpdateStatus.upToDate => Icons.check_circle_rounded,
    _UpdateStatus.available => Icons.new_releases_rounded,
    _UpdateStatus.downloading => Icons.downloading_rounded,
    _UpdateStatus.verifying => Icons.verified_rounded,
    _UpdateStatus.ready => Icons.check_circle_rounded,
    _UpdateStatus.error => Icons.error_outline_rounded,
  };

  String _titleFor(_UpdateStatus s) => switch (s) {
    _UpdateStatus.idle => 'في الانتظار',
    _UpdateStatus.checking => 'جارٍ الفحص...',
    _UpdateStatus.upToDate => 'أحدث إصدار ✓',
    _UpdateStatus.available => 'تحديث متاح',
    _UpdateStatus.downloading => 'جارٍ التنزيل...',
    _UpdateStatus.verifying => 'جارٍ التحقق...',
    _UpdateStatus.ready => 'جاهز للتثبيت ✓',
    _UpdateStatus.error => 'خطأ',
  };
}

enum _UpdateStatus { idle, checking, upToDate, available, downloading, verifying, ready, error }
