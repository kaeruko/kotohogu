import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_lift/google_drive_content_source.dart';

void main() {
  const sha = '8a284a0ab93db6f19256458a0a5a6b4a6cd357f08737e38568f50043e364a970';
  const url = 'https://d2aowvb1pjx3w2.cloudfront.net/releases/$sha/';

  test('Google Drive reads a public text file with cache-busting', () async {
    final result = await loadGoogleDriveContentEndpoint(
      fileId: 'test-file-id',
      now: DateTime.fromMillisecondsSinceEpoch(1234),
      fetchText: (uri) async {
        expect(uri.scheme, 'https');
        expect(uri.host, 'drive.google.com');
        expect(uri.path, '/uc');
        expect(uri.queryParameters['id'], 'test-file-id');
        expect(uri.queryParameters['export'], 'download');
        expect(uri.queryParameters['t'], '1234');
        return '$url\n';
      },
    );
    expect(result.toString(), url);
    expect(result.resolve('api/runtime/catalog').toString(),
        '${url}api/runtime/catalog');
  });

  test('bad Drive text is rejected, no fallback', () {
    for (final raw in [
      '', ' \n ', '$url\n$url',
      '<html>Google Drive sign in</html>',
      'http://10.0.2.2:8765/',
      'https://example.com/current.json?tracking=1',
      'https://example.com/current.json/',
      'https://user@example.com/current.json',
      'https://example.com/releases/latest/',
      'https://example.com/releases/$sha',
    ]) {
      expect(() => parseGoogleDriveContentEndpoint(raw),
          throwsFormatException, reason: raw);
    }
  });

  test('current.json URL is an explicitly valid Drive endpoint', () {
    const pointer = 'https://d2aowvb1pjx3w2.cloudfront.net/current.json';
    expect(parseGoogleDriveContentEndpoint(' $pointer\n').toString(), pointer);
  });

  test('existing pinned Drive file resolves latest release from current.json',
      () async {
    const pointer = 'https://d2aowvb1pjx3w2.cloudfront.net/current.json';
    const manifestHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    var calls = 0;
    final resolved = await resolveDriveReleaseBaseUri(
      Uri.parse(url),
      fetchPointer: (uri) async {
        calls++;
        expect(uri.toString(), pointer);
        return jsonEncode({
          'schemaVersion': 1,
          'releaseId': sha,
          'basePath': '/releases/$sha/',
          'manifestPath': '/releases/$sha/manifest.json',
          'manifestSha256': manifestHash,
        });
      },
    );
    expect(calls, 1);
    expect(resolved.toString(), url);
    expect(resolved.resolve('api/runtime/catalog').toString(),
        url + 'api/runtime/catalog');

    // When Drive explicitly contains /current.json it uses the same flow.
    final direct = await resolveDriveReleaseBaseUri(
      Uri.parse(pointer),
      fetchPointer: (uri) async {
        expect(uri.toString(), pointer);
        return jsonEncode({
          'schemaVersion': 1,
          'releaseId': sha,
          'basePath': '/releases/$sha/',
          'manifestPath': '/releases/$sha/manifest.json',
          'manifestSha256': manifestHash,
        });
      },
    );
    expect(direct, resolved);
  });

  test('a new current.json release replaces the prior pinned seed URL', () async {
    const nextSha =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final result = await resolveDriveReleaseBaseUri(
      Uri.parse(url),
      fetchPointer: (uri) async => jsonEncode({
        'schemaVersion': 1,
        'releaseId': nextSha,
        'basePath': '/releases/$nextSha/',
        'manifestPath': '/releases/$nextSha/manifest.json',
        'manifestSha256': nextSha,
      }),
    );
    expect(result.toString(),
        'https://d2aowvb1pjx3w2.cloudfront.net/releases/$nextSha/');
  });

  test('current.json rejects corrupt, inconsistent or changed schemas', () {
    const pointer = 'https://d2aowvb1pjx3w2.cloudfront.net/current.json';
    final uri = Uri.parse(pointer);
    final valid = <String, Object>{
      'schemaVersion': 1,
      'releaseId': sha,
      'basePath': '/releases/$sha/',
      'manifestPath': '/releases/$sha/manifest.json',
      'manifestSha256': List.filled(64, 'b').join(),
    };
    for (final invalid in <String>[
      '',
      '[]',
      '{}',
      '{bad json}',
      jsonEncode({...valid, 'schemaVersion': 2}),
      jsonEncode({...valid, 'schemaVersion': '1'}),
      jsonEncode({...valid, 'releaseId': 'latest'}),
      jsonEncode({...valid, 'basePath': '/releases/other/'}),
      jsonEncode({...valid, 'manifestPath': '/releases/other/manifest.json'}),
      jsonEncode({...valid, 'manifestSha256': 'bad'}),
      jsonEncode({...valid, 'newField': true}),
    ]) {
      expect(() => parseCurrentReleasePointer(uri, invalid),
          throwsFormatException, reason: invalid);
    }
    expect(() => parseCurrentReleasePointer(
        Uri.parse('http://d2aowvb1pjx3w2.cloudfront.net/current.json'),
        jsonEncode(valid)), throwsFormatException);
  });

  test('broken current.json fails; pinned Drive version is never a fallback',
      () async {
    var attempts = 0;
    await expectLater(
      resolveDriveReleaseBaseUri(Uri.parse(url),
          fetchPointer: (uri) async {
        attempts++;
        throw const FormatException('Corrupt current pointer');
      }),
      throwsFormatException,
    );
    expect(attempts, 1);
  });

  test('download error propagates without fallback', () async {
    await expectLater(
      loadGoogleDriveContentEndpoint(
        fileId: 'test-file-id',
        fetchText: (_) async => throw StateError('Drive unavailable'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('debug override skips Drive, release never accepts an override', () async {
    var driveCalls = 0;
    Future<Uri> fakeDrive() async {
      driveCalls++;
      return Uri.parse(url);
    }
    final local = await resolveTownContentEndpoint(
      debugOverride: 'http://10.0.2.2:8765',
      isRelease: false,
      loadDriveEndpoint: fakeDrive,
    );
    expect(local.toString(), 'http://10.0.2.2:8765');
    expect(driveCalls, 0);
    expect(
      () => resolveTownContentEndpoint(
        debugOverride: 'http://10.0.2.2:8765',
        isRelease: true,
        loadDriveEndpoint: fakeDrive,
      ),
      throwsStateError,
    );
    expect(driveCalls, 0);
    expect(
      (await resolveTownContentEndpoint(
        debugOverride: '',
        isRelease: true,
        loadDriveEndpoint: fakeDrive,
      )).toString(),
      url,
    );
    expect(driveCalls, 1);
  });

  test('invalid Drive file ID fails before network access', () async {
    var fetched = false;
    await expectLater(
      loadGoogleDriveContentEndpoint(
        fileId: ' ',
        fetchText: (_) async {
          fetched = true;
          return '$url\n';
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(fetched, false);
  });
}
