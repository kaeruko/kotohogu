import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'local_content_preview.dart';

/// Public read-only Drive file; the ID is not a credential.
const String kotohoguContentDriveFileId =
    '1EnL41yBQZ6oY5smL3jPC3RwFUfd-jJ8Q';

const Duration driveEndpointTimeout = Duration(seconds: 12);

/// The catalog and all its sprites are pinned to one immutable release.
class HostedTownContent {
  const HostedTownContent({required this.baseUri, required this.catalog});
  final Uri baseUri;
  final RemoteContentCatalog catalog;
}

Uri parseGoogleDriveContentEndpoint(String body) {
  final lines = body
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length != 1) {
    throw FormatException(
      'kotohogu_api.txt must contain exactly one nonempty HTTPS release URL; '
      'found ${lines.length} nonempty lines.',
    );
  }
  final raw = lines.single;
  final uri = Uri.parse(raw);
  if (isCurrentReleasePointerUri(uri)) return uri;
  final pinnedUri = contentPreviewUri(raw);
  if (pinnedUri.scheme != 'https') {
    throw FormatException('Google Drive content endpoint must use HTTPS: $uri');
  }
  return pinnedUri;
}

/// The mutable pointer lives at the CDN root. No query, fragment, or user info.
bool isCurrentReleasePointerUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    uri.path == '/current.json';

/// Validate the exact publishing format. Never infer or try another release.
Uri parseCurrentReleasePointer(Uri pointerUri, String body) {
  if (!isCurrentReleasePointerUri(pointerUri)) {
    throw FormatException('Expected an HTTPS /current.json URI: $pointerUri');
  }
  final json = objectOf(jsonDecode(body), 'current.json');
  requireFields(json, {
    'schemaVersion', 'releaseId', 'basePath', 'manifestPath',
    'manifestSha256',
  }, 'current.json');

  const digestPattern = r'^[0-9a-f]{64}

Future<String> _downloadDriveFile(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Google Drive returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    const maxFileBytes = 4096;
    final bytes = <int>[];
    await for (final chunk in response.timeout(driveEndpointTimeout)) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw const FormatException('Google Drive endpoint file is too large');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: false);
  } finally {
    client.close(force: true);
  }
}

Future<Uri> loadGoogleDriveContentEndpoint({
  String fileId = kotohoguContentDriveFileId,
  Future<String> Function(Uri uri)? fetchText,
  DateTime? now,
}) async {
  final id = fileId.trim();
  if (!RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id)) {
    throw StateError('Invalid Google Drive content file ID');
  }
  final downloadUrl = Uri.https('drive.google.com', '/uc', {
    'export': 'download',
    'id': id,
    't': (now ?? DateTime.now()).millisecondsSinceEpoch.toString(),
  });
  final download = fetchText ?? _downloadDriveFile;
  final body = await download(downloadUrl).timeout(driveEndpointTimeout);
  return parseGoogleDriveContentEndpoint(body);
}

/// Release always loads Drive; a debug-only define may override it.
Future<Uri> resolveTownContentEndpoint({
  required String debugOverride,
  required bool isRelease,
  required Future<Uri> Function() loadDriveEndpoint,
}) {
  if (debugOverride.isNotEmpty) {
    if (isRelease) {
      throw StateError(
        'KOTOHOGU_LOCAL_CONTENT_URL is restricted to non-release builds.',
      );
    }
    return Future<Uri>.value(contentPreviewUri(debugOverride));
  }
  return loadDriveEndpoint();
}

Future<HostedTownContent> loadAppTownContent() async {
  const override = String.fromEnvironment('KOTOHOGU_LOCAL_CONTENT_URL');
  final endpoint = await resolveTownContentEndpoint(
    debugOverride: override,
    isRelease: kReleaseMode,
    loadDriveEndpoint: loadGoogleDriveContentEndpoint,
  );
  // Keep explicit debug overrides pinned. Release and normal launches read
  // one current.json pointer and use its immutable base throughout the session.
  final baseUri = override.isNotEmpty
      ? endpoint
      : await resolveDriveReleaseBaseUri(endpoint);
  final catalog = await fetchLocalContent(baseUri);
  return HostedTownContent(baseUri: baseUri, catalog: catalog);
}
;
  final id = json['releaseId'];
  final manifestHash = json['manifestSha256'];
  if (json['schemaVersion'] != 1 ||
      id is! String ||
      !RegExp(digestPattern).hasMatch(id) ||
      json['basePath'] != '/releases/$id/' ||
      json['manifestPath'] != '/releases/$id/manifest.json' ||
      manifestHash is! String ||
      !RegExp(digestPattern).hasMatch(manifestHash)) {
    throw const FormatException('Invalid or inconsistent current.json release pointer');
  }

  // Catalog and sprite URLs will all use this single immutable release.
  return contentPreviewUri(pointerUri.resolve('/releases/$id/').toString());
}

