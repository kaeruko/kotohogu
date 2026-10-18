import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

// Preview-only entrypoint; the shipped game and saved collection are unchanged.
const _contentUrl = String.fromEnvironment('KOTOHOGU_LOCAL_CONTENT_URL');
final supportedFrames = List<String>.unmodifiable([
  'idle_front_01.png', 'clap_front_01.png', 'clap_front_02.png',
  for (final direction in ['front', 'back', 'left', 'right'])
    for (var n = 1; n <= 4; n++) 'walk_${direction}_0$n.png',
]);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (_contentUrl.isEmpty) {
    throw StateError('KOTOHOGU_LOCAL_CONTENT_URL must be specified');
  }
  runApp(LocalContentPreviewApp(baseUri: contentPreviewUri(_contentUrl)));
}

Uri localServerUri(String value) {
  final url = Uri.parse(value);
  if (url.scheme != 'http' ||
      !{'127.0.0.1', 'localhost', '10.0.2.2'}.contains(url.host) ||
      url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment ||
      (url.path.isNotEmpty && url.path != '/') || url.port == 0) {
    throw FormatException(
      'Use a local-only URL, e.g. http://10.0.2.2:8765: $value',
    );
  }
  return url;
}

/// Resolve only local development endpoints or immutable HTTPS releases.
Uri contentPreviewUri(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme == 'http') return localServerUri(value);
  if (uri.scheme != 'https' || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      uri.port != 443 ||
      !RegExp(r'^/releases/[a-f0-9]{64}/$').hasMatch(uri.path)) {
    throw FormatException(
      'Use local HTTP or a pinned HTTPS path ending in '
      '/releases/<64-character-sha256>/: $value',
    );
  }
  return uri;
}

Map<String, dynamic> objectOf(Object? raw, String field) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException('Expected JSON object: $field');
  }
  return raw;
}
List<dynamic> arrayOf(Object? raw, String field) {
  if (raw is! List<dynamic>) throw FormatException('Expected JSON array: $field');
  return raw;
}
void requireFields(Map<String, dynamic> data, Set<String> required,
    String field, {Set<String> optional = const {}}) {
  if (!data.keys.toSet().containsAll(required) ||
      data.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    throw FormatException('Unexpected or missing fields at $field: ${data.keys}');
  }
}
String nonempty(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected nonempty string: $field');
  }
  return value;
}

class RemoteResident {
  const RemoteResident({
    required this.id, required this.label, required this.artFolder,
    required this.profile, required this.homeAreaId,
    this.walkInTown = true,
  });
  final String id, label, artFolder, profile, homeAreaId;
  final bool walkInTown;

  factory RemoteResident.fromJson(Object? raw) {
    final row = objectOf(raw, 'resident');
    requireFields(row, {
      'key', 'id', 'label', 'artFolder', 'profile', 'homeAreaId',
      'nextDialogueNumber', 'inGacha', 'walkInTown',
    }, 'resident');
    final id = nonempty(row['id'], 'resident.id');
    final folder = nonempty(row['artFolder'], 'resident.artFolder');
    if (!RegExp(r'^[0-9]{2,}_[a-z][a-z0-9_]*$').hasMatch(id) ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(folder) ||
        folder.contains('..') ||
        row['key'] is! String || row['profile'] is! String ||
        row['inGacha'] is! bool || row['walkInTown'] is! bool ||
        row['nextDialogueNumber'] is! int ||
        (row['nextDialogueNumber'] as int) < 1 ||
        !{'plaza', 'park', 'shopping', 'village', 'salon'}
          .contains(row['homeAreaId'])) {
      throw FormatException('Invalid resident data: $id');
    }
    return RemoteResident(
      id: id,
      label: nonempty(row['label'], 'resident.label'),
      artFolder: folder,
      profile: row['profile'] as String,
      homeAreaId: row['homeAreaId'] as String,
      walkInTown: row['walkInTown'] as bool,
    );
  }
}

class RemoteDialogue {
  const RemoteDialogue(
    this.id, this.residentId, this.text, this.conditionCount,
    this.priority, this.once, {this.firstGreeting = false},
  );
  final String id, residentId, text;
  final int conditionCount;
  final int priority;
  final bool once;
  /// Initial hello, shown once before any other eligible resident dialogue.
  final bool firstGreeting;

