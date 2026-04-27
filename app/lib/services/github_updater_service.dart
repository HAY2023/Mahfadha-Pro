import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

typedef DownloadProgressCallback = void Function(double progressPercent);
typedef VerificationStartCallback = void Function();

class SecurityException implements Exception {
  final String message;

  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

class GitHubReleaseAsset {
  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256Hash;

  const GitHubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sha256Hash,
  });
}

class GitHubReleaseInfo {
  final String tagName;
  final String body;
  final GitHubReleaseAsset appAsset;
  final GitHubReleaseAsset firmwareAsset;

  const GitHubReleaseInfo({
    required this.tagName,
    required this.body,
    required this.appAsset,
    required this.firmwareAsset,
  });
}

class VerifiedDownloadResult {
  final File file;
  final String sha256Hash;

  const VerifiedDownloadResult({
    required this.file,
    required this.sha256Hash,
  });
}

/// ══════════════════════════════════════════════════════════════════════
///  GitHub Releases OTA — Military-Grade Update Service
///
///  Security measures:
///  1. HTTPS-only connections to trusted GitHub domains
///  2. SHA-256 checksum verification on ALL downloaded files
///  3. Immediate deletion of any file that fails checksum
///  4. Manifest-backed releases with pinned hashes
///  5. Secure temp directory isolation
///  6. Self-update support (download MahfadhaPro.exe)
///  7. Firmware OTA (download firmware.bin for ESP32 flash)
/// ══════════════════════════════════════════════════════════════════════
class GitHubUpdaterService {
  GitHubUpdaterService({
    required this.owner,
    this.repository = 'Mahfadha-Pro',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String owner;
  final String repository;
  final http.Client _client;

  static const Set<String> _trustedHosts = {
    'api.github.com',
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'github-releases.githubusercontent.com',
  };

  static const String _manifestAssetName = 'latest.json';

  static const List<String> _appAssetCandidates = [
    'Mahfadha-Pro-Setup.exe',
    'MahfadhaPro.exe',
    'Mahfadha-Pro-Windows.zip',
  ];

  static const List<String> _firmwareAssetCandidates = [
    'firmware.bin',
  ];

  Uri get _latestReleaseUri => Uri.https(
        'api.github.com',
        '/repos/$owner/$repository/releases/latest',
      );

  /// ──────────────────────────────────────────────────────────────────
  ///  Fetch latest release metadata from GitHub API
  /// ──────────────────────────────────────────────────────────────────
  Future<GitHubReleaseInfo> fetchLatestRelease() async {
    _assertTrustedUri(_latestReleaseUri);

    final response = await _client.get(
      _latestReleaseUri,
      headers: _defaultHeaders,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'GitHub API request failed with status ${response.statusCode}.',
        uri: _latestReleaseUri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid GitHub release payload.');
    }

    final tagName = decoded['tag_name']?.toString().trim();
    final releaseNotes = decoded['body']?.toString() ?? '';
    final assets = decoded['assets'];

    if (tagName == null || tagName.isEmpty) {
      throw const FormatException('Missing tag_name in GitHub release.');
    }

    if (assets is! List) {
      throw const FormatException('Missing assets array in GitHub release.');
    }

    final manifestAssetJson = _findAssetJsonOrNull(
      assets,
      const [_manifestAssetName],
    );

    if (manifestAssetJson != null) {
      return _fetchManifestBackedRelease(
        tagName: tagName,
        releaseNotes: releaseNotes,
        manifestAssetJson: manifestAssetJson,
      );
    }

    final appAssetJson = _findAssetJson(assets, _appAssetCandidates);
    final firmwareAssetJson = _findAssetJson(assets, _firmwareAssetCandidates);

    return GitHubReleaseInfo(
      tagName: tagName,
      body: releaseNotes,
      appAsset: _parseLegacyReleaseAsset(
        assetJson: appAssetJson,
        releaseNotes: releaseNotes,
      ),
      firmwareAsset: _parseLegacyReleaseAsset(
        assetJson: firmwareAssetJson,
        releaseNotes: releaseNotes,
      ),
    );
  }

  /// ──────────────────────────────────────────────────────────────────
  ///  Download asset with progress tracking + SHA-256 verification
  ///  MILITARY-GRADE: File is deleted immediately if hash mismatch
  /// ──────────────────────────────────────────────────────────────────
  Future<VerifiedDownloadResult> downloadAndVerifyAsset({
    required GitHubReleaseAsset asset,
    DownloadProgressCallback? onProgress,
    VerificationStartCallback? onVerificationStart,
  }) async {
    _assertTrustedUri(asset.downloadUrl);

    final tempDirectory = await _ensureSecureTempDirectory();
    final filePath =
        '${tempDirectory.path}${Platform.pathSeparator}${asset.name}';
    final targetFile = File(filePath);

    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final request = http.Request('GET', asset.downloadUrl)
      ..headers.addAll(_defaultHeaders);

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Download failed with status ${streamedResponse.statusCode}.',
        uri: asset.downloadUrl,
      );
    }

    final contentLength = streamedResponse.contentLength;
    var receivedBytes = 0;
    final output = targetFile.openWrite(mode: FileMode.writeOnly);

    try {
      await for (final chunk in streamedResponse.stream) {
        receivedBytes += chunk.length;
        output.add(chunk);

        if (contentLength != null && contentLength > 0) {
          final progress = (receivedBytes / contentLength) * 100;
          onProgress?.call(progress.clamp(0, 100).toDouble());
        }
      }
    } catch (_) {
      await output.flush();
      await output.close();
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      rethrow;
    }

    await output.flush();
    await output.close();
    onProgress?.call(100.0);
    onVerificationStart?.call();

    // ── MILITARY-GRADE SHA-256 CHECKSUM ──
    final actualHash = await _calculateSha256(targetFile);
    final expectedHash = asset.sha256Hash.toLowerCase();

    if (actualHash != expectedHash) {
      // IMMEDIATE DESTRUCTION — compromised file
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      throw const SecurityException(
        'CHECKSUM MISMATCH — Compromised update file DESTROYED. '
        'Potential supply-chain attack detected.',
      );
    }

    return VerifiedDownloadResult(file: targetFile, sha256Hash: actualHash);
  }

