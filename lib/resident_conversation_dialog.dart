import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dialogue_engine.dart';
import 'resident_collection.dart';

/// Splits long dialogue using its measured layout, not a character limit.
/// Prefer sentence/paragraph boundaries without changing the CMS source text.
List<String> paginateResidentDialogue(
  String text, {
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required double maxWidth,
  int maxLines = 5,
}) {
  if (text.isEmpty) return const [''];
  final remaining = text.runes.map(String.fromCharCode).toList();
  final pages = <String>[];

  bool fits(int count) {
    final painter = TextPainter(
      text: TextSpan(text: remaining.take(count).join(), style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final result = !painter.didExceedMaxLines;
    painter.dispose();
    return result;
  }

  while (remaining.isNotEmpty) {
    if (fits(remaining.length)) {
      pages.add(remaining.join());
      break;
    }

    // Find the longest prefix that truly fits at this screen width/text scale.
    var lower = 1;
    var upper = remaining.length;
    while (lower < upper) {
      final middle = (lower + upper + 1) ~/ 2;
      if (fits(middle)) {
        lower = middle;
      } else {
        upper = middle - 1;
      }
    }
    final fittingLength = lower;
    var cut = fittingLength;

    // Prefer finishing a sentence in the latter half of a page.
    final earliest = math.max(1, (fittingLength * 0.55).floor());
    for (var i = fittingLength - 1; i >= earliest - 1; i--) {
      if ('。！？!?…\n'.contains(remaining[i])) {
        cut = i + 1;
        while (cut < fittingLength && '」』）'.contains(remaining[cut])) {
          cut++;
        }
        break;
      }
    }

    pages.add(remaining.take(cut).join());
    remaining.removeRange(0, cut);
  }

  return pages;
}

/// Shows one readable page at a time, across both dialogue and reply.
/// Page advances never select a new line or modify saved progress.
class ResidentConversationDialog extends StatefulWidget {
  const ResidentConversationDialog({
    super.key,
    required this.speaker,
    required this.dialogue,
  });

  final TownResident speaker;
  final DialogueEntry dialogue;

  @override
  State<ResidentConversationDialog> createState() =>
      _ResidentConversationDialogState();
}

class _ResidentConversationDialogState
    extends State<ResidentConversationDialog> {
  int _turnIndex = 0;
  int _pageIndex = 0;

  void _advance({required int turnCount, required int pageCount}) {
    if (_pageIndex + 1 < pageCount) {
      setState(() => _pageIndex++);
    } else if (_turnIndex + 1 < turnCount) {
      setState(() {
        _turnIndex++;
        _pageIndex = 0;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void didUpdateWidget(covariant ResidentConversationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialogue.id != widget.dialogue.id ||
        oldWidget.speaker != widget.speaker) {
      _turnIndex = 0;
      _pageIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.dialogue.reply;
    final turns = [
      (speaker: widget.speaker, text: widget.dialogue.text),
      if (reply != null)
        (speaker: TownResident.fromId(reply.residentId), text: reply.text),
    ];
    final turn = turns[_turnIndex];

    final screen = MediaQuery.of(context);
    final scaler = screen.textScaler;
    final direction = Directionality.of(context);
    final availableHeight =
        screen.size.height - screen.padding.vertical - screen.viewInsets.bottom;
    final bodyHeight = math.min(290.0, math.max(120.0, availableHeight - 218));
    final textWidth = math.max(100.0, math.min(390.0, screen.size.width - 88));
    final bodyStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 20,
          height: 1.55,
        );
    final lineHeight = scaler.scale(20) * 1.55;
    final pageLines = math.max(
      1,
      math.min(5, ((bodyHeight - 36) / lineHeight).floor()),
    );
    final pages = paginateResidentDialogue(
      turn.text,
      style: bodyStyle,
      textDirection: direction,
      textScaler: scaler,
      maxWidth: textWidth,
      maxLines: pageLines,
    );
    final currentPage = math.min(_pageIndex, pages.length - 1);
    final isLast = currentPage == pages.length - 1 &&
        _turnIndex == turns.length - 1;

    // Keep tapping the dialogue itself as an alternate way to advance.
    return GestureDetector(
      onTap: () => _advance(turnCount: turns.length, pageCount: pages.length),
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 18, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: Row(
          children: [
            TownResidentAvatar(resident: turn.speaker, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                turn.speaker.label,
                style: const TextStyle(fontSize: 21),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: textWidth,
          height: bodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  // Scroll only as a safety net for extreme accessibility fonts.
                  child: Text(
                    pages[currentPage],
                    key: const ValueKey('dialogue-visible-line'),
                    style: bodyStyle,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (turns.length > 1)
                    Text(
                      '${_turnIndex + 1} / ${turns.length}',
                      key: const ValueKey('dialogue-turn-count'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (turns.length > 1 && pages.length > 1)
                    const SizedBox(width: 16),
                  if (pages.length > 1)
                    Text(
                      '${currentPage + 1} / ${pages.length} ページ',
                      key: const ValueKey('dialogue-page-count'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('dialogue-next-button'),
            style: TextButton.styleFrom(
              minimumSize: const Size(104, 52),
              textStyle: const TextStyle(fontSize: 18),
            ),
            onPressed: () =>
                _advance(turnCount: turns.length, pageCount: pages.length),
            child: Text(isLast ? 'また話そう' : 'つぎへ'),
          ),
        ],
      ),
    );
  }
}