  factory RemoteDialogue.fromJson(Object? raw) {
    final row = objectOf(raw, 'dialogue');
    requireFields(row, {
      'id', 'residentId', 'text', 'priority', 'once', 'logic', 'conditions',
    }, 'dialogue', optional: {'reply', 'firstGreeting'});
    final id = nonempty(row['id'], 'dialogue.id');
    final conditions = arrayOf(row['conditions'], 'dialogue.conditions');
    final firstGreeting = row['firstGreeting'] == true;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        row['priority'] is! int || row['once'] is! bool ||
        !{'all', 'any'}.contains(row['logic']) ||
        conditions.length > 8 ||
        conditions.any((row) => row is! Map<String, dynamic>) ||
        (row.containsKey('firstGreeting') && row['firstGreeting'] != true) ||
        (firstGreeting && (row['once'] != true ||
            row['priority'] == -1000 || conditions.isNotEmpty ||
            row.containsKey('reply')))) {
      throw FormatException('Invalid dialogue data: $id');
    }
    return RemoteDialogue(
      id,
      nonempty(row['residentId'], 'dialogue.residentId'),
      nonempty(row['text'], 'dialogue.text'),
      conditions.length,
      row['priority'] as int,
      row['once'] as bool,
      firstGreeting: firstGreeting,
    );
  }
}

class RemoteContentCatalog {
  const RemoteContentCatalog(this.characters, this.dialogues);
  final List<RemoteResident> characters;
  final List<RemoteDialogue> dialogues;

  factory RemoteContentCatalog.fromJson(String text) {
    final root = objectOf(jsonDecode(text), 'runtime catalog');
    requireFields(root, {'version', 'characters', 'dialogues'}, 'runtime catalog');
    if (root['version'] is! int || root['version'] != 1) {
      throw const FormatException('Unsupported catalog version');
    }
    final characters = arrayOf(root['characters'], 'characters')
      .map(RemoteResident.fromJson).toList();
    final dialogues = arrayOf(root['dialogues'], 'dialogues')
      .map(RemoteDialogue.fromJson).toList();
    if (characters.isEmpty || dialogues.isEmpty) {
      throw const FormatException('Empty runtime catalog');
    }
    final ids = <String>{}, folders = <String>{}, dialogueIds = <String>{};
    for (final row in characters) {
      if (!ids.add(row.id) || !folders.add(row.artFolder)) {
        throw FormatException('Duplicate resident ID or folder: ${row.id}');
      }
    }
    final defaultSpeakerIds = <String>{};
    final introductionSpeakerIds = <String>{};
    for (final row in dialogues) {
      if (!dialogueIds.add(row.id) || !ids.contains(row.residentId)) {
        throw FormatException('Duplicate or unknown-speaker dialogue: ${row.id}');
      }
      if (row.conditionCount == 0 && !row.once) {
        defaultSpeakerIds.add(row.residentId);
      }
      if (row.firstGreeting && !introductionSpeakerIds.add(row.residentId)) {
        throw FormatException('Duplicate first greeting: ${row.residentId}');
      }
    }
    if (!defaultSpeakerIds.containsAll(ids)) {
      throw FormatException('Resident lacks an unconditional line: ${ids.difference(defaultSpeakerIds)}');
    }
    return RemoteContentCatalog(
      List.unmodifiable(characters), List.unmodifiable(dialogues),
    );
  }

  RemoteResident residentById(String id) => characters.singleWhere(
    (item) => item.id == id,
    orElse: () => throw StateError('Resident was removed: $id'),
  );
  List<RemoteDialogue> linesFor(String id) => List.unmodifiable(
    dialogues.where((line) => line.residentId == id),
  );
}

Uri remoteSpriteUri(Uri baseUri, RemoteResident resident, String filename) {
  if (!supportedFrames.contains(filename)) {
    throw ArgumentError.value(filename, 'filename', 'Unrecognized frame');
  }
  return baseUri.resolve(
    'api/runtime/sprites/${Uri.encodeComponent(resident.artFolder)}/'
    '${Uri.encodeComponent(filename)}',
  );
}

