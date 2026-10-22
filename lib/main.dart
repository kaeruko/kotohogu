import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'celebration.dart';
import 'dialogue_engine.dart';
import 'marche.dart';
import 'town_rules.dart';
import 'oyasumi_club.dart';
import 'local_content_preview.dart';
import 'google_drive_content_source.dart';
import 'local_town_visitors.dart';
import 'progress.dart';
import 'home_skin.dart';
import 'game_home.dart';
import 'missions_screen.dart';
import 'history_screen.dart';
import 'debug_menu_screen.dart';
import 'dev_tools.dart';
import 'resident_collection.dart';
import 'resident_conversation_dialog.dart';
import 'resident_gacha.dart';
import 'gacha_hud.dart';
import 'kotohogisu_tutorial.dart';
import 'town_areas.dart';
import 'town_area_navigator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    FutureLiftApp(
      controller: ProgressController(
        LocalProgressStore(SharedPreferencesAsync()),
      ),
      remoteContentLoader: loadAppTownContent,
    ),
  );
}

const ink = Color(0xFF63351F);
const teal = Color(0xFF277A70);
const orange = Color(0xFFBF4E27);
const cream = Color(0xFFFBEDD3);

class FutureLiftApp extends StatelessWidget {
  const FutureLiftApp({
    super.key,
    required this.controller,
    this.dialogueCatalog,
    this.enableTutorial = true,
    this.remoteContentLoader,
    this.townRandom,
    this.initialPage = 0,
  }) : assert(initialPage >= 0 && initialPage <= 3);
  /// Used by the separate App Store screenshot entrypoint only.
  /// Production continues to start on the home page.
  final int initialPage;
  final ProgressController controller;
  /// Optional random stream for reproducible outings in tests.
  final math.Random? townRandom;
  final bool enableTutorial;
  /// Production entrypoint resolves the URL from Google Drive.
  /// Null keeps deterministic legacy widget tests network-independent.
  final Future<HostedTownContent> Function()? remoteContentLoader;
  /// Optional fixed catalog allows deterministic tests without asset-loading races.
  final DialogueCatalog? dialogueCatalog;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FutureLift',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: teal, surface: cream),
      scaffoldBackgroundColor: cream,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFFFFF4DA),
        indicatorColor: Color(0xFFFFD898),
      ),
    ),
    home: FutureLiftHome(
      controller: controller,
      dialogueCatalog: dialogueCatalog,
      enableTutorial: enableTutorial,
      remoteContentLoader: remoteContentLoader,
      townRandom: townRandom,
      initialPage: initialPage,
    ),
  );
}

class FutureLiftHome extends StatefulWidget {
  const FutureLiftHome({
    super.key,
    required this.controller,
    this.dialogueCatalog,
    this.enableTutorial = true,
    this.remoteContentLoader,
    this.townRandom,
    this.initialPage = 0,
  }) : assert(initialPage >= 0 && initialPage <= 3);
  /// Used by the separate App Store screenshot entrypoint only.
  /// Production continues to start on the home page.
  final int initialPage;
  final ProgressController controller;
  final math.Random? townRandom;
  final DialogueCatalog? dialogueCatalog;
  final bool enableTutorial;
  final Future<HostedTownContent> Function()? remoteContentLoader;

  @override
  State<FutureLiftHome> createState() => _FutureLiftHomeState();
}

