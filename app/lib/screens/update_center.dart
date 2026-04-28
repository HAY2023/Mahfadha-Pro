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
  static const String _currentDesktopVersion = '1.0.0+1';

  final GitHubUpdaterService _updater = GitHubUpdaterService(
    owner: 'HAY2023',
  );

  GitHubReleaseInfo? _releaseInfo;
  bool _isChecking = false;
  bool _isDownloadingApp = false;
  double _appProgress = 0;
  String? _appDownloadedPath;
  String? _appHash;
  DateTime? _lastCheckedAt;

  // ── Status types for visual feedback ──
  _UpdateStatus _appStatus = _UpdateStatus.idle;
  String _appStatusMessage = 'لم يتم فحص التحديثات بعد.';

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _updater.dispose();
    super.dispose();
  }

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
        _appStatusMessage =
            'الإصدار ${releaseInfo.tagName} متاح للتنزيل.\nالحزمة: ${releaseInfo.appAsset.name}';
      });
    } on NoReleasesException {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _lastCheckedAt = DateTime.now();
        _appStatus = _UpdateStatus.upToDate;
        _appStatusMessage =
            'أنت تستخدم أحدث إصدار.\nلا توجد تحديثات جديدة متاحة حالياً.';
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
        onProgress: (progressPercent) {
          if (!mounted) return;
          setState(() {
            _appProgress = progressPercent / 100;
          });
        },
        onVerificationStart: () {
          if (!mounted) return;
          setState(() {
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
        _appStatusMessage =
            'تم التنزيل والتحقق بنجاح ✓\nالتحديث جاهز للتثبيت.';
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

    final result = VerifiedDownloadResult(
      file: File(_appDownloadedPath!),
      sha256Hash: _appHash!,
    );

    await _updater.applyAppUpdate(result);
  }

  String _formatDate(DateTime value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$yyyy/$month/$day - $hh:$mm';
  }

  String _shortHash(String? hash) {
    if (hash == null || hash.isEmpty) return '-';
    if (hash.length <= 16) return hash;
    return '${hash.substring(0, 12)}...${hash.substring(hash.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          gradient: MarsTheme.backgroundGradient,
        ),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 380),
          tween: Tween(begin: 0, end: 1),
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 18 * (1 - value)),
              child: child,
            ),
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
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () {
            try {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.setCurrentPage(SidebarPage.home);
            } catch (_) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('رجوع'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مركز التحديثات',
                style: GoogleFonts.cairo(
                  color: MarsTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'تحديث التطبيق عبر GitHub Releases مع التحقق من SHA-256.',
                style: GoogleFonts.cairo(
                  color: MarsTheme.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final isActive = _isChecking;
            return Container(
              decoration: isActive
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: MarsTheme.cyanNeon
                              .withOpacity(0.2 * _pulseController.value),
                          blurRadius: 20,
                          spreadRadius: -4,
                        ),
                      ],
                    )
                  : null,
              child: child,
            );
          },
          child: ElevatedButton.icon(
            onPressed: _isChecking ? null : _checkForUpdates,
            icon: AnimatedRotation(
              turns: _isChecking ? 1.0 : 0.0,
              duration: const Duration(seconds: 1),
              child: const Icon(Icons.refresh_rounded, size: 18),
            ),
            label: Text(_isChecking ? 'جارٍ الفحص...' : 'فحص التحديثات'),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: MarsTheme.glassCard(borderRadius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _statusColor.withOpacity(0.2)),
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحديث تطبيق Mahfadha Pro',
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'يتضمن VC++ Runtime لضمان التشغيل على جميع الأجهزة.',
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textMuted,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Info Grid ──
          Row(
            children: [
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.local_offer_rounded,
                  label: 'الإصدار الحالي',
                  value: _currentDesktopVersion,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.new_releases_rounded,
                  label: 'الإصدار المتاح',
                  value: _releaseInfo?.tagName ?? '-',
                  highlight: _releaseInfo != null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoTile(
                  icon: Icons.schedule_rounded,
                  label: 'آخر فحص',
                  value: _lastCheckedAt != null
                      ? _formatDate(_lastCheckedAt!)
                      : '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Status Panel ──
          _buildStatusPanel(),
          const SizedBox(height: 16),

          // ── Progress Bar ──
          if (_isDownloadingApp || _appProgress > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _appProgress,
                      minHeight: 8,
                      backgroundColor: MarsTheme.surfaceLight,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _appProgress >= 1
                            ? MarsTheme.success
                            : MarsTheme.cyanNeon,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(_appProgress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.firaCode(
                    color: MarsTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Hash + Path details ──
          if (_appHash != null || _appDownloadedPath != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.fingerprint_rounded,
                    label: 'SHA-256',
                    value: _shortHash(_appHash),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoTile(
                    icon: Icons.folder_rounded,
                    label: 'المسار المؤقت',
                    value: _appDownloadedPath ?? '-',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          const Spacer(),

          // ── Action Buttons ──
          Row(
            children: [
              // Download button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_releaseInfo == null || _isDownloadingApp)
                      ? null
                      : _downloadAppUpdate,
                  icon: Icon(
                    _isDownloadingApp
                        ? Icons.downloading_rounded
                        : Icons.download_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isDownloadingApp ? 'جارٍ التنزيل...' : 'تنزيل التحديث',
                  ),
                ),
              ),

              // Install button (only when download is complete)
              if (_appStatus == _UpdateStatus.ready) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _installUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MarsTheme.success,
                    ),
                    icon: const Icon(Icons.install_desktop_rounded, size: 18),
                    label: const Text('تثبيت التحديث'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? MarsTheme.cyanNeon.withOpacity(0.06)
            : MarsTheme.surface.withOpacity(0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? MarsTheme.cyanNeon.withOpacity(0.2)
              : MarsTheme.borderGlow,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MarsTheme.textMuted, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.cairo(
                  color: MarsTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.firaCode(
              color: highlight ? MarsTheme.cyanNeon : MarsTheme.textPrimary,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final shouldPulse = _appStatus == _UpdateStatus.checking ||
                  _appStatus == _UpdateStatus.downloading ||
                  _appStatus == _UpdateStatus.verifying;
              return Opacity(
                opacity: shouldPulse
                    ? 0.5 + _pulseController.value * 0.5
                    : 1.0,
                child: child,
              );
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_statusIcon, color: _statusColor, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle,
                  style: GoogleFonts.cairo(
                    color: _statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _appStatusMessage,
                  style: GoogleFonts.cairo(
                    color: MarsTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Status helpers ──

  Color get _statusColor {
    switch (_appStatus) {
      case _UpdateStatus.idle:
        return MarsTheme.textMuted;
      case _UpdateStatus.checking:
        return MarsTheme.cyanNeon;
      case _UpdateStatus.upToDate:
        return MarsTheme.success;
      case _UpdateStatus.available:
        return MarsTheme.cyanNeon;
      case _UpdateStatus.downloading:
        return MarsTheme.warning;
      case _UpdateStatus.verifying:
        return MarsTheme.cyanNeon;
      case _UpdateStatus.ready:
        return MarsTheme.success;
      case _UpdateStatus.error:
        return MarsTheme.error;
    }
  }

  IconData get _statusIcon {
    switch (_appStatus) {
      case _UpdateStatus.idle:
        return Icons.info_outline_rounded;
      case _UpdateStatus.checking:
        return Icons.search_rounded;
      case _UpdateStatus.upToDate:
        return Icons.check_circle_rounded;
      case _UpdateStatus.available:
        return Icons.new_releases_rounded;
      case _UpdateStatus.downloading:
        return Icons.downloading_rounded;
      case _UpdateStatus.verifying:
        return Icons.verified_rounded;
      case _UpdateStatus.ready:
        return Icons.check_circle_rounded;
      case _UpdateStatus.error:
        return Icons.error_outline_rounded;
    }
  }

  String get _statusTitle {
    switch (_appStatus) {
      case _UpdateStatus.idle:
        return 'في الانتظار';
      case _UpdateStatus.checking:
        return 'جارٍ الفحص...';
      case _UpdateStatus.upToDate:
        return 'أحدث إصدار ✓';
      case _UpdateStatus.available:
        return 'تحديث متاح';
      case _UpdateStatus.downloading:
        return 'جارٍ التنزيل...';
      case _UpdateStatus.verifying:
        return 'جارٍ التحقق...';
      case _UpdateStatus.ready:
        return 'جاهز للتثبيت ✓';
      case _UpdateStatus.error:
        return 'خطأ';
    }
  }
}

enum _UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  ready,
  error,
}