Future<RemoteContentCatalog> fetchLocalContent(Uri baseUri) async {
  final url = baseUri.resolve('api/runtime/catalog');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final payload = await response.transform(utf8.decoder).join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'HTTP ${response.statusCode}: $payload', uri: url,
      );
    }
    if (response.headers.contentType?.mimeType != 'application/json') {
      throw FormatException(
        'Expected JSON from $url, got ${response.headers.contentType}',
      );
    }
    return RemoteContentCatalog.fromJson(payload);
  } finally {
    client.close(force: true);
  }
}

class LocalContentPreviewApp extends StatelessWidget {
  const LocalContentPreviewApp({super.key, required this.baseUri});
  final Uri baseUri;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ことほぎ・ローカル配信テスト',
    theme: ThemeData(colorSchemeSeed: const Color(0xFFB77B50)),
    home: LocalContentPreviewScreen(baseUri: baseUri),
  );
}

class LocalContentPreviewScreen extends StatefulWidget {
  const LocalContentPreviewScreen({super.key, required this.baseUri});
  final Uri baseUri;
  @override
  State<LocalContentPreviewScreen> createState() =>
      _LocalContentPreviewScreenState();
}

class _LocalContentPreviewScreenState extends State<LocalContentPreviewScreen> {
  late Future<RemoteContentCatalog> _catalog;
  String? _residentId;
  String _frame = 'idle_front_01.png';

  @override
  void initState() {
    super.initState();
    _catalog = fetchLocalContent(widget.baseUri);
  }

  void _reload() {
    setState(() {
      _catalog = fetchLocalContent(widget.baseUri);
      _frame = 'idle_front_01.png';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ことほぎ・配信テスト'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh),
          tooltip: '最新データを再取得'),
      ],
    ),
    body: FutureBuilder<RemoteContentCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              '配信データの取得・検証に失敗しました。処理を停止しました。\n'
              '${widget.baseUri}\n${snapshot.error}\n${snapshot.stackTrace}',
              key: const ValueKey('local-content-error'),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return _show(snapshot.requireData);
      },
    ),
  );

  Widget _show(RemoteContentCatalog contents) {
    final id = _residentId ?? contents.characters.first.id;
    final resident = contents.residentById(id);
    final lines = contents.linesFor(id);
    final url = remoteSpriteUri(widget.baseUri, resident, _frame);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('接続中: ${widget.baseUri}', style: Theme.of(context).textTheme.bodySmall),
        Text('住民 ${contents.characters.length}人・セリフ ${contents.dialogues.length}件'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            for (final character in contents.characters)
              ChoiceChip(
                label: Text(character.label),
                selected: id == character.id,
                onSelected: (_) => setState(() {
                  _residentId = character.id;
                  _frame = 'idle_front_01.png';
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('${resident.label}（${resident.id}）',
          style: Theme.of(context).textTheme.titleLarge),
        Text('エリア: ${resident.homeAreaId}'),
        if (resident.profile.isNotEmpty) Text(resident.profile),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('frame-${resident.id}-$_frame'),
          initialValue: _frame,
          decoration: const InputDecoration(labelText: '画像フレーム'),
          items: [
            for (final filename in supportedFrames)
              DropdownMenuItem(value: filename, child: Text(filename)),
          ],
          onChanged: (filename) {
            if (filename == null) throw StateError('Missing sprite frame');
            setState(() => _frame = filename);
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 240,
          child: Image.network(
            url.toString(),
            key: ValueKey('remote-sprite-${resident.id}-$_frame'),
            fit: BoxFit.contain,
            semanticLabel: '${resident.label}の立ち絵',
            errorBuilder: (context, error, stackTrace) => SelectableText(
              '画像を読み込めません。代替画像は使いません。\n$url\n$error',
              key: const ValueKey('remote-sprite-error'),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('セリフ ${lines.length}件',
          style: Theme.of(context).textTheme.titleMedium),
        for (final line in lines)
          ListTile(
            title: Text(line.text),
            subtitle: Text('${line.id}｜${line.firstGreeting ? '🌸 初対面・1回のみ' : '条件 ${line.conditionCount}件'}'),
          ),
        const SizedBox(height: 16),
        const Text(
          'ローカル配信の検証専用です。ガチャと住民の所持記録はまだ変更しません。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