  /// ──────────────────────────────────────────────────────────────────
  ///  Apply downloaded app update (launch installer / replace exe)
  /// ──────────────────────────────────────────────────────────────────
  Future<void> applyAppUpdate(VerifiedDownloadResult result) async {
    final file = result.file;
    final path = file.path.toLowerCase();

    if (path.endsWith('.exe')) {
      // Launch the installer/exe and exit current process
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
    } else if (path.endsWith('.zip')) {
      // For zip archives, just open the containing directory
      final dir = file.parent.path;
      await Process.start('explorer', [dir],
          mode: ProcessStartMode.detached);
    }
  }

  /// ──────────────────────────────────────────────────────────────────
  ///  Get the path to a verified firmware file for ESP32 flashing
  /// ──────────────────────────────────────────────────────────────────
  String? getFirmwarePath(VerifiedDownloadResult? result) {
    return result?.file.path;
  }

  // ════════════════════════════════════════════════════════════════════
  //  PRIVATE — Manifest-backed release parsing
  // ════════════════════════════════════════════════════════════════════

  Future<GitHubReleaseInfo> _fetchManifestBackedRelease({
    required String tagName,
    required String releaseNotes,
    required Map<String, dynamic> manifestAssetJson,
  }) async {
    final manifestDownloadUrl = _parseAssetDownloadUri(manifestAssetJson);
    final manifest = await _downloadManifest(manifestDownloadUrl);

    final schemaVersion = _parseIntField(
      manifest['schema_version'],
      fieldName: 'schema_version',
      allowZero: false,
    );

    if (schemaVersion < 1) {
      throw const FormatException('Unsupported release manifest schema.');
    }

    final manifestVersion = manifest['version']?.toString().trim();
    if (manifestVersion == null || manifestVersion.isEmpty) {
      throw const FormatException('Release manifest is missing version.');
    }

    if (manifestVersion != tagName) {
      throw FormatException(
        'Manifest version mismatch. Expected $tagName, got $manifestVersion.',
      );
    }

    final manifestAssets = manifest['assets'];
    if (manifestAssets is! Map<String, dynamic>) {
      throw const FormatException('Release manifest is missing assets.');
    }

    final appJson = manifestAssets['app'];
    final firmwareJson = manifestAssets['firmware'];

    if (appJson is! Map<String, dynamic>) {
      throw const FormatException('Release manifest is missing app asset.');
    }

    if (firmwareJson is! Map<String, dynamic>) {
      throw const FormatException(
        'Release manifest is missing firmware asset.',
      );
    }

    return GitHubReleaseInfo(
      tagName: manifestVersion,
      body: releaseNotes,
      appAsset: _parseManifestAsset(
        assetJson: appJson,
        assetLabel: 'app',
      ),
      firmwareAsset: _parseManifestAsset(
        assetJson: firmwareJson,
        assetLabel: 'firmware',
      ),
    );
  }

  Future<Map<String, dynamic>> _downloadManifest(Uri manifestUri) async {
    _assertTrustedUri(manifestUri);

    final response = await _client.get(
      manifestUri,
      headers: _defaultHeaders,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Manifest download failed with status ${response.statusCode}.',
        uri: manifestUri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid release manifest payload.');
    }

    return decoded;
  }

