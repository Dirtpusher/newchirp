import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Outcome of comparing the installed NewChirp version against the release
/// manifest published by newchirp.net.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;

  /// Page a user should open to download the newest release, when published.
  final String? releaseUrl;

  bool get updateAvailable =>
      compareVersions(latestVersion, currentVersion) > 0;
}

/// Raised when the release manifest cannot be retrieved or parsed.
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Queries the NewChirp download server for the newest published release.
class UpdateChecker {
  UpdateChecker({
    Uri? manifestUri,
    Duration timeout = const Duration(seconds: 12),
  })  : manifestUri = manifestUri ?? defaultManifestUri,
        _timeout = timeout;

  /// Machine-readable release manifest served by newchirp.net.
  ///
  /// Expected JSON body:
  ///
  ///     {
  ///       version: 1.0.2,
  ///       release_url: https://newchirp.net/#download,
  ///       downloads: {windows: ..., macos: ..., linux: ...}
  ///     }
  ///
  /// Only `version` is required; `release_url` (or `url`) is optional.
  static final Uri defaultManifestUri =
      Uri.parse('https://newchirp.net/api/releases/latest');

  final Uri manifestUri;
  final Duration _timeout;

  Future<UpdateCheckResult> check(String currentVersion) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(manifestUri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateCheckException(
          'The update service returned status ${response.statusCode}.',
        );
      }
      final body =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      final manifest = _parseManifest(body);
      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: manifest.version,
        releaseUrl: manifest.releaseUrl,
      );
    } on UpdateCheckException {
      rethrow;
    } on TimeoutException {
      throw UpdateCheckException('The update check timed out.');
    } on SocketException {
      throw UpdateCheckException('Could not reach the update service.');
    } on FormatException {
      throw UpdateCheckException(
        'The update service returned an unexpected response.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static _ReleaseManifest _parseManifest(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Manifest is not a JSON object.');
    }
    final version = decoded['version'] ?? decoded['latest'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('Manifest is missing a version.');
    }
    final urlValue = decoded['release_url'] ?? decoded['url'];
    return _ReleaseManifest(
      version: version.trim(),
      releaseUrl: urlValue is String && urlValue.trim().isNotEmpty
          ? urlValue.trim()
          : null,
    );
  }
}

class _ReleaseManifest {
  const _ReleaseManifest({required this.version, this.releaseUrl});

  final String version;
  final String? releaseUrl;
}

/// Compares two dotted version strings, ignoring any `+build` metadata.
///
/// Returns a positive number when [a] is newer than [b], a negative number
/// when [a] is older, and zero when they are equivalent.
int compareVersions(String a, String b) {
  final aParts = _versionParts(a);
  final bParts = _versionParts(b);
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final aPart = i < aParts.length ? aParts[i] : 0;
    final bPart = i < bParts.length ? bParts[i] : 0;
    if (aPart != bPart) return aPart - bPart;
  }
  return 0;
}

List<int> _versionParts(String version) {
  final core = version.split('+').first.split('-').first.trim();
  return core.split('.').map((part) {
    final digits = RegExp(r'\d+').stringMatch(part);
    return digits == null ? 0 : int.parse(digits);
  }).toList(growable: false);
}

/// Opens [url] in the operating system's default browser.
///
/// Returns false when no usable launcher is available.
Future<bool> openExternalUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
    return true;
  } on ProcessException {
    return false;
  }
}