class _FutureLiftHomeState extends State<FutureLiftHome>
    with WidgetsBindingObserver {
  final _townSceneKey = GlobalKey();
  final ScrollController _townScrollController = ScrollController();
  late int _page;
  // A debug run or explicitly opted-in TestFlight build shows the
  // developer entry directly. Store builds never include it.
  bool _developerMenuUnlocked = developerToolsAvailable;
  final _developerUnlockSequence = DeveloperMenuUnlockSequence();
  MissionPeriod _missionPeriod = MissionPeriod.daily;
  Mission _previewMission = Mission.strength;
  int _homeVisit = 0;
  TownArea _townArea = TownArea.plaza;
  late TownVisit _townVisit;
  bool _celebrating = false;
  bool _tutorialSaving = false;
  // Replaying is UI-only; it must not modify persisted tutorial or mission state.
  bool _tutorialReplay = false;
  static const _tutorialSeenId = 'tutorial_kotohogisu_v1';
  Timer? _midnight;
  int _marcheDailyDialogueRotation = 0;
  bool _marcheConversationOpen = false;
  bool _clubConversationOpen = false;
  final Map<String, int> _clubRotations = {};
  Timer? _clubClock;
  OyasumiScene _clubScene(Progress progress) => OyasumiScene(
    saved: progress.oyasumi, owned: progress.residents.owned,
    now: controller.clock(),
    enabled: _debugTownResidents == null,
    parkCleanerStarted: progress.seenDialogues.contains(
      OyasumiScene.parkCleanerUnlockId,
    ),
  );
  /// Debug-only town cast kept in memory; never written to the save file.
  List<TownResident>? _debugTownResidents;
  /// Debug-only, opt-in showcase of not-yet-owned remote residents.
  bool _showUnownedPreviewVisitors = false;
  /// In-memory only; recreated as normal whenever the app restarts.
  SalonUnlockDebugMode _salonUnlockMode = SalonUnlockDebugMode.normal;
  static Future<DialogueCatalog>? _cachedDialogueCatalog;
  late final Future<DialogueCatalog> _dialoguesFuture;
  // A single future carries both the pinned CDN URL and matching catalog.
  Future<HostedTownContent>? _remoteContentFuture;
  ProgressController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _townVisit = TownVisit(random: widget.townRandom);
    WidgetsBinding.instance.addObserver(this);
    _dialoguesFuture = widget.dialogueCatalog != null
        ? SynchronousFuture(widget.dialogueCatalog!)
        : (_cachedDialogueCatalog ??= DialogueCatalog.load());
    final loader = widget.remoteContentLoader;
    if (loader != null) _remoteContentFuture = loader();
    controller.initialize();
    _scheduleMidnight();
    _clubClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _page == 2) setState(() {});
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = controller.clock().toLocal();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(tomorrow.difference(now), () async {
      await controller.refreshDay();
      if (mounted) _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.refreshDay();
      _scheduleMidnight();
      _reloadLocalResidents();
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _clubClock?.cancel();
    _townScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _complete(Mission mission) async {
    if (_celebrating) return;
    final beforeBalance = controller.progress!.residents.availableKotohogi(
      controller.progress!.points,
    );
    final earned = await controller.complete(mission);
    if (!mounted || !earned) return;
    // Capture one committed snapshot: lifetime mission points and the
    // spendable kotohogi wallet are different values after gacha draws.
    final after = controller.progress!;
    final balance = after.residents.availableKotohogi(after.points);
    _celebrating = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Celebration(
        missionTitle: mission.title,
        total: balance,
        creditedKotohogi: balance - beforeBalance,
        residents: after.residents.owned,
      ),
    );
    _celebrating = false;
    // Also catches a midnight that occurred while saving or celebrating.
    await controller.refreshDay();
  }

  /// Replays the celebration without touching the progress store.
  Future<void> _previewCelebration() async {
    if (!developerToolsAvailable ||
        _celebrating ||
        controller.busy ||
        controller.failure != null ||
        controller.progress == null) {
      return;
    }
    final total = controller.progress!.residents.availableKotohogi(
      controller.progress!.points,
    );
    final missionTitle = _previewMission.title;
    _celebrating = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Celebration(
          missionTitle: missionTitle,
          total: total,
          preview: true,
          residents: controller.progress!.residents.owned,
        ),
      );
    } finally {
      _celebrating = false;
    }
  }

  void _replayTutorial() {
    if (!developerToolsAvailable ||
        _tutorialSaving ||
        _tutorialReplay ||
        _celebrating ||
        controller.busy ||
        controller.failure != null ||
        controller.progress == null) {
      return;
    }
    setState(() {
      _tutorialReplay = true;
      _page = 0;
      _homeVisit++;
    });
  }

  Future<void> _endTutorial({required bool openMissions}) async {
    if (_tutorialReplay) {
      // Preview-only: neither read nor mutate the saved seenDialogues flag.
      setState(() {
        _tutorialReplay = false;
        if (openMissions) _page = 1;
      });
      return;
    }
    if (_tutorialSaving || controller.busy || controller.failure != null) return;
    setState(() => _tutorialSaving = true);
    try {
      final recorded = await controller.recordDialogueSeen(_tutorialSeenId);
      if (!mounted || !recorded) return;
      if (openMissions) setState(() => _page = 1);
    } finally {
      if (mounted) setState(() => _tutorialSaving = false);
    }
  }

  /// Leaving debug previews must not strand the player in a locked area
  /// with all its navigation controls hidden.
  void _returnToUnlockedTownArea() {
    if (_debugTownResidents != null ||
        _salonUnlockMode != SalonUnlockDebugMode.normal ||
        controller.progress == null) {
      return;
    }
    final points = controller.progress!.points;
    if (!_townArea.isUnlocked(points, owned: controller.progress!.residents.owned)) {
      _townArea = TownArea.values.lastWhere(
        (area) => area.isUnlocked(points, owned: controller.progress!.residents.owned),
      );
    }
  }

  void _setDebugTownEnabled(bool enabled) {
    if (!developerToolsAvailable || controller.busy || controller.progress == null ||
        controller.failure != null) {
      return;
    }
    setState(() {
      _debugTownResidents = enabled
          ? visibleTownResidents(controller.progress!.residents.owned)
          : null;
      if (enabled) _showUnownedPreviewVisitors = false;
      _returnToUnlockedTownArea();
    });
  }

  void _setUnownedPreviewVisitors(bool enabled) {
    if (!developerToolsAvailable || controller.busy || controller.failure != null ||
        controller.progress == null) {
      return;
    }
    setState(() {
      _showUnownedPreviewVisitors = enabled;
      if (enabled) _debugTownResidents = null;
      _returnToUnlockedTownArea();
    });
  }

  void _setDebugTownResident(TownResident resident, bool selected) {
    if (!developerToolsAvailable || controller.busy || controller.failure != null) return;
    final current = _debugTownResidents;
    if (current == null) {
      throw StateError('Enable the debug town selection first.');
    }
    if (current.contains(resident) == selected) return;
    setState(() {
      _debugTownResidents = List<TownResident>.unmodifiable(
        selected
            ? [...current, resident]
            : current.where((value) => value != resident),
      );
    });
  }

  void _setSalonUnlockMode(SalonUnlockDebugMode mode) {
    if (!developerToolsAvailable || controller.busy || controller.failure != null ||
        controller.progress == null) {
      return;
    }
    setState(() {
      _salonUnlockMode = mode;
      _returnToUnlockedTownArea();
    });
  }

  void _onNavigationDestinationSelected(int index) {
    // In signed developer builds, seven quick taps on the Menu tab unlock
    // the local debug tools. Regular users always see the ordinary menu.
    if (index == 4 && developerToolsAvailable && !kDebugMode &&
        !_developerMenuUnlocked) {
      if (_developerUnlockSequence.registerHistoryTap(DateTime.now())) {
        setState(() => _developerMenuUnlocked = true);
        _selectPage(4);
        return;
      }
    } else if (index != 4) {
      _developerUnlockSequence.reset();
    }
    final destination = switch (index) {
      0 => 0, // Home
      1 => 1, // Self-care
      2 => 5, // Consultation
      3 => 2, // Town
      4 => 6, // Menu
      _ => throw RangeError.index(index, const [0, 1, 2, 3, 4]),
    };
    _selectPage(destination);
  }

  int get _selectedFooterIndex => switch (_page) {
    0 => 0,
    1 => 1,
    5 => 2,
    2 => 3,
    3 || 4 || 6 => 4,
    _ => throw StateError('Unexpected page: $_page'),
  };

  void _selectPage(int index) {
    setState(() {
      if (index == 2 && _page != 2) {
        _townVisit = TownVisit(random: widget.townRandom);
      }
      _page = index;
      if (index == 0) _homeVisit++;
    });
  }

  Future<void> _editPlayerName() async {
    final current = controller.progress;
    if (current == null || controller.busy || controller.failure != null) return;
    final formKey = GlobalKey<FormState>();
    var editedName = current.playerName;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('名前を変える'),
          content: Form(
            key: formKey,
            child: TextFormField(
              key: const ValueKey('player-name-input'),
              initialValue: current.playerName,
              onChanged: (value) => editedName = value,
              autofocus: true,
              maxLength: maxPlayerNameLength,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '名前',
                hintText: '新しい名前',
              ),
              validator: (value) {
                final name = value ?? '';
                if (name.isEmpty) return '名前を入力してください';
                if (name != name.trim()) {
                  return '前後の空白を取り除いてください';
                }
                if (!isValidPlayerName(name)) {
                  return '12文字以内の名前を入力してください';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-player-name'),
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('やめる'),
            ),
            FilledButton(
              key: const ValueKey('save-player-name'),
              onPressed: saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                updateDialog(() => saving = true);
                final saved = await controller.setPlayerName(editedName);
                if (!dialogContext.mounted) return;
                if (saved || controller.failure != null) {
                  Navigator.of(dialogContext).pop();
                } else {
                  updateDialog(() => saving = false);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDialogue(TownResident resident, {bool inSalon = false, bool inBakery = false, bool inCommunityCenter = false}) async {
    if (controller.busy || controller.failure != null ||
        controller.progress == null) {
      return;
    }
    final scene = _clubScene(controller.progress!);
    final clubGroup = scene.group(resident,
      inPlaza: !inSalon && !inBakery && !inCommunityCenter && _page == 2 && _townArea == TownArea.plaza);
    if (clubGroup != null) {
      await _showClubDialogue(scene, resident, clubGroup);
      return;
    }
    final catalog = await _dialoguesFuture;
    if (!mounted || controller.failure != null) return;
    final rules = TownRules(
      controller.progress!, visit: _townVisit,
      oyasumi: _clubScene(controller.progress!),
      debugTownResidents: _debugTownResidents);
    final site = inCommunityCenter ? 'community_center' :
        inBakery ? 'bakery' : inSalon ? 'salon' :
        _page == 2 ? 'town' : 'roster';
    final visibleIds = rules.conversationPeers(
      inCommunityCenter
          ? ConversationSite.communityCenter
          : inBakery
          ? ConversationSite.bakery
          : inSalon
          ? ConversationSite.salon
          : _page == 2
              ? ConversationSite.town
              : ConversationSite.roster,
      area: !inSalon && !inBakery && !inCommunityCenter && _page == 2 ? _townArea : null,
      previewSalonUnowned: inSalon && developerToolsAvailable &&
          _salonUnlockMode == SalonUnlockDebugMode.forceOpen,
    );
    final familyOuting = !inSalon && !inBakery && !inCommunityCenter &&
        _page == 2 && _townArea == TownArea.shopping &&
        _debugTownResidents == null &&
        _townVisit.isFamilyOuting(
          controller.progress!.residents.owned, controller.progress!.points,
          afterOyasumiClub: controller.progress!.oyasumi.completed == 3) &&
        (resident == familyOutingMother || resident == familyOutingDaughter);
    final line = familyOuting
        ? catalog.selectById(
            id: _townVisit.nextFamilyOutingDialogueId(resident),
            resident: resident,
            progress: controller.progress!,
            now: controller.clock(),
            townResidentIds: visibleIds,
            site: site,
          )
        : catalog.select(
            resident: resident,
            progress: controller.progress!,
            now: controller.clock(),
            townResidentIds: visibleIds,
            site: site,
          );
    // Conversations in the debug-only cast must not alter saved seen IDs.
    if (_debugTownResidents == null &&
        !(inSalon && developerToolsAvailable &&
            _salonUnlockMode == SalonUnlockDebugMode.forceOpen) &&
        !controller.progress!.seenDialogues.contains(line.id)) {
      final persisted = await controller.recordDialogueSeen(line.id);
      if (!persisted || !mounted) return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => ResidentConversationDialog(
        speaker: resident,
        dialogue: line,
      ),
    );
  }

  Future<void> _showClubDialogue(OyasumiScene scene, TownResident resident, String group) async {
    if (_clubConversationOpen) return;
    _clubConversationOpen = true;
    try {
    final key = '$group/${resident.id}';
    // A daytime conversation can involve only characters currently in the
    // same outdoor area. A roster conversation always stays solo.
    final peers = group == 'resting' && _page == 2
        ? TownRules(
            controller.progress!,
            visit: _townVisit,
            oyasumi: _clubScene(controller.progress!),
            debugTownResidents: _debugTownResidents,
          ).conversationPeers(ConversationSite.town, area: _townArea)
        : {resident.id};
    final line = scene.dialogue(
      resident, group, _clubRotations[key] ?? 0,
      availableResidentIds: peers,
    );
      final read = await showDialog<bool>(
        context: context,
        builder: (_) => PagedConversationDialog(
          conversationId: line.id, reportCompletion: true,
          badge: group == 'resting'
              ? null
              : group == 'patrol'
                  ? 'よまわり'
                  : 'ゆうぐれおやすみクラブ',
          turns: [
            for (final turn in line.turns)
              ConversationTurn(
                label: turn.resident.label,
                avatar: TownResidentAvatar(resident: turn.resident),
                text: turn.text,
              ),
          ],
        ),
      );
      if (read != true || !mounted) return;
      if (scene.introduction(resident, group)) {
        await controller.completeOyasumi(scene, resident, group);
      } else {
        _clubRotations[key] = (_clubRotations[key] ?? 0) + 1;
      }
    } finally {
      _clubConversationOpen = false;
    }
  }

  /// The stall has its own sequential story and daily conversation rotation.
  /// Reloading the app restarts only the everyday order, not the read story.
  Future<void> _visitMarche() async {
    final progress = controller.progress;
    if (_marcheConversationOpen || controller.busy ||
        controller.failure != null ||
        progress == null || !isMarcheOpen(progress)) {
      return;
    }
    _marcheConversationOpen = true;
    try {
      final catalog = await _dialoguesFuture;
      if (!mounted || controller.busy || controller.failure != null ||
          controller.progress == null ||
          !isMarcheOpen(controller.progress!)) {
        return;
      }
      final current = controller.progress!;
      final daily = isMarcheStoryComplete(current);
      final line = selectMarcheDialogue(
        catalog: catalog,
        progress: current,
        now: controller.clock(),
        dailyRotation: _marcheDailyDialogueRotation,
      );
      // Debug-only resident previews never alter real saved read history.
      if (_debugTownResidents == null &&
          !current.seenDialogues.contains(line.id)) {
        final persisted = await controller.recordDialogueSeen(line.id);
        if (!persisted || !mounted) return;
      }
      if (daily) _marcheDailyDialogueRotation++;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ResidentConversationDialog(
          speaker: tonkoMarcheOwner,
          dialogue: line,
        ),
      );
    } finally {
      _marcheConversationOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HostedTownContent>(
    future: _remoteContentFuture,
    builder: (context, hostedSnapshot) {
      if (_remoteContentFuture != null && hostedSnapshot.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '配信設定または住民データを取得できないため、停止しました。',
                      key: ValueKey('town-remote-content-error'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      '${hostedSnapshot.error}\n${hostedSnapshot.stackTrace}',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reloadLocalResidents,
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (_remoteContentFuture != null && !hostedSnapshot.hasData) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return FutureBuilder<DialogueCatalog>(
    future: _dialoguesFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  'セリフデータを確認できないため、停止しました。\n'
                  'assets/dialogues/dialogues.json\n'
                  '${snapshot.error}\n${snapshot.stackTrace}',
                  key: const ValueKey('dialogue-load-error'),
                ),
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return _buildWithProgress();
    },
      );
    },
  );

  /// One fixed safe-area HUD for every page in the main navigation.
  /// The full-screen wallpaper remains continuous behind the header.
  Widget _pageWithSharedHeader(
    Progress progress,
    Widget page, {
    String backgroundAsset = 'assets/kotohogu/town_background.png',
  }) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: Image.asset(
          backgroundAsset,
          key: const ValueKey('shared-page-background'),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
      PinnedGachaHud(
        displayName: progress.playerName,
        points: progress.residents.availableKotohogi(progress.points),
        contentBuilder: (context, availableHeight) => page,
      ),
    ],
  );

  Widget _buildWithProgress() => ListenableBuilder(
    listenable: controller,
    builder: (context, child) {
      if (controller.failure case final failure?) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 44,
                        color: teal,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '記録を確認できないため、停止しました',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '読み込み・保存・日付の確認で問題が起きました。\n'
                        'ことほぎの加算と操作を停止しています。\n'
                        '以下の診断情報を確認し、原因を解消してからアプリを再起動してください。',
                      ),
                      const SizedBox(height: 24),
                      ExpansionTile(
                        title: const Text('診断情報'),
                        children: [
                          SelectableText(
                            failure.diagnostics,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final progress = controller.progress;
      if (progress == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _page == 0
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        GameHome(
                          key: ValueKey(_homeVisit),
                          progress: progress,
                          onMissions: () => _selectPage(1),
                          onTown: () => _selectPage(2),
                          onResident: _showDialogue,
                          debugTownResidents: _debugTownResidents,
                        ),
                        if (_tutorialReplay ||
                            (widget.enableTutorial &&
                                !progress.seenDialogues.contains(_tutorialSeenId)))
                          KotohogisuTutorial(
                            saving: _tutorialSaving,
                            onSkip: () => _endTutorial(openMissions: false),
                            onFinish: () => _endTutorial(openMissions: true),
                          ),
                      ],
                    )
                  : _page == 1
                  ? _pageWithSharedHeader(
                      progress,
                      MissionsScreen(
                        progress: progress,
                        busy: controller.busy,
                        onComplete: _complete,
                        period: _missionPeriod,
                        drawBackground: false,
                        onPeriodChanged: (period) =>
                            setState(() => _missionPeriod = period),
                      ),
                      backgroundAsset: MissionsScreen.backgroundAsset,
                    )
                  : _page == 2
                  ? PinnedGachaHud(
                      displayName: progress.playerName,
                      points: progress.residents.availableKotohogi(
                        progress.points,
                      ),
                      contentBehindHud: true,
                      contentBuilder: (context, availableHeight) => ColoredBox(
                        color: const Color(0xFFFFF3DC),
                        // Keep the scene alive while scrolling to the gacha
                        // panel: lazily disposing its transformed semantics
                        // during route pop can leave a detached semantics node.
                        child: SingleChildScrollView(
                          key: ValueKey('page-$_page'),
                          controller: _townScrollController,
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: _town(progress, availableHeight),
                          ),
                        ),
                      ),
                    )
                  : _page == 3
                  ? _pageWithSharedHeader(
                      progress,
                      Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('history-return-menu'),
                              onPressed: () => _selectPage(6),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('メニューにもどる'),
                            ),
                          ),
                          Expanded(
                            child: HistoryScreen(
                              progress: progress,
                              busy: controller.busy,
                              drawBackground: false,
                              onClear: () async {
                                await controller.clearHistory();
                              },
                            ),
                          ),
                        ],
                      ),
                      backgroundAsset: HistoryScreen.backgroundAsset,
                    )
                  : _page == 4
                  ? _pageWithSharedHeader(
                      progress,
                      DebugMenuScreen(
                        progress: progress,
                        selectedMission: _previewMission,
                        onMissionChanged: (mission) =>
                            setState(() => _previewMission = mission),
                        onPreview: _previewCelebration,
                        onReplayTutorial: _replayTutorial,
                        onResetAll: controller.resetAllMissionsForDebug,
                        onAddTickets: controller.grantTicketsForDebug,
                        onAdvanceOyasumi: controller.advanceOyasumiForDebug,
                        onResetOyasumi: controller.resetOyasumiForDebug,
                        debugTownResidents: _debugTownResidents,
                        onDebugTownEnabled: _setDebugTownEnabled,
                        onDebugTownResidentChanged: _setDebugTownResident,
                        showUnownedPreviewVisitors: _showUnownedPreviewVisitors,
                        onUnownedPreviewVisitorsChanged: widget.remoteContentLoader == null
                            ? null : _setUnownedPreviewVisitors,
                        salonUnlockMode: _salonUnlockMode,
                        onSalonUnlockModeChanged: _setSalonUnlockMode,
                        busy: controller.busy || _celebrating,
                        drawBackground: false,
                      ),
                    )
                  : _page == 5
                  ? _pageWithSharedHeader(
                      progress,
                      ListView(
                        key: const ValueKey('consultation-page'),
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        children: [
                          const Text(
                            '移住相談会',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ことほぎで相談会を開いて、まちに新しい仲間を迎えよう。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ink),
                          ),
                          const SizedBox(height: 20),
                          ResidentGacha(
                            controller: controller,
                            onTown: () => _selectPage(2),
                          ),
                        ],
                      ),
                      backgroundAsset: 'assets/kotohogu/village_background_001.png',
                    )
                  : _page == 6
                  ? _pageWithSharedHeader(
                      progress,
                      ListView(
                        key: const ValueKey('main-menu-page'),
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                            'メニュー',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Card(
                            child: ListTile(
                              key: const ValueKey('menu-change-name'),
                              leading: const Icon(Icons.edit_rounded),
                              title: const Text('名前を変える'),
                              subtitle: Text(progress.playerName),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: controller.busy ? null : _editPlayerName,
                            ),
                          ),
                          Card(
                            child: ListTile(
                              key: const ValueKey('menu-history'),
                              leading: uiPart('12_nav_history', width: 48, height: 48),
                              title: const Text('履歴'),
                              subtitle: const Text('これまでにできたことを振り返る'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _selectPage(3),
                            ),
                          ),
                          if (developerToolsAvailable && _developerMenuUnlocked)
                            Card(
                              child: ListTile(
                                key: const ValueKey('menu-debug'),
                                leading: const Icon(Icons.developer_mode),
                                title: const Text('開発メニュー'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _selectPage(4),
                              ),
                            ),
                        ],
                      ),
                    )
                  : throw StateError('Unexpected page: $_page'),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 80,
          // Keep labels for accessibility, but display just the icons.
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          selectedIndex: _selectedFooterIndex,
          onDestinationSelected: (index) {
            if (_tutorialSaving ||
                _tutorialReplay ||
                (widget.enableTutorial &&
                    !progress.seenDialogues.contains(_tutorialSeenId))) {
              return;
            }
            _onNavigationDestinationSelected(index);
          },
          destinations: [
            NavigationDestination(
              key: const ValueKey('footer-home'),
              icon: uiPart('09_nav_home', width: 54, height: 58),
              label: 'ホーム',
            ),
            NavigationDestination(
              key: const ValueKey('footer-missions'),
              icon: uiPart('10_nav_quest', width: 54, height: 58),
              label: 'セルフケア',
            ),
            NavigationDestination(
              key: const ValueKey('footer-consultation'),
              icon: uiPart('13_nav_gacya', width: 54, height: 58),
              label: '相談会',
            ),
            NavigationDestination(
              key: const ValueKey('footer-town'),
              icon: uiPart('11_nav_town', width: 54, height: 58),
              label: 'まち',
            ),
            NavigationDestination(
              key: const ValueKey('footer-menu'),
              icon: uiPart('21_nav_menu', width: 54, height: 58),
              label: 'メニュー',
            ),
          ],
        ),
      );
    },
  );


  void _reloadLocalResidents() {
    final loader = widget.remoteContentLoader;
    if (loader == null) return;
    setState(() {
      // Re-read Drive on refresh/resume. Never switch to packaged assets.
      _remoteContentFuture = loader();
    });
  }

  Future<void> _showLocalVisitor(
      HostedTownContent hosted, RemoteResident resident) async {
    // Debug preview only. Reading a remote line must never update ownership
    // or mark anything as seen in the user's saved dialogue history.
    final line = visitorGreeting(hosted.catalog, resident.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => RemoteVisitorConversationDialog(
        speaker: resident,
        dialogue: line,
        baseUri: hosted.baseUri,
      ),
    );
  }

  Widget _townWithLocalVisitors(Progress progress) {
    final future = _remoteContentFuture;
    if (future == null) return _townNavigator(progress, null);
    return FutureBuilder<HostedTownContent>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                '配信データの取得に失敗したため、まちの表示を停止しました。\n'
                '${snapshot.error}\n'
                '${snapshot.stackTrace}',
                key: const ValueKey('town-remote-content-error'),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _townNavigator(progress, snapshot.requireData);
      },
    );
  }

  Widget _townNavigator(
      Progress progress, HostedTownContent? hosted) {
    final rules = TownRules(
      progress, visit: _townVisit,
      oyasumi: _clubScene(progress), debugTownResidents: _debugTownResidents);
    final visitors = hosted == null
        ? const <RemoteResident>[]
        : localVisitorsForArea(
            hosted.catalog,
            _townArea,
            lifetimePoints: progress.points,
            visit: _townVisit,
            owned: progress.residents.owned,
            debugTownSelectionActive: _debugTownResidents != null,
            debugRemotePreviewEnabled: developerToolsAvailable && _showUnownedPreviewVisitors,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        TownAreaNavigator(
          sceneKey: _townSceneKey,
          area: _townArea,
          visit: _townVisit,
          onAreaChanged: (area) => setState(() => _townArea = area),
          lifetimePoints: progress.points,
          residents: progress.residents.owned,
          debugTownResidents: _debugTownResidents,
          afterOyasumiClub: progress.oyasumi.completed == 3,
          remoteVisitors: visitors,
          remoteContentBaseUri: hosted?.baseUri,
          onRemoteVisitor: hosted == null ||
                  !developerToolsAvailable || !_showUnownedPreviewVisitors
              ? null
              : (resident) => _showLocalVisitor(hosted, resident),
          salonUnlockMode: developerToolsAvailable
              ? _salonUnlockMode : SalonUnlockDebugMode.normal,
          onResident: _showDialogue,
          onBakeryResident: (resident) =>
              _showDialogue(resident, inBakery: true),
          onSalonResident: (resident) =>
              _showDialogue(resident, inSalon: true),
          onCommunityCenterResident: (resident) =>
              _showDialogue(resident, inCommunityCenter: true),
          marcheOpen: rules.marcheOpen,
          oyasumi: rules.oyasumi,
          onVisitMarche: _visitMarche,
        ),
        if (widget.remoteContentLoader != null)
          Positioned(
            right: 14,
            bottom: 18,
            child: FloatingActionButton.small(
              key: const ValueKey('town-remote-reload'),
              tooltip: 'Google Driveの配信先と住民を再読み込み',
              onPressed: _reloadLocalResidents,
              child: const Icon(Icons.sync),
            ),
          ),
      ],
    );
  }

  List<Widget> _town(Progress progress, double viewportHeight) => [
    SizedBox(
      key: const ValueKey('town-page-fullscreen'),
      height: viewportHeight,
      child: _townWithLocalVisitors(progress),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      child: Column(
        children: [
          Text(
            _townArea.description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          ResidentGacha(
            controller: controller,
            onTown: () {
              if (_townScrollController.hasClients) {
                _townScrollController.jumpTo(0);
              }
            },
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, color: teal),
              SizedBox(width: 6),
              Flexible(child: Text('住民をタップして、おしゃべりしよう。')),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'まちは、休んでもそのまま。\nまた来たい日に、会いにきてください。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF627875), height: 1.8),
          ),
          const SizedBox(height: 18),
          const Text(
            'ことほぎは社会貢献をイメージしたゲーム内の値です。\n'
            '実際の介護費削減額や個人の健康効果を示すものではありません。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF627875), height: 1.6),
          ),
        ],
      ),
    ),
  ];
}
