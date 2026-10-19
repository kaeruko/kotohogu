import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dev_tools.dart';
import 'gacha_hud.dart';
import 'resident_collection.dart';
import 'local_content_preview.dart';
import 'salon_room.dart';
import 'bakery_room.dart';
import 'town.dart';
import 'town_areas.dart';

/// Swipe or use arrows to move between independent town neighborhoods.
class TownAreaNavigator extends StatefulWidget {
  const TownAreaNavigator({
    super.key,
    required this.area,
    this.visit,
    this.sceneKey,
    required this.onAreaChanged,
    required this.level,
    required this.lifetimePoints,
    required this.residents,
    this.debugTownResidents,
    this.remoteVisitors = const [],
    this.remoteContentBaseUri,
    this.onRemoteVisitor,
    this.salonUnlockMode = SalonUnlockDebugMode.normal,
    this.onResident,
    this.onSalonResident,
    this.onBakeryResident,
    this.marcheOpen = false,
    this.onVisitMarche,
  });

  final TownArea area;
  /// Shared across area changes and with town conversation conditions.
  final TownVisit? visit;
  /// Preserve the painted scene and its semantics when the long town page scrolls.
  final GlobalKey? sceneKey;
  final ValueChanged<TownArea> onAreaChanged;
  final int level;
  final int lifetimePoints;
  final List<TownResident> residents;
  final List<TownResident>? debugTownResidents;
  final List<RemoteResident> remoteVisitors;
  final Uri? remoteContentBaseUri;
  final Future<void> Function(RemoteResident)? onRemoteVisitor;
  final SalonUnlockDebugMode salonUnlockMode;
  final Future<void> Function(TownResident)? onResident;
  final Future<void> Function(TownResident)? onSalonResident;
  final Future<void> Function(TownResident)? onBakeryResident;
  final bool marcheOpen;
  final VoidCallback? onVisitMarche;

  @override
  State<TownAreaNavigator> createState() => _TownAreaNavigatorState();
}

class _TownAreaNavigatorState extends State<TownAreaNavigator> {
  late final _standaloneVisit = TownVisit();
  TownVisit get _visit => widget.visit ?? _standaloneVisit;
  int? _activePointer;
  Offset? _swipeStart;

  /// Only unlocked neighborhoods are navigable in normal play. Debug town
  /// previews and the salon facility test may temporarily explore all areas.
  bool _canVisit(TownArea area) =>
      area.isUnlocked(widget.lifetimePoints) ||
      widget.debugTownResidents != null ||
      (developerToolsAvailable &&
          widget.salonUnlockMode != SalonUnlockDebugMode.normal);

