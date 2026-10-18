import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resident_collection.dart';
import 'marche.dart';
import 'local_content_preview.dart';
import 'town_walk.dart';
import 'town_areas.dart';

const townNames = ['穏やかなまち', '花のあるまち', '笑顔が集まるまち', 'にぎやかなまち'];
/// The tappable front-right house doorway in the 941x1672 village artwork.
/// Keep this rect in source-image coordinates, not screen coordinates.
const villageSalonDoor = Rect.fromLTWH(782, 728, 112, 132);

/// Tonko's 540x474 image in source coordinates of the 768x1376 plaza.
const plazaMarcheRect = Rect.fromLTWH(509, 663, 214, 188);

/// Fixed position immediately in front of the tea counter.
const plazaMarcheStaffRoute = TownWalkRoute(.61, .59, stay: true);

/// Scale by a resident's fixed walking slot, so vertical motion does not
/// cause the sprite to pop between sizes. Foot positions stay unchanged.
double _townResidentScale(double homeY) {
  if (homeY < .55) return 1.2; // Farther from the viewer.
  if (homeY < .72) return 1.4; // Middle of the scene.
  return 1.5; // Foreground.
}


const townDescriptions = [
  'いつものまちで、みんなが暮らしています。',
  '道ばたに、色とりどりの花が咲きました。',
  '公園に、笑顔の住民が集まってきました。',
  '小さな飾りが、まちの日常を彩っています。',
];

/// The owned residents wander gently around the illustrated plaza.
class TownScene extends StatefulWidget {
  const TownScene({
    super.key,
    required this.level,
    required this.residents,
    this.area = TownArea.plaza,
    this.visit,
    required this.lifetimePoints,
    this.debugTownResidents,
    this.onResident,
    this.remoteVisitors = const [],
    this.remoteContentBaseUri,
    this.onRemoteVisitor,
    this.onEnterSalon,
    this.showSalonEntranceMarker = false,
    this.marcheOpen = false,
    this.onVisitMarche,
    this.fillViewport = false,
  });

  final int level;
  final List<TownResident> residents;
  final TownArea area;
  /// Main navigation supplies its shared visit. A standalone scene owns one.
  final TownVisit? visit;
  /// Lifetime mission points, not the spendable kotohogi balance.
  final int lifetimePoints;
  /// A temporary debug-only cast; null uses the owned residents.
  final List<TownResident>? debugTownResidents;
  final Future<void> Function(TownResident)? onResident;
  final List<RemoteResident> remoteVisitors;
  final Uri? remoteContentBaseUri;
  final Future<void> Function(RemoteResident)? onRemoteVisitor;
  final VoidCallback? onEnterSalon;
  /// Show the salon entrance sign only when entry is currently permitted.
  final bool showSalonEntranceMarker;
  final bool marcheOpen;
  final VoidCallback? onVisitMarche;

  /// Fit the *selected area's* own source dimensions to the phone.
  /// Walkers and background share a transform, without image distortion.
  final bool fillViewport;

  @override
  State<TownScene> createState() => _TownSceneState();
}

class _TownSceneState extends State<TownScene> {
  late final _standaloneVisit = TownVisit();
  static const _frameDuration = Duration(milliseconds: 150);
  Timer? _ticker;
  int _ticks = 0;
  final _pauseStarted = <TownResident, int>{};
  final _pausedMillis = <TownResident, int>{};
  final _remotePauseStarted = <String, int>{};
  final _remotePausedMillis = <String, int>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (enabled && _ticker == null) {
      _ticker = Timer.periodic(_frameDuration, (_) {
        if (mounted) setState(() => _ticks++);
      });
    } else if (!enabled) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _elapsedMillis(TownResident resident) {
    final now = _ticks * _frameDuration.inMilliseconds;
    final pauseStart = _pauseStarted[resident];
    final currentPause = pauseStart == null ? 0 : now - pauseStart;
    return now - (_pausedMillis[resident] ?? 0) - currentPause;
  }

