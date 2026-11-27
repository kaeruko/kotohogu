import 'dart:math';

import 'package:flutter/material.dart';

import 'sudoku_duel.dart';

/// Presentation only: never changes a move, score, save, or turn.
class DuelMoveEffect {
  const DuelMoveEffect({
    required this.cell,
    this.wrong = false,
    this.capturedRoom,
    this.targetRoom,
    this.freeChoice = false,
    this.victory = false,
    this.opponent = false,
  });

  final int cell;
  final bool wrong;
  final int? capturedRoom;
  final int? targetRoom;
  final bool freeChoice;
  final bool victory;
  final bool opponent;
}

class DuelMoveEffectPainter extends CustomPainter {
  DuelMoveEffectPainter({
    required this.boardSize,
    required this.effect,
    required this.progress,
    this.flatBoard = false,
  }) : super(repaint: progress);

  final DuelSize boardSize;
  final DuelMoveEffect effect;
  final Animation<double> progress;
  final bool flatBoard;

  static const _gold = Color(0xFFD99219);
  static const _cream = Color(0xFFFFE29A);
  static const _copper = Color(0xFFC56F42);
  static const _teal = Color(0xFF2C957D);
  static const _rose = Color(0xFFC65751);

  double _unit(double value) => value.clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t >= 1 || size.isEmpty) return;
    final side = boardSize.side;
    final rows = boardSize.boxRows;
    final columns = boardSize.boxColumns;
    final across = side ~/ columns;
    final down = side ~/ rows;
    final roomWidth = size.width / across;
    final roomHeight = size.height / down;

    // Mirrors the room margin (2), border (2), and header (24) in _DuelBoard.
    Rect roomRect(int room) => Rect.fromLTWH(
      ((room - 1) % across) * roomWidth + 2,
      ((room - 1) ~/ across) * roomHeight + 2,
      roomWidth - 4,
      roomHeight - 4,
    );
    final row = effect.cell ~/ side;
    final column = effect.cell % side;
    final source = roomRect(boardSize.roomOf(effect.cell));
    final cellWidth = flatBoard ? size.width / side : (roomWidth - 8) / columns;
    final cellHeight = flatBoard ? size.height / side : (roomHeight - 32) / rows;
    final cellRect = Rect.fromLTWH(
      flatBoard ? column * cellWidth : source.left + 2 + (column % columns) * cellWidth,
      flatBoard ? row * cellHeight : source.top + 26 + (row % rows) * cellHeight,
      cellWidth,
      cellHeight,
    );
    final center = cellRect.center;
    final radius = min(cellWidth, cellHeight) * .48;
    final ink = effect.opponent ? _copper : _gold;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (effect.wrong) {
      final opacity = (1 - t) * .85;
      final shift = sin(t * pi * 8) * (1 - t) * 3;
      if (flatBoard) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect.deflate(1), const Radius.circular(3)),
          Paint()..color = _rose.withValues(alpha: opacity * .20),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect.deflate(2).shift(Offset(shift, 0)),
          const Radius.circular(4),
        ),
        Paint()
          ..color = _rose.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.restore();
      return;
    }

    // A local, warm burst, rather than a full-screen flash.
    final pop = Curves.easeOut.transform(_unit(t / .55));
    final fade = 1 - _unit(t / .75);
    if (fade > 0) {
      canvas.drawCircle(
        center,
        radius * (.3 + pop * 1.05),
        Paint()..color = _cream.withValues(alpha: fade * .32),
      );
      canvas.drawCircle(
        center,
        radius * (.45 + pop * 1.2),
        Paint()
          ..color = ink.withValues(alpha: fade * .9)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      final rays = Paint()
        ..color = ink.withValues(alpha: fade)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final angle = i * pi / 4 + pi / 8;
        final direction = Offset(cos(angle), sin(angle));
        canvas.drawLine(
          center + direction * radius * (.5 + pop * .7),
          center + direction * radius * (.85 + pop * 1.1),
          rays,
        );
      }
    }

    if (effect.capturedRoom case final room?) {
      final rect = roomRect(room).deflate(1);
      final glow = sin(pi * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = _cream.withValues(alpha: glow * .22),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = ink.withValues(alpha: glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // The flag rises above its room and fades, leaving the real flag intact.
      final lift = Curves.easeOut.transform(_unit(t / .6));
      final anchor = Offset(rect.center.dx, rect.top + 30 - lift * 22);
      final flagPaint = Paint()..color = ink.withValues(alpha: 1 - t);
      canvas.drawLine(
        anchor + const Offset(-7, -12),
        anchor + const Offset(-7, 12),
        flagPaint..strokeWidth = 2,
      );
      canvas.drawPath(
        Path()
          ..moveTo(anchor.dx - 7, anchor.dy - 12)
          ..lineTo(anchor.dx + 9, anchor.dy - 9)
          ..lineTo(anchor.dx + 5, anchor.dy - 2)
          ..lineTo(anchor.dx - 7, anchor.dy)
          ..close(),
        flagPaint,
      );
    }

    final flight = _unit((t - .18) / .66);
    if (t > .18 && flight < 1) {
      final a = sin(pi * flight);
      if (effect.targetRoom case final room?) {
        final end = roomRect(room).center;
        final travel = Curves.easeInOut.transform(flight);
        final point = Offset.lerp(center, end, travel)! +
            Offset(0, -sin(pi * travel) * 16);
        for (var i = 3; i >= 0; i--) {
          final f = _unit(travel - i * .045);
          final tail = Offset.lerp(center, end, f)! +
              Offset(0, -sin(pi * f) * 16);
          canvas.drawCircle(
            i == 0 ? point : tail,
            4 - i * .7,
            Paint()..color = _teal.withValues(alpha: a * (1 - i * .2)),
          );
        }
      } else if (effect.freeChoice) {
        // No specific destination: a small outward ring signals free choice.
        canvas.drawCircle(
          center,
          radius * (1 + flight * 2),
          Paint()
            ..color = _teal.withValues(alpha: a * .7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    if (effect.victory) {
      final random = Random(23);
      const colors = [_gold, _teal, _rose, _copper];
      final fall = Curves.easeOut.transform(t);
      for (var i = 0; i < 32; i++) {
        final x = random.nextDouble() * size.width;
        final start = -random.nextDouble() * size.height * .28;
        final y = start + fall * size.height * (.45 + random.nextDouble() * .6);
        final angle = random.nextDouble() * pi + t * 4;
        canvas.save();
        canvas.translate(x + sin(t * pi + i) * 10, y);
        canvas.rotate(angle);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 4, height: 9),
            const Radius.circular(1),
          ),
          Paint()..color = colors[i % colors.length].withValues(
            alpha: (1 - t) * .95,
          ),
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DuelMoveEffectPainter oldDelegate) =>
      oldDelegate.effect != effect ||
      oldDelegate.boardSize != boardSize ||
      oldDelegate.flatBoard != flatBoard ||
      oldDelegate.progress != progress;
}
