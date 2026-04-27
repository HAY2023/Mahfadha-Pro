import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/github_updater_service.dart';
import '../theme/mars_theme.dart';

class UpdateCenterScreen extends StatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen> {
  static const String _currentDesktopVersion = '1.0.0+1';

  final GitHubUpdaterService _updater = GitHubUpdaterService(
    owner: 'HAY2023',
  );

  GitHubReleaseInfo? _releaseInfo;
  bool _isChecking = false;
  bool _isDownloadingApp = false;
  bool _isDownloadingFirmware = false;
  double _appProgress = 0;
  double _firmwareProgress = 0;
  String _appStatus = 'لم يتم تنفيذ فحص تحديث بعد.';
  String _firmwareStatus = 'لم يتم تنفيذ فحص تحديث بعد.';
  String? _appDownloadedPath;
  String? _firmwareDownloadedPath;
  String? _appHash;
  String? _firmwareHash;
  DateTime? _lastCheckedAt;

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_isChecking) {
      return;
    }

    setState(() {
      _isChecking = true;
      _releaseInfo = null;
      _appDownloadedPath = null;
      _firmwareDownloadedPath = null;
      _appHash = null;
      _firmwareHash = null;
      _appProgress = 0;
      _firmwareProgress = 0;
      _appStatus = 'Checking secure servers (GitHub)...';
      _firmwareStatus = 'Checking secure servers (GitHub)...';
    });

    try {
      final releaseInfo = await _updater.fetchLatestRelease();
      if (!mounted) {
        return;
      }

      setState(() {
        _isChecking = false;
        _releaseInfo = releaseInfo;
        _lastCheckedAt = DateTime.now();
        _appStatus =
            'تم العثور على الإصدار ${releaseInfo.tagName}. الحزمة المعتمدة للتطبيق: ${releaseInfo.appAsset.name}.';
        _firmwareStatus =
            'تم العثور على الإصدار ${releaseInfo.tagName}. ملف وحدة التشفير المعتمد: ${releaseInfo.firmwareAsset.name}.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isChecking = false;
        _appStatus = 'فشل الاتصال بخادم التحديثات الآمن: $error';
        _firmwareStatus = 'فشل الاتصال بخادم التحديثات الآمن: $error';
      });
    }
  }

  Future<void> _downloadAppUpdate() async {
    final releaseInfo = _releaseInfo;
    if (releaseInfo == null || _isDownloadingApp) {
      return;
    }

    setState(() {
      _isDownloadingApp = true;
      _appProgress = 0;
      _appDownloadedPath = null;
      _appHash = null;
      _appStatus = 'Downloading version ${releaseInfo.tagName}...';
    });

    try {
      final result = await _updater.downloadAndVerifyAsset(
        asset: releaseInfo.appAsset,
        onProgress: (progressPercent) {
          if (!mounted) {
            return;
          }

          setState(() {
            _appProgress = progressPercent / 100;
          });
        },
        onVerificationStart: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _appStatus = 'Verifying cryptographic signature...';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isDownloadingApp = false;
        _appProgress = 1;
        _appDownloadedPath = result.file.path;
        _appHash = result.sha256Hash;
        _appStatus =
            'اكتمل تنزيل تحديث التطبيق والتحقق منه بنجاح. الحزمة جاهزة للتثبيت المحلي.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isDownloadingApp = false;
        _appProgress = 0;
        _appStatus = error.toString();
      });
    }
  }

  Future<void> _downloadFirmwareUpdate() async {
    final releaseInfo = _releaseInfo;
    if (releaseInfo == null || _isDownloadingFirmware) {
      return;
    }

    setState(() {
      _isDownloadingFirmware = true;
      _firmwareProgress = 0;
      _firmwareDownloadedPath = null;
      _firmwareHash = null;
      _firmwareStatus = 'Downloading version ${releaseInfo.tagName}...';
    });

    try {
      final result = await _updater.downloadAndVerifyAsset(
        asset: releaseInfo.firmwareAsset,
        onProgress: (progressPercent) {
          if (!mounted) {
            return;
          }

          setState(() {
            _firmwareProgress = progressPercent / 100;
          });
        },
        onVerificationStart: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _firmwareStatus = 'Verifying cryptographic signature...';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isDownloadingFirmware = false;
        _firmwareProgress = 1;
        _firmwareDownloadedPath = result.file.path;
        _firmwareHash = result.sha256Hash;
        _firmwareStatus =
            'اكتمل تنزيل ملف وحدة التشفير والتحقق منه بنجاح. الملف جاهز للتمرير إلى جسر Python عبر USB.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isDownloadingFirmware = false;
        _firmwareProgress = 0;
        _firmwareStatus = error.toString();
      });
    }
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
    if (hash == null || hash.isEmpty) {
      return '-';
    }

    if (hash.length <= 16) {
      return hash;
    }

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
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildSectionCard(
                            title: 'تحديث التطبيق',
                            subtitle:
                                'قراءة manifest رسمي من GitHub ثم تنزيل الحزمة والتحقق من SHA-256 قبل أي اعتماد محلي.',
                            icon: Icons.system_update_alt_rounded,
                            child: _buildAppUpdateBody(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSectionCard(
                            title: 'تحديث وحدة التشفير',
                            subtitle:
                                'قراءة firmware.bin من نفس manifest الآمن ثم التحقق من سلامة الملف قبل تمريره إلى قناة USB.',
                            icon: Icons.memory_rounded,
                            child: _buildFirmwareUpdateBody(),
                          ),
                        ),
                      ],
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

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('رجوع'),
        ),
        const SizedBox(width: 14),
        Column(
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
              'قناة تحديث موحدة للتطبيق ووحدة التشفير عبر GitHub Releases و manifest رسمي.',
              style: GoogleFonts.cairo(
                color: MarsTheme.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _isChecking ? null : _checkForUpdates,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(_isChecking ? 'جارٍ الفحص' : 'التحقق من التحديثات'),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: MarsTheme.glassCard(borderRadius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MarsTheme.cyanNeon.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarsTheme.borderGlow),
                ),
                child: Icon(icon, color: MarsTheme.cyanNeon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.cairo(
                        color: MarsTheme.textMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildAppUpdateBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKeyValueRow('الإصدار الحالي', _currentDesktopVersion),
        const SizedBox(height: 10),
        _buildKeyValueRow('الإصدار المتاح', _releaseInfo?.tagName ?? '-'),
        const SizedBox(height: 10),
        _buildKeyValueRow(
          'آخر فحص',
          _lastCheckedAt == null ? '-' : _formatDate(_lastCheckedAt!),
        ),
        const SizedBox(height: 10),
        _buildKeyValueRow(
          'الحزمة المعتمدة',
          _releaseInfo?.appAsset.name ?? 'Mahfadha-Pro-Setup.exe',
        ),
        const SizedBox(height: 16),
        _buildStatusPanel(
          title: 'حالة التطبيق',
          message: _appStatus,
          color: _isDownloadingApp ? MarsTheme.warning : MarsTheme.cyanNeon,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: _isDownloadingApp || _appProgress > 0 ? _appProgress : 0,
            minHeight: 8,
            backgroundColor: MarsTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(
              _appProgress >= 1 ? MarsTheme.success : MarsTheme.cyanNeon,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildKeyValueRow('SHA-256', _shortHash(_appHash)),
        const SizedBox(height: 10),
        _buildKeyValueRow('المسار المؤقت', _appDownloadedPath ?? '-'),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_releaseInfo == null || _isDownloadingApp)
                ? null
                : _downloadAppUpdate,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              _isDownloadingApp ? 'جارٍ التنزيل' : 'تنزيل تحديث التطبيق',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFirmwareUpdateBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKeyValueRow('الإصدار المتاح', _releaseInfo?.tagName ?? '-'),
        const SizedBox(height: 10),
        _buildKeyValueRow(
          'الملف المعتمد',
          _releaseInfo?.firmwareAsset.name ?? 'firmware.bin',
        ),
        const SizedBox(height: 10),
        _buildKeyValueRow(
          'الحجم',
          _releaseInfo == null
              ? '-'
              : '${(_releaseInfo!.firmwareAsset.size / 1024).toStringAsFixed(1)} KB',
        ),
        const SizedBox(height: 16),
        _buildStatusPanel(
          title: 'حالة وحدة التشفير',
          message: _firmwareStatus,
          color:
              _isDownloadingFirmware ? MarsTheme.warning : MarsTheme.cyanNeon,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: _isDownloadingFirmware || _firmwareProgress > 0
                ? _firmwareProgress
                : 0,
            minHeight: 8,
            backgroundColor: MarsTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(
              _firmwareProgress >= 1
                  ? MarsTheme.success
                  : MarsTheme.cyanNeon,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildKeyValueRow('SHA-256', _shortHash(_firmwareHash)),
        const SizedBox(height: 10),
        _buildKeyValueRow('المسار المؤقت', _firmwareDownloadedPath ?? '-'),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_releaseInfo == null || _isDownloadingFirmware)
                ? null
                : _downloadFirmwareUpdate,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              _isDownloadingFirmware
                  ? 'جارٍ التنزيل'
                  : 'تنزيل تحديث وحدة التشفير',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyValueRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MarsTheme.surface.withOpacity(0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarsTheme.borderGlow),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              color: MarsTheme.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.firaCode(
                color: MarsTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel({
    required String title,
    required String message,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.cairo(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.cairo(
              color: MarsTheme.textSecondary,
              fontSize: 12.5,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}