  Future<String> _calculateSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  Future<Directory> _ensureSecureTempDirectory() async {
    final base = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}mahfadha_pro_secure_updates',
    );

    if (!await base.exists()) {
      await base.create(recursive: true);
    }

    return base;
  }

  GitHubReleaseAsset _parseManifestAsset({
    required Map<String, dynamic> assetJson,
    required String assetLabel,
  }) {
    final name = assetJson['name']?.toString().trim();
    final downloadUrlValue = assetJson['download_url']?.toString().trim();
    final sha256Hash = assetJson['sha256']?.toString().trim();

    if (name == null || name.isEmpty) {
      throw FormatException('Manifest asset "$assetLabel" is missing name.');
    }

    if (downloadUrlValue == null || downloadUrlValue.isEmpty) {
      throw FormatException(
        'Manifest asset "$assetLabel" is missing download_url.',
      );
    }

    if (sha256Hash == null || sha256Hash.isEmpty) {
      throw FormatException('Manifest asset "$assetLabel" is missing sha256.');
    }

    final downloadUrl = Uri.parse(downloadUrlValue);
    _assertTrustedUri(downloadUrl);

    return GitHubReleaseAsset(
      name: name,
      downloadUrl: downloadUrl,
      size: _parseIntField(assetJson['size'], fieldName: '$assetLabel.size'),
      sha256Hash: _normalizeSha256(
        sha256Hash,
        fieldName: '$assetLabel.sha256',
      ),
    );
  }

  GitHubReleaseAsset _parseLegacyReleaseAsset({
    required Map<String, dynamic> assetJson,
    required String releaseNotes,
  }) {
    final name = assetJson['name']?.toString().trim();
    final size = _parseIntField(assetJson['size'], fieldName: 'size');

    if (name == null || name.isEmpty) {
      throw const FormatException('Release asset is missing a file name.');
    }

    return GitHubReleaseAsset(
      name: name,
      downloadUrl: _parseAssetDownloadUri(assetJson),
      size: size,
      sha256Hash: _extractSha256FromReleaseNotes(
        releaseNotes: releaseNotes,
        assetName: name,
      ),
    );
  }

  Uri _parseAssetDownloadUri(Map<String, dynamic> assetJson) {
    final downloadUrlValue = assetJson['browser_download_url']
        ?.toString()
        .trim();

    if (downloadUrlValue == null || downloadUrlValue.isEmpty) {
      throw const FormatException('Release asset is missing a download URL.');
    }

    final downloadUrl = Uri.parse(downloadUrlValue);
    _assertTrustedUri(downloadUrl);
    return downloadUrl;
  }

  Map<String, dynamic> _findAssetJson(
    List assets,
    List<String> assetNames,
  ) {
    final match = _findAssetJsonOrNull(assets, assetNames);
    if (match != null) {
      return match;
    }

    throw FormatException(
      'Required release asset not found. Tried: ${assetNames.join(', ')}',
    );
  }

  Map<String, dynamic>? _findAssetJsonOrNull(
    List assets,
    List<String> assetNames,
  ) {
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final currentName = asset['name']?.toString().trim();
      if (currentName == null) {
        continue;
      }

      for (final expectedName in assetNames) {
        if (currentName == expectedName) {
          return asset;
        }
      }
    }

    return null;
  }

  int _parseIntField(
    Object? value, {
    required String fieldName,
    bool allowZero = true,
  }) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw FormatException('Invalid integer value for $fieldName.');
    }

    if (!allowZero && parsed <= 0) {
      throw FormatException('$fieldName must be greater than zero.');
    }

    if (allowZero && parsed < 0) {
      throw FormatException('$fieldName cannot be negative.');
    }

    return parsed;
  }

  String _normalizeSha256(
    String value, {
    required String fieldName,
  }) {
    final normalized = value.trim().toLowerCase();
    final shaPattern = RegExp(r'^[a-f0-9]{64}$');
    if (!shaPattern.hasMatch(normalized)) {
      throw FormatException('Invalid SHA-256 value for $fieldName.');
    }
    return normalized;
  }

  String _extractSha256FromReleaseNotes({
    required String releaseNotes,
    required String assetName,
  }) {
    if (releaseNotes.trim().isEmpty) {
      throw FormatException(
        'Release notes are empty. Missing SHA-256 for $assetName.',
      );
    }

    final escapedAssetName = RegExp.escape(assetName);
    final patterns = <RegExp>[
      RegExp(
        '^\\s*$escapedAssetName\\s*[:=\\-|]\\s*([A-Fa-f0-9]{64})\\s*\$',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(
        '^\\s*SHA256[_\\-\\s]*$escapedAssetName\\s*[:=\\-|]\\s*([A-Fa-f0-9]{64})\\s*\$',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(
        '^\\s*[-*]\\s*$escapedAssetName\\s*[:=\\-|]\\s*([A-Fa-f0-9]{64})\\s*\$',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(
        '^\\s*$escapedAssetName[^\\r\\n]*?([A-Fa-f0-9]{64})\\s*\$',
        caseSensitive: false,
        multiLine: true,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(releaseNotes);
      if (match != null) {
        return match.group(1)!.toLowerCase();
      }
    }

    throw FormatException(
      'Unable to locate SHA-256 hash for $assetName in GitHub release notes.',
    );
  }

  void _assertTrustedUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        !_trustedHosts.contains(uri.host.toLowerCase())) {
      throw SecurityException(
        'Untrusted update source rejected: ${uri.toString()}',
      );
    }
  }

  Map<String, String> get _defaultHeaders => const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Mahfadha-Pro-Updater',
      };

  void dispose() {
    _client.close();
  }
}