  Future<void> _talk(TownResident resident) async {
    final callback = widget.onResident;
    if (callback == null || _pauseStarted.containsKey(resident)) return;
    setState(() {
      _pauseStarted[resident] = _ticks * _frameDuration.inMilliseconds;
    });
    try {
      await callback(resident);
    } finally {
      if (mounted) {
        setState(() {
          final start = _pauseStarted.remove(resident)!;
          _pausedMillis[resident] = (_pausedMillis[resident] ?? 0) +
              _ticks * _frameDuration.inMilliseconds - start;
        });
      }
    }
  }

  Future<void> _talkToVisitor(RemoteResident resident) async {
    final callback = widget.onRemoteVisitor;
    if (callback == null || _remotePauseStarted.containsKey(resident.id)) return;
    setState(() {
      _remotePauseStarted[resident.id] = _ticks * _frameDuration.inMilliseconds;
    });
    try {
      await callback(resident);
    } finally {
      if (mounted) {
        setState(() {
          final started = _remotePauseStarted.remove(resident.id)!;
          _remotePausedMillis[resident.id] =
              (_remotePausedMillis[resident.id] ?? 0) +
              _ticks * _frameDuration.inMilliseconds - started;
        });
      }
    }
  }

  int _visitorElapsed(RemoteResident resident) {
    final now = _ticks * _frameDuration.inMilliseconds;
    final started = _remotePauseStarted[resident.id];
    final ongoingPause = started == null ? 0 : now - started;
    return now - (_remotePausedMillis[resident.id] ?? 0) - ongoingPause;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fillViewport) {
      final sourceWidth = widget.area.sourceWidth;
      final sourceHeight = widget.area.sourceHeight;
      if (sourceWidth == null || sourceHeight == null ||
          sourceWidth <= 0 || sourceHeight <= 0) {
        throw StateError('No source image dimensions for ${widget.area.id}');
      }
      // Canvas dimensions match this area's actual image. The background and
      // walking sprites scale/crop together at any device aspect ratio.
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: sourceWidth.toDouble(),
            height: sourceHeight.toDouble(),
            child: _scene(
              context, sourceWidth.toDouble(), sourceHeight.toDouble()),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 1.22,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _scene(context, constraints.maxWidth, constraints.maxHeight),
        ),
      ),
    );
  }

  Widget _scene(BuildContext context, double width, double height) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final visibleResidents = areaResidents(
      widget.residents,
      widget.area,
      lifetimePoints: widget.lifetimePoints,
      visit: widget.visit ?? _standaloneVisit,
      debugOverride: widget.debugTownResidents,
      marcheOpen: widget.marcheOpen,
    );
    if (widget.remoteVisitors.isNotEmpty && widget.remoteContentBaseUri == null) {
      throw StateError('Remote visitors require a local content base URI');
    }
    if (widget.remoteVisitors.map((r) => r.id).toSet().length !=
        widget.remoteVisitors.length) {
      throw StateError('Duplicate remote visitor IDs');
    }
    if (widget.remoteVisitors.any(
        (visitor) => visibleResidents.any((owned) => owned.id == visitor.id))) {
      throw StateError('A remote visitor duplicates an existing walker');
    }
    // Paint Tonko in front of the stall, not behind its transparent sprite.
    final shopkeeperIndex = widget.area == TownArea.plaza &&
            widget.marcheOpen && widget.debugTownResidents == null
        ? visibleResidents.indexOf(tonkoMarcheOwner)
        : -1;
    final count = visibleResidents.length + widget.remoteVisitors.length;
    final size = (width * (count <= townWalkSlots.length
        ? .14
        : math.min(.14, .64 / math.sqrt(count * 1.3).ceil())))
        .clamp(22.0, 76.0);
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            widget.area.backgroundAsset ??
                (throw StateError('Missing background for ${widget.area.id}')),
            key: const ValueKey('town-background'),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        // Total slots include visitors, but each collection must be indexed
        // using its own length. Otherwise two owned + one remote attempts to
        // read visibleResidents[2] and throws RangeError.
        for (var index = 0; index < visibleResidents.length; index++)
          if (index != shopkeeperIndex) _resident(
            visibleResidents[index],
            index,
            count,
            width,
            height,
            size,
            reduced,
          ),
        for (var index = 0; index < widget.remoteVisitors.length; index++)
          _visitor(
            widget.remoteVisitors[index],
            visibleResidents.length + index,
            count,
            width,
            height,
            size,
            reduced,
          ),
        if (widget.area == TownArea.plaza && widget.marcheOpen)
          Positioned(
            left: width * plazaMarcheRect.left / 768,
            top: height * plazaMarcheRect.top / 1376,
            width: width * plazaMarcheRect.width / 768,
            height: height * plazaMarcheRect.height / 1376,
            child: Semantics(
              button: widget.onVisitMarche != null,
              label: 'とんこの薬草茶房',
              child: Tooltip(
                message: 'とんこの薬草茶房',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('plaza-marche-entrance'),
                    onTap: widget.onVisitMarche,
                    child: Image.asset(
                      'assets/kotohogu/marche.png',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (shopkeeperIndex >= 0)
          _resident(
            visibleResidents[shopkeeperIndex],
            shopkeeperIndex,
            count,
            width,
            height,
            size,
            reduced,
          ),
        if (widget.area == TownArea.village &&
            widget.showSalonEntranceMarker && widget.onEnterSalon != null)
          Positioned(
            // Source-image coordinates, just above and left of the blue
            // doorway; both the sign and its tap area follow BoxFit.cover.
            left: width * 635 / 941,
            top: height * 635 / 1672,
            width: width * 245 / 941,
            height: height * 84 / 1672,
            child: Semantics(
              button: true,
              label: '桜の美容室の入口はこちら',
              child: Tooltip(
                message: '桜の美容室に入る',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('village-salon-open-marker'),
                    onTap: widget.onEnterSalon,
                    borderRadius: BorderRadius.circular(18),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E8),
                          border: Border.all(
                            color: const Color(0xFFBB6887), width: 3),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55703E38),
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.content_cut,
                                    size: 24, color: Color(0xFFAC5377)),
                                SizedBox(width: 5),
                                Text(
                                  '桜の美容室',
                                  style: TextStyle(
                                    color: Color(0xFF773B52),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '入口はこちら ↘',
                              style: TextStyle(
                                color: Color(0xFF773B52),
                                fontWeight: FontWeight.w700,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.area == TownArea.village && widget.onEnterSalon != null)
          Positioned(
            left: width * villageSalonDoor.left / 941,
            top: height * villageSalonDoor.top / 1672,
            width: width * villageSalonDoor.width / 941,
            height: height * villageSalonDoor.height / 1672,
            child: Semantics(
              button: true,
              label: '桜の美容室に入る',
              child: Tooltip(
                message: '桜の美容室',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('village-salon-entrance'),
                    onTap: widget.onEnterSalon,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _resident(
    TownResident resident,
    int index,
    int totalSlots,
    double width,
    double height,
    double size,
    bool reduced,
  ) {
    final isShopkeeper = widget.area == TownArea.plaza &&
        widget.marcheOpen && widget.debugTownResidents == null &&
        resident == tonkoMarcheOwner;
    final route = isShopkeeper
        ? plazaMarcheStaffRoute
        : widget.area == TownArea.park
            ? parkWalkRoute(resident.id, index, totalSlots: totalSlots)
            : null;
    final origin = route == null
        ? townWalkOrigin(index, totalSlots: totalSlots)
        : (route.x, route.y);
    final pose = reduced
        ? TownWalkPose(
            x: origin.$1,
            y: origin.$2,
            direction: null,
            frame: 0,
          )
        : townWalkPose(
            index,
            Duration(milliseconds: _elapsedMillis(resident)),
            totalSlots: totalSlots,
            route: route,
          );
    final direction = pose.direction;
    final walking = direction != null &&
        !_pauseStarted.containsKey(resident) && !reduced;
    // Occasionally step in place; the foot anchor never moves.
    final stepping = isShopkeeper && !reduced &&
        !_pauseStarted.containsKey(resident) && _ticks % 56 < 12;
    final asset = stepping
        ? resident.walkAsset(WalkDirection.front, (_ticks ~/ 3) % 4)
        : walking
            ? resident.walkAsset(direction, pose.frame)
            : resident.idleAsset;
    // Keep the original bottom-center of the walking sprite as its foot
    // anchor while increasing visual size and its matching tap target.
    final scaledSize = size * _townResidentScale(origin.$2);
    final footX = width * pose.x + size / 2;
    final footY = height * pose.y + size;
    final sprite = Image.asset(
      asset,
      key: isShopkeeper
          ? const ValueKey('marche-shopkeeper-sprite')
          : ValueKey('resident-sprite-$index'),
      width: scaledSize,
      height: scaledSize,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    return Positioned(
      left: footX - scaledSize / 2,
      top: footY - scaledSize,
      child: Semantics(
        button: isShopkeeper
            ? widget.onVisitMarche != null
            : widget.onResident != null,
        label: isShopkeeper
            ? 'とんこの薬草茶房でおはなし'
            : '${resident.label}のおはなし',
        child: Tooltip(
          message: isShopkeeper ? 'とんこ（店番中）' : resident.label,
          child: InkWell(
            key: isShopkeeper
                ? const ValueKey('marche-shopkeeper')
                : ValueKey('resident-$index'),
            borderRadius: BorderRadius.circular(20),
            onTap: isShopkeeper
                ? widget.onVisitMarche
                : widget.onResident == null ? null : () => _talk(resident),
            child: walking && resident.mirrorWalk(direction)
                ? Transform.flip(flipX: true, child: sprite)
                : sprite,
          ),
        ),
      ),
    );
  }
  Widget _visitor(
    RemoteResident resident,
    int index,
    int totalSlots,
    double width,
    double height,
    double size,
    bool reduced,
  ) {
    final baseUri = widget.remoteContentBaseUri;
    if (baseUri == null) {
      throw StateError('Missing remote sprite base URI for ${resident.id}');
    }
    final parkRoute = widget.area == TownArea.park
        ? parkWalkRoute(resident.id, index, totalSlots: totalSlots)
        : null;
    final origin = parkRoute == null
        ? townWalkOrigin(index, totalSlots: totalSlots)
        : (parkRoute.x, parkRoute.y);
    final pose = reduced
        ? TownWalkPose(x: origin.$1, y: origin.$2, direction: null, frame: 0)
        : townWalkPose(
            index,
            Duration(milliseconds: _visitorElapsed(resident)),
            totalSlots: totalSlots,
            route: parkRoute,
          );
    final walking = pose.direction != null &&
        !_remotePauseStarted.containsKey(resident.id) && !reduced;
    final filename = walking
        ? 'walk_${pose.direction!.name}_0${pose.frame + 1}.png'
        : 'idle_front_01.png';
    final uri = remoteSpriteUri(baseUri, resident, filename);
    final scale = size * _townResidentScale(origin.$2);
    final footX = width * pose.x + size / 2;
    final footY = height * pose.y + size;
    final sprite = Image.network(
      uri.toString(),
      key: ValueKey('remote-visitor-sprite-${resident.id}'),
      width: scale,
      height: scale,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: scale,
        height: scale,
        child: Tooltip(
          message: 'スプライト取得エラー $uri: $error',
          child: const Icon(Icons.broken_image_outlined, color: Colors.red),
        ),
      ),
    );
    return Positioned(
      left: footX - scale / 2,
      top: footY - scale,
      child: Semantics(
        button: widget.onRemoteVisitor != null,
        label: '配信テスト・${resident.label}のおはなし',
        child: Tooltip(
          message: '配信テスト: ${resident.label}',
          child: InkWell(
            key: ValueKey('remote-visitor-${resident.id}'),
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onRemoteVisitor == null
                ? null : () => _talkToVisitor(resident),
            child: sprite,
          ),
        ),
      ),
    );
  }

}
