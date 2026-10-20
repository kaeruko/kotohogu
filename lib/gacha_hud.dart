import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_skin.dart';
import 'progress.dart' show defaultPlayerName;
import 'resident_collection.dart';

/// Compact, responsive game HUD. The player's saved name appears in all
/// screens, using the existing decorative nameplate.
class GachaHud extends StatelessWidget {
  const GachaHud({
    super.key,
    required this.points,
    this.displayName = defaultPlayerName,
  });

  final int points;
  final String displayName;

  // Share available HUD width so currency values remain legible on phones.
  static const double nameplateShare = .38;
  static const double balanceShare = 1 - nameplateShare;
  static const double horizontalGap = 6;
  /// Slightly smaller currency frame; the player nameplate keeps its size.
  static const double kotohogiBarScale = .88;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Never ask KotohogiBar to lay out with a zero/unbounded width.
      // A positioned HUD supplies a finite, explicit width below.
      if (!width.isFinite || width <= 6) {
        return const SizedBox.shrink();
      }
      final leftWidth = (width - horizontalGap) * nameplateShare;
      final rightWidth = (width - horizontalGap) * balanceShare;
      return SizedBox(
        width: width,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftWidth,
              child: PlayerNameplate(displayName: displayName),
            ),
            const SizedBox(width: horizontalGap),
            SizedBox(
              width: rightWidth,
              child: Align(
                alignment: Alignment.topRight,
                child: FractionallySizedBox(
                  widthFactor: kotohogiBarScale,
                  child: KotohogiBar(points: points),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The same decorative player nameplate is used in home and gacha.
class PlayerNameplate extends StatelessWidget {
  const PlayerNameplate({
    super.key,
    this.displayName = defaultPlayerName,
  });

  final String displayName;

  @override
  Widget build(BuildContext context) => AspectRatio(
          aspectRatio: 788 / 209,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/kotohogi_hud/player_nameplate.png',
                  key: const ValueKey('gacha-player-nameplate'),
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
                Positioned(
                  left: c.maxWidth * .028,
                  top: c.maxHeight * .055,
                  width: c.maxHeight * .85,
                  height: c.maxHeight * .85,
                  child: ClipOval(
                    child: Image.asset(
                      TownResident.shiba.idleAsset,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                // One-line name only; keep text centered in the nameplate
                // with generous breathing room beside the avatar.
                Positioned(
                  left: c.maxWidth * .30,
                  right: c.maxWidth * .055,
                  top: c.maxHeight * .25,
                  bottom: c.maxHeight * .25,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      displayName,
                      key: const ValueKey('player-display-name'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: const Color(0xFFFFEFCD),
                        fontWeight: FontWeight.w900,
                        fontSize: c.maxHeight * .36,
                        height: 1.05,
                        shadows: const [
                          Shadow(
                            color: Color(0xFF3F1D16),
                            blurRadius: 2,
                            offset: Offset(0, 1),
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

/// A fixed HUD at the same safe-area position across home, town, shrine,
/// and result screens. Only the content underneath it is scrollable.
/// The builder gets the actual remaining height (after the HUD).
class PinnedGachaHud extends StatelessWidget {
  const PinnedGachaHud({
    super.key,
    required this.points,
    required this.contentBuilder,
    this.displayName = defaultPlayerName,
    this.contentBehindHud = false,
  });

  final int points;
  final String displayName;
  final Widget Function(BuildContext, double) contentBuilder;

  /// Allow a full-bleed scene to paint behind the pinned HUD.
  /// The default retains the usual reserved top spacing for other pages.
  final bool contentBehindHud;

  static const double edge = 12;
  static const double top = 12;
  static const double bottomGap = 10;
  static const double maxHudWidth = 570;

  /// Vertical space covered by the decorative HUD, based on its rendered size.
  /// Full-bleed pages use this same measurement to position their controls
  /// underneath the artwork rather than relying on a fixed offset.
  static double reservedHeightForWidth(double viewportWidth) {
    final width =
        math.min(maxHudWidth, math.max(0.0, viewportWidth - edge * 2));
    if (width <= 6) return top + bottomGap;
    final leftWidth =
        (width - GachaHud.horizontalGap) * GachaHud.nameplateShare;
    final rightWidth =
        (width - GachaHud.horizontalGap) * GachaHud.balanceShare;
    final leftHeight = leftWidth * 209 / 788;
    final rightHeight =
        rightWidth * GachaHud.kotohogiBarScale * 314 / 982;
    return top + math.max(leftHeight, rightHeight) + bottomGap;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width =
          math.min(maxHudWidth, math.max(0.0, constraints.maxWidth - edge * 2));
      final reservedHeight = reservedHeightForWidth(constraints.maxWidth);
      final remainingHeight = math.max(0.0, constraints.maxHeight - reservedHeight);
      // When nested in Center > ConstrainedBox > Stack, the parent can
      // provide loose constraints. A Stack with only Positioned children
      // otherwise sizes itself to 0x0, breaking both the points bar and
      // the home screen's responsive action button widths.
      return Stack(
        children: [
          const SizedBox.expand(),
          Positioned.fill(
            top: contentBehindHud ? 0 : reservedHeight,
            child: contentBuilder(
              context,
              contentBehindHud ? constraints.maxHeight : remainingHeight,
            ),
          ),
          if (width > 6)
            Positioned(
              left: edge,
              right: edge,
              top: top,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: GachaHud(
                    points: points,
                    displayName: displayName,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// The identical header on modal consultation and reveal routes.
/// Ignoring taps prevents this decorative overlay from blocking scene actions.
class GameHeaderOverlay extends StatelessWidget {
  const GameHeaderOverlay({super.key, required this.points, this.displayName = defaultPlayerName});

  final int points;
  final String displayName;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: IgnorePointer(
      child: PinnedGachaHud(
        points: points,
        displayName: displayName,
        contentBehindHud: true,
        contentBuilder: (context, availableHeight) => const SizedBox.expand(),
      ),
    ),
  );
}