  void _move(int direction) {
    final next = widget.area.index + direction;
    if (next < 0 || next >= TownArea.values.length) return;
    final destination = TownArea.values[next];
    if (!_canVisit(destination)) return; // Also protects horizontal swipes.
    widget.onAreaChanged(destination);
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    final debugPreview = widget.debugTownResidents != null;
    final unlocked = area.isUnlocked(widget.lifetimePoints);
    // Facility debug modes also allow traversing intermediate neighborhoods.
    final salonOverride = developerToolsAvailable &&
        widget.salonUnlockMode != SalonUnlockDebugMode.normal;
    final accessible = _canVisit(area);
    final canGoPrevious =
        area.index > 0 && _canVisit(TownArea.values[area.index - 1]);
    final canGoNext = area.index < TownArea.values.length - 1 &&
        _canVisit(TownArea.values[area.index + 1]);
    final showNavigation = canGoPrevious || canGoNext;
    final unlockedAreas = unlockedTownAreas(widget.lifetimePoints);
    final unlockedIndex = unlockedAreas.indexOf(area);
    // Locked areas reached by debug navigation are deliberately not counted.
    final areaCounter = unlockedIndex < 0
        ? '未開放'
        : '${unlockedIndex + 1} / ${unlockedAreas.length}';
    // The shopping-street lantern strings leave a central opening for a sign.
    // Keep the conventional heading when the area is still locked.
    final hangingShoppingSign =
        area == TownArea.shopping && accessible && area.backgroundAsset != null;
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
      behavior: HitTestBehavior.translucent,
      // A passive pointer listener keeps taps and semantics with the resident
      // buttons and avoids an extra competing horizontal drag recognizer.
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _swipeStart = event.position;
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _swipeStart = null;
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        final start = _swipeStart;
        _activePointer = null;
        _swipeStart = null;
        if (start == null) return;
        final distance = event.position - start;
        if (distance.dx.abs() < 65 ||
            distance.dx.abs() <= distance.dy.abs() * 1.3) {
          return;
        }
        _move(distance.dx < 0 ? 1 : -1);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (accessible && area.backgroundAsset != null)
            TownScene(
              key: widget.sceneKey,
              level: widget.level,
              area: area,
              visit: _visit,
              lifetimePoints: widget.lifetimePoints,
              residents: widget.residents,
              debugTownResidents: widget.debugTownResidents,
              remoteVisitors: widget.remoteVisitors,
              remoteContentBaseUri: widget.remoteContentBaseUri,
              onRemoteVisitor: widget.onRemoteVisitor,
              onResident: widget.onResident,
              marcheOpen: widget.marcheOpen,
              onVisitMarche: widget.onVisitMarche,
              showBakeryEntranceMarker: isBakeryUnlocked(widget.residents),
              onEnterBakery: () {
                if (!isBakeryUnlocked(widget.residents)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(
                      'パティシエをガチャでお迎えすると、洋菓子店に入れるよ')),
                  );
                  return;
                }
                Navigator.of(context).push<void>(MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/shopping/bakery'),
                  builder: (_) => BakeryRoom(onResident: widget.onBakeryResident),
                ));
              },
              showSalonEntranceMarker: isSalonAccessible(
                widget.residents,
                debugMode: widget.salonUnlockMode,
              ),
              onEnterSalon: () {
                if (!isSalonAccessible(
                  widget.residents,
                  debugMode: widget.salonUnlockMode,
                )) {
                  final forcedClosed = developerToolsAvailable &&
                      widget.salonUnlockMode ==
                          SalonUnlockDebugMode.forceClosed;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(forcedClosed
                          ? 'デバッグ設定で桜の美容室を未開放にしています'
                          : 'つやこさんをガチャでお迎えすると、桜の美容室が開放されるよ'),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/village/salon'),
                    builder: (_) => SalonRoom(
                      ownedResidents: widget.residents,
                      previewUnownedResidents: developerToolsAvailable &&
                          widget.salonUnlockMode == SalonUnlockDebugMode.forceOpen,
                      onResident: widget.onSalonResident,
                    ),
                  ),
                );
              },
              fillViewport: true,
            )
          else
            _AreaPreparation(
              area: area,
              unlocked: unlocked,
              debugPreview: debugPreview || salonOverride,
              lifetimePoints: widget.lifetimePoints,
              residents: areaResidents(
                widget.residents,
                area,
                lifetimePoints: widget.lifetimePoints,
                visit: _visit,
                debugOverride: widget.debugTownResidents,
              ),
              onResident: widget.onResident,
            ),
          if (showNavigation)
            Positioned(
            // The pinned currency HUD grows on wide screens (e.g. iPads).
            // Keep the area name and page counter fully below that artwork.
            top: math.max(
              92.0,
              PinnedGachaHud.reservedHeightForWidth(constraints.maxWidth) + 12,
            ),
            left: 12,
            right: 12,
            child: Row(
              children: [
                if (canGoPrevious)
                  IconButton.filledTonal(
                    key: const ValueKey('town-area-previous'),
                    tooltip: '前のエリア',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: hangingShoppingSign
                      ? Center(
                          child: Text(
                            areaCounter,
                            style: const TextStyle(
                              color: Color(0xFF63351F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xEEFFF5DB),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          area.label,
                          key: const ValueKey('town-area-name'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF63351F),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          areaCounter,
                          style: const TextStyle(
                            color: Color(0xFF87664A), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canGoNext)
                  IconButton.filledTonal(
                    key: const ValueKey('town-area-next'),
                    tooltip: '次のエリア',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
          if (hangingShoppingSign)
            Positioned(
              // Keep the sign above the distant shrine roof, rather than
              // halfway down the street scene on tablets. On narrow phones,
              // clear the navigation row and its page counter as well.
              top: math.max(
                constraints.maxWidth * .23,
                math.max(
                  92.0,
                  PinnedGachaHud.reservedHeightForWidth(constraints.maxWidth) + 12,
                ) + 56,
              ),
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  key: const ValueKey('town-area-hanging-sign'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBCD),
                    border: Border.all(
                      color: const Color(0xFF9B503C), width: 2),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44804C32),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    area.label,
                    key: const ValueKey('town-area-name'),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF63351F),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                key: const ValueKey('town-page-title-panel'),
                decoration: BoxDecoration(
                  color: const Color(0xEEFFF6DC),
                  border: Border.all(color: const Color(0xFFD4A64E), width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (area == TownArea.plaza) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF277A70),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'LEVEL ${widget.level}',
                          style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        area == TownArea.plaza
                            ? townNames[widget.level] : area.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFF63351F),
                          fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Unfinished background art stays explicit; residents can still chat in
/// unlocked areas, while a locked area reveals neither its roster nor chats.
class _AreaPreparation extends StatelessWidget {
  const _AreaPreparation({
    required this.area,
    required this.unlocked,
    required this.debugPreview,
    required this.lifetimePoints,
    required this.residents,
    required this.onResident,
  });

  final TownArea area;
  final bool unlocked;
  final bool debugPreview;
  final int lifetimePoints;
  final List<TownResident> residents;
  final Future<void> Function(TownResident)? onResident;

  @override
  Widget build(BuildContext context) {
    final accessible = unlocked || debugPreview;
    return ColoredBox(
      color: const Color(0xFFFFF1DE),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 172, 24, 84),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                accessible ? Icons.home_work_outlined : Icons.lock_outline,
                size: 56, color: const Color(0xFF906B55)),
              const SizedBox(height: 14),
              Text(
                accessible ? '景色を準備中だよ' : 'まだ行けないエリアだよ',
                key: const ValueKey('town-area-status'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF63351F),
                  fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                accessible ? area.description
                    : '累計${area.unlockAt}ことほぎで開放\n'
                      'あと${area.unlockAt - lifetimePoints}ことほぎ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6E5B4A), height: 1.7),
              ),
              if (debugPreview && !unlocked) ...[
                const SizedBox(height: 6),
                const Text('デバッグ用プレビュー',
                    style: TextStyle(fontSize: 12)),
              ],
              if (accessible) ...[
                const SizedBox(height: 22),
                if (residents.isEmpty)
                  const Text('住民が引っ越してくるのを待っているよ。')
                else ...[
                  const Text('このエリアの住民',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final resident in residents)
                        Semantics(
                          button: onResident != null,
                          label: '${resident.label}のおはなし',
                          child: InkWell(
                            key: ValueKey('area-resident-${resident.id}'),
                            onTap: onResident == null ? null
                                : () => onResident!(resident),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 88,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF9EA),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE7CBA0)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    resident.idleAsset,
                                    width: 58, height: 58,
                                    excludeFromSemantics: true),
                                  Text(
                                    resident.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
