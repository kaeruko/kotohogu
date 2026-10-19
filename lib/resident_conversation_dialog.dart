import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dialogue_engine.dart';
import 'resident_collection.dart';
import 'local_content_preview.dart';

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

/// One speaker turn in the shared, paginated dialogue viewer.
class ConversationTurn {
  const ConversationTurn({
    required this.label,
    required this.avatar,
    required this.text,
  });

  final String label;
  final Widget avatar;
  final String text;
}

/// Shared dialogue presentation for acquired residents and remote CMS previews.
/// Paging and font scaling must remain identical in both entry points.
class PagedConversationDialog extends StatefulWidget {
  const PagedConversationDialog({
    super.key,
    required this.conversationId,
    required this.turns,
    this.badge,
    this.reportCompletion = false,
  });

  final String conversationId;
  final List<ConversationTurn> turns;
  final String? badge;
  final bool reportCompletion;

  @override
  State<PagedConversationDialog> createState() => _PagedConversationDialogState();
}

class _PagedConversationDialogState extends State<PagedConversationDialog> {
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
      if (widget.reportCompletion) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant PagedConversationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _turnIndex = 0;
      _pageIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final turn = widget.turns[_turnIndex];
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
    // Reserve additional space when a preview-specific label is present.
    final footerAndBadge = widget.badge == null ? 36.0 : 70.0;
    final pageLines = math.max(
      1,
      math.min(5, ((bodyHeight - footerAndBadge) / lineHeight).floor()),
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
        _turnIndex == widget.turns.length - 1;

    // The body itself may be tapped to advance, not only the button.
    return GestureDetector(
      onTap: () => _advance(
        turnCount: widget.turns.length,
        pageCount: pages.length,
      ),
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
            turn.avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                turn.label,
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
              if (widget.badge != null) ...[
                Text(
                  widget.badge!,
                  key: const ValueKey('dialogue-source-badge'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: SingleChildScrollView(
                  // Only a safety net for extreme accessibility text sizes.
                  child: Text(
                    pages[currentPage],
                    key: const ValueKey('dialogue-visible-line'),
                    style: bodyStyle,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (widget.turns.length > 1)
                    Text(
                      '${_turnIndex + 1} / ${widget.turns.length}',
                      key: const ValueKey('dialogue-turn-count'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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
            onPressed: () => _advance(
              turnCount: widget.turns.length,
              pageCount: pages.length,
            ),
            child: Text(isLast ? 'また話そう' : 'つぎへ'),
          ),
        ],
      ),
    );
  }
}

/// Acquired residents and their replies use the shared pager.
class ResidentConversationDialog extends StatelessWidget {
  const ResidentConversationDialog({
    super.key,
    required this.speaker,
    required this.dialogue,
  });

  final TownResident speaker;
  final DialogueEntry dialogue;

  @override
  Widget build(BuildContext context) {
    final reply = dialogue.reply;
    return PagedConversationDialog(
      conversationId: 'resident:${speaker.id}:${dialogue.id}',
      turns: [
        ConversationTurn(
          label: speaker.label,
          avatar: TownResidentAvatar(resident: speaker, size: 48),
          text: dialogue.text,
        ),
        if (reply != null)
          ConversationTurn(
            label: TownResident.fromId(reply.residentId).label,
            avatar: TownResidentAvatar(
              resident: TownResident.fromId(reply.residentId),
              size: 48,
            ),
            text: reply.text,
          ),
      ],
    );
  }
}

/// Unowned remote visitors are only shown from a debug preview and do not
/// update the user's collected characters or dialogue history.
class RemoteVisitorConversationDialog extends StatelessWidget {
  const RemoteVisitorConversationDialog({
    super.key,
    required this.speaker,
    required this.dialogue,
    required this.baseUri,
  });

  final RemoteResident speaker;
  final RemoteDialogue dialogue;
  final Uri baseUri;

  @override
  Widget build(BuildContext context) => PagedConversationDialog(
        conversationId: 'remote:${speaker.id}:${dialogue.id}',
        badge: '配信テストの来訪者',
        turns: [
          ConversationTurn(
            label: speaker.label,
            avatar: SizedBox(
              width: 48,
              height: 48,
              child: Image.network(
                remoteSpriteUri(
                  baseUri,
                  speaker,
                  'idle_front_01.png',
                ).toString(),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Tooltip(
                  message: '画像の取得に失敗しました: $error',
                  child: const Icon(Icons.broken_image, color: Colors.red),
                ),
              ),
            ),
            text: dialogue.text,
          ),
        ],
      );
}
