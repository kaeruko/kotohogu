import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resident_collection.dart';
import 'google_drive_content_source.dart';
import 'local_content_preview.dart';

/// Shared design coordinates for the 1080 x 1920 consultation artwork.
/// The background, platform, and arrival effects all use the same cover scale.
abstract final class ConsultationComposition {
  static const double width = 1080;
  static const double height = 1920;

  // The separately exported stage is intentionally lower than the old
  // background's baked-in stage, filling the empty lower half.
  static const Rect stage = Rect.fromLTWH(90, 1240, 900, 252);
  static const Rect resident = Rect.fromLTWH(330, 975, 420, 385);
  static const Rect glow = Rect.fromLTWH(160, 900, 760, 570);
  // Leave clear space above the arriving resident's head. Keep the source
  // banner's size and artwork unchanged; only shift its design-space y.
  static const Rect banner = Rect.fromLTWH(100, 440, 880, 450);

  /// Maps design-space coordinates onto a BoxFit.cover stage.
  static Widget cover(Widget child) => ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    ),
  );
}

/// Residents queue directly in front of the consultation booths.
///
/// The background is 1080 x 1920. Rendering the sprites on the *same*
/// design-sized canvas keeps them aligned even when BoxFit.cover crops a phone
/// with a taller or wider aspect ratio.
class ConsultationBackground extends StatefulWidget {
  const ConsultationBackground({super.key});

  @override
  State<ConsultationBackground> createState() =>
      _ConsultationBackgroundState();
}

class _ConsultationBackgroundState extends State<ConsultationBackground> {
  Timer? _ticker;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 170), (_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => _step = (_step + 1) % 16);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConsultationComposition.cover(
    Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/gacya/bg.png',
            key: const ValueKey('gacha-shrine-bg'),
            fit: BoxFit.fill,
            excludeFromSemantics: true,
          ),
        ),
        // The stage is now an independent transparent PNG, drawn on both
        // the waiting screen and the arrival screen.
        Positioned.fromRect(
          rect: ConsultationComposition.stage,
          child: Image.asset(
            'assets/gacya/stage.png',
            key: const ValueKey('consultation-stage'),
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
        for (var slot = 0; slot < 4; slot++) _walkingResident(slot),
      ],
    ),
  );

  Widget _walkingResident(int slot) {
    const characters = [
      TownResident.rabbit,
      TownResident.penguin,
      TownResident.cat,
      TownResident.squirrel,
    ];
    // Left-hand booth queues, intentionally above and left of the blue stage.
    // The later slots stand slightly farther away from the counters.
    const positions = <(double, double)>[
      (70, 750),
      (190, 810),
      (315, 755),
      (430, 820),
    ];
    final resident = characters[slot];
    final step = _step + slot * 2;
    final frame = step % 4;
    final progress = ((step % 16) / 16) * math.pi * 2;
    final position = positions[slot];
    return Positioned(
      key: ValueKey('consultation-walker-$slot'),
      left: position.$1 + math.sin(progress) * 9,
      top: position.$2 + math.cos(progress) * 5,
      width: 220,
      height: 220,
      child: Image.asset(
        resident.walkAsset(WalkDirection.back, frame),
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Displays the already-owned residents without creating a second gacha economy.
void showResidentCollection(BuildContext context, ResidentCollection owned,
    {HostedTownContent? hosted}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFFF2D9),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '住民一覧',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: Color(0xFF522A19),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: (MediaQuery.sizeOf(sheetContext).height * .42)
                  .clamp(130.0, 370.0),
              child: SingleChildScrollView(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 16,
                  children: [
                    for (final resident in owned.owned)
                      SizedBox(
                        width: 90,
                        child: Column(
                          children: [
                            TownResidentAvatar(resident: resident, size: 76),
                            Text(resident.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('累計${owned.counts[resident.id]}回',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    if (hosted != null)
                      for (final id in owned.remotelyOwnedIds)
                        SizedBox(
                          width: 90,
                          child: Column(
                            children: [
                              RemoteResidentAvatar(
                                resident: hosted.catalog.residentById(id),
                                baseUri: hosted.baseUri, size: 76,
                              ),
                              Text(hosted.catalog.residentById(id).label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('累計${owned.counts[id]}回',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The new art already contains its label and ornamentation.
class ConsultationArtButton extends StatelessWidget {
  const ConsultationArtButton({
    super.key,
    required this.asset,
    required this.label,
    required this.onPressed,
    required this.buttonKey,
  });

  final String asset;
  final String label;
  final VoidCallback? onPressed;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: Tooltip(
      message: label,
      child: TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Opacity(
          opacity: onPressed == null ? .45 : 1,
          child: Image.asset(
            asset,
            width: double.infinity,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}

/// Bottom buttons match the artwork's left/right slots on 1080px layouts.
class ConsultationActions extends StatelessWidget {
  const ConsultationActions({
    super.key,
    required this.onResidents,
    required this.onAgain,
    required this.againLabel,
    this.againKey = const ValueKey('button_again'),
  });

  final VoidCallback onResidents;
  final VoidCallback? onAgain;
  final String againLabel;
  final Key againKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        Expanded(
          child: ConsultationArtButton(
            asset: 'assets/gacya/resident_list_button.png',
            label: '住民一覧',
            buttonKey: const ValueKey('resident-list-button'),
            onPressed: onResidents,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ConsultationArtButton(
            asset: 'assets/gacya/button.png',
            label: againLabel,
            buttonKey: againKey,
            onPressed: onAgain,
          ),
        ),
      ],
    ),
  );
}

/// A consistent bottom navigation action for the consultation hall and
/// resident reveal. Uses the supplied art rather than the default arrow icon.
class ConsultationTownBackButton extends StatelessWidget {
  const ConsultationTownBackButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 164,
    height: 58,
    child: ConsultationArtButton(
      asset: 'assets/gacya/back.png',
      label: 'まちへ',
      buttonKey: const ValueKey('consultation-town-back'),
      onPressed: onPressed,
    ),
  );
}