Future<String> _downloadCurrentReleasePointer(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('CloudFront current.json returned HTTP ' +
              response.statusCode.toString(),
          uri: uri);
    }
    if (response.headers.contentType?.mimeType != 'application/json') {
      throw FormatException(
          'Expected application/json for $uri, got ' +
              response.headers.contentType.toString());
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > 4096) {
        throw FormatException('CloudFront current.json is too large: $uri');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: false);
  } finally {
    client.close(force: true);
  }
}

/// The existing Drive text still contains a pinned release URL for old apps.
/// New apps use that URL only to locate its CloudFront origin; the release
/// itself always comes from current.json. A future Drive value of current.json
/// is also explicitly accepted. Neither mode falls back to an old release.
Future<Uri> resolveDriveReleaseBaseUri(
  Uri configuredEndpoint, {
  Future<String> Function(Uri uri)? fetchPointer,
}) async {
  final Uri pointerUri;
  if (isCurrentReleasePointerUri(configuredEndpoint)) {
    pointerUri = configuredEndpoint;
  } else {
    final pinned = contentPreviewUri(configuredEndpoint.toString());
    if (pinned.scheme != 'https') {
      throw FormatException('Drive release origin must be HTTPS: $pinned');
    }
    pointerUri = pinned.resolve('/current.json');
  }
  final text = await (fetchPointer ?? _downloadCurrentReleasePointer)(pointerUri);
  return parseCurrentReleasePointer(pointerUri, text);
}

Future<String> _downloadDriveFile(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Google Drive returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    const maxFileBytes = 4096;
    final bytes = <int>[];
    await for (final chunk in response.timeout(driveEndpointTimeout)) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw const FormatException('Google Drive endpoint file is too large');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: false);
  } finally {
    client.close(force: true);
  }
}

Future<Uri> loadGoogleDriveContentEndpoint({
  String fileId = kotohoguContentDriveFileId,
  Future<String> Function(Uri uri)? fetchText,
  DateTime? now,
}) async {
  final id = fileId.trim();
  if (!RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id)) {
    throw StateError('Invalid Google Drive content file ID');
  }
  final downloadUrl = Uri.https('drive.google.com', '/uc', {
    'export': 'download',
    'id': id,
    't': (now ?? DateTime.now()).millisecondsSinceEpoch.toString(),
  });
  final download = fetchText ?? _downloadDriveFile;
  final body = await download(downloadUrl).timeout(driveEndpointTimeout);
  return parseGoogleDriveContentEndpoint(body);
}

/// Release always loads Drive; a debug-only define may override it.
Future<Uri> resolveTownContentEndpoint({
  required String debugOverride,
  required bool isRelease,
  required Future<Uri> Function() loadDriveEndpoint,
}) {
  if (debugOverride.isNotEmpty) {
    if (isRelease) {
      throw StateError(
        'KOTOHOGU_LOCAL_CONTENT_URL is restricted to non-release builds.',
      );
    }
    return Future<Uri>.value(contentPreviewUri(debugOverride));
  }
  return loadDriveEndpoint();
}

Future<HostedTownContent> loadAppTownContent() async {
  const override = String.fromEnvironment('KOTOHOGU_LOCAL_CONTENT_URL');
  final endpoint = await resolveTownContentEndpoint(
    debugOverride: override,
    isRelease: kReleaseMode,
    loadDriveEndpoint: loadGoogleDriveContentEndpoint,
  );
  final catalog = await fetchLocalContent(endpoint);
  return HostedTownContent(baseUri: endpoint, catalog: catalog);
}
